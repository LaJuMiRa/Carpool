import CarpoolKit
import SwiftUI

/// Live-Aktivität auf dem Sperrbildschirm (F08): Auto, „Du fährst seit 09:12", mitlaufende Fahrzeit,
/// Fortschritt bis zur nächsten Person, Button „Zurückgeben". Immer in dunklen Farben.
public struct TripActivityView: View {
    private let attributes: TripActivityAttributes
    private let state: TripActivityAttributes.ContentState

    public init(attributes: TripActivityAttributes, state: TripActivityAttributes.ContentState) {
        self.attributes = attributes
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: Spacing.s) {
                CarSilhouette(model: attributes.model, paint: attributes.paint)
                    .frame(width: 96, height: 43)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.carTitle).font(.headline).foregroundStyle(Color.ink)
                    Text(state.sinceText).font(.footnote).foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    TripTimer(startedAt: state.startedAt)
                        .font(.title3.bold())
                        .foregroundStyle(Color.ink)
                    Text("unterwegs").font(.caption).foregroundStyle(Color.inkSecondary)
                }
            }
            if let nextAt = state.nextAt, nextAt > state.startedAt {
                ProgressView(timerInterval: state.startedAt...nextAt, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(CarColor(slot: attributes.colorSlot).base)
                .accessibilityHidden(true)
            }
            if let next = state.nextText {
                HStack {
                    Text(state.startTime)
                    Spacer()
                    Text(next)
                }
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
            }
            Link(destination: DeepLink.returnCar.url) {
                Text("Zurückgeben")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.onInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.ink, in: Capsule())
            }
        }
        .padding(Spacing.m)
        .environment(\.colorScheme, .dark)
    }
}

/// Mitlaufende Fahrzeit, vom System aktualisiert.
public struct TripTimer: View {
    private let startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    public var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}
