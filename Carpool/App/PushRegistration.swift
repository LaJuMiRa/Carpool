import CarpoolKit
import Observation
import OSLog
import UIKit
import UserNotifications

/// Fragt nach der Erlaubnis für Mitteilungen und meldet das Gerätetoken beim Backend an
/// (`register_device`). Beim Abmelden wird es wieder abgemeldet, damit keine Nachrichten
/// für die alte Person mehr ankommen.
@MainActor
@Observable
final class PushRegistration {
    private(set) var token: String?
    private var api: (any CarpoolAPI)?
    private let log = Logger(subsystem: "at.rauscher.carpool", category: "push")

    /// Im Debug-Build mit automatischer Anmeldung (UI-Tests) nicht nach Mitteilungen fragen.
    static var promptAllowed: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["DEV_EMAIL"] == nil
        #else
        true
        #endif
    }

    /// Nach dem Anmelden: Erlaubnis erfragen (nur beim ersten Mal sichtbar) und Token anmelden.
    func start(api: any CarpoolAPI) async {
        self.api = api
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            log.error("Mitteilungen nicht erlaubt: \(error.localizedDescription, privacy: .public)")
        }
        await registerIfPossible()
    }

    /// Vor dem Abmelden, solange die Anmeldung noch gilt.
    func stop() async {
        if let api, let token {
            do {
                try await api.unregisterDevice(token: token)
            } catch {
                log.error("Token nicht abgemeldet: \(error.localizedDescription, privacy: .public)")
            }
        }
        api = nil
    }

    func received(token: String) {
        self.token = token
        Task { await registerIfPossible() }
    }

    func failed(_ error: any Error) {
        log.error("Kein Gerätetoken: \(error.localizedDescription, privacy: .public)")
    }

    private func registerIfPossible() async {
        guard let api, let token else { return }
        do {
            try await api.registerDevice(token: token)
        } catch {
            log.error("Token nicht angemeldet: \(error.localizedDescription, privacy: .public)")
        }
    }
}
