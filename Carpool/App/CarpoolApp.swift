import CarpoolKit
import CarpoolUI
import SwiftUI

@main
struct CarpoolApp: App {
    @State private var session = AppSession.live()

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-designCatalog") {
                    DesignCatalogView(initialSection: UserDefaults.standard.string(forKey: "designCatalogSection"))
                } else if ProcessInfo.processInfo.arguments.contains("-previewFamily") {
                    // Beispiel-Familie ohne Netzwerk, angemeldet als Lisa.
                    MainTabView(session: AppSession(api: PreviewAPI()), member: PreviewAPI.lisa)
                } else {
                    content
                }
                #else
                content
                #endif
            }
            .tint(Color.ink)
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
