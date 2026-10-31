import Foundation
import Testing
@testable import CarpoolKit

struct OverviewStateTests {
    private func state(me: Member, now: Date, bookings: [Booking] = Fixture.bookings()) -> OverviewState {
        OverviewState(snapshot: Fixture.snapshot(me: me, bookings: bookings), now: now, timeText: Fixture.text)
    }

    @Test func mockupF02FromLisasView() throws {
        let overview = state(me: Fixture.lisa, now: Fixture.at(10))
        #expect(overview.title == "1 von 3 frei")

        let trip = try #require(overview.myTrip)
        #expect(trip.car == Fixture.radieschen)
        #expect(trip.sinceText == "Du fährst seit 09:12")
        #expect(trip.fuelOnTakeText == "Tank beim Nehmen ¾")
        #expect(trip.next?.bannerText == "Jonas braucht ihn ab 18:00")
        #expect(trip.next?.returnNoteText == "Jonas bekommt eine Nachricht, dass Radieschen bereit ist.")

        #expect(overview.rows.map(\.car.title) == ["Octavia", "Flitzer"])
        let octavia = overview.rows[0]
        #expect(octavia.status == .busy)
        #expect(octavia.detail == "Mama, zurück um 17:30")
        #expect(!octavia.canTake)
        let flitzer = overview.rows[1]
        #expect(flitzer.status == .free)
        #expect(flitzer.detail == "Frei bis 14:00, dann Felix")
        #expect(!flitzer.canTake, "Lisa fährt schon")
    }

    @Test func freeCarCanBeTakenWhenNotDriving() {
        let overview = state(me: Fixture.papa, now: Fixture.at(10))
        #expect(overview.myTrip == nil)
        #expect(overview.rows.count == 3)
        #expect(overview.rows.first { $0.car == Fixture.flitzer }?.canTake == true)
        #expect(overview.rows.first { $0.car == Fixture.radieschen }?.detail == "Lisa, seit 09:12")
    }

    @Test func reservationSoonMakesCarReserved() throws {
        let overview = state(me: Fixture.papa, now: Fixture.at(13, 15))
        let flitzer = try #require(overview.rows.first { $0.car == Fixture.flitzer })
        #expect(flitzer.status == .reserved)
        #expect(flitzer.detail == "Felix ab 14:00")
        #expect(!flitzer.canTake)
        #expect(overview.title == "0 von 3 frei")
    }

    @Test func runningReservationShowsEnd() throws {
        let overview = state(me: Fixture.papa, now: Fixture.at(15))
        let flitzer = try #require(overview.rows.first { $0.car == Fixture.flitzer })
        #expect(flitzer.detail == "Felix bis 19:00")
    }

    @Test func ownReservationSoonCanBeTaken() throws {
        let overview = state(me: Fixture.felix, now: Fixture.at(13, 50))
        let flitzer = try #require(overview.rows.first { $0.car == Fixture.flitzer })
        #expect(flitzer.status == .reserved)
        #expect(flitzer.statusText == "für dich")
        #expect(flitzer.detail == "Deine Reservierung ab 14:00")
        #expect(flitzer.canTake)
    }

    @Test func nextUpTomorrowNamesTheDay() throws {
        var bookings = Fixture.bookings().filter { $0.carId != Fixture.radieschen.id || $0.kind == .trip }
        bookings.append(Booking(id: UUID(), familyId: Fixture.familyID, carId: Fixture.radieschen.id,
                                memberId: Fixture.jonas.id, startsAt: Fixture.at(8, dayOffset: 1),
                                endsAt: Fixture.at(9, dayOffset: 1), kind: .reservation))
        let overview = state(me: Fixture.lisa, now: Fixture.at(10), bookings: bookings)
        #expect(overview.myTrip?.next?.bannerText == "Jonas braucht ihn ab morgen 08:00")
    }

    @Test func freeWithoutReservationTodayHasNoDetail() throws {
        let overview = state(me: Fixture.papa, now: Fixture.at(20))
        let flitzer = try #require(overview.rows.first { $0.car == Fixture.flitzer })
        #expect(flitzer.status == .free)
        #expect(flitzer.detail == nil)
    }
}

struct FamilySnapshotTests {
    @Test func applyingTakeAddsRunningTrip() throws {
        let snapshot = Fixture.snapshot(me: Fixture.papa)
        let after = snapshot.applyingTake(carID: Fixture.flitzer.id, at: Fixture.at(10))
        let trip = try #require(after.myRunningTrip)
        #expect(trip.carId == Fixture.flitzer.id)
        #expect(trip.fuelQuartersOnTake == 2)
        #expect(snapshot.myRunningTrip == nil, "Original bleibt unverändert")
    }

    @Test func applyingTakeConvertsOwnReservation() throws {
        let snapshot = Fixture.snapshot(me: Fixture.felix)
        let after = snapshot.applyingTake(carID: Fixture.flitzer.id, at: Fixture.at(13, 50))
        let trip = try #require(after.myRunningTrip)
        #expect(trip.plannedEndsAt == Fixture.at(19))
        #expect(after.bookings.count == snapshot.bookings.count)
    }

    @Test func applyingReturnRemovesTripAndSetsFuel() {
        let snapshot = Fixture.snapshot(me: Fixture.lisa)
        let after = snapshot.applyingReturn(carID: Fixture.radieschen.id, fuel: FuelLevel(quarters: 1))
        #expect(after.myRunningTrip == nil)
        #expect(after.car(Fixture.radieschen.id)?.fuelQuarters == 1)
        #expect(snapshot.car(Fixture.radieschen.id)?.fuelQuarters == 3)
    }
}

struct CarpoolErrorTests {
    @Test func knownCodesHaveGermanText() {
        #expect(CarpoolError(code: "car_busy").message == "Das Auto ist gerade unterwegs.")
        #expect(CarpoolError(code: "gibt_es_nicht").message == "Das hat nicht geklappt. Versuch es noch einmal.")
    }

    @Test func urlErrorsBecomeNetwork() {
        #expect(CarpoolError.from(URLError(.notConnectedToInternet)).code == "network")
    }

    @Test(arguments: [("invalid_credentials", "invalid_credentials"), ("user_already_exists", "email_exists"),
                      ("email_exists", "email_exists"), ("validation_failed", "invalid_email"),
                      ("over_request_rate_limit", "unknown")])
    func authCodes(raw: String, code: String) {
        #expect(CarpoolError.authCode(raw) == code)
    }

    @Test func messagesHaveNoExclamationMarks() {
        #expect(CarpoolError.messages.values.allSatisfy { !$0.contains("!") })
    }
}
