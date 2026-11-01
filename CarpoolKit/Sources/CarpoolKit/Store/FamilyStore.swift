import Foundation
import Observation

/// Daten und Aktionen einer Familie für Übersicht (und später Kalender).
/// Nehmen und Zurückgeben werden sofort lokal angezeigt und danach vom Server bestätigt.
@MainActor
@Observable
public final class FamilyStore {
    public struct UndoOffer: Identifiable, Equatable, Sendable {
        public enum Kind: Sendable { case take, `return` }

        public let id = UUID()
        public let kind: Kind
        public let carTitle: String

        /// „Flitzer gehört dir" / „Radieschen zurückgegeben"
        public var text: String {
            switch kind {
            case .take: "\(carTitle) gehört dir"
            case .return: "\(carTitle) zurückgegeben"
            }
        }
    }

    public private(set) var snapshot: FamilySnapshot?
    public private(set) var loadError: CarpoolError?
    /// Fehler einer Aktion; die Oberfläche zeigt ihn an und setzt ihn mit `dismissError()` zurück.
    public private(set) var actionError: CarpoolError?
    public private(set) var undoOffer: UndoOffer?
    /// Eigene Einstellungen; nil, solange nicht geladen.
    public private(set) var settings: MemberSettings?

    public let member: Member
    public let api: any CarpoolAPI
    private var changesTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    /// Wartezeit, um mehrere Realtime-Ereignisse zu einem Neuladen zusammenzufassen.
    static let refreshDebounce: Duration = .milliseconds(300)

    public init(member: Member, api: any CarpoolAPI) {
        self.member = member
        self.api = api
    }

    public func start() async {
        if changesTask == nil {
            changesTask = Task { [weak self, api, familyID = member.familyId] in
                for await _ in api.familyChanges(familyID: familyID) {
                    self?.scheduleRefresh()
                }
            }
        }
        await refresh()
    }

    public func stop() {
        changesTask?.cancel()
        changesTask = nil
        refreshTask?.cancel()
    }

    public func refresh() async {
        do {
            snapshot = try await api.snapshot(for: member)
            loadError = nil
        } catch {
            loadError = CarpoolError.from(error)
        }
        if settings == nil {
            settings = try? await api.settings(memberID: member.id)
        }
    }

    public func take(_ car: Car, now: Date = Date()) async {
        guard let before = snapshot else { return }
        snapshot = before.applyingTake(carID: car.id, at: now)
        undoOffer = UndoOffer(kind: .take, carTitle: car.title)
        do {
            _ = try await api.takeCar(car.id)
        } catch {
            fail(error, restoring: before)
        }
        await refresh()
    }

    public func returnCar(_ car: Car, fuel: FuelLevel) async {
        guard let before = snapshot else { return }
        snapshot = before.applyingReturn(carID: car.id, fuel: fuel)
        undoOffer = UndoOffer(kind: .return, carTitle: car.title)
        do {
            try await api.returnCar(car.id, fuel: fuel)
        } catch {
            fail(error, restoring: before)
        }
        await refresh()
    }

    public func undo() async {
        undoOffer = nil
        do {
            try await api.undoLastAction()
        } catch {
            actionError = CarpoolError.from(error)
        }
        await refresh()
    }

    /// Eigene Reservierung löschen, auf Wunsch mit allen folgenden Terminen der Serie.
    public func cancel(_ booking: Booking, wholeSeries: Bool) async {
        if let before = snapshot {
            let removed = before.bookings.filter {
                $0.id == booking.id || (wholeSeries && booking.seriesId != nil && $0.seriesId == booking.seriesId
                    && $0.startsAt >= booking.startsAt)
            }
            snapshot = before.removing(Set(removed.map(\.id)))
        }
        do {
            try await api.cancelBooking(booking.id, wholeSeries: wholeSeries)
        } catch {
            actionError = CarpoolError.from(error)
        }
        await refresh()
    }

    /// Fremde Reservierung als Hauptnutzer übernehmen. Liefert `.noReplacement`, wenn erst
    /// bestätigt werden muss, dass es kein Ersatzauto gibt; nil bei Fehler (`actionError`).
    public func displace(_ booking: Booking, acceptNoReplacement: Bool) async -> DisplaceResult? {
        do {
            let result = try await api.displace(bookingID: booking.id, acceptNoReplacement: acceptNoReplacement)
            await refresh()
            return result
        } catch {
            actionError = CarpoolError.from(error)
            await refresh()
            return nil
        }
    }

    // MARK: Mitglieder, Familie, Autos, Schäden, Einstellungen

    /// Führt eine Schreibaktion aus, lädt neu und meldet Erfolg; Fehler landen in `actionError`.
    @discardableResult
    public func perform(_ action: @Sendable (any CarpoolAPI) async throws -> Void) async -> Bool {
        do {
            try await action(api)
            await refresh()
            return true
        } catch {
            actionError = CarpoolError.from(error)
            await refresh()
            return false
        }
    }

    public func rename(firstName: String, short: String) async -> Bool {
        let name = firstName.trimmingCharacters(in: .whitespaces)
        let short = short.trimmingCharacters(in: .whitespaces)
        guard (2...40).contains(name.count), short.count == 2 else {
            actionError = CarpoolError(code: "invalid_name")
            return false
        }
        return await perform { [member] in
            try await $0.updateName(memberID: member.id, firstName: name, short: short)
        }
    }

    /// Einstellungen sofort lokal übernehmen, dann speichern; bei Fehler zurück.
    public func update(_ new: MemberSettings) async {
        let before = settings
        settings = new
        do {
            try await api.updateSettings(new)
        } catch {
            settings = before
            actionError = CarpoolError.from(error)
        }
    }

    public func dismissUndo(_ offer: UndoOffer) {
        if undoOffer == offer { undoOffer = nil }
    }

    public func dismissError() {
        actionError = nil
    }

    // MARK: Intern

    private func fail(_ error: any Error, restoring before: FamilySnapshot) {
        snapshot = before
        undoOffer = nil
        actionError = CarpoolError.from(error)
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDebounce)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
