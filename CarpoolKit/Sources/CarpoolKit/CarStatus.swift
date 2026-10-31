/// Zustand eines Autos aus Sicht der Familie. Wort immer mitanzeigen, nie nur Farbe.
public enum CarStatus: String, Sendable, CaseIterable {
    /// Keine laufende Fahrt, keine Reservierung im betrachteten Zeitraum.
    case free
    /// Reservierung beginnt bald bzw. liegt im gewählten Zeitraum.
    case reserved
    /// Offene Fahrt.
    case busy

    public var label: String {
        switch self {
        case .free: "frei"
        case .reserved: "reserviert"
        case .busy: "unterwegs"
        }
    }
}
