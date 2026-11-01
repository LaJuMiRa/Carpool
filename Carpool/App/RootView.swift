import CarpoolKit
import CarpoolUI
import SwiftUI

/// Schwebende Tab-Bar: Autos · Kalender · Mitglieder.
struct MainTabView: View {
    let session: AppSession
    @State private var store: FamilyStore
    @Environment(\.scenePhase) private var scenePhase

    init(session: AppSession, member: Member) {
        self.session = session
        _store = State(initialValue: FamilyStore(member: member, api: session.api))
    }

    var body: some View {
        TabView {
            Tab("Autos", systemImage: "car.2") {
                OverviewScreen(store: store)
            }
            Tab("Kalender", systemImage: "calendar") {
                CalendarScreen(store: store)
            }
            Tab("Mitglieder", systemImage: "person.2") {
                MembersScreen(session: session, store: store)
            }
        }
        .task { await store.start() }
        .onDisappear { store.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}
