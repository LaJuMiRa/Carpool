import CarpoolUI
import SwiftUI

/// Eingabefelder flach in einer Karte, getrennt durch Linien.
struct FormCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, Spacing.m)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
    }
}

extension View {
    /// Einheitliche Höhe und Schrift für Textfelder in einer `FormCard`.
    func formFieldStyle() -> some View {
        font(.body)
            .foregroundStyle(Color.ink)
            .frame(minHeight: ControlSize.buttonHeight)
    }
}

/// Fehlertext unter einem Formular.
struct FormError: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.danger)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }
}

/// Primär-Button mit Ladeanzeige.
struct BusyButton: View {
    let title: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().tint(Color.onInk) }
            }
        }
        .buttonStyle(.carpoolPrimary)
        .accessibilityLabel(title)
    }
}
