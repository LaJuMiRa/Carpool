import Foundation

/// Was der Kalender (F10/F11) anzeigt: Woche mit Punkten je Auto, Buchungen des gewählten Tags.
/// Regeln und Texte stehen auch in CLAUDE.md („Kalender"), für die Android-App.
public struct CalendarState: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        /// Tagesbeginn in der Zeitzone der Familie.
        public let date: Date
        /// „Mo"
        public let weekday: String
        /// „26"
        public let number: String
        public let isToday: Bool
        public let isSelected: Bool
        /// Kalenderfarben (`color_slot`) der Autos mit Buchung an diesem Tag, sortiert.
        public let carSlots: [Int]

        public var id: Date { date }
    }

    public struct Entry: Sendable, Equatable, Identifiable {
        public let booking: Booking
        public let car: Car
        /// Linke Spalte: Beginn an diesem Tag („08:00"), leer, wenn sie früher begonnen hat.
        public let startLabel: String
        /// „08:00–17:30", „seit 09:12", „ab 18:00", „bis 10:00", „ganztägig"
        public let timeText: String
        public let personShort: String
        /// „Felix"; „Du" bei eigenen Buchungen.
        public let personName: String
        public let isDriving: Bool
        public let isRepeating: Bool
        /// Eigene Reservierung, die noch nicht vorbei ist: bearbeiten, übergeben, löschen.
        public let canCancel: Bool
        /// Eigene Reservierung oder eigene laufende Fahrt: verlängern.
        public let canExtend: Bool
        /// Schon vorbei (abgeschlossene Fahrt, vergangene Reservierung): gedämpft, ohne Aktionen.
        public let isPast: Bool
        /// Hauptnutzer darf diese zukünftige Reservierung übernehmen.
        public let canDisplace: Bool

        public var id: UUID { booking.id }

        /// „Felix, Flitzer, 14:00–19:00, wiederholt sich"
        public var accessibilityText: String {
            [personName, car.title, timeText, isDriving ? "fährt gerade" : nil,
             isRepeating ? "wiederholt sich" : nil].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// Monat des gewählten Tags: „Oktober".
    public let title: String
    /// „Heute", „Morgen", „Samstag, 31. Oktober"
    public let dayTitle: String
    public let week: [Day]
    public let entries: [Entry]
    public let selectedDay: Date

    /// - Parameter history: vergangene Buchungen (abgeschlossene Fahrten, vorbei gegangene Reservierungen)
    ///   für zurückliegende Tage; Doppelte mit dem aktuellen Stand werden ignoriert.
    public init(snapshot: FamilySnapshot, history: [Booking] = [], selectedDay: Date, now: Date,
                timeText: TimeText) {
        let calendar = timeText.weekCalendar
        let day = calendar.startOfDay(for: selectedDay)
        let current = Set(snapshot.bookings.map(\.id))
        let past = history.filter { !current.contains($0.id) && [.active, .completed].contains($0.status) }
        let builder = CalendarBuilder(snapshot: snapshot, all: snapshot.bookings + past, now: now, text: timeText,
                                      calendar: calendar)
        self.selectedDay = day
        self.title = timeText.month(day, relativeTo: now)
        self.dayTitle = timeText.dayTitle(day, relativeTo: now)
        self.week = builder.week(containing: day)
        self.entries = builder.entries(on: day)
    }

    /// Tagesbeginn von `date` plus `weeks` Wochen (Woche blättern).
    public static func day(_ date: Date, movedByWeeks weeks: Int, timeText: TimeText) -> Date {
        let calendar = timeText.weekCalendar
        return calendar.date(byAdding: .weekOfYear, value: weeks, to: calendar.startOfDay(for: date)) ?? date
    }
}

private struct CalendarBuilder {
    let snapshot: FamilySnapshot
    /// Aktuelle und vergangene Buchungen.
    let all: [Booking]
    let now: Date
    let text: TimeText
    let calendar: Calendar

    /// Zeitraum, den eine Buchung im Kalender belegt. Laufende Fahrt: bis geplantes Ende, mindestens jetzt.
    func interval(of booking: Booking) -> (start: Date, end: Date) {
        if let endsAt = booking.endsAt { return (booking.startsAt, endsAt) }
        return (booking.startsAt, max(booking.plannedEndsAt ?? now, now, booking.startsAt))
    }

    func bookings(on day: Date) -> [Booking] {
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return all.filter { booking in
            guard booking.status == .active || booking.status == .completed,
                  snapshot.car(booking.carId) != nil else { return false }
            let range = interval(of: booking)
            // Gerade erst genommen: Beginn = Ende = jetzt, trotzdem an diesem Tag zeigen.
            return range.start < next && max(range.end, range.start.addingTimeInterval(1)) > day
        }
    }

    func week(containing day: Date) -> [CalendarState.Day] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return [] }
        return (0..<7).compactMap { offset -> CalendarState.Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let slots = Set(bookings(on: date).compactMap { snapshot.car($0.carId)?.colorSlot }).sorted()
            return CalendarState.Day(
                date: date, weekday: Weekday(of: date, calendar: calendar).short,
                number: String(calendar.component(.day, from: date)),
                isToday: calendar.isDate(date, inSameDayAs: now), isSelected: date == day, carSlots: slots)
        }
    }

    func entries(on day: Date) -> [CalendarState.Entry] {
        bookings(on: day)
            .sorted { ($0.startsAt, snapshot.car($0.carId)?.colorSlot ?? 0)
                < ($1.startsAt, snapshot.car($1.carId)?.colorSlot ?? 0) }
            .compactMap { entry(for: $0, on: day) }
    }

    func entry(for booking: Booking, on day: Date) -> CalendarState.Entry? {
        guard let car = snapshot.car(booking.carId) else { return nil }
        let member = snapshot.member(booking.memberId)
        let isMine = booking.memberId == snapshot.me.id
        let startsToday = calendar.isDate(booking.startsAt, inSameDayAs: day)
        let isPast = booking.status == .completed || (booking.endsAt.map { $0 <= now } ?? false)
        let ownOpenReservation = isMine && booking.kind == .reservation && !isPast
        return CalendarState.Entry(
            booking: booking, car: car,
            startLabel: startsToday ? text.time(booking.startsAt) : "",
            timeText: timeText(for: booking, on: day, startsToday: startsToday),
            personShort: member?.short ?? "?",
            personName: isMine ? "Du" : (member?.firstName ?? "Jemand"),
            isDriving: booking.isRunningTrip,
            isRepeating: booking.seriesId != nil,
            canCancel: ownOpenReservation,
            canExtend: ownOpenReservation || (isMine && booking.isRunningTrip),
            isPast: isPast,
            canDisplace: !isMine && !isPast && booking.kind == .reservation && booking.startsAt > now
                && car.primaryMemberId == snapshot.me.id)
    }

    func timeText(for booking: Booking, on day: Date, startsToday: Bool) -> String {
        if booking.isRunningTrip && booking.plannedEndsAt == nil {
            return startsToday ? "seit \(text.time(booking.startsAt))"
                : "seit \(text.dayAndTime(booking.startsAt, relativeTo: day))"
        }
        let end = interval(of: booking).end
        let endsToday = calendar.isDate(end, inSameDayAs: day)
            || end == calendar.date(byAdding: .day, value: 1, to: day)
        let endText = end == calendar.date(byAdding: .day, value: 1, to: day) ? "24:00" : text.time(end)
        switch (startsToday, endsToday) {
        case (true, true): return "\(text.time(booking.startsAt))–\(endText)"
        case (true, false): return "ab \(text.time(booking.startsAt))"
        case (false, true): return "bis \(endText)"
        case (false, false): return "ganztägig"
        }
    }
}
