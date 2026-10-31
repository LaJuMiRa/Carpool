import CarpoolKit
import SwiftUI

/// Kleine Tankanzeige aus vier Segmenten.
public struct FuelGauge: View {
    public enum Style {
        /// Striche mit Text (Detail: „▬▬▬ ¾").
        case bars
        /// Punkte ohne Text (Auswahlliste).
        case dots
    }

    private let level: FuelLevel
    private let style: Style

    public init(_ level: FuelLevel, style: Style = .bars) {
        self.level = level
        self.style = style
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            HStack(spacing: style == .bars ? 3 : 4) {
                ForEach(FuelLevel.range, id: \.self) { quarter in
                    Capsule()
                        .fill(quarter <= level.quarters ? Color.ink : Color.hairline)
                        .frame(width: style == .bars ? 16 : 5, height: 5)
                }
            }
            if style == .bars {
                Text(level.label).font(.body).foregroundStyle(Color.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tank \(level.spokenLabel)")
    }
}
