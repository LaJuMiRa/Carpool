import Foundation
import Testing
@testable import CarpoolKit

private func conflict(_ member: Member, _ start: Date, _ end: Date?, kind: Booking.Kind = .reservation,
                      canDisplace: Bool = false) -> ReservationConflict {
    ReservationConflict(bookingId: UUID(), kind: kind, startsAt: start, endsAt: end, memberId: member.id,
                        firstName: member.firstName, canDisplace: canDisplace)
}

struct ReservationTextsTests {
    private let now = Fixture.at(9)
    private let saturday = Fixture.at(10, dayOffset: 1)

    private func text(_ conflicts: [ReservationConflict], me: Member = Fixture.papa,
                      start: Date? = nil) -> String {
        ReservationTexts.conflict(conflicts, car: "Octavia", me: me.id, requestedStart: start ?? saturday,
                                  now: now, text: Fixture.text)
    }

    @Test func mockupF12() {
        let felix = conflict(Fixture.felix, saturday, Fixture.at(16, dayOffset: 1))
        #expect(text([felix]) == "Felix hat Octavia von 10:00 bis 16:00.")
        #expect(text([felix], start: Fixture.at(10)) == "Felix hat Octavia morgen von 10:00 bis 16:00.")
        #expect(text([felix], me: Fixture.felix) == "Du hast Octavia schon von 10:00 bis 16:00.")
    }

    @Test func trips() {
        #expect(text([conflict(Fixture.mama, Fixture.at(8), Fixture.at(17, 30), kind: .trip)])
            == "Mama fährt Octavia bis 17:30.")
        #expect(text([conflict(Fixture.mama, Fixture.at(8), nil, kind: .trip)])
            == "Mama ist gerade mit Octavia unterwegs.")
    }

    @Test func severalOccurrences() {
        let three = (1...3).map { conflict(Fixture.felix, Fixture.at(10, dayOffset: $0 * 7), nil) }
        #expect(text(three) == "Felix hat Octavia an 3 Terminen.")
        let mixed = [conflict(Fixture.felix, saturday, nil), conflict(Fixture.jonas, Fixture.at(10, dayOffset: 8), nil)]
        #expect(text(mixed) == "Octavia ist an 2 Terminen belegt.")
    }

    @Test func mockupF14() {
        let felix = conflict(Fixture.felix, saturday, Fixture.at(16, dayOffset: 1), canDisplace: true)
        #expect(ReservationTexts.displaceTitle([felix]) == "Felix’ Buchung übernehmen?")
        #expect(ReservationTexts.displaceMessage([felix], now: now, text: Fixture.text)
            == "Felix verliert die Reservierung morgen, 10:00–16:00, und bekommt eine Nachricht.")
        let lisa = conflict(Fixture.lisa, Fixture.at(10, dayOffset: 2), nil)
        #expect(ReservationTexts.displaceTitle([lisa, lisa]) == "Lisas Buchungen übernehmen?")
        #expect(ReservationTexts.displaceMessage([felix, lisa], now: now, text: Fixture.text)
            == "Felix und Lisa verlieren ihre Reservierungen und bekommen eine Nachricht.")
        #expect(ReservationTexts.noReplacementMessage([felix])
            == "Für Felix ist in dieser Zeit kein anderes Auto frei.")
    }
}

@MainActor
struct ReservationModelTests {
    private let now = Fixture.at(10)

    private func model(_ api: FakeAPI, me: Member = Fixture.papa) -> ReservationModel {
        ReservationModel(snapshot: Fixture.snapshot(me: me), api: api, day: Fixture.at(0, dayOffset: 1),
                         clock: { Fixture.at(10) })
    }

    /// Wartet, bis die Prüfung nach einer Änderung durch ist.
    private func settle(_ model: ReservationModel) async {
        for _ in 0..<100 where model.check == nil && model.checkError == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func freeCarCanBeReserved() async {
        let api = FakeAPI(.init(freeCars: [Fixture.radieschen, Fixture.octavia, Fixture.flitzer]))
        let model = model(api)
        model.start()
        await settle(model)
        #expect(model.draft.preset == .tomorrow)
        #expect(model.selectedCar == Fixture.radieschen, "erstes Auto nach Kalenderfarbe")
        #expect(model.status(of: Fixture.octavia) == .free)
        #expect(model.conflictBanner == nil)
        #expect(model.canSubmit)

        await model.submit()
        #expect(model.step == .done)
        #expect(api.calls.last == "reserve displace=false accept=false")
    }

    @Test func conflictShowsBannerWithSwapCars() async throws {
        let felix = conflict(Fixture.felix, Fixture.at(8, dayOffset: 1), Fixture.at(17, dayOffset: 1))
        let api = FakeAPI(.init(checkResults: [.success, ReservationResult(
            ok: false, reason: .conflict, conflicts: [felix], freeCarIds: [Fixture.flitzer.id])]))
        let model = model(api)
        model.start()
        await settle(model)
        model.select(car: Fixture.octavia)
        await settle(model)

        let banner = try #require(model.conflictBanner)
        #expect(banner.text == "Felix hat Octavia von 08:00 bis 17:00.")
        #expect(banner.personShort == "Fe")
        #expect(banner.swapCars == [Fixture.flitzer])
        #expect(!banner.canDisplace)
        #expect(model.submitTitle == "Octavia ist belegt")
        #expect(!model.canSubmit)
        #expect(model.status(of: Fixture.octavia) == .reserved)
        #expect(model.status(of: Fixture.flitzer) == .free)

        model.select(car: Fixture.flitzer)
        #expect(model.draft.carID == Fixture.flitzer.id)
    }

    @Test func displaceAsksForConfirmationAndWarnsWithoutReplacement() async throws {
        let felix = conflict(Fixture.felix, Fixture.at(8, dayOffset: 1), Fixture.at(17, dayOffset: 1),
                             canDisplace: true)
        let blocked = ReservationResult(ok: false, reason: .conflict, conflicts: [felix])
        let api = FakeAPI(.init(checkResults: [blocked], reserveResults: [
            ReservationResult(ok: false, reason: .noReplacement, conflicts: [felix]), .success]))
        let model = model(api)
        model.start()
        await settle(model)

        #expect(model.conflictBanner?.canDisplace == true)
        model.requestDisplace()
        #expect(model.step == .confirmDisplace([felix]))

        await model.confirmDisplace()
        #expect(model.step == .confirmNoReplacement([felix]))

        await model.confirmNoReplacement()
        #expect(model.step == .done)
        #expect(api.calls.suffix(2) == ["reserve displace=true accept=false", "reserve displace=true accept=true"])
    }

    @Test func repeatIsSentAsRRule() async {
        let api = FakeAPI(.init(freeCars: []))
        let model = model(api)
        model.setRepeat([.monday], until: nil)
        model.start()
        await settle(model)
        #expect(api.state.withLock { $0.requests.last?.rrule } == "FREQ=WEEKLY;BYDAY=MO")
    }
}

@MainActor
struct CalendarStoreTests {
    @Test func cancelRemovesLocallyAndCallsServer() async throws {
        let mine = Booking(id: UUID(), familyId: Fixture.familyID, carId: Fixture.flitzer.id,
                           memberId: Fixture.papa.id, startsAt: Fixture.at(14), endsAt: Fixture.at(16),
                           kind: .reservation)
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.papa, bookings: [mine])))
        let store = FamilyStore(member: Fixture.papa, api: api)
        await store.refresh()
        await store.cancel(mine, wholeSeries: false)
        #expect(api.calls == ["cancel series=false"])
        #expect(store.actionError == nil)
    }

    @Test func displacePassesResultThrough() async {
        let booking = Fixture.bookings()[2]
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.papa), displaceResults: [.noReplacement]))
        let store = FamilyStore(member: Fixture.papa, api: api)
        #expect(await store.displace(booking, acceptNoReplacement: false) == .noReplacement)
        #expect(api.calls == ["displace accept=false"])
    }
}
