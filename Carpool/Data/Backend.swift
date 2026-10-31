import CarpoolKit
import Foundation

extension SupabaseConfig {
    /// Konfiguration aus der Info.plist der App.
    static func fromMainBundle() throws(LoadError) -> SupabaseConfig {
        try load(from: Bundle.main.infoDictionary ?? [:])
    }
}
