import CarpoolKit
import SwiftUI

/// Tank-Regler (F06): folgt dem Daumen 1:1, beim Greifen 1.08, rastet beim
/// Loslassen per Feder auf das nächste Viertel ein, Haptik pro Stufe.
public struct FuelPicker: View {
    @Binding private var level: FuelLevel
    @State private var dragFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackHeight: CGFloat = 56
    private let knobSize: CGFloat = 44

    public init(level: Binding<FuelLevel>) {
        _level = level
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .lastTextBaseline) {
                Text("Tankstand").metaStyle()
                Spacer()
                Text(displayedLevel.label)
                    .font(.title2.bold())
                    .foregroundStyle(Color.ink)
                    .contentTransition(.opacity)
                    .animation(Motion.numberFade, value: displayedLevel)
            }
            track
            labels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tankstand")
        .accessibilityValue(level.spokenLabel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: level = FuelLevel(quarters: level.quarters + 1)
            case .decrement: level = FuelLevel(quarters: level.quarters - 1)
            @unknown default: break
            }
        }
        .sensoryFeedback(.selection, trigger: displayedLevel)
    }

    /// Während des Ziehens die Stufe unter dem Daumen, sonst der gespeicherte Wert.
    private var displayedLevel: FuelLevel {
        dragFraction.map(FuelLevel.nearest(toFraction:)) ?? level
    }

    private var track: some View {
        GeometryReader { proxy in
            let travel = proxy.size.width - knobSize - 12
            let fraction = dragFraction ?? level.fraction
            let knobX = 6 + travel * fraction
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.hairline)
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.ink)
                    .frame(width: knobX + knobSize / 2)
                Circle()
                    .fill(Color.surface)
                    .overlay(Circle().strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
                    .frame(width: knobSize, height: knobSize)
                    .scaleEffect(dragFraction == nil ? 1 : 1.08)
                    .offset(x: knobX)
                    .animation(Motion.press, value: dragFraction == nil)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = (value.location.x - 6 - knobSize / 2) / max(travel, 1)
                        dragFraction = min(max(raw, FuelLevel(quarters: 1).fraction), 1)
                    }
                    .onEnded { _ in
                        guard let fraction = dragFraction else { return }
                        let snapped = FuelLevel.nearest(toFraction: fraction)
                        withAnimation(Motion.resolved(Motion.gesture, reduceMotion: reduceMotion)) {
                            level = snapped
                            dragFraction = nil
                        }
                    }
            )
        }
        .frame(height: trackHeight)
    }

    /// Die Stufen liegen genau unter den Rastpunkten des Knopfs.
    private var labels: some View {
        GeometryReader { proxy in
            let travel = proxy.size.width - knobSize - 12
            ForEach(FuelLevel.range, id: \.self) { quarter in
                let level = FuelLevel(quarters: quarter)
                Text(level.label)
                    .metaStyle()
                    .fixedSize()
                    .position(x: 6 + knobSize / 2 + travel * level.fraction, y: 8)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
