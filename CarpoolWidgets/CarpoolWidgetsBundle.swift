import SwiftUI
import WidgetKit

@main
struct CarpoolWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FamilyWidget()
        MyCarWidget()
        NextTripWidget()
        TripLiveActivity()
    }
}
