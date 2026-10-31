import CarpoolKit
import CarpoolUI
import SwiftUI

/// Vorläufige Mitglieder-Seite: Familie, Mitglieder, Code, Abmelden. Ausbau in Phase 6.
struct MembersScreen: View {
    let session: AppSession
    let store: FamilyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let snapshot = store.snapshot {
                    Text(snapshot.family.name).screenTitleStyle()
                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.members.enumerated()), id: \.element.id) { index, member in
                            if index > 0 { Hairline() }
                            HStack(spacing: Spacing.s) {
                                Avatar(short: member.short, size: .large)
                                Text(member.firstName).font(.headline).foregroundStyle(Color.ink)
                                Spacer()
                                if member.role == .admin {
                                    Text("Admin").metaStyle()
                                }
                            }
                            .padding(.vertical, Spacing.s)
                        }
                    }
                    .cardStyle(padding: Spacing.m)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mitglied einladen").font(.headline).foregroundStyle(Color.ink)
                            Text("Code weitergeben").metaStyle()
                        }
                        Spacer()
                        Text(snapshot.family.inviteCode)
                            .font(.title3.monospaced().weight(.semibold))
                            .foregroundStyle(Color.ink)
                            .textSelection(.enabled)
                    }
                    .cardStyle()
                }
                Button("Abmelden") { Task { try? await session.signOut() } }
                    .buttonStyle(.carpoolSecondary)
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.l)
        }
        .background(Color.paper)
    }
}
