import SwiftUI

/// Buchung im Kalender: Fläche in Autofarbe (tint), Text in car-ink.
public struct BookingBlock: View {
    public enum Marker { case none, driving, repeating }

    private let time: String
    private let carName: String
    private let personShort: String
    private let personName: String?
    private let color: CarColor
    private let marker: Marker

    /// - Parameters:
    ///   - time: „08:00–17:30" oder „seit 09:12".
    ///   - personName: zweite Zeile, z. B. „Papa, jede Woche"; sonst der Autoname.
    public init(time: String, carName: String, personShort: String, personName: String? = nil,
                color: CarColor, marker: Marker = .none) {
        self.time = time
        self.carName = carName
        self.personShort = personShort
        self.personName = personName
        self.color = color
        self.marker = marker
    }

    public var body: some View {
        HStack(spacing: Spacing.s) {
            Avatar(short: personShort, size: .small)
            VStack(alignment: .leading, spacing: 1) {
                Text(time).font(.headline).foregroundStyle(color.ink)
                Text(personName ?? carName).font(.subheadline).foregroundStyle(color.ink.opacity(0.85))
            }
            Spacer(minLength: Spacing.xs)
            switch marker {
            case .none: EmptyView()
            case .driving:
                Image(systemName: "car.side")
                    .font(.body)
                    .foregroundStyle(color.ink)
                    .accessibilityLabel("fährt gerade")
            case .repeating:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(color.ink)
                    .accessibilityLabel("wiederholt sich")
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.tint, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Hinweis mit Person in Autofarbe oder Statusfarbe („Jonas braucht ihn ab 18:00").
public struct InfoBanner<Content: View>: View {
    private let personShort: String?
    private let text: String
    private let background: Color
    private let foreground: Color
    private let content: Content

    public init(personShort: String?, text: String, background: Color, foreground: Color,
                @ViewBuilder content: () -> Content) {
        self.personShort = personShort
        self.text = text
        self.background = background
        self.foreground = foreground
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                if let personShort {
                    Avatar(short: personShort, size: .small)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                }
                Text(text).font(.callout).foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.small + 2, style: .continuous))
    }
}

public extension InfoBanner where Content == EmptyView {
    init(personShort: String?, text: String, color: CarColor) {
        self.init(personShort: personShort, text: text, background: color.tint, foreground: color.ink) {
            EmptyView()
        }
    }
}
