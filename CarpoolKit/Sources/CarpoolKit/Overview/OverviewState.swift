import Foundation

/// Was die Übersicht anzeigt. Wird aus dem Snapshot und der aktuellen Zeit berechnet.
/// Regeln und Texte stehen auch in CLAUDE.md („Übersicht"), für die Android-App.
public struct OverviewState: Sendable, Equatable {
    /// Ab so kurz vorher gilt ein Auto als „reserviert".
    public static let reservedLead: TimeInterval = 60 * 60

    public struct MyTrip: Sendable, Equatable, Identifiable {
        public let car: Car
        public let bookingID: UUID
        public var id: UUID { bookingID }
        /// „09:12"
        public let sinceTime: String
        /// „Du fährst seit 09:12"
        public var sinceText: String { "Du fährst seit \(sinceTime)" }
        /// „Tank beim Nehmen ¾"
        public let fuelOnTakeText: String?
        /// Nächste Person mit Reservierung auf diesem Auto.
        public let next: NextUp?
    }

    public struct NextUp: Sendable, Equatable {
        public let member: Member
        public let startsAt: Date
        /// „Jonas braucht ihn ab 18:00"
        public let bannerText: String
        /// „Jonas bekommt eine Nachricht, dass Radieschen bereit ist."
        public let returnNoteText: String
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public let car: Car
        public let status: CarStatus
        /// Abweichendes Statuswort, z. B. „für dich".
        public let statusText: String?
        public let detail: String?
        public let canTake: Bool

        public var id: UUID { car.id }
    }

    /// „1 von 3 frei"
    public let title: String
    public let myTrip: MyTrip?
    public let rows: [Row]

    public init(snapshot: FamilySnapshot, now: Date, timeText: TimeText = TimeText()) {
        let builder = Builder(snapshot: snapshot, now: now, text: timeText)
        let myTrip = builder.myTrip()
        let rows = snapshot.cars
            .filter { $0.id != myTrip?.car.id }
            .map { builder.row(for: $0, iAmDriving: myTrip != nil) }
        let freeCount = rows.filter { $0.status == .free }.count
        self.title = "\(freeCount) von \(snapshot.cars.count) frei"
        self.myTrip = myTrip
        self.rows = rows
    }
}

private struct Builder {
    let snapshot: FamilySnapshot
    let now: Date
    let text: TimeText

    func name(_ memberID: UUID) -> String {
        snapshot.member(memberID)?.firstName ?? "Jemand"
    }

    /// Nächste aktive Reservierung eines anderen Mitglieds, die noch nicht vorbei ist.
    func nextReservation(on carID: UUID, excludingMe: Bool) -> Booking? {
        snapshot.bookings.first {
            $0.carId == carID && $0.kind == .reservation && $0.status == .active
                && ($0.endsAt ?? .distantFuture) > now && (!excludingMe || $0.memberId != snapshot.me.id)
        }
    }

    func myTrip() -> OverviewState.MyTrip? {
        guard let trip = snapshot.myRunningTrip, let car = snapshot.car(trip.carId) else { return nil }
        let next = nextReservation(on: car.id, excludingMe: true).flatMap { booking -> OverviewState.NextUp? in
            guard let member = snapshot.member(booking.memberId) else { return nil }
            let when = text.dayAndTime(booking.startsAt, relativeTo: now)
            return OverviewState.NextUp(
                member: member, startsAt: booking.startsAt,
                bannerText: "\(member.firstName) braucht ihn ab \(when)",
                returnNoteText: "\(member.firstName) bekommt eine Nachricht, dass \(car.title) bereit ist.")
        }
        return OverviewState.MyTrip(
            car: car, bookingID: trip.id,
            sinceTime: text.time(trip.startsAt),
            fuelOnTakeText: trip.fuelQuartersOnTake.map { "Tank beim Nehmen \(FuelLevel(quarters: $0).label)" },
            next: next)
    }

    func row(for car: Car, iAmDriving: Bool) -> OverviewState.Row {
        if let trip = snapshot.runningTrip(for: car.id) {
            let detail = trip.plannedEndsAt.map { "\(name(trip.memberId)), zurück um \(text.time($0))" }
                ?? "\(name(trip.memberId)), seit \(text.time(trip.startsAt))"
            return .init(car: car, status: .busy, statusText: nil, detail: detail, canTake: false)
        }

        if let reservation = nextReservation(on: car.id, excludingMe: false),
           reservation.startsAt <= now.addingTimeInterval(OverviewState.reservedLead) {
            let isMine = reservation.memberId == snapshot.me.id
            let running = reservation.startsAt <= now
            let who = isMine ? "Deine Reservierung" : name(reservation.memberId)
            let detail = running
                ? "\(who) bis \(text.time(reservation.endsAt ?? now))"
                : "\(who) ab \(text.time(reservation.startsAt))"
            return .init(car: car, status: .reserved, statusText: isMine ? "für dich" : nil, detail: detail,
                         canTake: isMine && !iAmDriving)
        }

        let detail = nextReservation(on: car.id, excludingMe: false)
            .flatMap { text.calendar.isDate($0.startsAt, inSameDayAs: now) ? $0 : nil }
            .map { booking in
                let who = booking.memberId == snapshot.me.id ? "du" : name(booking.memberId)
                return "Frei bis \(text.time(booking.startsAt)), dann \(who)"
            }
        return .init(car: car, status: .free, statusText: nil, detail: detail, canTake: !iAmDriving)
    }
}
