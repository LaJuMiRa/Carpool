import Foundation

/// Verbindungsdaten zum Supabase-Projekt. Werden aus der Info.plist gelesen,
/// die sie über `Config/Secrets.xcconfig` bekommt.
public struct SupabaseConfig: Sendable, Equatable {
    public let url: URL
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    public enum LoadError: Error, Equatable {
        case missingURL
        case invalidURL(String)
        case missingAnonKey
    }

    /// Liest `SupabaseURL` und `SupabaseAnonKey` aus einem Info-Dictionary.
    public static func load(from info: [String: Any]) throws(LoadError) -> SupabaseConfig {
        guard let rawURL = (info["SupabaseURL"] as? String)?.trimmingCharacters(in: .whitespaces),
              !rawURL.isEmpty else {
            throw .missingURL
        }
        guard let url = URL(string: rawURL), url.scheme != nil, url.host() != nil else {
            throw .invalidURL(rawURL)
        }
        guard let key = (info["SupabaseAnonKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty else {
            throw .missingAnonKey
        }
        return SupabaseConfig(url: url, anonKey: key)
    }
}
