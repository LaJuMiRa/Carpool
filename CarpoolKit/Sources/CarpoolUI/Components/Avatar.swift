import SwiftUI

/// Kreis mit den ersten zwei Buchstaben des Vornamens („Li").
public struct Avatar: View {
    public enum Size {
        case small, regular, large

        var diameter: CGFloat {
            switch self {
            case .small: 24
            case .regular: 32
            case .large: 44
            }
        }

        var font: Font {
            switch self {
            case .small: .caption2.weight(.semibold)
            case .regular: .caption.weight(.semibold)
            case .large: .callout.weight(.semibold)
            }
        }
    }

    private let short: String
    private let size: Size

    public init(short: String, size: Size = .regular) {
        self.short = short
        self.size = size
    }

    public var body: some View {
        Text(short)
            .font(size.font)
            .foregroundStyle(Color.ink)
            .frame(width: size.diameter, height: size.diameter)
            .background(Color.surface, in: Circle())
            .overlay(Circle().strokeBorder(Color.hairlineStrong, lineWidth: ControlSize.hairline))
            .accessibilityHidden(true)
    }
}
