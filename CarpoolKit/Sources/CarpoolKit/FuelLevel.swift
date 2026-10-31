/// Tankstand in Vierteln (1 = ¼ … 4 = voll), wie in `cars.fuel_quarters`.
public struct FuelLevel: Sendable, Hashable, Comparable {
    public static let range = 1...4

    public let quarters: Int

    /// Werte außerhalb von 1…4 werden auf den nächsten gültigen Wert begrenzt.
    public init(quarters: Int) {
        self.quarters = min(max(quarters, Self.range.lowerBound), Self.range.upperBound)
    }

    public static let full = FuelLevel(quarters: 4)

    /// Anzeige: ¼, ½, ¾, voll.
    public var label: String {
        switch quarters {
        case 1: "¼"
        case 2: "½"
        case 3: "¾"
        default: "voll"
        }
    }

    /// Für VoiceOver.
    public var spokenLabel: String {
        switch quarters {
        case 1: "ein Viertel"
        case 2: "halb voll"
        case 3: "drei Viertel"
        default: "voll"
        }
    }

    public var fraction: Double { Double(quarters) / Double(Self.range.upperBound) }

    /// Nächste Viertelstufe für einen Anteil 0…1 (z. B. Position am Regler).
    public static func nearest(toFraction fraction: Double) -> FuelLevel {
        FuelLevel(quarters: Int((fraction * Double(range.upperBound)).rounded()))
    }

    public static func < (lhs: FuelLevel, rhs: FuelLevel) -> Bool { lhs.quarters < rhs.quarters }
}
