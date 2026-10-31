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

    public let member: Member
    private let api: any CarpoolAPI
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
