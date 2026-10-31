import SwiftUI

/// Farb-Tokens aus dem Design System. Namen 1:1 wie im Asset-Katalog.
public extension Color {
    static let paper = token("paper")
    static let surface = token("surface")
    static let ink = token("ink")
    static let inkSecondary = token("ink-secondary")
    static let inkMuted = token("ink-muted")
    static let onInk = token("on-ink")
    static let hairline = token("hairline")
    static let hairlineStrong = token("hairline-strong")
    static let statusFree = token("status-free")
    static let statusReserved = token("status-reserved")
    static let statusBusy = token("status-busy")
    static let danger = token("danger")

    private static func token(_ name: String) -> Color {
        Color(name, bundle: .module)
    }
}

/// Kalenderfarbe eines Autos (`cars.color_slot`). Es gibt drei Farbsätze;
/// ab dem vierten Auto wiederholen sie sich.
public struct CarColor: Sendable, Hashable {
    public static let setCount = 3

    public let slot: Int

    public init(slot: Int) {
        self.slot = slot
    }

    /// Farbsatz 1…3, auf den der Slot abgebildet wird.
    public var set: Int { ((max(slot, 1) - 1) % Self.setCount) + 1 }

    /// Kräftige Farbe: Punkte, Markierungen.
    public var base: Color { Color("car-\(set)", bundle: .module) }
    /// Heller Hintergrund: Buchungsblöcke, Hinweise.
    public var tint: Color { Color("car-\(set)-tint", bundle: .module) }
    /// Text auf `tint`.
    public var ink: Color { Color("car-\(set)-ink", bundle: .module) }
}
