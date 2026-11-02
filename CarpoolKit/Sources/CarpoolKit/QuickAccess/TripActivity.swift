import ActivityKit
import Foundation

/// Live-Aktivität, solange ich fahre (F08): Auto, Fahrzeit, wer als Nächstes dran ist.
public struct TripActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let startedAt: Date
        /// „Du fährst seit 09:12"
        public let sinceText: String
        /// „09:12" (Anfang des Fortschrittsbalkens)
        public let startTime: String
        /// „Jonas ab 18:00"; nil, wenn niemand das Auto danach braucht.
        public let nextText: String?
        /// Ende des Fortschrittsbalkens.
        public let nextAt: Date?

        public init(trip: OverviewState.MyTrip, now: Date, timeText: TimeText) {
            self.startedAt = trip.startedAt
            self.sinceText = trip.sinceText
            self.startTime = trip.sinceTime
            self.nextText = trip.next.map {
                "\($0.member.firstName) ab \(timeText.dayAndTime($0.startsAt, relativeTo: now))"
            }
            self.nextAt = trip.next?.startsAt
        }
    }

    public let bookingID: UUID
    public let carTitle: String
    public let model: String
    public let paint: String
    public let colorSlot: Int

    public init(trip: OverviewState.MyTrip) {
        self.bookingID = trip.bookingID
        self.carTitle = trip.car.title
        self.model = trip.car.model
        self.paint = trip.car.paint
        self.colorSlot = trip.car.colorSlot
    }
}
