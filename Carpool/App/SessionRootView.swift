import CarpoolKit
import CarpoolUI
import SwiftUI

/// Wählt den Bildschirm nach Anmeldestand: Anmelden, Familie einrichten oder App.
struct SessionRootView: View {
    let session: AppSession

    var body: some View {
        Group {
            switch session.phase {
            case .starting:
                if let error = session.loadError {
                    MessageScreen(text: error.message, actionTitle: "Erneut versuchen") {
                        Task { await session.retry() }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.paper)
                }
            case .signedOut:
                AuthScreen(session: session)
            case .needsFamily:
                FamilySetupScreen(session: session)
            case .ready(let member):
                MainTabView(session: session, member: member)
                    .id(member.id)
            }
        }
        .task { session.start() }
        #if DEBUG
        .onChange(of: session.phase) { _, phase in
            if phase == .signedOut { DevLogin.signInIfConfigured(session) }
        }
        #endif
    }
}

#if DEBUG
/// Nur Entwicklung: meldet sich automatisch an, wenn `DEV_EMAIL` und `DEV_PASSWORD`
/// als Umgebungsvariablen gesetzt sind (z. B. `SIMCTL_CHILD_DEV_EMAIL=…` beim Start im Simulator).
enum DevLogin {
    @MainActor
    static func signInIfConfigured(_ session: AppSession) {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["DEV_EMAIL"], let password = environment["DEV_PASSWORD"] else { return }
        Task { try? await session.signIn(email: email, password: password) }
    }
}
#endif

/// Einfacher Hinweis mit optionaler Aktion (Fehler, fehlende Konfiguration).
struct MessageScreen: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.l) {
            Text(text)
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.carpoolSecondary)
            }
        }
        .padding(Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }
}
