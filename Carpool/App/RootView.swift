import SwiftUI

/// Schwebende Tab-Bar: Autos · Kalender · Mitglieder.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Autos", systemImage: "car.2") {
                PlaceholderScreen(text: "Übersicht folgt in Phase 4")
            }
            Tab("Kalender", systemImage: "calendar") {
                PlaceholderScreen(text: "Kalender folgt in Phase 5")
            }
            Tab("Mitglieder", systemImage: "person.2") {
                PlaceholderScreen(text: "Mitglieder folgen in Phase 6")
            }
        }
    }
}

private struct PlaceholderScreen: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView()
}
