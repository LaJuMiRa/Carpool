import SwiftUI

/// Auswahl-Chip („Jetzt", „Morgen"). Wechsel ohne Animation.
public struct Chip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.onInk : Color.ink)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 36)
                .background(isSelected ? Color.ink : Color.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.hairlineStrong,
                                                lineWidth: ControlSize.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
