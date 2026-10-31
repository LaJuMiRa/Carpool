import CarpoolKit
import CarpoolUI
import SwiftUI

/// Übersicht (F02/F04/F07): Titel „x von n frei", eigene Fahrt, alle anderen Autos.
struct OverviewScreen: View {
    let store: FamilyStore

    @State private var returnTrip: OverviewState.MyTrip?
    @State private var appIsActive = true
    @Namespace private var carSpace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// So lange bleibt der Rückgängig-Hinweis sichtbar (nur während die App aktiv ist).
    private static let undoDuration: Duration = .seconds(5)

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .background(Color.paper)
        .safeAreaInset(edge: .bottom) { undoToast }
        .sheet(item: $returnTrip) { trip in
            ReturnSheet(trip: trip) { fuel in
                Task { await store.returnCar(trip.car, fuel: fuel) }
            }
        }
        .alert(store.actionError?.message ?? "", isPresented: errorBinding) {
            Button("OK", role: .cancel) { store.dismissError() }
        }
        .sensoryFeedback(.success, trigger: store.undoOffer?.id) { _, new in new != nil }
        .onChange(of: scenePhase) { _, phase in appIsActive = phase == .active }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let snapshot = store.snapshot {
            let state = OverviewState(snapshot: snapshot, now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text(state.title)
                        .screenTitleStyle()
                        .contentTransition(.numericText())
                        .accessibilityAddTraits(.isHeader)
                    if let trip = state.myTrip {
                        MyTripCard(trip: trip, namespace: carSpace) { returnTrip = trip }
                            .transition(.opacity)
                        if !state.rows.isEmpty { SectionHeader("Andere Autos") }
                    }
                    carList(state.rows)
                }
                .padding(.horizontal, Spacing.page)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xl)
                .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion), value: state)
            }
            .refreshable { await store.refresh() }
        } else if let error = store.loadError {
            MessageScreen(text: error.message, actionTitle: "Erneut versuchen") {
                Task { await store.refresh() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func carList(_ rows: [OverviewState.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Hairline() }
                CarRow(naming: row.car.naming, paint: row.car.paint, status: row.status,
                       statusText: row.statusText, detail: row.detail,
                       silhouetteID: row.car.id, namespace: carSpace) {
                    if row.canTake {
                        Button("Nehmen") { Task { await store.take(row.car) } }
                            .buttonStyle(.carpoolCompact)
                            .accessibilityLabel("\(row.car.title) nehmen")
                            .accessibilityIdentifier("take.\(row.car.title)")
                    }
                }
                .transition(.opacity)
                .animation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion)
                    .delay(Double(index) * 0.04), value: rows.map(\.id))
            }
        }
    }

    @ViewBuilder
    private var undoToast: some View {
        if let offer = store.undoOffer {
            UndoToast(text: offer.text) {
                Task { await store.undo() }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xs)
            .transition(.undoToast(reduceMotion: reduceMotion))
            .task(id: offer.id) { await expire(offer) }
        }
    }

    /// Zählt nur, solange die App im Vordergrund ist.
    private func expire(_ offer: FamilyStore.UndoOffer) async {
        let step = Duration.milliseconds(100)
        var remaining = Self.undoDuration
        while remaining > .zero {
            try? await Task.sleep(for: step)
            if Task.isCancelled { return }
            if appIsActive { remaining -= step }
        }
        withAnimation { store.dismissUndo(offer) }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.actionError != nil }, set: { if !$0 { store.dismissError() } })
    }
}

extension Car {
    var naming: CarNaming { CarNaming(make: make, model: model, nickname: nickname) }
}

#Preview {
    let store = FamilyStore(member: PreviewAPI.lisa, api: PreviewAPI())
    OverviewScreen(store: store).task { await store.refresh() }
}
