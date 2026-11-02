import Foundation
import Testing
@testable import CarpoolKit

@Suite("Splash")
struct LaunchSplashTests {
    private func makeStore() -> LaunchSplashStore {
        let name = "launch-splash-\(UUID().uuidString)"
        return LaunchSplashStore(defaults: UserDefaults(suiteName: name)!)
    }

    @Test("Erster Start: Splash erscheint, danach nicht mehr")
    func onlyFirstLaunch() {
        let store = makeStore()

        #expect(store.shouldShow)
        store.markShown()
        #expect(!store.shouldShow)
    }

    @Test("„Immer“: Splash erscheint bei jedem Start")
    func always() {
        let store = makeStore()
        store.mode = .always
        store.markShown()

        #expect(store.shouldShow)
    }

    @Test("Zurück auf „Erster Start“: kein Splash, wenn schon gesehen")
    func backToFirst() {
        let store = makeStore()
        store.mode = .always
        store.markShown()
        store.mode = .first

        #expect(!store.shouldShow)
    }

    @Test("Einstellung bleibt gespeichert")
    func persists() {
        let defaults = UserDefaults(suiteName: "launch-splash-\(UUID().uuidString)")!
        let first = LaunchSplashStore(defaults: defaults)
        first.mode = .always

        #expect(LaunchSplashStore(defaults: defaults).mode == .always)
    }
}
