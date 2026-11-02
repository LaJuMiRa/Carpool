import CarpoolKit
import SwiftUI

/// Inhalte der Widgets (F09). Liegen im Design System, damit Widget-Extension und App
/// (Vorschau in den Einstellungen) dieselben Ansichten zeigen. Hintergrund setzt der Aufrufer.

/// Groß: alle Autos mit Status, darunter „Radieschen zurückgeben", wenn ich fahre.
public struct FamilyWidgetView: View {
    private let state: WidgetState
    private let maxCars: Int

    public init(state: WidgetState, maxCars: Int = 3) {
        self.state = state
        self.maxCars = maxCars
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Carpool").font(.caption.weight(.semibold)).foregroundStyle(Color.ink)
                Spacer()
                Text(state.title).font(.caption).foregroundStyle(Color.inkMuted)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs, alignment: .leading),
                                     count: 3), alignment: .leading, spacing: Spacing.s) {
                ForEach(state.cars.prefix(maxCars)) { item in
                    carCell(item)
                }
            }
            Spacer(minLength: 0)
            if let title = state.returnTitle {
                Link(destination: DeepLink.returnCar.url) {
                    WidgetButtonLabel(title: title, height: 34)
                }
            }
        }
    }

    private func carCell(_ item: WidgetState.CarItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CarSilhouette(model: item.car.model, paint: item.car.paint)
                .frame(width: 64, height: 28)
                .accessibilityHidden(true)
            Text(item.car.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            WidgetStatus(status: item.status, text: item.statusText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Klein: eigenes Auto. Während der Fahrt mit „Zurückgeben" (ganzes Widget öffnet die Rückgabe).
public struct MyCarWidgetView: View {
    private let state: WidgetState

    public init(state: WidgetState) {
        self.state = state
    }

    public var body: some View {
        if let item = state.myCar {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.car.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                WidgetStatus(status: item.status, text: item.statusText)
                Spacer(minLength: Spacing.xxs)
                CarSilhouette(model: item.car.model, paint: item.car.paint)
                    .frame(maxWidth: 120, maxHeight: 54)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Spacer(minLength: Spacing.xxs)
                if state.myTrip != nil {
                    WidgetButtonLabel(title: "Zurückgeben", height: 32)
                } else if let detail = item.detail {
                    Text(detail).font(.caption).foregroundStyle(Color.inkSecondary).lineLimit(2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Carpool").font(.footnote.weight(.semibold)).foregroundStyle(Color.ink)
                Spacer()
                Text(state.title).font(.title3.bold()).foregroundStyle(Color.ink)
                Text("Du fährst gerade nicht.").font(.caption).foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Ziel beim Antippen: Rückgabe während der Fahrt, sonst die Übersicht.
    public static func link(for state: WidgetState) -> URL {
        (state.myTrip != nil ? DeepLink.returnCar : .overview).url
    }
}

/// Klein: nächste Fahrt („18:00 · Jonas nimmt Radieschen").
public struct NextTripWidgetView: View {
    private let state: WidgetState

    public init(state: WidgetState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nächste Fahrt").font(.footnote.weight(.semibold)).foregroundStyle(Color.ink)
            Spacer(minLength: Spacing.xxs)
            if let next = state.next {
                VStack(alignment: .leading, spacing: 2) {
                    if let day = next.day {
                        Text(day).font(.caption.weight(.medium)).foregroundStyle(Color.inkMuted)
                    }
                    Text(next.time)
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.ink)
                    Text(next.text)
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: Spacing.xxs)
                Circle().fill(CarColor(slot: next.colorSlot).base).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            } else {
                Text(WidgetState.nothingPlannedText).font(.footnote).foregroundStyle(Color.inkSecondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Status wie in der App: Punkt + Wort.
struct WidgetStatus: View {
    let status: CarStatus
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(status.color).lineLimit(1)
        }
    }
}

/// Primär-Button im Widget (dunkel, abgerundet).
struct WidgetButtonLabel: View {
    let title: String
    let height: CGFloat

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.onInk)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
