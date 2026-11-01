import Foundation
import Observation

/// Reservieren-Formular (F12) mit Konflikt-Hinweis und Übernehmen (F14).
/// Prüft jede Änderung beim Backend (`check_reservation`, `free_cars`); entscheidet selbst nichts.
@MainActor
@Observable
public final class ReservationModel {
    public enum Step: Equatable, Sendable {
        case editing
        /// Hauptnutzer will übernehmen: Bestätigung (destruktiv).
        case confirmDisplace([ReservationConflict])
        /// Für mindestens einen Verdrängten gibt es kein Ersatzauto: bewusst bestätigen.
        case confirmNoReplacement([ReservationConflict])
        case done
    }

    /// Hinweis direkt im Formular, wenn das gewählte Auto belegt ist.
    public struct ConflictBanner: Equatable, Sendable {
        public let text: String
        public let personShort: String?
        public let colorSlot: Int
        /// Freie Autos für genau diesen Zeitraum zum Tauschen.
        public let swapCars: [Car]
        /// Alle Konflikte darf ich als Hauptnutzer übernehmen.
        public let canDisplace: Bool
        public let conflicts: [ReservationConflict]
    }

    public private(set) var draft: ReservationDraft
    public private(set) var step: Step = .editing
    public private(set) var isSubmitting = false
    public private(set) var error: CarpoolError?
    /// Ergebnis der Prüfung für den aktuellen Entwurf (nil = läuft noch).
    public private(set) var check: ReservationResult?
    /// Fehler der Prüfung (z. B. Beginn in der Vergangenheit), als Hinweis im Formular.
    public private(set) var checkError: CarpoolError?
    /// Freie Autos im (ersten) Zeitraum; nil = noch unbekannt.
    public private(set) var freeCarIDs: Set<UUID>?

    public let snapshot: FamilySnapshot
    public let text: TimeText
    private let api: any CarpoolAPI
    private let clock: @Sendable () -> Date
    private var checkTask: Task<Void, Never>?

    /// Wartezeit, bevor eine Änderung geprüft wird.
    static let checkDebounce: Duration = .milliseconds(250)

    /// - Parameter carID: vorausgewähltes Auto (z. B. aus dem Auto-Detail).
    public init(snapshot: FamilySnapshot, api: any CarpoolAPI, day: Date, carID: UUID? = nil,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.snapshot = snapshot
        self.api = api
        self.clock = clock
        self.text = TimeText(family: snapshot.family)
        let now = clock()
        let car = carID.flatMap(snapshot.car) ?? snapshot.cars.first { $0.primaryMemberId == snapshot.me.id }
            ?? snapshot.cars.first
        self.draft = .initial(day: day, carID: car?.id, now: now, calendar: text.calendar)
    }

    // MARK: Eingaben

    public var presets: [ReservationDraft.Preset] { ReservationDraft.presets(now: clock(), calendar: text.calendar) }
    public var canRepeat: Bool { draft.canRepeat(calendar: text.calendar) }
    public var selectedCar: Car? { draft.carID.flatMap(snapshot.car) }

    public func select(_ preset: ReservationDraft.Preset) {
        update(draft.applying(preset, now: clock(), calendar: text.calendar))
    }

    public func select(car: Car) { update(draft.with(carID: car.id)) }
    public func setStart(_ date: Date) { update(draft.with(start: date)) }
    public func setEnd(_ date: Date) { update(draft.with(end: date)) }
    public func setRepeat(_ days: Set<Weekday>, until: Date?) { update(draft.with(repeatDays: days, until: until)) }

    /// Startet die erste Prüfung sofort.
    public func start() {
        scheduleCheck(debounce: false)
    }

    // MARK: Anzeige

    /// Status einer Autokachel für den gewählten Zeitraum: frei / belegt; nil = noch unbekannt.
    public func status(of car: Car) -> CarStatus? {
        if car.id == draft.carID, let check { return check.ok ? .free : .reserved }
        if let check, !check.ok, check.reason == .conflict { return check.freeCarIds.contains(car.id) ? .free : .reserved }
        return freeCarIDs.map { $0.contains(car.id) ? .free : .reserved }
    }

    public var conflictBanner: ConflictBanner? {
        guard let check, !check.ok, !check.conflicts.isEmpty, let car = selectedCar else { return nil }
        let conflicts = check.conflicts
        let people = Set(conflicts.map(\.memberId))
        let short = people.count == 1 ? snapshot.member(conflicts[0].memberId)?.short : nil
        return ConflictBanner(
            text: ReservationTexts.conflict(conflicts, car: car.title, me: snapshot.me.id,
                                            requestedStart: draft.startsAt, now: clock(), text: text),
            personShort: short, colorSlot: car.colorSlot,
            swapCars: check.freeCarIds.compactMap(snapshot.car),
            canDisplace: conflicts.allSatisfy(\.canDisplace),
            conflicts: conflicts)
    }

    /// Text des Primär-Buttons: „Reservieren" oder „Octavia ist belegt".
    public var submitTitle: String {
        if conflictBanner != nil, let car = selectedCar { return "\(car.title) ist belegt" }
        return "Reservieren"
    }

    public var canSubmit: Bool {
        conflictBanner == nil && checkError == nil && !isSubmitting
            && draft.request(calendar: text.calendar) != nil
    }

    // MARK: Aktionen

    public func submit() async {
        await reserve(displace: false, acceptNoReplacement: false)
    }

    public func requestDisplace() {
        guard let banner = conflictBanner, banner.canDisplace else { return }
        step = .confirmDisplace(banner.conflicts)
    }

    public func confirmDisplace() async {
        await reserve(displace: true, acceptNoReplacement: false)
    }

    public func confirmNoReplacement() async {
        await reserve(displace: true, acceptNoReplacement: true)
    }

    public func cancelConfirmation() {
        if step != .done { step = .editing }
    }

    public func dismissError() { error = nil }

    // MARK: Intern

    private func update(_ new: ReservationDraft) {
        guard new != draft else { return }
        draft = new
        error = nil
        scheduleCheck(debounce: true)
    }

    private func reserve(displace: Bool, acceptNoReplacement: Bool) async {
        guard let request = draft.request(calendar: text.calendar), !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await api.reserve(request, displace: displace, acceptNoReplacement: acceptNoReplacement)
            handle(result, for: request)
        } catch {
            step = .editing
            self.error = CarpoolError.from(error)
        }
    }

    private func handle(_ result: ReservationResult, for request: ReservationRequest) {
        if result.ok {
            step = .done
            return
        }
        switch result.reason {
        case .noReplacement:
            step = .confirmNoReplacement(result.conflicts)
        case .notDisplaceable:
            step = .editing
            error = CarpoolError(code: "not_displaceable")
            check = result
        case .conflict, nil:
            // Inzwischen belegt: Hinweis im Formular zeigen.
            step = .editing
            if draft.request(calendar: text.calendar) == request { check = result }
        }
    }

    private func scheduleCheck(debounce: Bool) {
        checkTask?.cancel()
        check = nil
        checkError = nil
        guard let request = draft.request(calendar: text.calendar) else {
            freeCarIDs = nil
            return
        }
        checkTask = Task { [weak self, api] in
            if debounce {
                try? await Task.sleep(for: Self.checkDebounce)
                guard !Task.isCancelled else { return }
            }
            async let checked = api.checkReservation(request)
            async let free = api.freeCars(from: request.startsAt, to: request.endsAt)
            do {
                let (result, cars) = try await (checked, free)
                guard !Task.isCancelled else { return }
                self?.check = result
                self?.freeCarIDs = Set(cars.map(\.id))
            } catch {
                guard !Task.isCancelled else { return }
                self?.checkError = CarpoolError.from(error)
            }
        }
    }
}
