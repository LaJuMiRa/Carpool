import Foundation

/// Wochentag für wiederkehrende Reservierungen (`BYDAY` in der RRULE). Montag = 1.
public enum Weekday: Int, CaseIterable, Sendable, Comparable, Hashable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    /// Kürzel in der RRULE.
    public var code: String { ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][rawValue - 1] }
    /// „Mo"
    public var short: String { ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"][rawValue - 1] }
    /// „Montag"
    public var name: String {
        ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][rawValue - 1]
    }

    /// Wochentag eines Datums im gegebenen Kalender.
    public init(of date: Date, calendar: Calendar) {
        // Calendar: Sonntag = 1 … Samstag = 7
        let weekday = calendar.component(.weekday, from: date)
        self = Weekday(rawValue: weekday == 1 ? 7 : weekday - 1)!
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Eingabe für `reserve` / `check_reservation`. Zeiten in UTC, `until` als Tag der Familie.
public struct ReservationRequest: Sendable, Equatable {
    public let carID: UUID
    public let startsAt: Date
    public let endsAt: Date
    /// Leer = einmalig.
    public let repeatDays: Set<Weekday>
    /// Letzter Tag der Serie („yyyy-MM-dd"), nil = offen.
    public let until: String?

    public init(carID: UUID, startsAt: Date, endsAt: Date, repeatDays: Set<Weekday> = [], until: String? = nil) {
        self.carID = carID
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.repeatDays = repeatDays
        self.until = repeatDays.isEmpty ? nil : until
    }

    /// „FREQ=WEEKLY;BYDAY=MO,TU" oder nil.
    public var rrule: String? {
        guard !repeatDays.isEmpty else { return nil }
        return "FREQ=WEEKLY;BYDAY=" + repeatDays.sorted().map(\.code).joined(separator: ",")
    }
}

/// Belegung, die einer Reservierung im Weg steht (`conflicts[]`).
public struct ReservationConflict: Decodable, Sendable, Equatable, Identifiable {
    public let bookingId: UUID
    public let kind: Booking.Kind
    public let startsAt: Date
    /// Ende bzw. geplantes Ende; nil bei laufender Fahrt ohne Plan.
    public let endsAt: Date?
    public let memberId: UUID
    public let firstName: String
    public let canDisplace: Bool

    public var id: UUID { bookingId }

    public init(bookingId: UUID, kind: Booking.Kind, startsAt: Date, endsAt: Date?, memberId: UUID,
                firstName: String, canDisplace: Bool) {
        self.bookingId = bookingId
        self.kind = kind
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.memberId = memberId
        self.firstName = firstName
        self.canDisplace = canDisplace
    }

    /// Aus einer Buchung im Kalender (Übernehmen ohne Formular).
    public init(booking: Booking, firstName: String, canDisplace: Bool) {
        self.init(bookingId: booking.id, kind: booking.kind, startsAt: booking.startsAt,
                  endsAt: booking.endsAt ?? booking.plannedEndsAt, memberId: booking.memberId,
                  firstName: firstName, canDisplace: canDisplace)
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case bookingId = "booking_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case memberId = "member_id"
        case firstName = "first_name"
        case canDisplace = "can_displace"
    }
}

/// Antwort von `reserve` und `check_reservation`.
public struct ReservationResult: Decodable, Sendable, Equatable {
    public enum Reason: String, Decodable, Sendable {
        /// Belegt; Tauschen oder (als Hauptnutzer) Übernehmen möglich.
        case conflict
        /// Übernehmen nicht erlaubt (z. B. laufende Fahrt dabei).
        case notDisplaceable = "not_displaceable"
        /// Für mindestens einen Verdrängten gibt es kein Ersatzauto; bewusst bestätigen.
        case noReplacement = "no_replacement"
    }

    public let ok: Bool
    public let reason: Reason?
    public let conflicts: [ReservationConflict]
    public let freeCarIds: [UUID]
    public let bookingIds: [UUID]
    public let displacedCount: Int

    public init(ok: Bool, reason: Reason? = nil, conflicts: [ReservationConflict] = [], freeCarIds: [UUID] = [],
                bookingIds: [UUID] = [], displacedCount: Int = 0) {
        self.ok = ok
        self.reason = reason
        self.conflicts = conflicts
        self.freeCarIds = freeCarIds
        self.bookingIds = bookingIds
        self.displacedCount = displacedCount
    }

    public static let success = ReservationResult(ok: true)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        reason = try container.decodeIfPresent(Reason.self, forKey: .reason)
        conflicts = try container.decodeIfPresent([ReservationConflict].self, forKey: .conflicts) ?? []
        freeCarIds = try container.decodeIfPresent([UUID].self, forKey: .freeCarIds) ?? []
        bookingIds = try container.decodeIfPresent([UUID].self, forKey: .bookingIds) ?? []
        displacedCount = try container.decodeIfPresent(Int.self, forKey: .displacedCount) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case ok, reason, conflicts
        case freeCarIds = "free_car_ids"
        case bookingIds = "booking_ids"
        case displacedCount = "displaced_count"
    }
}

/// Antwort von `displace`.
public enum DisplaceResult: Sendable, Equatable {
    case displaced(replacementFound: Bool)
    /// Kein Ersatzauto frei; erst nach bewusster Bestätigung erneut aufrufen.
    case noReplacement
}
