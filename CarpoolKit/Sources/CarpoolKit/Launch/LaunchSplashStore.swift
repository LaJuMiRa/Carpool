import Foundation

/// Merkt sich auf dem Gerät, ob der Splash (F01) erscheint. Der Splash läuft, bevor Anmeldung und
/// Einstellungen geladen sind; deshalb spiegelt die App `settings.launch_animation` hierher.
/// Regel: „Erster Start" → nur, solange er auf diesem Gerät noch nie lief; „Immer" → bei jedem Start.
public struct LaunchSplashStore {
    private static let modeKey = "launchAnimation"
    private static let shownKey = "launchSplashShown"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var mode: MemberSettings.LaunchAnimation {
        get { defaults.string(forKey: Self.modeKey).flatMap(MemberSettings.LaunchAnimation.init) ?? .first }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.modeKey) }
    }

    public var shouldShow: Bool {
        mode == .always || !defaults.bool(forKey: Self.shownKey)
    }

    public func markShown() {
        defaults.set(true, forKey: Self.shownKey)
    }
}
