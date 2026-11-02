import CarpoolKit
import CarpoolUI
import SwiftUI
import WidgetKit

/// Eintrag der Zeitleiste: Zustand zu einem Zeitpunkt, nil = noch nie angemeldet.
struct FamilyEntry: TimelineEntry {
    let date: Date
    let state: WidgetState?
}

/// Liest den letzten Stand, den die App gespeichert hat, und rechnet ihn für jede Buchungsgrenze
/// der nächsten Stunden neu. Kein Netzwerk; die App lädt die Widgets nach jeder Änderung neu.
struct FamilyProvider: TimelineProvider {
    func placeholder(in context: Context) -> FamilyEntry {
        FamilyEntry(date: .now, state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FamilyEntry) -> Void) {
        completion(entries(now: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyEntry>) -> Void) {
        let entries = entries(now: .now)
        let refresh = Date.now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func entries(now: Date) -> [FamilyEntry] {
        guard let snapshot = SharedSnapshotStore.shared?.load() else {
            return [FamilyEntry(date: now, state: nil)]
        }
        let text = TimeText(family: snapshot.family)
        return WidgetState.timelineDates(snapshot: snapshot, now: now).map {
            FamilyEntry(date: $0, state: WidgetState(snapshot: snapshot, now: $0, timeText: text))
        }
    }
}

/// Hinweis, solange die App noch keinen Stand gespeichert hat.
private struct SignedOutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Carpool").font(.footnote.weight(.semibold)).foregroundStyle(Color.ink)
            Spacer()
            Text("Öffne die App, um dich anzumelden.").font(.footnote).foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func widgetBackground() -> some View {
        containerBackground(Color.surface, for: .widget)
    }
}

/// Mittel: drei Autos; groß: bis zu sechs.
private struct FamilyWidgetContent: View {
    let state: WidgetState
    @Environment(\.widgetFamily) private var family

    var body: some View {
        FamilyWidgetView(state: state, maxCars: family == .systemLarge ? 6 : 3)
    }
}

struct FamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FamilyWidget", provider: FamilyProvider()) { entry in
            Group {
                if let state = entry.state {
                    FamilyWidgetContent(state: state)
                } else {
                    SignedOutView()
                }
            }
            .widgetURL(DeepLink.overview.url)
            .widgetBackground()
        }
        .configurationDisplayName("Alle Autos")
        .description("Wer welches Auto hat, und Zurückgeben.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct MyCarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MyCarWidget", provider: FamilyProvider()) { entry in
            Group {
                if let state = entry.state {
                    MyCarWidgetView(state: state).widgetURL(MyCarWidgetView.link(for: state))
                } else {
                    SignedOutView()
                }
            }
            .widgetBackground()
        }
        .configurationDisplayName("Mein Auto")
        .description("Dein Auto, während der Fahrt mit Zurückgeben.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTripWidget", provider: FamilyProvider()) { entry in
            Group {
                if let state = entry.state {
                    NextTripWidgetView(state: state)
                } else {
                    SignedOutView()
                }
            }
            .widgetURL(DeepLink.calendar.url)
            .widgetBackground()
        }
        .configurationDisplayName("Nächste Fahrt")
        .description("Wann du oder jemand nach dir das Auto braucht.")
        .supportedFamilies([.systemSmall])
    }
}
