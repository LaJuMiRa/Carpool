import CarpoolKit
import Foundation

extension SupabaseConfig {
    /// Konfiguration aus der Info.plist der App.
    static func fromMainBundle() throws(LoadError) -> SupabaseConfig {
        try load(from: Bundle.main.infoDictionary ?? [:])
    }
}

extension AppSession {
    /// Session mit echtem Backend, oder nil, wenn die Konfiguration fehlt.
    static func live() -> AppSession? {
        guard let config = try? SupabaseConfig.fromMainBundle() else { return nil }
        return AppSession(api: SupabaseCarpoolAPI(config: config))
    }
}
