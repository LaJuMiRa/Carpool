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
