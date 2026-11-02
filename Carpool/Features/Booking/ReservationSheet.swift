import CarpoolKit
import CarpoolUI
import SwiftUI

/// Reservieren (F12): Zeitraum, Wiederholung, Auto. Ist das Auto belegt, steht direkt im Formular,
/// wer es hat, mit allen freien Autos zum Tauschen und (als Hauptnutzer) „Übernehmen".
/// Im Bearbeiten-Modus (F11 „Bearbeiten") ohne Schnellwahl und Wiederholen.
struct ReservationSheet: View {
    let onDone: () -> Void

    @State private var model: ReservationModel
    @State private var editingTime = false
    @State private var showsRepeat = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(snapshot: FamilySnapshot, api: any CarpoolAPI, day: Date, carID: UUID? = nil,
         onDone: @escaping () -> Void) {
        self.onDone = onDone
        _model = State(initialValue: ReservationModel(snapshot: snapshot, api: api, day: day, carID: carID))
    }

    /// Eigene Reservierung bearbeiten.
    init(snapshot: FamilySnapshot, api: any CarpoolAPI, editing booking: Booking, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _model = State(initialValue: ReservationModel(snapshot: snapshot, api: api, editing: booking))
        _editingTime = State(initialValue: true)
    }

    /// Eine schon laufende Reservierung behält ihren Beginn.
    private var startIsFixed: Bool {
        guard let booking = model.editing else { return false }
        return booking.startsAt <= .now
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header
                    whenSection
                    carSection
                }
                .padding(.horizontal, Spacing.page)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) { submitButton }
            .background(Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsRepeat) { RepeatScreen(model: model) }
        }
        .environment(\.timeZone, model.text.calendar.timeZone)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
        .task { model.start() }
        .sheet(isPresented: confirmationBinding) { confirmationSheet }
        .alert(model.error?.message ?? "", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.dismissError() }
        }
        .onChange(of: model.step) { _, step in
            if step == .done {
                onDone()
                dismiss()
            }
        }
    }

    // MARK: Abschnitte

    private var header: some View {
        HStack {
            Text(model.isEditing ? "Reservierung ändern" : "Reservieren")
                .font(.title.bold())
                .kerning(-0.4)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Schließen")
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Wann").sectionLabelStyle()
            if !model.isEditing { presetChips }

            VStack(spacing: 0) {
                timeRow
                if editingTime {
                    timeEditor
                }
                if !model.isEditing {
                    Hairline()
                    repeatRow
                }
            }
            .padding(.horizontal, Spacing.m)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))

            if let error = model.checkError {
                Text(error.message).font(.callout).foregroundStyle(Color.danger)
            }
        }
    }

    private var presetChips: some View {
        ScrollView(.horizontal) {
                HStack(spacing: Spacing.xs) {
                    ForEach(model.presets, id: \.self) { preset in
                        Chip(preset.title, isSelected: model.draft.preset == preset) {
                            model.select(preset)
                            editingTime = preset == .custom
                        }
                        .accessibilityLabel(preset == .custom ? "Eigener Zeitraum" : preset.title)
                    }
                }
            }
            .scrollIndicators(.hidden)
    }

    private var timeRow: some View {
        Button { editingTime.toggle() } label: {
            HStack(spacing: Spacing.s) {
                Text(model.draft.dateText(model.text)).font(.body).foregroundStyle(Color.ink)
                Spacer(minLength: Spacing.xs)
                Text(model.draft.timeText(model.text)).font(.callout).foregroundStyle(Color.inkSecondary)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Zeitraum ändern")
    }

    private var timeEditor: some View {
        VStack(spacing: 0) {
            Hairline()
            if startIsFixed {
                LabeledContent("Beginn", value: model.text.time(model.draft.startsAt))
                    .frame(minHeight: 48)
            } else {
                DatePicker("Beginn", selection: Binding(get: { model.draft.startsAt }, set: { model.setStart($0) }),
                           in: Date.now.addingTimeInterval(-5 * 60)...)
                    .frame(minHeight: 48)
            }
            Hairline()
            DatePicker("Ende", selection: Binding(get: { model.draft.endsAt }, set: { model.setEnd($0) }),
                       in: model.draft.startsAt.addingTimeInterval(5 * 60)...)
                .frame(minHeight: 48)
        }
        .font(.body)
        .foregroundStyle(Color.ink)
    }

    private var repeatRow: some View {
        Button { showsRepeat = true } label: {
            HStack(spacing: Spacing.s) {
                Text("Wiederholen").font(.body).foregroundStyle(Color.ink)
                Spacer(minLength: Spacing.xs)
                Text(model.canRepeat ? model.draft.repeatText(model.text) : "nur am selben Tag")
                    .font(.callout)
                    .foregroundStyle(model.canRepeat ? Color.inkSecondary : Color.inkMuted)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.inkMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canRepeat)
    }

    private var carSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Welches Auto").sectionLabelStyle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3),
                      spacing: Spacing.xs) {
                ForEach(model.snapshot.cars) { car in
                    let status = model.status(of: car)
                    CarTile(naming: car.naming, paint: car.paint, status: status,
                            statusText: status == .reserved ? "belegt" : nil,
                            isSelected: model.draft.carID == car.id) {
                        model.select(car: car)
                    }
                    .accessibilityIdentifier("reserve.car.\(car.title)")
                }
            }
            if let banner = model.conflictBanner {
                ConflictBannerView(banner: banner, onSwap: { model.select(car: $0) },
                                   onDisplace: { model.requestDisplace() })
                    .padding(.top, Spacing.xxs)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(Motion.resolved(Motion.expand, reduceMotion: reduceMotion), value: model.conflictBanner)
    }

    private var submitButton: some View {
        Button { Task { await model.submit() } } label: {
            Text(model.submitTitle)
                .contentTransition(.opacity)
                .animation(Motion.crossfade, value: model.submitTitle)
        }
        .buttonStyle(.carpoolPrimary)
        .disabled(!model.canSubmit)
        .accessibilityIdentifier("reserve.submit")
        .padding(.horizontal, Spacing.page)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.xs)
        .background(Color.paper)
    }

    // MARK: Übernehmen

    @ViewBuilder
    private var confirmationSheet: some View {
        if let car = model.selectedCar {
            switch model.step {
            case .confirmDisplace(let conflicts):
                DisplaceConfirmSheet(conflicts: conflicts, car: car, now: .now, text: model.text) {
                    Task { await model.confirmDisplace() }
                }
            case .confirmNoReplacement(let conflicts):
                DisplaceConfirmSheet(noReplacementFor: conflicts) {
                    Task { await model.confirmNoReplacement() }
                }
                .id("noReplacement")
            case .editing, .done:
                EmptyView()
            }
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: {
            switch model.step {
            case .confirmDisplace, .confirmNoReplacement: true
            case .editing, .done: false
            }
        }, set: { shown in
            if !shown { model.cancelConfirmation() }
        })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.error != nil }, set: { if !$0 { model.dismissError() } })
    }
}

/// Hinweis im Formular: wer das Auto hat, freie Autos zum Tauschen, optional Übernehmen.
private struct ConflictBannerView: View {
    let banner: ReservationModel.ConflictBanner
    let onSwap: (Car) -> Void
    let onDisplace: () -> Void

    var body: some View {
        let color = CarColor(slot: banner.colorSlot)
        InfoBanner(personShort: banner.personShort, text: banner.text, background: color.tint,
                   foreground: color.ink) {
            if banner.swapCars.isEmpty && !banner.canDisplace {
                Text("Kein anderes Auto ist frei.").font(.callout).foregroundStyle(color.ink)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xs) { buttons }
                VStack(spacing: Spacing.xs) { buttons }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(banner.swapCars) { car in
            Button { onSwap(car) } label: {
                HStack(spacing: 6) {
                    CarDot(CarColor(slot: car.colorSlot))
                    Text(car.title).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.carpoolCompact)
            .accessibilityLabel("Stattdessen \(car.title)")
            .accessibilityIdentifier("reserve.swap.\(car.title)")
        }
        if banner.canDisplace {
            Button(role: .destructive, action: onDisplace) {
                Text("Übernehmen").foregroundStyle(Color.danger).frame(maxWidth: .infinity)
            }
            .buttonStyle(.carpoolCompact)
            .accessibilityIdentifier("reserve.displace")
        }
    }
}
