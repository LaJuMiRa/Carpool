import CarpoolKit
import CarpoolUI
import SwiftUI

/// Auto hinzufügen (F17) bzw. bearbeiten (nur Admins). Marke und Modell in einem Feld,
/// Fahrzeugbild erscheint live in der gewählten Farbe.
struct CarFormSheet: View {
    let store: FamilyStore
    let snapshot: FamilySnapshot
    let car: Car?

    @State private var form: CarForm
    @State private var isSaving = false
    @State private var confirmsRemove = false
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: TimeText { TimeText(family: snapshot.family) }

    init(store: FamilyStore, snapshot: FamilySnapshot, car: Car?) {
        self.store = store
        self.snapshot = snapshot
        self.car = car
        let calendar = TimeText(family: snapshot.family).calendar
        _form = State(initialValue: car.map { CarForm(car: $0, calendar: calendar) } ?? CarForm())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                field("Marke und Modell", hint: form.nameHint) {
                    TextField("z. B. VW Golf", text: $form.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($nameFocused)
                        .accessibilityIdentifier("car.name")
                }
                preview
                field("Spitzname (optional)") {
                    TextField("Wie nennt ihr ihn?", text: $form.nickname)
                        .accessibilityIdentifier("car.nickname")
                }
                primaryPicker
                field("Kennzeichen (optional)") {
                    TextField("z. B. W-12345A", text: $form.plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                if car != nil { conditionFields }
                Button(car == nil ? "Hinzufügen" : "Speichern", action: save)
                    .buttonStyle(.carpoolPrimary)
                    .disabled(isSaving || form.input(calendar: text.calendar) == nil)
                    .accessibilityIdentifier("car.save")
                if car != nil {
                    Button("Auto entfernen", role: .destructive) { confirmsRemove = true }
                        .buttonStyle(.carpoolDestructive)
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.paper)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
        .onAppear { if car == nil { nameFocused = true } }
        .confirmationDialog("\(car?.title ?? "Auto") entfernen?", isPresented: $confirmsRemove,
                            titleVisibility: .visible) {
            Button("Entfernen", role: .destructive, action: remove)
        } message: {
            Text("Das Auto verschwindet aus Übersicht und Kalender.")
        }
        .storeErrorAlert(store)
    }

    // MARK: Teile

    private var header: some View {
        HStack {
            Text(car == nil ? "Auto hinzufügen" : "Auto bearbeiten")
                .font(.title.bold())
                .kerning(-0.4)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Abbrechen") { dismiss() }
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
        }
    }

    /// Fahrzeugbild in Lackfarbe; erscheint mit Überblenden und Unschärfe (300 ms).
    private var preview: some View {
        VStack(spacing: Spacing.s) {
            let hasModel = !form.previewModel.trimmingCharacters(in: .whitespaces).isEmpty
            CarSilhouette(model: form.previewModel, paint: form.paint)
                .frame(width: 240, height: 108)
                .opacity(hasModel ? 1 : 0.25)
                .blur(radius: hasModel || reduceMotion ? 0 : 6)
                .animation(.easeOut(duration: 0.3), value: hasModel)
                .accessibilityHidden(true)
            HStack(spacing: Spacing.s) {
                ForEach(CarForm.paints, id: \.self) { paint in
                    paintSwatch(paint)
                }
            }
            Text("Farbe wählen, damit das Bild zu eurem Auto passt").metaStyle()
        }
        .frame(maxWidth: .infinity)
    }

    private func paintSwatch(_ paint: String) -> some View {
        let selected = form.paint.lowercased() == paint
        return Button { form.paint = paint } label: {
            Circle()
                .fill(PaintColor.color(for: paint))
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Color.hairlineStrong, lineWidth: selected ? 0 : 1))
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Color.ink : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(paint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var primaryPicker: some View {
        field("Hauptnutzer (optional)") {
            Picker("Hauptnutzer", selection: $form.primaryMemberId) {
                Text("Niemand").tag(UUID?.none)
                ForEach(snapshot.members) { member in
                    Text(member.firstName).tag(UUID?.some(member.id))
                }
            }
            .pickerStyle(.menu)
            .tint(Color.ink)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var conditionFields: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader("Zustand")
            FormCard {
                optionalDate("Pickerl bis", $form.pickerlUntil)
                Hairline()
                optionalDate("Service fällig", $form.serviceDue)
                Hairline()
                HStack {
                    Text("Kilometerstand")
                    TextField("optional", value: $form.odometerKm, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .formFieldStyle()
            }
        }
    }

    private func optionalDate(_ title: String, _ date: Binding<Date?>) -> some View {
        HStack {
            Toggle(title, isOn: Binding(get: { date.wrappedValue != nil }, set: { on in
                date.wrappedValue = on ? text.calendar.startOfDay(for: .now) : nil
            }))
            .tint(Color.statusFree)
            .fixedSize()
            Spacer()
            if let value = date.wrappedValue {
                DatePicker(title, selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .formFieldStyle()
    }

    /// Beschriftetes Eingabefeld wie im Mockup: Label darüber, Feld mit Rand.
    private func field<Content: View>(_ label: String, hint: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabelStyle()
            content()
                .font(.body)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: ControlSize.buttonHeight)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.hairlineStrong, lineWidth: ControlSize.hairline))
            if let hint { Text(hint).metaStyle() }
        }
    }

    // MARK: Aktionen

    private func save() {
        guard let input = form.input(calendar: text.calendar) else { return }
        isSaving = true
        Task {
            let ok = await store.perform { [car, familyID = snapshot.family.id] api in
                if let car {
                    try await api.updateCar(car.id, input: input)
                } else {
                    try await api.addCar(input, familyID: familyID)
                }
            }
            isSaving = false
            if ok { dismiss() }
        }
    }

    private func remove() {
        guard let car else { return }
        Task {
            if await store.perform({ try await $0.archiveCar(car.id) }) { dismiss() }
        }
    }
}
