import AppIntents
import CarpoolKit
import CarpoolUI
import SwiftUI

/// Schnellzugriff → Widgets: Vorschau mit echten Daten und kurze Anleitung zum Hinzufügen.
struct WidgetsInfoScreen: View {
    let store: FamilyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Halte den Home-Bildschirm gedrückt, tippe auf „Bearbeiten“ und dann auf „Widget hinzufügen“. Suche nach Carpool.")
                    .font(.callout)
                    .foregroundStyle(Color.inkSecondary)
                if let snapshot = store.snapshot {
                    previews(snapshot)
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.paper)
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func previews(_ snapshot: FamilySnapshot) -> some View {
        let text = TimeText(family: snapshot.family)
        let state = WidgetState(snapshot: snapshot, now: .now, timeText: text)
        let trip = OverviewState(snapshot: snapshot, now: .now, timeText: text).myTrip
        return VStack(alignment: .leading, spacing: Spacing.l) {
            preview("Alle Autos") {
                FamilyWidgetView(state: state).widgetFrame(width: 338, height: 158)
            }
            preview("Mein Auto · Nächste Fahrt") {
                HStack(spacing: Spacing.m) {
                    MyCarWidgetView(state: state).widgetFrame(width: 158, height: 158)
                    NextTripWidgetView(state: state).widgetFrame(width: 158, height: 158)
                }
            }
            if let trip {
                preview("Live-Aktivität während der Fahrt") {
                    TripActivityView(attributes: TripActivityAttributes(trip: trip),
                                     state: .init(trip: trip, now: .now, timeText: text))
                        .background(Color.black.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func preview<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title)
            content()
        }
        .accessibilityElement(children: .contain)
    }
}

private extension View {
    /// Rahmen wie auf dem Home-Bildschirm (Widget-Größen eines 6,1"-iPhones).
    func widgetFrame(width: CGFloat, height: CGFloat) -> some View {
        padding(16)
            .frame(width: width, height: height)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
    }
}

/// Schnellzugriff → Kurzbefehle und Siri: „Auto zurückgeben" fragt nur nach dem Tankstand.
struct ShortcutsInfoScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("„Auto zurückgeben“ gibt das Auto zurück, das du gerade fährst, und fragt nur nach dem Tankstand. Geht auch über Siri oder die Aktionstaste.")
                    .font(.callout)
                    .foregroundStyle(Color.inkSecondary)
                Label("Sag zu Siri: „Auto zurückgeben mit Carpool“", systemImage: "mic")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .padding(Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: ControlSize.hairline))
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.m)
        }
        .background(Color.paper)
        .navigationTitle("Kurzbefehle und Siri")
        .navigationBarTitleDisplayMode(.inline)
    }
}
