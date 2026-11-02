import Foundation

/// Was die Widgets anzeigen (F09). Wird aus dem gespeicherten Snapshot für einen Zeitpunkt berechnet,
/// damit die Zeitleiste ohne Netzwerk weiterläuft. Regeln stehen auch in CLAUDE.md („Schnellzugriff").
public struct WidgetState: Sendable, Equatable {
    public struct CarItem: Sendable, Equatable, Identifiable {
        public let car: Car
        public let status: CarStatus
        /// „bei dir", „für dich" oder das Statuswort.
        public let statusText: String
        /// Zweite Zeile im kleinen Widget, z. B. „Felix ab 14:00".
        public let detail: String?
        public var id: UUID { car.id }
    }

    public struct NextTrip: Sendable, Equatable {
        /// „18:00"
        public let time: String
        /// nil = heute, sonst „Morgen" bzw. „Mo, 2. Nov".
        public let day: String?
        /// „Jonas nimmt Radieschen" / „Du nimmst Flitzer"
        public let text: String
        public let colorSlot: Int
    }

    /// „2 von 3 frei"
    public let title: String
    /// Alle Autos in Kalenderfarben-Reihenfolge, das eigene mit „bei dir".
    public let cars: [CarItem]
    /// Auto, das ich gerade fahre.
    public let myTrip: OverviewState.MyTrip?
    /// Kleines Widget: das gefahrene Auto, sonst das, dessen Hauptnutzer ich bin.
    public let myCar: CarItem?
    public let next: NextTrip?

    /// „Radieschen zurückgeben"
    public var returnTitle: String? { myTrip.map { "\($0.car.title) zurückgeben" } }

    public static let mineText = "bei dir"
    public static let nothingPlannedText = "Nichts geplant."

    public init(snapshot: FamilySnapshot, now: Date, timeText: TimeText) {
        let overview = OverviewState(snapshot: snapshot, now: now, timeText: timeText)
        let items = snapshot.cars.map { car -> CarItem in
            if let trip = overview.myTrip, trip.car.id == car.id {
                return CarItem(car: car, status: .busy, statusText: Self.mineText,
                               detail: "seit \(trip.sinceTime)")
            }
            let row = overview.rows.first { $0.car.id == car.id }
            let status = row?.status ?? .free
            return CarItem(car: car, status: status, statusText: row?.statusText ?? status.label, detail: row?.detail)
        }
        let myCarID = overview.myTrip?.car.id
            ?? snapshot.cars.first { $0.primaryMemberId == snapshot.me.id }?.id

        self.title = overview.title
        self.cars = items
        self.myTrip = overview.myTrip
        self.myCar = items.first { $0.car.id == myCarID }
        self.next = Self.nextTrip(snapshot: snapshot, myTrip: overview.myTrip, now: now, text: timeText)
    }

    /// Fahre ich, zählt die nächste Person auf meinem Auto; sonst meine eigene nächste Reservierung.
    private static func nextTrip(snapshot: FamilySnapshot, myTrip: OverviewState.MyTrip?, now: Date,
                                 text: TimeText) -> NextTrip? {
        let reservations = snapshot.bookings.filter {
            $0.kind == .reservation && $0.status == .active && ($0.endsAt ?? .distantFuture) > now
        }
        let booking: Booking?
        if let myTrip {
            booking = reservations.first { $0.carId == myTrip.car.id && $0.memberId != snapshot.me.id }
                ?? reservations.first { $0.memberId == snapshot.me.id }
        } else {
            booking = reservations.first { $0.memberId == snapshot.me.id }
        }
        guard let booking, let car = snapshot.car(booking.carId) else { return nil }
        let mine = booking.memberId == snapshot.me.id
        let who = mine ? "Du nimmst" : "\(snapshot.member(booking.memberId)?.firstName ?? "Jemand") nimmt"
        return NextTrip(time: text.time(booking.startsAt), day: day(booking.startsAt, now: now, text: text),
                        text: "\(who) \(car.title)", colorSlot: car.colorSlot)
    }

    private static func day(_ date: Date, now: Date, text: TimeText) -> String? {
        switch text.dayTitle(date, relativeTo: now) {
        case "Heute": nil
        case "Morgen": "Morgen"
        default: text.shortDate(date)
        }
    }

    /// Zeitpunkte, an denen sich die Anzeige ändern kann: jetzt und jede Grenze einer Buchung
    /// (Beginn, Ende, „reserviert" ab 60 min vorher) innerhalb des Horizonts. Höchstens `limit` Stück.
    public static func timelineDates(snapshot: FamilySnapshot, now: Date, horizon: TimeInterval = 12 * 3600,
                                     limit: Int = 40) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        let boundaries = snapshot.bookings.flatMap { booking in
            [booking.startsAt.addingTimeInterval(-OverviewState.reservedLead), booking.startsAt,
             booking.endsAt, booking.plannedEndsAt].compactMap { $0 }
        }
        let future = Set(boundaries.filter { $0 > now && $0 <= end }).sorted()
        return Array(([now] + future).prefix(limit))
    }
}
