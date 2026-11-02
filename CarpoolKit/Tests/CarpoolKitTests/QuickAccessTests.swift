import Foundation
import Testing
@testable import CarpoolKit

@Suite("Widgets")
struct WidgetStateTests {
    @Test("Während der Fahrt: eigenes Auto „bei dir“, Zurückgeben, nächste Person auf dem Auto")
    func whileDriving() {
        let state = WidgetState(snapshot: Fixture.snapshot(me: Fixture.lisa), now: Fixture.at(12, 25),
                                timeText: Fixture.text)

        #expect(state.title == "1 von 3 frei")
        #expect(state.cars.map(\.car.title) == ["Radieschen", "Octavia", "Flitzer"])
        #expect(state.cars.map(\.statusText) == ["bei dir", "unterwegs", "frei"])
        #expect(state.myCar?.car.id == Fixture.radieschen.id)
        #expect(state.myCar?.detail == "seit 09:12")
        #expect(state.returnTitle == "Radieschen zurückgeben")
        #expect(state.next == WidgetState.NextTrip(time: "18:00", day: nil, text: "Jonas nimmt Radieschen",
                                                    colorSlot: 1))
    }

    @Test("Ohne Fahrt: eigene nächste Reservierung, kein Zurückgeben")
    func ownReservation() {
        let state = WidgetState(snapshot: Fixture.snapshot(me: Fixture.felix), now: Fixture.at(12, 25),
                                timeText: Fixture.text)

        #expect(state.returnTitle == nil)
        #expect(state.myCar == nil)
        #expect(state.next?.text == "Du nimmst Flitzer")
        #expect(state.next?.time == "14:00")
        #expect(state.cars.first { $0.car.id == Fixture.radieschen.id }?.statusText == "unterwegs")
    }

    @Test("Reservierung morgen trägt den Tag, Hauptnutzer-Auto im kleinen Widget")
    func tomorrowAndPrimaryCar() {
        let flitzer = Car(id: Fixture.flitzer.id, familyId: Fixture.familyID, make: "Toyota", model: "Yaris",
                          paint: "blau", nickname: "Flitzer", primaryMemberId: Fixture.jonas.id, colorSlot: 3,
                          fuelQuarters: 2)
        let tomorrow = Booking(id: UUID(), familyId: Fixture.familyID, carId: flitzer.id,
                               memberId: Fixture.jonas.id, startsAt: Fixture.at(8, dayOffset: 1),
                               endsAt: Fixture.at(12, dayOffset: 1), kind: .reservation)
        let snapshot = FamilySnapshot(family: Fixture.family, me: Fixture.jonas,
                                      members: [Fixture.jonas], cars: [flitzer], bookings: [tomorrow])
        let state = WidgetState(snapshot: snapshot, now: Fixture.at(20), timeText: Fixture.text)

        #expect(state.next?.day == "Morgen")
        #expect(state.next?.time == "08:00")
        #expect(state.myCar?.car.id == flitzer.id)
        #expect(state.myCar?.statusText == "frei")
    }

    @Test("Zeitleiste: jetzt plus jede Buchungsgrenze, sortiert und ohne Doppelte")
    func timeline() {
        let dates = WidgetState.timelineDates(snapshot: Fixture.snapshot(me: Fixture.lisa), now: Fixture.at(12, 25))

        #expect(dates == [Fixture.at(12, 25), Fixture.at(13), Fixture.at(14), Fixture.at(17), Fixture.at(17, 30),
                          Fixture.at(18), Fixture.at(19), Fixture.at(22)])
    }

    @Test("Snapshot wird für die Widgets gespeichert und gelöscht")
    func sharedStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedSnapshotStore(directory: directory)
        let snapshot = Fixture.snapshot(me: Fixture.lisa)

        #expect(store.load() == nil)
        try store.save(snapshot)
        #expect(store.load() == snapshot)
        store.clear()
        #expect(store.load() == nil)
    }
}

@Suite("Live-Aktivität, Deep Links, Push")
struct TripActivityTests {
    @Test("Inhalt der Live-Aktivität aus der eigenen Fahrt")
    func content() throws {
        let now = Fixture.at(12, 25)
        let trip = try #require(OverviewState(snapshot: Fixture.snapshot(me: Fixture.lisa), now: now,
                                              timeText: Fixture.text).myTrip)
        let attributes = TripActivityAttributes(trip: trip)
        let state = TripActivityAttributes.ContentState(trip: trip, now: now, timeText: Fixture.text)

        #expect(attributes.carTitle == "Radieschen")
        #expect(attributes.colorSlot == 1)
        #expect(state.sinceText == "Du fährst seit 09:12")
        #expect(state.startTime == "09:12")
        #expect(state.startedAt == Fixture.at(9, 12))
        #expect(state.nextText == "Jonas ab 18:00")
        #expect(state.nextAt == Fixture.at(18))
    }

    @Test("Deep Links hin und zurück", arguments: [DeepLink.overview, .returnCar, .calendar, .car(UUID())])
    func roundTrip(link: DeepLink) {
        #expect(DeepLink(url: link.url) == link)
    }

    @Test("Fremde oder kaputte Links werden ignoriert")
    func invalidLinks() {
        #expect(DeepLink(url: URL(string: "https://example.com/return")!) == nil)
        #expect(DeepLink(url: URL(string: "carpool://car/kein-auto")!) == nil)
        #expect(DeepLink(url: URL(string: "carpool://irgendwas")!) == nil)
    }

    @Test("Push-Art bestimmt das Ziel beim Antippen")
    func notificationTargets() {
        let carID = UUID()
        #expect(DeepLink(notificationKind: "car_free", carID: carID) == .overview)
        #expect(DeepLink(notificationKind: "return_overdue", carID: carID) == .returnCar)
        #expect(DeepLink(notificationKind: "booking_displaced", carID: carID) == .calendar)
        #expect(DeepLink(notificationKind: "reservation_soon", carID: carID) == .calendar)
        #expect(DeepLink(notificationKind: "service_pickerl", carID: carID) == .car(carID))
        #expect(DeepLink(notificationKind: nil, carID: nil) == .overview)
    }

    @Test("Gerätetoken als Hex")
    func tokenHex() {
        #expect(PushToken.hex(Data([0x0a, 0xff, 0x00])) == "0aff00")
    }
}
