import Foundation
import Observation

/// Anmeldung und Familienzugehörigkeit. Entscheidet, welcher Bildschirm sichtbar ist.
@MainActor
@Observable
public final class AppSession {
    public enum Phase: Equatable {
        case starting
        case signedOut
        case needsFamily
        case ready(Member)
    }

    public private(set) var phase: Phase = .starting
    /// Fehler beim Laden der Mitgliedschaft (z. B. offline); mit `retry()` erneut versuchen.
    public private(set) var loadError: CarpoolError?

    public let api: any CarpoolAPI
    private var userID: UUID?
    private var authTask: Task<Void, Never>?

    public init(api: any CarpoolAPI) {
        self.api = api
    }

    public func start() {
        guard authTask == nil else { return }
        authTask = Task { [weak self, api] in
            for await userID in api.authChanges() {
                await self?.handle(userID: userID)
            }
        }
    }

    public func retry() async {
        await handle(userID: userID)
    }

    public func signIn(email: String, password: String) async throws(CarpoolError) {
        try await perform { try await api.signIn(email: Self.clean(email), password: password) }
    }

    public func signUp(email: String, password: String) async throws(CarpoolError) {
        let result = try await perform { try await api.signUp(email: Self.clean(email), password: password) }
        if result == .confirmationRequired {
            throw CarpoolError(code: "confirmation_required")
        }
    }

    public func signOut() async throws(CarpoolError) {
        try await perform { try await api.signOut() }
    }

    /// Konto löschen; danach abgemeldet. Fehler (Fahrt läuft, letzter Admin) kommen unverändert an.
    public func deleteAccount() async throws(CarpoolError) {
        try await perform { try await api.deleteAccount() }
        await handle(userID: nil)
    }

    public func createFamily(name: String, firstName: String) async throws(CarpoolError) {
        try await perform {
            try await api.createFamily(name: name.trimmingCharacters(in: .whitespaces),
                                       firstName: firstName.trimmingCharacters(in: .whitespaces))
        }
        await handle(userID: userID)
    }

    public func joinFamily(inviteCode: String, firstName: String) async throws(CarpoolError) {
        try await perform {
            try await api.joinFamily(inviteCode: inviteCode.trimmingCharacters(in: .whitespaces),
                                     firstName: firstName.trimmingCharacters(in: .whitespaces))
        }
        await handle(userID: userID)
    }

    // MARK: Intern

    func handle(userID: UUID?) async {
        self.userID = userID
        guard let userID else {
            loadError = nil
            phase = .signedOut
            return
        }
        do {
            let member = try await api.membership(userID: userID)
            loadError = nil
            phase = member.map(Phase.ready) ?? .needsFamily
        } catch {
            loadError = CarpoolError.from(error)
            if phase == .signedOut { phase = .starting }
        }
    }

    private func perform<T>(_ body: () async throws -> T) async throws(CarpoolError) -> T {
        do {
            return try await body()
        } catch {
            throw CarpoolError.from(error)
        }
    }

    private static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
