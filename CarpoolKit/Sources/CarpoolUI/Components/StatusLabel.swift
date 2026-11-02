import CarpoolKit
import SwiftUI

public extension CarStatus {
    var color: Color {
        switch self {
        case .free: .statusFree
        case .reserved: .statusReserved
        case .busy: .statusBusy
        }
    }
}

/// Punkt + Wort. Farbe nie ohne Wort. Optional abweichender Text („belegt", „bei dir").
public struct StatusLabel: View {
    private let status: CarStatus
    private let text: String?

    public init(_ status: CarStatus, text: String? = nil) {
        self.status = status
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
            ZStack(alignment: .leading) {
                Text(text ?? status.label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(status.color)
                    .id(text ?? status.label)
                    .transition(.statusFade)
            }
        }
        .animation(Motion.crossfade, value: status)
        .animation(Motion.crossfade, value: text)
        .accessibilityElement(children: .combine)
    }
}

/// Kleiner Farbpunkt eines Autos (Kalender, Tauschen-Buttons). Nie ohne Namen daneben.
public struct CarDot: View {
    private let color: CarColor

    public init(_ color: CarColor) {
        self.color = color
    }

    public var body: some View {
        Circle()
            .fill(color.base)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

public extension AnyTransition {
    /// Statuswechsel: Überblenden mit 2 pt Unschärfe (keine Bewegung, gilt auch bei „Bewegung reduzieren").
    static var statusFade: AnyTransition {
        .modifier(active: BlurFade(isActive: true), identity: BlurFade(isActive: false))
    }
}

private struct BlurFade: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content.blur(radius: isActive ? 2 : 0).opacity(isActive ? 0 : 1)
    }
}
