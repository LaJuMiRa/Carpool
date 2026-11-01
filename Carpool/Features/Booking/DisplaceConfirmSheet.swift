import CarpoolKit
import CarpoolUI
import SwiftUI

/// Bestätigung vor dem Übernehmen (F14) bzw. Warnung ohne Ersatzauto. Ernste Aktion: keine Zier-Animation,
/// beim Bestätigen Haptik „Warnung".
struct DisplaceConfirmSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void

    @State private var contentHeight: CGFloat = 320
    @State private var confirmed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(title)
                .font(.title.bold())
                .kerning(-0.4)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Spacing.xxs) {
                Button(confirmTitle) {
                    confirmed = true
                    onConfirm()
                }
                .buttonStyle(.carpoolDestructiveProminent)
                .accessibilityIdentifier("displace.confirm")
                Button("Abbrechen") { dismiss() }
                    .font(.body)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.s)
        .sensoryFeedback(.warning, trigger: confirmed) { _, new in new }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }
}

extension DisplaceConfirmSheet {
    /// Erste Bestätigung: „Felix’ Buchung übernehmen?" … „Octavia übernehmen".
    init(conflicts: [ReservationConflict], car: Car, now: Date, text: TimeText, onConfirm: @escaping () -> Void) {
        self.init(title: ReservationTexts.displaceTitle(conflicts),
                  message: ReservationTexts.displaceMessage(conflicts, now: now, text: text),
                  confirmTitle: "\(car.title) übernehmen", onConfirm: onConfirm)
    }

    /// Zweite Bestätigung, wenn kein Ersatzauto frei ist.
    init(noReplacementFor conflicts: [ReservationConflict], onConfirm: @escaping () -> Void) {
        self.init(title: "Kein Ersatzauto frei",
                  message: ReservationTexts.noReplacementMessage(conflicts) + " Willst du trotzdem übernehmen?",
                  confirmTitle: "Trotzdem übernehmen", onConfirm: onConfirm)
    }
}
