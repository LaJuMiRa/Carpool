import Foundation

/// Eingaben im Reservieren-Formular (F12). Unveränderlich; Änderungen liefern eine neue Kopie.
/// Schnellwahl und Texte stehen auch in CLAUDE.md („Reservieren"), für die Android-App.
public struct ReservationDraft: Sendable, Equatable {
    public enum Preset: String, CaseIterable, Sendable {
        /// Ab jetzt (auf 5 min aufgerundet) für 2 Stunden.
        case now
        /// Heute 18:00–22:00; nur vor 18:00.
        case tonight
        /// Morgen 08:00–17:00.
        case tomorrow
        /// Eigener Zeitraum.
        case custom

        public var title: String {
            switch self {
            case .now: "Jetzt"
            case .tonight: "Heute Abend"
            case .tomorrow: "Morgen"
            case .custom: "…"
            }
        }
    }

    static let nowDuration: TimeInterval = 2 * 60 * 60
    static let roundingMinutes = 5
    static let tonight = (start: 18, end: 22)
    static let dayRange = (start: 8, end: 17)

    public let preset: Preset
    public let startsAt: Date
    public let endsAt: Date
    public let carID: UUID?
    /// Leer = einmalig.
    public let repeatDays: Set<Weekday>
    /// Letzter Tag der Serie (Tagesbeginn), nil = ohne Ende.
    public let repeatUntil: Date?

    public init(preset: Preset, startsAt: Date, endsAt: Date, carID: UUID?, repeatDays: Set<Weekday> = [],
                repeatUntil: Date? = nil) {
        self.preset = preset
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.carID = carID
        self.repeatDays = repeatDays
        self.repeatUntil = repeatUntil
    }

    /// Startwerte: heute „Jetzt", morgen „Morgen", sonst der gewählte Tag 08:00–17:00.
    public static func initial(day: Date, carID: UUID?, now: Date, calendar: Calendar) -> ReservationDraft {
        let base = ReservationDraft(preset: .now, startsAt: now, endsAt: now, carID: carID)
        if calendar.isDate(day, inSameDayAs: now) { return base.applying(.now, now: now, calendar: calendar) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return base.applying(.tomorrow, now: now, calendar: calendar)
        }
        let start = at(dayRange.start, on: day, calendar: calendar)
        return base.with(preset: .custom, startsAt: start, endsAt: at(dayRange.end, on: day, calendar: calendar))
    }

    /// Schnellwahl, die jetzt sinnvoll ist.
    public static func presets(now: Date, calendar: Calendar) -> [Preset] {
        calendar.component(.hour, from: now) < tonight.start ? Preset.allCases : [.now, .tomorrow, .custom]
    }

    public func applying(_ preset: Preset, now: Date, calendar: Calendar) -> ReservationDraft {
        let today = calendar.startOfDay(for: now)
        switch preset {
        case .now:
            let start = Self.roundedUp(now, calendar: calendar)
            return with(preset: preset, startsAt: start, endsAt: start.addingTimeInterval(Self.nowDuration))
        case .tonight:
            return with(preset: preset, startsAt: Self.at(Self.tonight.start, on: today, calendar: calendar),
                        endsAt: Self.at(Self.tonight.end, on: today, calendar: calendar))
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return with(preset: preset, startsAt: Self.at(Self.dayRange.start, on: tomorrow, calendar: calendar),
                        endsAt: Self.at(Self.dayRange.end, on: tomorrow, calendar: calendar))
        case .custom:
            return with(preset: .custom)
        }
    }

    /// Eigener Beginn; das Ende rückt mit, damit die Dauer gleich bleibt.
    public func with(start: Date) -> ReservationDraft {
        with(preset: .custom, startsAt: start, endsAt: start.addingTimeInterval(endsAt.timeIntervalSince(startsAt)))
    }

    public func with(end: Date) -> ReservationDraft {
        with(preset: .custom, endsAt: end)
    }

    public func with(carID: UUID) -> ReservationDraft {
        ReservationDraft(preset: preset, startsAt: startsAt, endsAt: endsAt, carID: carID, repeatDays: repeatDays,
                         repeatUntil: repeatUntil)
    }

    public func with(repeatDays: Set<Weekday>, until: Date?) -> ReservationDraft {
        ReservationDraft(preset: preset, startsAt: startsAt, endsAt: endsAt, carID: carID, repeatDays: repeatDays,
                         repeatUntil: repeatDays.isEmpty ? nil : until)
    }

    // MARK: Prüfen

    public var isValidRange: Bool { endsAt > startsAt }

    /// Wiederholen geht nur, wenn die Reservierung am selben Tag endet.
    public func canRepeat(calendar: Calendar) -> Bool {
        calendar.isDate(startsAt, inSameDayAs: endsAt) && isValidRange
    }

    /// Anfrage an das Backend, oder nil, wenn noch etwas fehlt.
    public func request(calendar: Calendar) -> ReservationRequest? {
        guard let carID, isValidRange else { return nil }
        let days = canRepeat(calendar: calendar) ? repeatDays : []
        let until = repeatUntil.map { day in
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        return ReservationRequest(carID: carID, startsAt: startsAt, endsAt: endsAt, repeatDays: days, until: until)
    }

    // MARK: Texte

    /// Linke Seite der Zeitzeile: „Sa, 31. Okt"; über mehrere Tage „Fr, 30. Okt – So, 1. Nov".
    public func dateText(_ text: TimeText) -> String {
        if text.calendar.isDate(startsAt, inSameDayAs: endsAt) { return text.shortDate(startsAt) }
        return "\(text.shortDate(startsAt)) – \(text.shortDate(endsAt))"
    }

    /// Rechte Seite: „10:00 – 16:00".
    public func timeText(_ text: TimeText) -> String {
        "\(text.time(startsAt)) – \(text.time(endsAt))"
    }

    /// „Nie", „Jeden Sa", „Mo–Do", „Mo, Mi, Fr", „Jeden Tag"; mit Ende „Mo–Do bis 30. Nov".
    public func repeatText(_ text: TimeText) -> String {
        guard !repeatDays.isEmpty else { return "Nie" }
        let days = Self.weekdayText(repeatDays)
        guard let repeatUntil else { return days }
        return "\(days) bis \(text.dayMonth(repeatUntil))"
    }

    static func weekdayText(_ days: Set<Weekday>) -> String {
        if days.count == 7 { return "Jeden Tag" }
        if days.count == 1, let day = days.first { return "Jeden \(day.short)" }
        var runs: [[Weekday]] = []
        for day in days.sorted() {
            if let last = runs.last?.last, last.rawValue + 1 == day.rawValue {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        return runs.map { run in
            run.count >= 3 ? "\(run[0].short)–\(run[run.count - 1].short)" : run.map(\.short).joined(separator: ", ")
        }.joined(separator: ", ")
    }

    // MARK: Intern

    private func with(preset: Preset, startsAt: Date? = nil, endsAt: Date? = nil) -> ReservationDraft {
        ReservationDraft(preset: preset, startsAt: startsAt ?? self.startsAt, endsAt: endsAt ?? self.endsAt,
                         carID: carID, repeatDays: repeatDays, repeatUntil: repeatUntil)
    }

    static func at(_ hour: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    static func roundedUp(_ date: Date, calendar: Calendar) -> Date {
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let extra = (roundingMinutes - minute % roundingMinutes) % roundingMinutes
        let truncated = date.addingTimeInterval(-Double(second))
        return truncated.addingTimeInterval(Double(extra * 60))
    }
}
