import ActivityKit
import CarpoolKit
import OSLog
import WidgetKit

/// Hält Widgets und Live-Aktivität auf dem Stand der App: speichert den Snapshot für die Widgets,
/// lädt ihre Zeitleisten neu und startet, aktualisiert oder beendet die Live-Aktivität der eigenen Fahrt.
@MainActor
enum QuickAccessSync {
    private nonisolated static let log = Logger(subsystem: "at.rauscher.carpool", category: "quick-access")

    static func update(_ snapshot: FamilySnapshot, now: Date = .now) async {
        do {
            try SharedSnapshotStore.shared?.save(snapshot)
        } catch {
            log.error("Snapshot für Widgets nicht gespeichert: \(error.localizedDescription, privacy: .public)")
        }
        WidgetCenter.shared.reloadAllTimelines()
        let text = TimeText(family: snapshot.family)
        await syncActivity(trip: OverviewState(snapshot: snapshot, now: now, timeText: text).myTrip,
                           now: now, text: text)
    }

    /// Beim Abmelden: nichts mehr von der Familie zeigen.
    static func clear() async {
        SharedSnapshotStore.shared?.clear()
        WidgetCenter.shared.reloadAllTimelines()
        await syncActivity(trip: nil, now: .now, text: TimeText())
    }

    private nonisolated static func syncActivity(trip: OverviewState.MyTrip?, now: Date, text: TimeText) async {
        let activities = Activity<TripActivityAttributes>.activities
        for activity in activities where activity.attributes.bookingID != trip?.bookingID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let trip else { return }

        let state = TripActivityAttributes.ContentState(trip: trip, now: now, timeText: text)
        if let current = activities.first(where: { $0.attributes.bookingID == trip.bookingID }) {
            if current.content.state != state {
                await current.update(ActivityContent(state: state, staleDate: nil))
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: TripActivityAttributes(trip: trip),
                                     content: ActivityContent(state: state, staleDate: nil))
        } catch {
            log.error("Live-Aktivität nicht gestartet: \(error.localizedDescription, privacy: .public)")
        }
    }
}
