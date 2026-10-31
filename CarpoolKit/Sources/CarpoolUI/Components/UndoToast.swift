import SwiftUI

/// Hinweis nach Nehmen/Zurückgeben mit „Rückgängig" (F07). Schwebt über der Tab-Bar.
public struct UndoToast: View {
    private let text: String
    private let onUndo: () -> Void

    public init(text: String, onUndo: @escaping () -> Void) {
        self.text = text
        self.onUndo = onUndo
    }

    public var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "checkmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.statusFree)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Rückgängig", action: onUndo)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 40)
                .background(Color.hairline, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityIdentifier("undo")
        }
        .padding(.leading, Spacing.m)
        .padding(.trailing, Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }
}

public extension AnyTransition {
    /// 250 ms von unten herein, 200 ms auf demselben Weg hinaus; bei „Bewegung reduzieren" nur Überblenden.
    static func undoToast(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity.animation(.easeOut(duration: 0.15)) }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).animation(.easeOut(duration: 0.25)),
            removal: .move(edge: .bottom).combined(with: .opacity).animation(.easeOut(duration: 0.2)))
    }
}
