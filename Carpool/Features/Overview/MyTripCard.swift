import CarpoolKit
import CarpoolUI
import SwiftUI

/// Karte „Du fährst" (F02): seit wann, Tank beim Nehmen, wer als Nächstes dran ist, Zurückgeben.
struct MyTripCard: View {
    let trip: OverviewState.MyTrip
    let namespace: Namespace.ID
    let onReturn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text(trip.sinceText).metaStyle()
                Spacer()
                if let fuel = trip.fuelOnTakeText {
                    Text(fuel).metaStyle()
                }
            }
            HStack(spacing: Spacing.m) {
                CarSilhouette(model: trip.car.model, paint: trip.car.paint)
                    .matchedGeometryEffect(id: trip.car.id, in: namespace)
                    .frame(width: 140)
                CarTitle(trip.car.naming, size: .large)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(trip.car.naming.spokenName), bei dir")
            if let next = trip.next {
                InfoBanner(personShort: next.member.short, text: next.bannerText,
                           color: CarColor(slot: trip.car.colorSlot))
            }
            Button("Zurückgeben", action: onReturn)
                .buttonStyle(.carpoolPrimary)
                .accessibilityIdentifier("trip.return")
        }
        .cardStyle()
    }
}
