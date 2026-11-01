import Foundation
import Testing
@testable import CarpoolKit

struct CalendarStateTests {
    private func state(me: Member, day: Date = Fixture.at(0), now: Date = Fixture.at(10),
                       bookings: [Booking] = Fixture.bookings(), cars: [Car]? = nil) -> CalendarState {
        let snapshot = FamilySnapshot(family: Fixture.family, me: me,
                                      members: [Fixture.papa, Fixture.mama, Fixture.lisa, Fixture.jonas, Fixture.felix],
                                      cars: cars ?? [Fixture.flitzer, Fixture.radieschen, Fixture.octavia],
                                      bookings: bookings)
        return CalendarState(snapshot: snapshot, selectedDay: day, now: now, timeText: Fixture.text)
    }

    @Test func mockupF10Today() {
        let calendar = state(me: Fixture.lisa)
        #expect(calendar.title == "Oktober")
        #expect(calendar.dayTitle == "Heute")
        #expect(calendar.entries.map(\.startLabel) == ["08:00", "09:12", "14:00", "18:00"])
        #expect(calendar.entries.map(\.timeText) == ["08:00–17:30", "seit 09:12", "14:00–19:00", "18:00–22:00"])
        #expect(calendar.entries.map(\.car.title) == ["Octavia", "Radieschen", "Flitzer", "Radieschen"])
        #expect(calendar.entries.map(\.isDriving) == [true, true, false, false])
        #expect(calendar.entries[1].personName == "Du")
        #expect(calendar.entries[0].accessibilityText == "Mama, Octavia, 08:00–17:30, fährt gerade")
    }

    @Test func weekStartsMondayWithCarDots() {
        let calendar = state(me: Fixture.lisa)
        #expect(calendar.week.map(\.weekday) == ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
        #expect(calendar.week.map(\.number) == ["26", "27", "28", "29", "30", "31", "1"])
        let friday = calendar.week[4]
        #expect(friday.isToday && friday.isSelected)
        #expect(friday.carSlots == [1, 2, 3])
        #expect(calendar.week[5].carSlots.isEmpty)
    }

    @Test func otherDayTitles() {
        #expect(state(me: Fixture.lisa, day: Fixture.at(0, dayOffset: 1)).dayTitle == "Morgen")
        #expect(state(me: Fixture.lisa, day: Fixture.at(0, dayOffset: 4)).dayTitle == "Dienstag, 3. November")
        #expect(state(me: Fixture.lisa, day: Fixture.at(0, dayOffset: 4)).title == "November")
    }

    @Test func multiDayReservationSplitsAcrossDays() {
        let trip = Booking(id: UUID(), familyId: Fixture.familyID, carId: Fixture.flitzer.id,
                           memberId: Fixture.felix.id, startsAt: Fixture.at(18, dayOffset: 1),
                           endsAt: Fixture.at(10, dayOffset: 3), kind: .reservation)
        let texts = (1...3).map { state(me: Fixture.lisa, day: Fixture.at(0, dayOffset: $0), bookings: [trip])
            .entries.map(\.timeText) }
        #expect(texts == [["ab 18:00"], ["ganztägig"], ["bis 10:00"]])
        #expect(state(me: Fixture.lisa, day: Fixture.at(0, dayOffset: 2), bookings: [trip]).entries[0].startLabel == "")
    }

    @Test func ownReservationCanBeCancelled() {
        let mine = Booking(id: UUID(), familyId: Fixture.familyID, carId: Fixture.flitzer.id,
                           memberId: Fixture.lisa.id, startsAt: Fixture.at(14), endsAt: Fixture.at(16),
                           kind: .reservation, seriesId: UUID())
        let entry = state(me: Fixture.lisa, bookings: [mine]).entries[0]
        #expect(entry.canCancel)
        #expect(entry.isRepeating)
        #expect(!entry.canDisplace)
        #expect(state(me: Fixture.felix, bookings: [mine]).entries[0].canCancel == false)
    }

    @Test func primaryUserCanDisplaceFutureReservationsOnly() {
        let flitzer = Car(id: Fixture.flitzer.id, familyId: Fixture.familyID, make: "Toyota", model: "Yaris",
                          paint: "blau", nickname: "Flitzer", primaryMemberId: Fixture.papa.id, colorSlot: 3,
                          fuelQuarters: 2)
        let cars = [flitzer, Fixture.radieschen, Fixture.octavia]
        let papa = state(me: Fixture.papa, cars: cars)
        #expect(papa.entries.first { $0.car.id == flitzer.id }?.canDisplace == true)
        #expect(papa.entries.filter { $0.car.id != flitzer.id }.allSatisfy { !$0.canDisplace })

        let later = state(me: Fixture.papa, now: Fixture.at(15), cars: cars)
        #expect(later.entries.first { $0.car.id == flitzer.id }?.canDisplace == false, "läuft schon")
    }

    @Test func movingWeeks() {
        let next = CalendarState.day(Fixture.at(10), movedByWeeks: 1, timeText: Fixture.text)
        #expect(next == Fixture.at(0, dayOffset: 7))
    }
}
