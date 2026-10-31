import SwiftUI

/// Inhalte flach: Fläche surface, Rand hairline, keine Schatten.
public struct CardStyle: ViewModifier {
    let padding: CGFloat

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
    }
}

public extension View {
    func cardStyle(padding: CGFloat = Spacing.card) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

/// Überschrift über einer Karte, optional mit Aktion rechts („Schäden … Melden").
public struct SectionHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).sectionLabelStyle()
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

public extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Zeile in einer Karte mit Linie darunter („Pickerl … bis März 2027").
public struct PropertyRow<Value: View>: View {
    private let label: String
    private let value: Value

    public init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    public var body: some View {
        HStack {
            Text(label).font(.body).foregroundStyle(Color.ink)
            Spacer(minLength: Spacing.s)
            value.font(.body).foregroundStyle(Color.inkSecondary)
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

public extension PropertyRow where Value == Text {
    init(_ label: String, value: String) {
        self.init(label) { Text(value) }
    }
}

/// Trennlinie zwischen Zeilen.
public struct Hairline: View {
    public init() {}

    public var body: some View {
        Rectangle().fill(Color.hairline).frame(height: ControlSize.hairline)
    }
}
