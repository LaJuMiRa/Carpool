import CarpoolKit
import CarpoolUI
import SwiftUI

/// Rückgabe (F06): einzige Eingabe ist der Tankstand, vorausgewählt der zuletzt gemeldete.
struct ReturnSheet: View {
    let trip: OverviewState.MyTrip
    let onReturn: (FuelLevel) -> Void

    @State private var fuel: FuelLevel
    @State private var contentHeight: CGFloat = 420
    @Environment(\.dismiss) private var dismiss

    init(trip: OverviewState.MyTrip, onReturn: @escaping (FuelLevel) -> Void) {
        self.trip = trip
        self.onReturn = onReturn
        _fuel = State(initialValue: trip.car.fuel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(alignment: .top, spacing: Spacing.m) {
                CarSilhouette(model: trip.car.model, paint: trip.car.paint)
                    .frame(width: 96)
                    .padding(.top, Spacing.xxs)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("\(trip.car.title) zurückgeben").sheetTitleStyle()
                    Text("Seit \(trip.sinceTime) unterwegs").font(.subheadline).foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .accessibilityLabel("Schließen")
            }

            FuelPicker(level: $fuel)

            if let next = trip.next {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Avatar(short: next.member.short)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    Text(next.returnNoteText)
                        .font(.callout)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Zurückgeben") {
                onReturn(fuel)
                dismiss()
            }
            .buttonStyle(.carpoolPrimary)
            .accessibilityIdentifier("return.confirm")
        }
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.m)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
    }
}
