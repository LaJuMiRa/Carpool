import ActivityKit
import CarpoolKit
import CarpoolUI
import SwiftUI
import WidgetKit

/// Live-Aktivität + Dynamic Island, solange ich fahre (F08). Gestartet und beendet von der App.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripActivityView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(DeepLink.overview.url)
        } dynamicIsland: { context in
            let color = CarColor(slot: context.attributes.colorSlot).base
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CarSilhouette(model: context.attributes.model, paint: context.attributes.paint)
                        .frame(width: 72, height: 32)
                        .padding(.leading, Spacing.xxs)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 0) {
                        Text(context.attributes.carTitle).font(.headline)
                        Text(context.state.sinceText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TripTimer(startedAt: context.state.startedAt)
                        .font(.headline)
                        .frame(maxWidth: 72)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let next = context.state.nextText {
                            Text(next).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Link(destination: DeepLink.returnCar.url) {
                            Text("Zurückgeben")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, Spacing.s)
                                .frame(minHeight: 32)
                                .background(.white, in: Capsule())
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "car.side.fill").foregroundStyle(color)
                    .accessibilityLabel(context.attributes.carTitle)
            } compactTrailing: {
                TripTimer(startedAt: context.state.startedAt)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "car.side.fill").foregroundStyle(color)
                    .accessibilityLabel(context.attributes.carTitle)
            }
            .widgetURL(DeepLink.overview.url)
        }
    }
}
