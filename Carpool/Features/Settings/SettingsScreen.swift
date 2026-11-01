import CarpoolKit
import CarpoolUI
import SwiftUI

/// Erscheinungsbild, nur auf diesem Gerät gespeichert.
enum Appearance: String, CaseIterable {
    case system, light, dark

    static let storageKey = "appearance"

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Einstellungen (F16): Profil, Familie (Admin), Autos, Benachrichtigungen, Darstellung, Abmelden.
struct SettingsScreen: View {
    let session: AppSession
    let store: FamilyStore
    @Binding var path: NavigationPath

    @State private var carSheet: CarSheet?
    @State private var confirmsNewCode = false
    @State private var familyName = ""
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system.rawValue

    /// Auto anlegen oder bearbeiten.
    enum CarSheet: Identifiable {
        case add
        case edit(Car)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let car): car.id.uuidString
            }
        }
    }

    var body: some View {
        ScrollView {
            if let snapshot = store.snapshot {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text("Einstellungen").screenTitleStyle().accessibilityAddTraits(.isHeader)
                    profileSection(snapshot)
                    if snapshot.isAdmin { familySection(snapshot) }
                    carsSection(snapshot)
                    if let settings = store.settings {
                        notificationSection(settings)
                        displaySection(settings)
                    }
                    Button("Abmelden", role: .destructive) { Task { try? await session.signOut() } }
                        .font(.body)
                        .foregroundStyle(Color.danger)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, Spacing.m)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card,
                                                                        style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.signOut")
                }
                .padding(.horizontal, Spacing.page)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xl)
                .onAppear { familyName = snapshot.family.name }
            }
        }
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $carSheet) { sheet in
            if let snapshot = store.snapshot {
                switch sheet {
                case .add: CarFormSheet(store: store, snapshot: snapshot, car: nil)
                case .edit(let car): CarFormSheet(store: store, snapshot: snapshot, car: car)
                }
            }
        }
        .confirmationDialog("Neuen Einladungscode erstellen?", isPresented: $confirmsNewCode,
                            titleVisibility: .visible) {
            Button("Neuen Code erstellen", role: .destructive) {
                Task { await store.perform { _ = try await $0.regenerateInviteCode() } }
            }
        } message: {
            Text("Der alte Code funktioniert dann nicht mehr.")
        }
    }

    // MARK: Abschnitte

    private func profileSection(_ snapshot: FamilySnapshot) -> some View {
        SettingsGroup("Profil") {
            Button { path.append(SettingsRoute.profile) } label: {
                HStack(spacing: Spacing.s) {
                    Avatar(short: snapshot.me.short, size: .large)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snapshot.me.firstName).font(.headline).foregroundStyle(Color.ink)
                        Text("Kürzel „\(snapshot.me.short)“").metaStyle()
                    }
                    Spacer()
                    Chevron()
                }
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.profile")
        }
    }

    private func familySection(_ snapshot: FamilySnapshot) -> some View {
        SettingsGroup("Familie") {
            HStack {
                Text("Name").foregroundStyle(Color.ink)
                TextField("Familienname", text: $familyName)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Color.inkSecondary)
                    .submitLabel(.done)
                    .onSubmit { saveFamilyName(snapshot) }
            }
            .frame(minHeight: 48)
            Hairline()
            Button { confirmsNewCode = true } label: {
                HStack {
                    Text("Neuer Einladungscode").foregroundStyle(Color.ink)
                    Spacer()
                    Text(snapshot.family.inviteCode).font(.body.monospaced()).foregroundStyle(Color.inkMuted)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func carsSection(_ snapshot: FamilySnapshot) -> some View {
        SettingsGroup("Autos") {
            ForEach(Array(snapshot.cars.enumerated()), id: \.element.id) { index, car in
                if index > 0 { Hairline() }
                Button { carSheet = .edit(car) } label: {
                    HStack(spacing: Spacing.xs) {
                        CarDot(CarColor(slot: car.colorSlot))
                        Text(car.title).foregroundStyle(Color.ink)
                        Spacer()
                        Text(car.nickname == nil ? car.make : "\(car.make) \(car.model)")
                            .font(.callout).foregroundStyle(Color.inkMuted)
                        if snapshot.isAdmin { Chevron() }
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!snapshot.isAdmin)
            }
            if snapshot.isAdmin {
                if !snapshot.cars.isEmpty { Hairline() }
                Button { carSheet = .add } label: {
                    Label("Auto hinzufügen", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.addCar")
            }
        }
    }

    private func notificationSection(_ settings: MemberSettings) -> some View {
        SettingsGroup("Benachrichtigungen") {
            toggle("Auto wieder frei", settings, \.notifyCarFree)
            Hairline()
            toggle("Meine Buchung wurde übernommen", settings, \.notifyBookingDisplaced)
            Hairline()
            toggle("Reservierung beginnt bald", settings, \.notifyReservationSoon)
            Hairline()
            toggle("Rückgabe überfällig", settings, \.notifyReturnOverdue)
            Hairline()
            toggle("Service und Pickerl", settings, \.notifyServicePickerl)
        }
    }

    private func displaySection(_ settings: MemberSettings) -> some View {
        SettingsGroup("Darstellung") {
            pickerRow("Erscheinungsbild", selection: $appearance,
                      options: Appearance.allCases.map { ($0.rawValue, $0.title) })
            Hairline()
            pickerRow("Startanimation", selection: binding(settings, \.launchAnimation),
                      options: MemberSettings.LaunchAnimation.allCases.map { ($0, $0.title) })
            Hairline()
            pickerRow("Fahrendes Auto", subtitle: "Im Kalender bei laufenden Fahrten",
                      selection: binding(settings, \.calendarCarAnimation),
                      options: MemberSettings.CarAnimation.allCases.map { ($0, $0.title) })
        }
    }

    // MARK: Hilfen

    private func toggle(_ title: String, _ settings: MemberSettings,
                        _ key: WritableKeyPath<MemberSettings, Bool>) -> some View {
        Toggle(title, isOn: binding(settings, key))
            .tint(Color.statusFree)
            .foregroundStyle(Color.ink)
            .frame(minHeight: 48)
    }

    private func pickerRow<Value: Hashable>(_ title: String, subtitle: String? = nil, selection: Binding<Value>,
                                            options: [(Value, String)]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).foregroundStyle(Color.ink)
                if let subtitle { Text(subtitle).metaStyle() }
            }
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu)
            .tint(Color.inkSecondary)
            .labelsHidden()
        }
        .frame(minHeight: 48)
    }

    private func binding<Value>(_ settings: MemberSettings,
                                _ key: WritableKeyPath<MemberSettings, Value>) -> Binding<Value> {
        Binding(get: { (store.settings ?? settings)[keyPath: key] }, set: { value in
            var changed = store.settings ?? settings
            changed[keyPath: key] = value
            Task { await store.update(changed) }
        })
    }

    private func saveFamilyName(_ snapshot: FamilySnapshot) {
        let name = familyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != snapshot.family.name else {
            familyName = snapshot.family.name
            return
        }
        Task { await store.perform { try await $0.renameFamily(snapshot.family.id, name: name) } }
    }
}

/// Bereich mit Überschrift und Karte voller Zeilen.
struct SettingsGroup<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title)
            VStack(spacing: 0) { content }
                .font(.body)
                .padding(.horizontal, Spacing.m)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
        }
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.inkMuted)
            .accessibilityHidden(true)
    }
}
