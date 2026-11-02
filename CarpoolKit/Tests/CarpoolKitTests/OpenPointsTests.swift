import Foundation
import Testing
@testable import CarpoolKit

/// Mitglieder entfernen, Reservierung bearbeiten / verlängern / übergeben, vergangene Fahrten im Kalender.
struct OpenPointsTests {
    private static let removedFelix = Member(id: Fixture.felix.id, familyId: Fixture.familyID, userId: nil,
                                             firstName: "Felix", short: "Fe", role: .member,
                                             removedAt: Fixture.at(8))

    private func snapshot(me: Member, members: [Member]? = nil, bookings: [Booking] = Fixture.bookings())
        -> FamilySnapshot {
        FamilySnapshot(family: Fixture.family, me: me,
                       members: members ?? [Fixture.papa, Fixture.mama, Fixture.lisa, Fixture.jonas, Fixture.felix],
                       cars: [Fixture.flitzer, Fixture.radieschen, Fixture.octavia], bookings: bookings)
    }

    // MARK: Mitglieder entfernen

    @Test("Entfernte Mitglieder: nicht in der Liste, Name bleibt für alte Buchungen")
    func removedMembersAreHidden() {
        let members = [Fixture.papa, Fixture.mama, Fixture.lisa, Fixture.jonas, Self.removedFelix]
        let snap = snapshot(me: Fixture.papa, members: members)
        #expect(snap.activeMembers.map(\.firstName) == ["Papa", "Mama", "Lisa", "Jonas"])
        #expect(snap.member(Fixture.felix.id)?.firstName == "Felix")

        let state = MembersState(snapshot: snap, now: Fixture.at(10), timeText: Fixture.text)
        #expect(!state.rows.map(\.member.firstName).contains("Felix"))
    }

    @Test("Entfernen: nur Admins, nicht sich selbst")
    func onlyAdminsRemoveOthers() {
        let asPapa = MembersState(snapshot: snapshot(me: Fixture.papa), now: Fixture.at(10), timeText: Fixture.text)
        #expect(asPapa.rows.filter(\.canRemove).map(\.member.firstName) == ["Mama", "Lisa", "Jonas", "Felix"])

        let asLisa = MembersState(snapshot: snapshot(me: Fixture.lisa), now: Fixture.at(10), timeText: Fixture.text)
        #expect(asLisa.rows.allSatisfy { !$0.canRemove })
    }

    @Test("Mitglied liest removed_at aus der Datenbank")
    func memberDecodesRemovedAt() throws {
        let json = """
        {"id":"\(UUID())","family_id":"\(UUID())","user_id":null,"first_name":"Felix","short":"Fe",
         "role":"member","removed_at":"2026-11-02T10:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let member = try decoder.decode(Member.self, from: Data(json.utf8))
        #expect(member.isRemoved)
    }

    // MARK: Kontextmenü

    @Test("Eigene Reservierung: bearbeiten, verlängern, übergeben, löschen")
    func ownReservationActions() {
        let calendar = CalendarState(snapshot: snapshot(me: Fixture.felix), selectedDay: Fixture.at(0),
                                     now: Fixture.at(10), timeText: Fixture.text)
        let entry = calendar.entries.first { $0.car.id == Fixture.flitzer.id }
        #expect(entry?.canCancel == true)
        #expect(entry?.canExtend == true)
    }

    @Test("Eigene laufende Fahrt: nur verlängern")
    func runningTripCanBeExtended() {
        let calendar = CalendarState(snapshot: snapshot(me: Fixture.lisa), selectedDay: Fixture.at(0),
                                     now: Fixture.at(10), timeText: Fixture.text)
        let trip = calendar.entries.first { $0.isDriving && $0.personName == "Du" }
        #expect(trip?.canExtend == true)
        #expect(trip?.canCancel == false)
        let others = calendar.entries.filter { $0.personName != "Du" }
        #expect(others.allSatisfy { !$0.canExtend })
    }

    @Test("Verlängern: um 30 min, 1 h, 2 h ab dem Ende")
    func extensionOptionsForReservation() {
        let felix = Fixture.bookings()[2]  // Flitzer 14:00–19:00
        let options = BookingExtension.options(for: felix, now: Fixture.at(10), text: Fixture.text)
        #expect(options.map(\.title) == ["Bis 19:30", "Bis 20:00", "Bis 21:00"])
        #expect(options.map(\.endsAt) == [Fixture.at(19, 30), Fixture.at(20), Fixture.at(21)])
    }

    @Test("Verlängern einer Fahrt ohne Plan: ab jetzt, auf 5 min aufgerundet")
    func extensionOptionsForOpenTrip() {
        let lisa = Fixture.bookings()[1]  // seit 09:12, ohne geplantes Ende
        let options = BookingExtension.options(for: lisa, now: Fixture.at(10, 2), text: Fixture.text)
        #expect(options.map(\.title) == ["Bis 10:35", "Bis 11:05", "Bis 12:05"])
    }

    @Test("Übergeben: an alle anderen aktiven Mitglieder")
    func transferTargets() {
        let members = [Fixture.papa, Fixture.mama, Fixture.lisa, Fixture.jonas, Self.removedFelix]
        let snap = snapshot(me: Fixture.lisa, members: members)
        #expect(BookingExtension.transferTargets(in: snap).map(\.firstName) == ["Papa", "Mama", "Jonas"])
    }

    // MARK: Bearbeiten

    @MainActor
    @Test("Bearbeiten: Formular mit der Buchung, Anfrage trägt die Buchung, „Speichern“")
    func editingReservation() async throws {
        let booking = Fixture.bookings()[2]
        let api = FakeAPI(.init(snapshot: snapshot(me: Fixture.felix)))
        let model = ReservationModel(snapshot: snapshot(me: Fixture.felix), api: api, editing: booking,
                                     clock: { Fixture.at(10) })
        #expect(model.isEditing)
        #expect(model.draft.startsAt == Fixture.at(14))
        #expect(model.draft.endsAt == Fixture.at(19))
        #expect(model.draft.carID == Fixture.flitzer.id)
        #expect(!model.canRepeat)
        #expect(model.submitTitle == "Speichern")

        model.setEnd(Fixture.at(20))
        await model.submit()
        #expect(api.state.withLock { $0.requests.last?.bookingID } == booking.id)
        #expect(model.step == .done)
    }

    // MARK: Vergangene Fahrten

    @Test("Kalender zeigt abgeschlossene Fahrten vergangener Tage, gedämpft und ohne Aktionen")
    func historyAppearsOnPastDays() {
        let done = Booking(id: UUID(), familyId: Fixture.familyID, carId: Fixture.octavia.id,
                           memberId: Fixture.jonas.id, startsAt: Fixture.at(9, 12, dayOffset: -2),
                           endsAt: Fixture.at(11, 40, dayOffset: -2), kind: .trip, status: .completed)
        let calendar = CalendarState(snapshot: snapshot(me: Fixture.jonas), history: [done],
                                     selectedDay: Fixture.at(0, dayOffset: -2), now: Fixture.at(10),
                                     timeText: Fixture.text)
        #expect(calendar.entries.map(\.timeText) == ["09:12–11:40"])
        #expect(calendar.entries.first?.isPast == true)
        #expect(calendar.entries.first?.canCancel == false)
        #expect(calendar.entries.first?.canExtend == false)
        #expect(calendar.week.first { $0.number == "28" }?.carSlots == [Fixture.octavia.colorSlot])
    }

    @Test("Doppelte Buchungen aus Verlauf und aktuellem Stand erscheinen nur einmal")
    func historyIsDeduplicated() {
        let bookings = Fixture.bookings()
        let calendar = CalendarState(snapshot: snapshot(me: Fixture.jonas, bookings: bookings), history: [bookings[2]],
                                     selectedDay: Fixture.at(0), now: Fixture.at(10), timeText: Fixture.text)
        #expect(calendar.entries.count == 4)
    }

    // MARK: Push und Fehler

    @Test("Push „übergeben“ öffnet den Kalender")
    func transferPushOpensCalendar() {
        #expect(DeepLink(notificationKind: "booking_transferred", carID: nil) == .calendar)
    }

    @Test("Neue Fehlercodes haben eigene Texte", arguments: [
        "too_many_attempts", "cannot_remove_self", "member_driving", "not_editable"
    ])
    func newErrorCodesHaveMessages(code: String) {
        #expect(CarpoolError(code: code).message != CarpoolError(code: "unknown").message)
    }

    @Test("Fehler mit eigenem Text (z. B. Konflikt beim Verlängern)")
    func errorWithDetail() {
        #expect(CarpoolError(code: "conflict", detail: "Lisa hat Radieschen von 19:30 bis 21:00.").message
            == "Lisa hat Radieschen von 19:30 bis 21:00.")
    }
}

@MainActor
struct OpenPointsStoreTests {
    @Test("Verlängern mit Konflikt: Hinweis nennt, wer das Auto hat")
    func extendConflictNamesPerson() async {
        let felixBooking = Fixture.bookings()[2]
        let conflict = ReservationConflict(bookingId: UUID(), kind: .reservation, startsAt: Fixture.at(19, 30),
                                           endsAt: Fixture.at(21), memberId: Fixture.lisa.id, firstName: "Lisa",
                                           canDisplace: false)
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.felix),
                                reserveResults: [ReservationResult(ok: false, reason: .conflict,
                                                                   conflicts: [conflict])]))
        let store = FamilyStore(member: Fixture.felix, api: api)
        await store.refresh()

        let ok = await store.extend(felixBooking, to: Fixture.at(20), now: Fixture.at(10))
        #expect(!ok)
        #expect(store.actionError?.message == "Lisa hat Flitzer von 19:30 bis 21:00.")
    }

    @Test("Verlauf wird für eine vergangene Woche geladen und beim Neuladen aktualisiert")
    func historyIsLoadedForPastWeeks() async {
        let done = Booking(id: UUID(), familyId: Fixture.familyID, carId: Fixture.octavia.id,
                           memberId: Fixture.jonas.id, startsAt: Fixture.at(9, dayOffset: -2),
                           endsAt: Fixture.at(11, dayOffset: -2), kind: .trip, status: .completed)
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.jonas), history: [done]))
        let store = FamilyStore(member: Fixture.jonas, api: api)

        await store.showHistory(from: Fixture.at(0, dayOffset: -4), to: Fixture.at(0, dayOffset: 3))
        #expect(store.history == [done])
        await store.refresh()
        #expect(api.calls.filter { $0 == "history" }.count == 2)
    }

    @Test("Zukünftige Woche: kein Verlauf nötig")
    func noHistoryForFutureWeeks() async {
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.jonas)))
        let store = FamilyStore(member: Fixture.jonas, api: api)
        await store.showHistory(from: Date().addingTimeInterval(86_400), to: Date().addingTimeInterval(8 * 86_400))
        #expect(!api.calls.contains("history"))
        #expect(store.history.isEmpty)
    }
}

@MainActor
struct DeleteAccountTests {
    @Test("Konto löschen: Backend wird aufgerufen, danach abgemeldet")
    func deleteAccountSignsOut() async throws {
        let api = FakeAPI(.init(membership: Fixture.lisa))
        let session = AppSession(api: api)
        await session.handle(userID: UUID())
        #expect(session.phase == .ready(Fixture.lisa))

        try await session.deleteAccount()
        #expect(api.calls.contains("deleteAccount"))
        #expect(session.phase == .signedOut)
    }

    @Test("Konto löschen: Fehler (z. B. letzter Admin) kommt an, Anmeldung bleibt")
    func deleteAccountErrorKeepsSession() async {
        let api = FakeAPI(.init(membership: Fixture.papa, writeError: CarpoolError(code: "transfer_admin_first")))
        let session = AppSession(api: api)
        await session.handle(userID: UUID())
        await #expect(throws: CarpoolError(code: "transfer_admin_first")) { try await session.deleteAccount() }
        #expect(session.phase == .ready(Fixture.papa))
        #expect(CarpoolError(code: "transfer_admin_first").message
            == "Mach zuerst jemand anderen zum Admin, dann kannst du dein Konto löschen.")
    }
}
