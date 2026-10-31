import CarpoolUI
import SwiftUI

@main
struct CarpoolApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-designCatalog") {
                DesignCatalogView(initialSection: UserDefaults.standard.string(forKey: "designCatalogSection"))
            } else {
                RootView()
            }
            #else
            RootView()
            #endif
        }
    }
}
