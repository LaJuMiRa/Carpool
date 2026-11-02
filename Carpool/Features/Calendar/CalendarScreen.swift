import CarpoolKit
import CarpoolUI
import SwiftUI

/// Kalender (F10/F11): Woche mit Punkten je Auto, Buchungen des gewählten Tags, Kontextmenü
/// (Bearbeiten, Verlängern, An jemand übergeben, Löschen, Übernehmen). Vergangene Tage zeigen
/// auch abgeschlossene Fahrten. Woche blättern und Tag antippen ohne Animation.
struct CalendarScreen: View {
    let store: FamilyStore

    /// Gewählter Tag; nil = heute.
    @State private var selectedDay: Date?
    @State private var reservationDay: ReservationDay?
    @State private var displaceTarget: DisplaceTarget?
    @State private var editTarget: Booking?
    @State private var transferTarget: TransferTarget?
    /// Laufende Fahrten, deren Icon schon eingefahren ist (nur einmal beim Öffnen).
    @State private var drivenIn: Set<UUID> = []
    @State private var reserved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct ReservationDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    private struct TransferTarget: Identifiable {
        let booking: Booking
        let member: Member
        var id: String { "\(booking.id)-\(member.id)" }
    }

    /// Buchung, die übernommen werden soll; `noReplacement` = zweite Bestätigung.
    private struct DisplaceTarget: Identifiable {
        let entry: CalendarState.Entry
        let noReplacement: Bool
        var id: String { "\(entry.id)-\(noReplacement)" }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .background(Color.paper)
        .sheet(item: $reservationDay) { day in
            if let snapshot = store.snapshot {
                ReservationSheet(snapshot: snapshot, api: store.api, day: day.date) {
                    reserved.toggle()
                    Task { await store.refresh() }
                }
            }
        }
        .sheet(item: $displaceTarget) { target in displaceSheet(target) }
        .sheet(item: $editTarget) { booking in
            if let snapshot = store.snapshot {
                ReservationSheet(snapshot: snapshot, api: store.api, editing: booking) {
                    reserved.toggle()
                    Task { await store.refresh() }
                }
            }
        }
        .alert(transferTarget.map { "Reservierung an \($0.member.firstName) übergeben?" } ?? "",
               isPresented: transferBinding, presenting: transferTarget) { target in
            Button("An \(target.member.firstName) übergeben") {
                Task {
                    await store.perform { try await $0.transferBooking(target.booking.id, to: target.member.id) }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { target in
            Text("\(target.member.firstName) bekommt eine Nachricht. Danach gehört die Reservierung nicht mehr dir.")
        }
        .alert(store.actionError?.message ?? "", isPresented: errorBinding) {
            Button("OK", role: .cancel) { store.dismissError() }
        }
        .sensoryFeedback(.success, trigger: reserved)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let snapshot = store.snapshot {
            let text = TimeText(family: snapshot.family)
            let state = CalendarState(snapshot: snapshot, history: store.history, selectedDay: selectedDay ?? now,
                                      now: now, timeText: text)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header(state, now: now)
                    WeekStrip(days: state.week) { selectedDay = $0 } onSwipe: { weeks in
                        selectedDay = CalendarState.day(state.selectedDay, movedByWeeks: weeks, timeText: text)
                    }
                    dayList(state)
                        .id(state.selectedDay)
                }
                .padding(.horizontal, Spacing.page)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .refreshable { await store.refresh() }
            .task(id: state.week.first?.date) {
                guard let start = state.week.first?.date,
                      let end = text.weekCalendar.date(byAdding: .day, value: 7, to: start) else { return }
                await store.showHistory(from: start, to: end)
            }
        } else if let error = store.loadError {
            MessageScreen(text: error.message, actionTitle: "Erneut versuchen") {
                Task { await store.refresh() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ state: CalendarState, now: Date) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(state.title)
                .sheetTitleStyle()
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Heute") { selectedDay = nil }
                .buttonStyle(.glass)
                .controlSize(.large)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("calendar.today")
            Button { reservationDay = ReservationDay(date: state.selectedDay) } label: {
                // Eigene Farbe für das Zeichen: in Dunkel ist `ink` hell, Weiß darauf wäre unsichtbar.
                Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(Color.onInk)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(Color.ink)
            .accessibilityLabel("Reservieren")
            .accessibilityIdentifier("calendar.reserve")
        }
    }

    private func dayList(_ state: CalendarState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(state.dayTitle)
                .font(.title3.bold())
                .foregroundStyle(Color.ink)
                .padding(.bottom, Spacing.xxs)
                .accessibilityAddTraits(.isHeader)
            if state.entries.isEmpty {
                Text("Nichts reserviert.")
                    .font(.callout)
                    .foregroundStyle(Color.inkMuted)
                    .padding(.top, Spacing.xs)
            }
            ForEach(state.entries) { entry in
                row(entry)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(Motion.resolved(Motion.appear, reduceMotion: reduceMotion), value: state.entries.map(\.id))
    }

    private func row(_ entry: CalendarState.Entry) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Text(entry.startLabel)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.inkMuted)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 14)
                .accessibilityHidden(true)
            BookingBlock(time: entry.timeText, carName: entry.car.title, personShort: entry.personShort,
                         color: CarColor(slot: entry.car.colorSlot),
                         marker: entry.isDriving ? .driving : (entry.isRepeating ? .repeating : .none),
                         driveAnimation: driveAnimation(for: entry))
                .opacity(entry.isPast ? 0.55 : 1)
                .accessibilityLabel(entry.accessibilityText)
                .contextMenu { menu(for: entry) }
                .onAppear { if entry.isDriving { drivenIn.insert(entry.id) } }
        }
    }

    /// Einstellung „Fahrendes Auto": einmal beim ersten Erscheinen, dauerhaft oder aus.
    private func driveAnimation(for entry: CalendarState.Entry) -> BookingBlock.DriveAnimation {
        guard entry.isDriving else { return .none }
        switch store.settings?.calendarCarAnimation ?? .once {
        case .once: return drivenIn.contains(entry.id) ? .none : .once
        case .loop: return .loop
        case .off: return .none
        }
    }

    @ViewBuilder
    private func menu(for entry: CalendarState.Entry) -> some View {
        if entry.canCancel {
            Button("Bearbeiten", systemImage: "pencil") { editTarget = entry.booking }
        }
        if entry.canExtend, let snapshot = store.snapshot {
            Menu("Verlängern", systemImage: "clock") {
                ForEach(BookingExtension.options(for: entry.booking, now: .now,
                                                 text: TimeText(family: snapshot.family))) { option in
                    Button(option.title) { Task { await store.extend(entry.booking, to: option.endsAt) } }
                }
            }
        }
        if entry.canCancel, let snapshot = store.snapshot {
            Menu("An jemand übergeben", systemImage: "arrow.right") {
                ForEach(BookingExtension.transferTargets(in: snapshot)) { member in
                    Button(member.firstName) { transferTarget = TransferTarget(booking: entry.booking, member: member) }
                }
            }
        }
        if entry.canCancel {
            Divider()
            if entry.isRepeating {
                Button("Nur diesen Termin löschen", systemImage: "trash", role: .destructive) {
                    Task { await store.cancel(entry.booking, wholeSeries: false) }
                }
                Button("Diesen und alle folgenden löschen", systemImage: "trash", role: .destructive) {
                    Task { await store.cancel(entry.booking, wholeSeries: true) }
                }
            } else {
                Button("Löschen", systemImage: "trash", role: .destructive) {
                    Task { await store.cancel(entry.booking, wholeSeries: false) }
                }
            }
        }
        if entry.canDisplace {
            Button("Übernehmen", systemImage: "arrow.uturn.backward", role: .destructive) {
                displaceTarget = DisplaceTarget(entry: entry, noReplacement: false)
            }
        }
    }

    // MARK: Übernehmen

    @ViewBuilder
    private func displaceSheet(_ target: DisplaceTarget) -> some View {
        let conflicts = [ReservationConflict(booking: target.entry.booking, firstName: target.entry.personName,
                                             canDisplace: true)]
        if target.noReplacement {
            DisplaceConfirmSheet(noReplacementFor: conflicts) { displace(target, accept: true) }
        } else if let snapshot = store.snapshot {
            DisplaceConfirmSheet(conflicts: conflicts, car: target.entry.car, now: .now,
                                 text: TimeText(family: snapshot.family)) {
                displace(target, accept: false)
            }
        }
    }

    private func displace(_ target: DisplaceTarget, accept: Bool) {
        displaceTarget = nil
        Task {
            let result = await store.displace(target.entry.booking, acceptNoReplacement: accept)
            if result == .noReplacement {
                displaceTarget = DisplaceTarget(entry: target.entry, noReplacement: true)
            }
        }
    }

    private var transferBinding: Binding<Bool> {
        Binding(get: { transferTarget != nil }, set: { if !$0 { transferTarget = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.actionError != nil }, set: { if !$0 { store.dismissError() } })
    }
}

/// Wochenleiste: Wochentag, Datum, Punkte je Auto mit Buchung. Wischen blättert eine Woche.
private struct WeekStrip: View {
    let days: [CalendarState.Day]
    let onSelect: (Date) -> Void
    let onSwipe: (Int) -> Void

    /// Ab dieser Wischweite wird geblättert.
    private static let swipeThreshold: CGFloat = 50

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(days) { day in
                Button { onSelect(day.date) } label: { label(day) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityText(day))
                    .accessibilityAddTraits(day.isSelected ? .isSelected : [])
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.width < -Self.swipeThreshold { onSwipe(1) }
            if value.translation.width > Self.swipeThreshold { onSwipe(-1) }
        })
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Nächste Woche") { onSwipe(1) }
        .accessibilityAction(named: "Vorige Woche") { onSwipe(-1) }
    }

    private func label(_ day: CalendarState.Day) -> some View {
        VStack(spacing: 6) {
            Text(day.weekday)
                .font(.caption2.weight(day.isSelected ? .semibold : .regular))
                .foregroundStyle(day.isSelected ? Color.ink : Color.inkMuted)
            Text(day.number)
                .font(.body.weight(day.isSelected || day.isToday ? .semibold : .regular))
                .foregroundStyle(day.isSelected ? Color.onInk : Color.ink)
                .frame(width: 36, height: 36)
                .background(day.isSelected ? Color.ink : Color.clear, in: Circle())
                .overlay(Circle().strokeBorder(day.isToday && !day.isSelected ? Color.hairlineStrong : .clear))
            HStack(spacing: 2) {
                ForEach(day.carSlots, id: \.self) { slot in
                    Circle().fill(CarColor(slot: slot).base).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func accessibilityText(_ day: CalendarState.Day) -> String {
        let bookings = day.carSlots.isEmpty ? "keine Buchung" : "\(day.carSlots.count) Autos gebucht"
        return "\(day.weekday) \(day.number), \(day.isToday ? "heute, " : "")\(bookings)"
    }
}
