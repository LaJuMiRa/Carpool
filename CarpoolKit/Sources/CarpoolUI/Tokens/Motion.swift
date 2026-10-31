import SwiftUI

/// Bewegung nur mit Zweck. Häufige Aktionen (Tab-Wechsel, Scrollen, Chips) ohne Animation.
public enum Motion {
    /// Standard-Feder für Zustandswechsel.
    public static let standard = Animation.spring(duration: 0.3, bounce: 0)
    /// Nachfedern nur nach Gesten mit Schwung.
    public static let gesture = Animation.spring(duration: 0.3, bounce: 0.2)
    /// Gemeinsames Element Karte → Detail.
    public static let zoom = Animation.spring(duration: 0.35, bounce: 0)
    /// Druck auf Buttons: sofort auf 0.97.
    public static let press = Animation.easeOut(duration: 0.12)
    public static let pressedScale: CGFloat = 0.97
    /// Überblenden von Status und Zahlen.
    public static let crossfade = Animation.easeOut(duration: 0.2)
    public static let numberFade = Animation.easeOut(duration: 0.15)

    /// Bei „Bewegung reduzieren" wird jede Bewegung zu kurzem Überblenden.
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : animation
    }
}
