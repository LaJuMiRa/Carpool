import Foundation

/// Was die Mitglieder-Seite (F15) anzeigt. Regeln und Texte stehen auch in CLAUDE.md.
public struct MembersState: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public enum Tone: Sendable, Equatable {
            /// Fährt gerade: Statusfarbe „unterwegs".
            case driving
            /// Hauptnutzer: Punkt in der Autofarbe.
            case car(colorSlot: Int)
            case plain
        }

        public let member: Member
        public let isMe: Bool
        /// „fährt gerade Octavia", „Hauptnutzer von Flitzer · heute 18:00", „nächste Fahrt heute 14:00"
        public let detail: String?
        public let tone: Tone
        public let isAdmin: Bool
        /// Noch nicht mit einem Konto beigetreten.
        public let hasJoined: Bool

        public var id: UUID { member.id }
    }

    public let title: String
    public let rows: [Row]
    public let inviteCode: String
    /// Text zum Teilen der Einladung.
    public let inviteMessage: String

    public init(snapshot: FamilySnapshot, now: Date, timeText: TimeText) {
        title = snapshot.family.name
        inviteCode = snapshot.family.inviteCode
        inviteMessage = "Komm in unsere Familie „\(snapshot.family.name)“ bei Carpool. "
            + "Melde dich in der App an und gib diesen Code ein: \(snapshot.family.inviteCode)"
        rows = snapshot.members.map { member in
            Self.row(for: member, snapshot: snapshot, now: now, text: timeText)
        }
    }

    static func row(for member: Member, snapshot: FamilySnapshot, now: Date, text: TimeText) -> Row {
        let base = { (detail: String?, tone: Row.Tone) in
            Row(member: member, isMe: member.id == snapshot.me.id, detail: detail, tone: tone,
                isAdmin: member.role == .admin, hasJoined: member.userId != nil)
        }
        if let trip = snapshot.bookings.first(where: { $0.isRunningTrip && $0.memberId == member.id }),
           let car = snapshot.car(trip.carId) {
            return base("fährt gerade \(car.title)", .driving)
        }
        let next = snapshot.bookings.first {
            $0.memberId == member.id && $0.kind == .reservation && $0.status == .active
                && ($0.endsAt ?? .distantFuture) > now
        }
        let nextText = next.map { relative($0.startsAt <= now ? now : $0.startsAt, now: now, text: text) }
        if let car = snapshot.cars.first(where: { $0.primaryMemberId == member.id }) {
            let detail = ["Hauptnutzer von \(car.title)", nextText].compactMap { $0 }.joined(separator: " · ")
            return base(detail, .car(colorSlot: car.colorSlot))
        }
        if let nextText {
            return base("nächste Fahrt \(nextText)", .plain)
        }
        return base(member.userId == nil ? "noch nicht beigetreten" : nil, .plain)
    }

    /// „heute 18:00", „morgen 08:00", „Mo 08:00", „jetzt"
    static func relative(_ date: Date, now: Date, text: TimeText) -> String {
        if date <= now { return "jetzt" }
        let value = text.dayAndTime(date, relativeTo: now)
        return text.calendar.isDate(date, inSameDayAs: now) ? "heute \(value)" : value
    }
}
