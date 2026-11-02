import CarpoolKit
import CarpoolUI
import SwiftUI

/// Mitglieder (F15): Familienname, wer gerade fährt, Hauptnutzer, nächste Fahrt; Einladung teilen.
/// Zahnrad öffnet die Einstellungen (F16).
struct MembersScreen: View {
    let session: AppSession
    let store: FamilyStore

    @State private var path = NavigationPath()
    /// Mitglied, das nach Bestätigung entfernt wird.
    @State private var removeTarget: Member?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .background(Color.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .settings: SettingsScreen(session: session, store: store, path: $path)
                case .profile: ProfileScreen(store: store)
                case .widgets: WidgetsInfoScreen(store: store)
                case .shortcuts: ShortcutsInfoScreen()
                }
            }
        }
        .alert(store.actionError?.message ?? "", isPresented: errorBinding) {
            Button("OK", role: .cancel) { store.dismissError() }
        }
        .alert(removeTarget.map { "\($0.firstName) entfernen?" } ?? "", isPresented: removeBinding,
               presenting: removeTarget) { member in
            Button("Entfernen", role: .destructive) {
                Task { await store.perform { try await $0.removeMember(member.id) } }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { member in
            Text("\(member.firstName) sieht die Familie danach nicht mehr. Künftige Reservierungen werden gelöscht.")
        }
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } })
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let snapshot = store.snapshot {
            let state = MembersState(snapshot: snapshot, now: now, timeText: TimeText(family: snapshot.family))
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    HStack(alignment: .center) {
                        Text(state.title)
                            .screenTitleStyle()
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button { path.append(SettingsRoute.settings) } label: {
                            Image(systemName: "gearshape").font(.title3)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("Einstellungen")
                        .accessibilityIdentifier("members.settings")
                    }
                    memberList(state, isAdmin: snapshot.isAdmin)
                    inviteCard(state)
                }
                .padding(.horizontal, Spacing.page)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xl)
                .animation(Motion.resolved(Motion.crossfade, reduceMotion: reduceMotion), value: state)
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

    private func memberList(_ state: MembersState, isAdmin: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Hairline() }
                MemberRow(row: row)
                    .contextMenu { if isAdmin && !row.isMe { adminMenu(row) } }
            }
        }
        .padding(.horizontal, Spacing.m)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
    }

    @ViewBuilder
    private func adminMenu(_ row: MembersState.Row) -> some View {
        if row.isAdmin {
            Button("Admin-Rechte entfernen", systemImage: "person.badge.minus") {
                Task { await store.perform { try await $0.setRole(.member, memberID: row.member.id) } }
            }
        } else {
            Button("Zum Admin machen", systemImage: "person.badge.key") {
                Task { await store.perform { try await $0.setRole(.admin, memberID: row.member.id) } }
            }
        }
        if row.canRemove {
            Divider()
            Button("Aus der Familie entfernen", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                removeTarget = row.member
            }
        }
    }

    private func inviteCard(_ state: MembersState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mitglied einladen").font(.headline).foregroundStyle(Color.ink)
                    Text("Code eingeben oder Einladung teilen").metaStyle()
                }
                Spacer()
                Text(state.inviteCode)
                    .font(.body.monospaced().weight(.semibold))
                    .kerning(1)
                    .foregroundStyle(Color.ink)
                    .textSelection(.enabled)
                    .accessibilityLabel("Code \(state.inviteCode.map(String.init).joined(separator: " "))")
            }
            ShareLink(item: state.inviteMessage) {
                Text("Einladung teilen")
            }
            .buttonStyle(.carpoolSecondary)
            .accessibilityIdentifier("members.share")
        }
        .cardStyle()
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.actionError != nil }, set: { if !$0 { store.dismissError() } })
    }
}

/// Ziele innerhalb des Mitglieder-Tabs.
enum SettingsRoute: Hashable {
    case settings, profile, widgets, shortcuts
}

private struct MemberRow: View {
    let row: MembersState.Row

    var body: some View {
        HStack(spacing: Spacing.s) {
            Avatar(short: row.member.short, size: .large)
                .opacity(row.hasJoined ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.isMe ? "\(row.member.firstName) (du)" : row.member.firstName)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                if let detail = row.detail {
                    HStack(spacing: 6) {
                        dot
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(row.tone == .driving ? Color.statusBusy : Color.inkMuted)
                            .contentTransition(.opacity)
                    }
                }
            }
            Spacer(minLength: Spacing.xs)
            if row.isAdmin {
                Text("Admin")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: Radius.small)
                        .strokeBorder(Color.hairlineStrong, lineWidth: ControlSize.hairline))
            }
        }
        .frame(minHeight: 68)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var dot: some View {
        switch row.tone {
        case .driving: Circle().fill(Color.statusBusy).frame(width: 7, height: 7)
        case .car(let slot): CarDot(CarColor(slot: slot))
        case .plain: EmptyView()
        }
    }
}
