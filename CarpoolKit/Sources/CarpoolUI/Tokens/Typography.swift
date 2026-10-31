import SwiftUI

/// Nur SF Pro über Systemstile, damit Dynamic Type greift.
public extension View {
    /// Screen-Titel: large title, fett, enger gesetzt. Nur wenn er etwas aussagt.
    func screenTitleStyle() -> some View {
        font(.largeTitle.bold()).kerning(-0.8).foregroundStyle(Color.ink)
    }

    /// Sheet-Titel und Spitznamen.
    func sheetTitleStyle() -> some View {
        font(.title2.bold()).kerning(-0.4).foregroundStyle(Color.ink)
    }

    /// Kleine Bereichs-Überschrift über Karten („Andere Autos").
    func sectionLabelStyle() -> some View {
        font(.callout.weight(.medium)).foregroundStyle(Color.inkMuted)
    }

    /// Labels und Metadaten.
    func metaStyle() -> some View {
        font(.caption.weight(.medium)).foregroundStyle(Color.inkMuted)
    }
}
