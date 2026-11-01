import Foundation

/// Was das Auto-Detail (F05) anzeigt. Regeln und Texte stehen auch in CLAUDE.md.
public struct CarDetailState: Sendable, Equatable {
    public enum Tone: Sendable, Equatable { case normal, warning, danger }

    public struct Upcoming: Sendable, Equatable, Identifiable {
        public let booking: Booking
        /// „Heute, 18:00–22:00", „Mo, 2. Nov, 08:00–17:00"
        public let timeText: String
        public let personShort: String
        /// „Jonas", „Du", „Papa, jede Woche"
        public let personText: String
        public let isRepeating: Bool
        public var id: UUID { booking.id }
    }

    public struct DamageRow: Sendable, Equatable, Identifiable {
        public let damage: Damage
        /// „Lisa, 12. Okt · fahrbereit"
        public let meta: String
        public var id: UUID { damage.id }
    }

    public struct Condition: Sendable, Equatable {
        public let label: String
        public let value: String
        public let tone: Tone
    }

    /// Höchstens so viele kommende Buchungen.
    static let upcomingLimit = 4
    /// Ab so wenigen Tagen werden Pickerl und Service hervorgehoben.
    static let warningDays = 30

    public let car: Car
    public let status: CarStatus
    /// „bei dir", „für dich"; sonst das Statuswort.
    public let statusText: String?
    /// „seit 09:12", „Mama, zurück um 17:30", „Felix ab 14:00"
    public let statusDetail: String?
    /// „Hauptnutzer: Papa"
    public let primaryText: String?
    public let isMine: Bool
    public let canTake: Bool
    public let upcoming: [Upcoming]
    public let damages: [DamageRow]
    public let conditions: [Condition]

    public init(car: Car, snapshot: FamilySnapshot, now: Date, timeText text: TimeText) {
        self.car = car
        let overview = OverviewState(snapshot: snapshot, now: now, timeText: text)
        if let trip = overview.myTrip, trip.car.id == car.id {
            status = .busy
            statusText = "bei dir"
            statusDetail = "seit \(trip.sinceTime)"
            isMine = true
            canTake = false
        } else {
            let row = overview.rows.first { $0.car.id == car.id }
            status = row?.status ?? .free
            statusText = row?.statusText
            statusDetail = row?.detail
            isMine = false
            canTake = row?.canTake ?? false
        }
        primaryText = car.primaryMemberId.flatMap(snapshot.member).map { member in
            "Hauptnutzer: \(member.id == snapshot.me.id ? "du" : member.firstName)"
        }
        upcoming = snapshot.bookings
            .filter { $0.carId == car.id && $0.kind == .reservation && $0.status == .active
                && ($0.endsAt ?? .distantFuture) > now }
            .prefix(Self.upcomingLimit)
            .map { Self.upcoming($0, snapshot: snapshot, now: now, text: text) }
        damages = snapshot.openDamages(for: car.id).map { damage in
            let who = damage.reportedBy.flatMap(snapshot.member)?.firstName ?? "Jemand"
            let drivable = damage.drivable ? "fahrbereit" : "nicht fahrbereit"
            return DamageRow(damage: damage, meta: "\(who), \(text.dayMonth(damage.createdAt)) · \(drivable)")
        }
        conditions = Self.conditions(car, now: now, text: text)
    }

    static func upcoming(_ booking: Booking, snapshot: FamilySnapshot, now: Date, text: TimeText) -> Upcoming {
        let calendar = text.calendar
        let day: String
        if calendar.isDate(booking.startsAt, inSameDayAs: now) {
            day = "Heute"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(booking.startsAt, inSameDayAs: tomorrow) {
            day = "Morgen"
        } else {
            day = text.shortDate(booking.startsAt)
        }
        let end = booking.endsAt.map { end in
            calendar.isDate(end, inSameDayAs: booking.startsAt)
                ? text.time(end) : text.dayAndTime(end, relativeTo: booking.startsAt)
        }
        let member = snapshot.member(booking.memberId)
        let name = booking.memberId == snapshot.me.id ? "Du" : (member?.firstName ?? "Jemand")
        return Upcoming(booking: booking,
                        timeText: "\(day), \(text.time(booking.startsAt))" + (end.map { "–\($0)" } ?? ""),
                        personShort: member?.short ?? "?",
                        personText: booking.seriesId == nil ? name : "\(name), jede Woche",
                        isRepeating: booking.seriesId != nil)
    }

    static func conditions(_ car: Car, now: Date, text: TimeText) -> [Condition] {
        var rows: [Condition] = []
        if let pickerl = car.pickerlUntil.flatMap({ day(from: $0, calendar: text.calendar) }) {
            rows.append(pickerlCondition(pickerl, now: now, text: text))
        }
        if let service = car.serviceDue.flatMap({ day(from: $0, calendar: text.calendar) }) {
            rows.append(serviceCondition(service, now: now, text: text))
        }
        if let plate = car.plate { rows.append(Condition(label: "Kennzeichen", value: plate, tone: .normal)) }
        if let km = car.odometerKm {
            rows.append(Condition(label: "Kilometerstand",
                                  value: "\(km.formatted(.number.locale(Locale(identifier: "de_AT")))) km",
                                  tone: .normal))
        }
        return rows
    }

    /// Pickerl gilt bis Monatsende: „bis März 2027"; bald „bis März 2027" (gelb); danach „abgelaufen".
    static func pickerlCondition(_ until: Date, now: Date, text: TimeText) -> Condition {
        let calendar = text.calendar
        let monthEnd = calendar.dateInterval(of: .month, for: until)?.end ?? until
        let days = daysBetween(now, monthEnd, calendar: calendar)
        let value = "bis \(text.monthYear(until))"
        if days <= 0 { return Condition(label: "Pickerl", value: "abgelaufen", tone: .danger) }
        return Condition(label: "Pickerl", value: value, tone: days <= warningDays ? .warning : .normal)
    }

    /// „in 3 Wochen", „in 5 Tagen", „morgen", „heute", „überfällig"; weit weg „Mai 2027".
    static func serviceCondition(_ due: Date, now: Date, text: TimeText) -> Condition {
        let days = daysBetween(now, due, calendar: text.calendar)
        let value: String
        switch days {
        case ..<0: return Condition(label: "Service", value: "überfällig", tone: .danger)
        case 0: value = "heute"
        case 1: value = "morgen"
        case 2...13: value = "in \(days) Tagen"
        case 14...60: value = "in \(days / 7) Wochen"
        default: value = text.monthYear(due)
        }
        return Condition(label: "Service", value: value, tone: days <= warningDays ? .warning : .normal)
    }

    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// „2027-03-31" → Tagesbeginn in der Zeitzone der Familie.
    public static func day(from string: String, calendar: Calendar) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Tagesbeginn → „2027-03-31".
    public static func string(from day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
