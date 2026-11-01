import Foundation

/// Nutzertexte zu Konflikten und Übernehmen (F12, F14). Stehen auch in CLAUDE.md.
public enum ReservationTexts {
    /// Hinweis im Formular, wer das Auto hat.
    /// - „Felix hat Octavia von 10:00 bis 16:00."
    /// - „Felix hat Octavia am Samstag von 10:00 bis 16:00." (anderer Tag als der gewünschte Beginn)
    /// - „Mama fährt Octavia bis 17:30." / „Mama ist gerade mit Octavia unterwegs."
    /// - „Du hast Octavia schon von 10:00 bis 16:00."
    /// - mehrere Termine: „Felix hat Octavia an 3 Terminen." / „Octavia ist an 3 Terminen belegt."
    public static func conflict(_ conflicts: [ReservationConflict], car: String, me: UUID, requestedStart: Date,
                                now: Date, text: TimeText) -> String {
        guard let first = conflicts.first else { return "" }
        if conflicts.count > 1 {
            let people = Set(conflicts.map(\.memberId))
            if people.count == 1 {
                return first.memberId == me ? "Du hast \(car) schon an \(conflicts.count) Terminen."
                    : "\(first.firstName) hat \(car) an \(conflicts.count) Terminen."
            }
            return "\(car) ist an \(conflicts.count) Terminen belegt."
        }
        if first.kind == .trip {
            guard let end = first.endsAt, end > now else {
                return first.memberId == me ? "Du bist gerade mit \(car) unterwegs."
                    : "\(first.firstName) ist gerade mit \(car) unterwegs."
            }
            let until = text.dayAndTime(end, relativeTo: now)
            return first.memberId == me ? "Du fährst \(car) bis \(until)." : "\(first.firstName) fährt \(car) bis \(until)."
        }
        let range = rangeText(start: first.startsAt, end: first.endsAt, requestedStart: requestedStart,
                              now: now, text: text)
        return first.memberId == me ? "Du hast \(car) schon \(range)." : "\(first.firstName) hat \(car) \(range)."
    }

    /// Titel des Bestätigungs-Sheets: „Felix’ Buchung übernehmen?" / „Lisas Buchungen übernehmen?"
    public static func displaceTitle(_ conflicts: [ReservationConflict]) -> String {
        let names = orderedNames(conflicts)
        if names.count == 1 {
            return "\(possessive(names[0])) \(conflicts.count == 1 ? "Buchung" : "Buchungen") übernehmen?"
        }
        return "Buchungen übernehmen?"
    }

    /// „Felix verliert seine Reservierung am Samstag, 10:00–16:00, und bekommt eine Nachricht."
    /// Mehrere: „Felix verliert 3 Reservierungen und bekommt eine Nachricht."
    /// Mehrere Personen: „Felix und Jonas verlieren ihre Reservierungen und bekommen eine Nachricht."
    public static func displaceMessage(_ conflicts: [ReservationConflict], now: Date, text: TimeText) -> String {
        let names = orderedNames(conflicts)
        guard let first = conflicts.first else { return "" }
        if names.count > 1 {
            return "\(list(names)) verlieren ihre Reservierungen und bekommen eine Nachricht."
        }
        if conflicts.count > 1 {
            return "\(first.firstName) verliert \(conflicts.count) Reservierungen und bekommt eine Nachricht."
        }
        let day = text.onDay(first.startsAt, relativeTo: now)
        let end = first.endsAt.map { "–\(text.time($0))" } ?? ""
        return "\(first.firstName) verliert die Reservierung \(day), \(text.time(first.startsAt))\(end), "
            + "und bekommt eine Nachricht."
    }

    /// Warnung, wenn kein Ersatzauto frei ist: „Für Felix ist in dieser Zeit kein anderes Auto frei."
    public static func noReplacementMessage(_ conflicts: [ReservationConflict]) -> String {
        "Für \(list(orderedNames(conflicts))) ist in dieser Zeit kein anderes Auto frei."
    }

    /// Genitiv für Vornamen: „Felix’", „Lisas".
    public static func possessive(_ name: String) -> String {
        let last = name.lowercased().last
        return ["s", "ß", "x", "z"].contains(last) ? "\(name)’" : "\(name)s"
    }

    // MARK: Intern

    static func rangeText(start: Date, end: Date?, requestedStart: Date, now: Date, text: TimeText) -> String {
        let calendar = text.calendar
        let endText = end.map { calendar.isDate($0, inSameDayAs: start) ? text.time($0)
            : text.dayAndTime($0, relativeTo: start) }
        let span = endText.map { "von \(text.time(start)) bis \($0)" } ?? "ab \(text.time(start))"
        if calendar.isDate(start, inSameDayAs: requestedStart) { return span }
        return "\(text.onDay(start, relativeTo: now)) \(span)"
    }

    static func orderedNames(_ conflicts: [ReservationConflict]) -> [String] {
        var seen = Set<UUID>()
        return conflicts.compactMap { seen.insert($0.memberId).inserted ? $0.firstName : nil }
    }

    static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " und " + names[names.count - 1]
    }
}
