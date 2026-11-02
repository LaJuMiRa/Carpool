import CarpoolKit
import CarpoolUI
import SwiftUI

/// Schwebende Tab-Bar: Autos · Kalender · Mitglieder.
struct MainTabView: View {
    let session: AppSession
    /// Push nur mit echtem Backend und ohne automatische Test-Anmeldung (sonst stört die Rückfrage).
    let usesPush: Bool
    /// Beispiel-Familie (`-previewFamily`): nichts auf das Gerät schreiben – keine Widgets, keine
    /// Live-Aktivität, keine gespiegelten Einstellungen. Sonst bleiben Beispieldaten auf dem Gerät, und
    /// das Ende der Live-Aktivität startet die App ohne Startargumente neu.
    let isPreview: Bool
    @State private var store: FamilyStore
    @Environment(AppRouter.self) private var router
    @Environment(PushRegistration.self) private var push
    @Environment(\.scenePhase) private var scenePhase

    init(session: AppSession, member: Member, isPreview: Bool = false) {
        self.session = session
        self.isPreview = isPreview
        self.usesPush = !isPreview && PushRegistration.promptAllowed
        _store = State(initialValue: FamilyStore(member: member, api: session.api))
    }

    var body: some View {
        TabView(selection: Bindable(router).tab) {
            Tab("Autos", systemImage: "car.2", value: AppTab.cars) {
                OverviewScreen(store: store)
            }
            Tab("Kalender", systemImage: "calendar", value: AppTab.calendar) {
                CalendarScreen(store: store)
            }
            Tab("Mitglieder", systemImage: "person.2", value: AppTab.members) {
                MembersScreen(session: session, store: store)
            }
        }
        .task { await store.start() }
        .task { if usesPush { await push.start(api: session.api) } }
        .onChange(of: store.snapshot) { _, snapshot in
            // Widgets und Live-Aktivität folgen jeder Änderung (auch per Realtime).
            if let snapshot, !isPreview { Task { await QuickAccessSync.update(snapshot) } }
        }
        .onChange(of: store.settings?.launchAnimation) { _, mode in
            // Der Splash läuft vor dem Laden der Einstellungen; deshalb auf dem Gerät merken.
            if let mode, !isPreview { LaunchSplashStore().mode = mode }
        }
        .onDisappear { store.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}
