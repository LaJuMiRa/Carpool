import CarpoolKit
import Foundation
import Observation

/// Tabs der schwebenden Leiste.
enum AppTab: Hashable {
    case cars, calendar, members
}

/// Wohin Widgets, Live-Aktivität und Push-Nachrichten springen. Die Screens lesen die offene
/// Anfrage und setzen sie zurück, sobald sie erledigt ist.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .cars
    /// Rückgabe-Sheet für die eigene Fahrt öffnen.
    var wantsReturn = false
    /// Auto-Detail öffnen.
    var carToShow: UUID?

    func open(_ link: DeepLink) {
        switch link {
        case .overview:
            tab = .cars
        case .returnCar:
            tab = .cars
            wantsReturn = true
        case .calendar:
            tab = .calendar
        case .car(let id):
            tab = .cars
            carToShow = id
        }
    }

    func open(_ url: URL) {
        if let link = DeepLink(url: url) { open(link) }
    }
}
