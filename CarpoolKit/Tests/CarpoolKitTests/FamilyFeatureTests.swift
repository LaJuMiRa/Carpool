import Foundation
import Testing
@testable import CarpoolKit

private func car(_ base: Car, primary: Member? = nil, plate: String? = nil, pickerl: String? = nil,
                 service: String? = nil, km: Int? = nil) -> Car {
    Car(id: base.id, familyId: base.familyId, make: base.make, model: base.model, paint: base.paint,
        nickname: base.nickname, plate: plate, primaryMemberId: primary?.id, colorSlot: base.colorSlot,
        fuelQuarters: base.fuelQuarters, pickerlUntil: pickerl, serviceDue: service, odometerKm: km)
}

private func snapshot(me: Member, cars: [Car], damages: [Damage] = []) -> FamilySnapshot {
    FamilySnapshot(family: Fixture.family, me: me,
                   members: [Fixture.papa, Fixture.mama, Fixture.lisa, Fixture.jonas, Fixture.felix],
                   cars: cars, bookings: Fixture.bookings(), damages: damages)
}

struct MembersStateTests {
    @Test func mockupF15() {
        let cars = [car(Fixture.radieschen, primary: Fixture.papa), Fixture.octavia,
                    car(Fixture.flitzer, primary: Fixture.jonas)]
        let jonasTrip = Booking(id: UUID(), familyId: Fixture.familyID, carId: Fixture.flitzer.id,
                                memberId: Fixture.jonas.id, startsAt: Fixture.at(18), endsAt: Fixture.at(20),
                                kind: .reservation)
        let base = snapshot(me: Fixture.lisa, cars: cars)
        let withJonas = FamilySnapshot(family: base.family, me: base.me, members: base.members, cars: base.cars,
                                       bookings: base.bookings.filter { $0.memberId != Fixture.jonas.id } + [jonasTrip])
        let state = MembersState(snapshot: withJonas, now: Fixture.at(10), timeText: Fixture.text)
        #expect(state.title == "Familie Berger")
        let details = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.member.firstName, $0.detail) })
        #expect(details["Papa"] == "Hauptnutzer von Radieschen")
        #expect(details["Mama"] == "fährt gerade Octavia")
        #expect(details["Lisa"] == "fährt gerade Radieschen")
        #expect(details["Jonas"] == "Hauptnutzer von Flitzer · heute 18:00")
        #expect(details["Felix"] == "nächste Fahrt heute 14:00")
        #expect(state.rows.first { $0.member == Fixture.mama }?.tone == .driving)
        #expect(state.rows.first { $0.member == Fixture.papa }?.isAdmin == true)
        #expect(state.inviteMessage.hasSuffix("Code ein: K7P-2QX"))
    }
}

struct CarDetailStateTests {
    @Test func mockupF05ForLisa() {
        let golf = car(Fixture.radieschen, primary: Fixture.papa, plate: "BN-123AB", pickerl: "2027-03-31",
                       service: "2026-11-20")
        let damage = Damage(id: UUID(), familyId: Fixture.familyID, carId: golf.id, reportedBy: Fixture.lisa.id,
                            description: "Kratzer Stoßstange hinten", drivable: true,
                            createdAt: Fixture.at(12, dayOffset: -18))
        let snap = snapshot(me: Fixture.lisa, cars: [golf, Fixture.octavia, Fixture.flitzer], damages: [damage])
        let detail = CarDetailState(car: golf, snapshot: snap, now: Fixture.at(10), timeText: Fixture.text)
        #expect(detail.isMine)
        #expect(detail.statusText == "bei dir")
        #expect(detail.statusDetail == "seit 09:12")
        #expect(detail.primaryText == "Hauptnutzer: Papa")
        #expect(detail.upcoming.map(\.timeText) == ["Heute, 18:00–22:00"])
        #expect(detail.upcoming.map(\.personText) == ["Jonas"])
        #expect(detail.damages.map(\.meta) == ["Lisa, 12. Okt · fahrbereit"])
        #expect(detail.conditions.map(\.value) == ["bis März 2027", "in 3 Wochen", "BN-123AB"])
        #expect(detail.conditions[1].tone == .warning)
    }

    @Test func otherCarCanBeTaken() {
        let snap = snapshot(me: Fixture.papa, cars: [Fixture.radieschen, Fixture.octavia, Fixture.flitzer])
        let detail = CarDetailState(car: Fixture.flitzer, snapshot: snap, now: Fixture.at(10), timeText: Fixture.text)
        #expect(!detail.isMine && detail.canTake)
        #expect(detail.status == .free)
        #expect(detail.upcoming.first?.personText == "Felix")
    }

    @Test(arguments: [("2026-10-29", "überfällig"), ("2026-10-30", "heute"), ("2026-10-31", "morgen"),
                      ("2026-11-04", "in 5 Tagen"), ("2026-12-20", "in 7 Wochen"), ("2027-05-03", "Mai 2027")])
    func serviceTexts(due: String, expected: String) throws {
        let day = try #require(CarDetailState.day(from: due, calendar: Fixture.text.calendar))
        #expect(CarDetailState.serviceCondition(day, now: Fixture.at(10), text: Fixture.text).value == expected)
    }

    @Test func expiredPickerl() throws {
        let day = try #require(CarDetailState.day(from: "2026-09-01", calendar: Fixture.text.calendar))
        let condition = CarDetailState.pickerlCondition(day, now: Fixture.at(10), text: Fixture.text)
        #expect(condition.value == "abgelaufen" && condition.tone == .danger)
    }
}

struct CarFormTests {
    @Test func splitsMakeAndModel() {
        #expect(CarForm(name: " BMW  X3 ").makeAndModel! == ("BMW", "X3"))
        #expect(CarForm(name: "Land Rover Defender 110").makeAndModel! == ("Land Rover", "Defender 110"))
        #expect(CarForm(name: "Mercedes-Benz C-Klasse").makeAndModel! == ("Mercedes-Benz", "C-Klasse"))
        #expect(CarForm(name: "BMW").makeAndModel == nil)
        #expect(CarForm(name: "BMW").nameHint == "Marke und Modell, z. B. „VW Golf“")
    }

    @Test func inputCleansOptionalFields() throws {
        let form = CarForm(name: "VW Golf", paint: "silber", nickname: "  ", plate: "bn-123ab",
                           pickerlUntil: Fixture.at(0, dayOffset: 152))
        let input = try #require(form.input(calendar: Fixture.text.calendar))
        #expect(input.nickname == nil)
        #expect(input.plate == "BN-123AB")
        #expect(input.pickerlUntil == "2027-03-31")
    }

    @Test func roundTripsExistingCar() {
        let golf = car(Fixture.radieschen, primary: Fixture.papa, pickerl: "2027-03-31")
        let form = CarForm(car: golf, calendar: Fixture.text.calendar)
        #expect(form.name == "VW Golf")
        #expect(form.nickname == "Radieschen")
        #expect(form.input(calendar: Fixture.text.calendar)?.pickerlUntil == "2027-03-31")
    }
}

@MainActor
struct FamilyStoreWriteTests {
    @Test func renameValidatesAndCallsServer() async {
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.lisa)))
        let store = FamilyStore(member: Fixture.lisa, api: api)
        #expect(await store.rename(firstName: "L", short: "Li") == false)
        #expect(store.actionError?.code == "invalid_name")
        #expect(await store.rename(firstName: " Lisa ", short: "Lí"))
        #expect(api.calls == ["name Lisa Lí"])
    }

    @Test func failedSettingsUpdateRollsBack() async {
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.lisa),
                                writeError: CarpoolError(code: "network")))
        let store = FamilyStore(member: Fixture.lisa, api: api)
        await store.refresh()
        var changed = store.settings!
        changed.calendarCarAnimation = .loop
        await store.update(changed)
        #expect(store.settings?.calendarCarAnimation == .once)
        #expect(store.actionError?.code == "network")
    }

    @Test func performReportsSuccess() async {
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.papa)))
        let store = FamilyStore(member: Fixture.papa, api: api)
        let report = DamageReport(carID: Fixture.flitzer.id, description: " Delle ", drivable: true, photo: Data([1]))
        #expect(await store.perform { try await $0.reportDamage(report, familyID: Fixture.familyID) })
        #expect(api.calls == ["damage Delle photo=true"])
    }
}
