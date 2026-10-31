import Foundation
import Supabase

/// Gemeinsamer Zugang zum Supabase-Backend für App, Widgets und App Intents.
public final class CarpoolBackend: Sendable {
    public let client: SupabaseClient

    public init(config: SupabaseConfig) {
        client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
    }
}
