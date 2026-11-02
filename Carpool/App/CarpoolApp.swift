import CarpoolKit
import CarpoolUI
import SwiftUI

@main
struct CarpoolApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = AppSession.live()
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue
    @State private var showsSplash = LaunchSplashGate.shouldShow

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-designCatalog") {
                    DesignCatalogView(initialSection: UserDefaults.standard.string(forKey: "designCatalogSection"))
                } else if ProcessInfo.processInfo.arguments.contains("-previewFamily") {
                    // Beispiel-Familie ohne Netzwerk, angemeldet als Lisa.
                    MainTabView(session: AppSession(api: PreviewAPI()), member: PreviewAPI.lisa, usesPush: false)
                } else {
                    content
                }
                #else
                content
                #endif
            }
            .overlay {
                if showsSplash {
                    SplashView(hold: LaunchSplashGate.hold) {
                        LaunchSplashStore().markShown()
                        withAnimation(.easeOut(duration: 0.2)) { showsSplash = false }
                    }
                    .transition(.opacity)
                }
            }
            .environment(appDelegate.router)
            .environment(appDelegate.push)
            .onOpenURL { appDelegate.router.open($0) }
            .tint(Color.ink)
            .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session {
            SessionRootView(session: session)
        } else {
            MessageScreen(text: "Supabase ist nicht eingerichtet. Prüfe Config/Secrets.xcconfig.")
        }
    }
}

/// Splash (F01) beim Start: nach der Einstellung „Startanimation“ (lokal gespiegelt).
/// Debug: in Vorschau-Familie, Design-Katalog und mit Test-Anmeldung aus, außer mit `-splash`.
enum LaunchSplashGate {
    /// Debug `-splashHold`: Endstand bleibt 8 s, damit UI-Tests ihn nach dem Start noch sehen.
    static var hold: TimeInterval {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-splashHold") { return 8 }
        #endif
        return SplashTimeline.hold
    }

    static var shouldShow: Bool {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("-splash") || process.arguments.contains("-splashHold") { return true }
        if process.arguments.contains("-previewFamily") || process.arguments.contains("-designCatalog")
            || process.environment["DEV_EMAIL"] != nil {
            return false
        }
        #endif
        return LaunchSplashStore().shouldShow
    }
}
