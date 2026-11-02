import CarpoolKit
import CarpoolUI
import SwiftUI

@main
struct CarpoolApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = AppSession.live()
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue

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
