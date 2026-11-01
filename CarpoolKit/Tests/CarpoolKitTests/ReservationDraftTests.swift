import Foundation
import Testing
@testable import CarpoolKit

struct ReservationDraftTests {
    private let calendar = Fixture.text.calendar
    private let car = Fixture.flitzer.id

    private func draft(day: Date = Fixture.at(0), now: Date = Fixture.at(10, 2)) -> ReservationDraft {
        .initial(day: day, carID: car, now: now, calendar: calendar)
    }

    @Test func todayStartsWithNowRoundedUp() {
        let draft = draft()
        #expect(draft.preset == .now)
        #expect(draft.startsAt == Fixture.at(10, 5))
        #expect(draft.endsAt == Fixture.at(12, 5))
    }

    @Test func presets() {
        let tonight = draft().applying(.tonight, now: Fixture.at(10), calendar: calendar)
        #expect(tonight.startsAt == Fixture.at(18) && tonight.endsAt == Fixture.at(22))
        let tomorrow = draft().applying(.tomorrow, now: Fixture.at(10), calendar: calendar)
        #expect(tomorrow.startsAt == Fixture.at(8, dayOffset: 1) && tomorrow.endsAt == Fixture.at(17, dayOffset: 1))
        #expect(ReservationDraft.presets(now: Fixture.at(10), calendar: calendar).contains(.tonight))
        #expect(!ReservationDraft.presets(now: Fixture.at(18, 30), calendar: calendar).contains(.tonight))
    }

    @Test func initialForOtherDays() {
        #expect(draft(day: Fixture.at(0, dayOffset: 1)).preset == .tomorrow)
        let later = draft(day: Fixture.at(0, dayOffset: 3))
        #expect(later.preset == .custom)
        #expect(later.startsAt == Fixture.at(8, dayOffset: 3))
    }

    @Test func movingStartKeepsDuration() {
        let moved = draft().with(start: Fixture.at(14))
        #expect(moved.preset == .custom)
        #expect(moved.endsAt == Fixture.at(16))
    }

    @Test func texts() {
        let text = Fixture.text
        let saturday = draft(day: Fixture.at(0, dayOffset: 1))
            .with(start: Fixture.at(10, dayOffset: 1)).with(end: Fixture.at(16, dayOffset: 1))
        #expect(saturday.dateText(text) == "Sa, 31. Okt")
        #expect(saturday.timeText(text) == "10:00 – 16:00")
        #expect(saturday.repeatText(text) == "Nie")
        #expect(saturday.with(repeatDays: [.saturday], until: nil).repeatText(text) == "Jeden Sa")
        #expect(saturday.with(repeatDays: [.monday, .tuesday, .wednesday, .thursday], until: Fixture.at(0, dayOffset: 31))
            .repeatText(text) == "Mo–Do bis 30. Nov")
        let weekend = saturday.with(end: Fixture.at(18, dayOffset: 2))
        #expect(weekend.dateText(text) == "Sa, 31. Okt – So, 1. Nov")
    }

    @Test func weekdayTexts() {
        #expect(ReservationDraft.weekdayText([.monday, .wednesday, .friday]) == "Mo, Mi, Fr")
        #expect(ReservationDraft.weekdayText([.monday, .tuesday, .wednesday, .friday]) == "Mo–Mi, Fr")
        #expect(ReservationDraft.weekdayText([.monday, .tuesday]) == "Mo, Di")
        #expect(ReservationDraft.weekdayText(Set(Weekday.allCases)) == "Jeden Tag")
    }

    @Test func requestBuildsRRuleOnlyForSameDay() throws {
        let series = draft().with(repeatDays: [.thursday, .monday], until: Fixture.at(0, dayOffset: 14))
        let request = try #require(series.request(calendar: calendar))
        #expect(request.rrule == "FREQ=WEEKLY;BYDAY=MO,TH")
        #expect(request.until == "2026-11-13")

        let overnight = series.with(end: Fixture.at(9, dayOffset: 1))
        #expect(!overnight.canRepeat(calendar: calendar))
        #expect(overnight.request(calendar: calendar)?.rrule == nil)
    }

    @Test func invalidRangeHasNoRequest() {
        #expect(draft().with(end: Fixture.at(9)).request(calendar: calendar) == nil)
    }
}
