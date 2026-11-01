import CarpoolKit
import CarpoolUI
import SwiftUI

/// Auto-Detail (F05): Bild, Titel, Status, Nehmen/Zurückgeben + Reservieren, Schäden,
/// nächste Buchungen, Zustand.
struct CarDetailScreen: View {
    let carID: UUID
    let store: FamilyStore
    let onReturn: (OverviewState.MyTrip) -> Void

    @State private var reservesCar: Car?
    @State private var reportsDamage = false
    @State private var shownDamage: CarDetailState.DamageRow?
    @State private var reserved = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let snapshot = store.snapshot, let car = snapshot.car(carID) {
                let text = TimeText(family: snapshot.family)
                content(CarDetailState(car: car, snapshot: snapshot, now: context.date, timeText: text),
                        snapshot: snapshot, now: context.date)
            } else {
                MessageScreen(text: CarpoolError(code: "car_not_found").message)
            }
        }
        .background(Color.paper)
        .sheet(item: $reservesCar) { car in
            if let snapshot = store.snapshot {
                ReservationSheet(snapshot: snapshot, api: store.api, day: .now, carID: car.id) {
                    reserved.toggle()
                    Task { await store.refresh() }
                }
            }
        }
        .sheet(isPresented: $reportsDamage) {
            if let car = store.snapshot?.car(carID) { DamageReportSheet(store: store, car: car) }
        }
        .sheet(item: $shownDamage) { row in DamageDetailSheet(store: store, row: row) }
        .sensoryFeedback(.success, trigger: reserved)
        .storeErrorAlert(store)
    }

    private func content(_ state: CarDetailState, snapshot: FamilySnapshot, now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                CarSilhouette(model: state.car.model, paint: state.car.paint)
                    .frame(width: 300, height: 135)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    CarDetailTitle(state.car.naming)
                    statusLine(state)
                }
                actions(state, snapshot: snapshot, now: now)
                damagesSection(state)
                if !state.upcoming.isEmpty { upcomingSection(state) }
                conditionSection(state)
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.xl)
            .animation(Motion.crossfade, value: state)
        }
        .refreshable { await store.refresh() }
    }

    private func statusLine(_ state: CarDetailState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.m) { statusParts(state) }
            VStack(alignment: .leading, spacing: Spacing.xxs) { statusParts(state) }
        }
    }

    @ViewBuilder
    private func statusParts(_ state: CarDetailState) -> some View {
        HStack(spacing: 6) {
            StatusLabel(state.status, text: state.statusText)
            if let detail = state.statusDetail {
                Text(detail).font(.footnote).foregroundStyle(Color.inkMuted)
            }
        }
        if let primary = state.primaryText {
            HStack(spacing: 6) {
                CarDot(CarColor(slot: state.car.colorSlot))
                Text(primary).font(.footnote).foregroundStyle(Color.inkMuted)
            }
        }
    }

    private func actions(_ state: CarDetailState, snapshot: FamilySnapshot, now: Date) -> some View {
        HStack(spacing: Spacing.xs) {
            if state.isMine, let trip = OverviewState(snapshot: snapshot, now: now).myTrip {
                Button("Zurückgeben") { onReturn(trip) }
                    .buttonStyle(.carpoolPrimary)
                    .accessibilityIdentifier("detail.return")
            } else if state.canTake {
                Button("Nehmen") { Task { await store.take(state.car) } }
                    .buttonStyle(.carpoolPrimary)
                    .accessibilityIdentifier("detail.take")
            }
            Button("Reservieren") { reservesCar = state.car }
                .buttonStyle(.carpoolSecondary)
                .accessibilityIdentifier("detail.reserve")
        }
    }

    private func damagesSection(_ state: CarDetailState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader("Schäden") {
                Button("Melden") { reportsDamage = true }
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                    .accessibilityLabel("Schaden melden")
                    .accessibilityIdentifier("detail.reportDamage")
            }
            if state.damages.isEmpty {
                Text("Keine offenen Schäden.").font(.callout).foregroundStyle(Color.inkMuted)
            }
            ForEach(state.damages) { row in
                Button { shownDamage = row } label: { DamageCard(store: store, row: row) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func upcomingSection(_ state: CarDetailState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader("Nächste Buchungen")
            ForEach(state.upcoming) { item in
                BookingBlock(time: item.timeText, carName: state.car.title, personShort: item.personShort,
                             personName: item.personText, color: CarColor(slot: state.car.colorSlot),
                             marker: item.isRepeating ? .repeating : .none)
            }
        }
    }

    private func conditionSection(_ state: CarDetailState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader("Zustand")
            VStack(spacing: 0) {
                PropertyRow("Tank") { FuelGauge(state.car.fuel) }
                ForEach(state.conditions, id: \.label) { condition in
                    Hairline()
                    PropertyRow(condition.label) {
                        Text(condition.value).foregroundStyle(color(condition.tone))
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
        }
    }

    private func color(_ tone: CarDetailState.Tone) -> Color {
        switch tone {
        case .normal: .inkSecondary
        case .warning: .statusReserved
        case .danger: .danger
        }
    }
}

/// Schaden in der Liste: Foto, Beschreibung mit Warn-Icon, Melder und Datum.
private struct DamageCard: View {
    let store: FamilyStore
    let row: CarDetailState.DamageRow

    var body: some View {
        HStack(spacing: Spacing.s) {
            DamagePhoto(store: store, path: row.damage.photoPath)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Label(row.damage.description, systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.danger)
                    .lineLimit(2)
                Text(row.meta).metaStyle()
            }
            Spacer(minLength: 0)
            Chevron()
        }
        .padding(Spacing.s)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schaden: \(row.damage.description), \(row.meta)")
    }
}
