import SwiftUI

/// Gemeinsames Druckverhalten: sofort auf 0.97, 120 ms.
private struct PressEffect: ViewModifier {
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? Motion.pressedScale : 1)
            .animation(Motion.press, value: isPressed)
    }
}

/// Höchstens ein Primär-Button pro Screen: ink-Fläche, 50 pt, Radius 14.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.onInk : Color.inkMuted)
            .frame(maxWidth: .infinity, minHeight: ControlSize.buttonHeight)
            .padding(.horizontal, Spacing.m)
            .background(isEnabled ? Color.ink : Color.hairline,
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .modifier(PressEffect(isPressed: configuration.isPressed))
    }
}

/// Sekundär: Fläche surface, Rand hairline-strong.
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: ControlSize.buttonHeight)
            .padding(.horizontal, Spacing.m)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairlineStrong, lineWidth: ControlSize.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .modifier(PressEffect(isPressed: configuration.isPressed))
    }
}

/// Kompakter Button in Zeilen, z. B. „Nehmen" neben einem Auto.
public struct CompactButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.ink)
            .frame(minHeight: ControlSize.compactButtonHeight)
            .padding(.horizontal, Spacing.m)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairlineStrong, lineWidth: ControlSize.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .modifier(PressEffect(isPressed: configuration.isPressed))
    }
}

/// Zerstörerische Aktion (Verdrängen): Text in danger, sonst wie sekundär.
public struct DestructiveButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.danger)
            .frame(maxWidth: .infinity, minHeight: ControlSize.buttonHeight)
            .padding(.horizontal, Spacing.m)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.danger.opacity(0.5), lineWidth: ControlSize.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .modifier(PressEffect(isPressed: configuration.isPressed))
    }
}

/// Bestätigung einer zerstörerischen Aktion im Sheet (F14 „Octavia übernehmen"): Fläche danger.
public struct DestructiveProminentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.paper)
            .frame(maxWidth: .infinity, minHeight: ControlSize.buttonHeight)
            .padding(.horizontal, Spacing.m)
            .background(Color.danger, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .modifier(PressEffect(isPressed: configuration.isPressed))
    }
}

public extension ButtonStyle where Self == DestructiveProminentButtonStyle {
    static var carpoolDestructiveProminent: DestructiveProminentButtonStyle { DestructiveProminentButtonStyle() }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var carpoolPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var carpoolSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

public extension ButtonStyle where Self == CompactButtonStyle {
    static var carpoolCompact: CompactButtonStyle { CompactButtonStyle() }
}

public extension ButtonStyle where Self == DestructiveButtonStyle {
    static var carpoolDestructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}
