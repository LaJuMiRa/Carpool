import Foundation

/// Uhrzeiten und Tage für Nutzertexte („17:30", „Mo 08:00").
public struct TimeText: Sendable {
    public let calendar: Calendar
    private let locale = Locale(identifier: "de_AT")

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// Uhrzeiten in der Zeitzone der Familie (Kalender, Reservieren).
    public init(family: Family) {
        self.init(timeZone: TimeZone(identifier: family.timeZone) ?? .current)
    }

    /// Kalender mit Wochenbeginn Montag.
    public var weekCalendar: Calendar {
        var calendar = calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// „Oktober"; in einem anderen Jahr als `now` „Jänner 2027".
    public func month(_ date: Date, relativeTo now: Date) -> String {
        let month = date.formatted(style.month(.wide))
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? month : "\(month) \(calendar.component(.year, from: date))"
    }

    /// „31. Okt"
    public func dayMonth(_ date: Date) -> String {
        let month = date.formatted(style.month(.abbreviated)).replacingOccurrences(of: ".", with: "")
        return "\(calendar.component(.day, from: date)). \(month)"
    }

    /// „Sa, 31. Okt"
    public func shortDate(_ date: Date) -> String {
        "\(Weekday(of: date, calendar: calendar).short), \(dayMonth(date))"
    }

    /// „Samstag, 31. Oktober"
    public func longDate(_ date: Date) -> String {
        let weekday = Weekday(of: date, calendar: calendar).name
        return "\(weekday), \(calendar.component(.day, from: date)). \(date.formatted(style.month(.wide)))"
    }

    /// „Heute", „Morgen", „Gestern", sonst „Samstag, 31. Oktober".
    public func dayTitle(_ date: Date, relativeTo now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Heute" }
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                             to: calendar.startOfDay(for: date)).day
        switch offset {
        case 1: return "Morgen"
        case -1: return "Gestern"
        default: return longDate(date)
        }
    }

    /// „am Samstag" (andere Woche: „am Sa, 7. Nov"); heute „heute", morgen „morgen".
    public func onDay(_ date: Date, relativeTo now: Date) -> String {
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        switch offset {
        case 0: return "heute"
        case 1: return "morgen"
        case 2..<7: return "am \(Weekday(of: date, calendar: calendar).name)"
        default: return "am \(shortDate(date))"
        }
    }

    public func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// „17:30" am selben Tag, „morgen 08:00", sonst „Mo 08:00".
    public func dayAndTime(_ date: Date, relativeTo now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "morgen \(time(date))"
        }
        let weekday = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar,
                                                      timeZone: calendar.timeZone).weekday(.abbreviated))
            .replacingOccurrences(of: ".", with: "")
        return "\(weekday) \(time(date))"
    }
}
