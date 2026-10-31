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
            Text(text ?? status.label)
                .font(.callout.weight(.medium))
                .foregroundStyle(status.color)
                .contentTransition(.opacity)
        }
        .animation(Motion.crossfade, value: status)
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
