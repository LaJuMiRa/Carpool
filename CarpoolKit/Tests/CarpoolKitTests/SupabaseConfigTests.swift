import Foundation
import Testing
@testable import CarpoolKit

struct SupabaseConfigTests {
    @Test func loadsValidConfig() throws {
        let config = try SupabaseConfig.load(from: [
            "SupabaseURL": "http://127.0.0.1:54321",
            "SupabaseAnonKey": "abc"
        ])
        #expect(config.url.absoluteString == "http://127.0.0.1:54321")
        #expect(config.anonKey == "abc")
    }

    @Test func missingURLFails() {
        #expect(throws: SupabaseConfig.LoadError.missingURL) {
            try SupabaseConfig.load(from: ["SupabaseAnonKey": "abc"])
        }
    }

    @Test func emptyURLFails() {
        #expect(throws: SupabaseConfig.LoadError.missingURL) {
            try SupabaseConfig.load(from: ["SupabaseURL": "  ", "SupabaseAnonKey": "abc"])
        }
    }

    @Test func invalidURLFails() {
        #expect(throws: SupabaseConfig.LoadError.invalidURL("kein url")) {
            try SupabaseConfig.load(from: ["SupabaseURL": "kein url", "SupabaseAnonKey": "abc"])
        }
    }

    @Test func missingKeyFails() {
        #expect(throws: SupabaseConfig.LoadError.missingAnonKey) {
            try SupabaseConfig.load(from: ["SupabaseURL": "http://127.0.0.1:54321", "SupabaseAnonKey": ""])
        }
    }
}
