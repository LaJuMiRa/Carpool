import Foundation
import Testing
@testable import CarpoolKit

@MainActor
struct AppSessionTests {
    @Test func phasesFollowAuthAndMembership() async throws {
        let api = FakeAPI()
        let session = AppSession(api: api)
        #expect(session.phase == .starting)

        await session.handle(userID: nil)
        #expect(session.phase == .signedOut)

        await session.handle(userID: UUID())
        #expect(session.phase == .needsFamily)

        try await session.createFamily(name: " Familie Berger ", firstName: "Papa ")
        #expect(session.phase == .ready(Fixture.papa))
        #expect(api.calls.contains("createFamily Familie Berger Papa"))
    }

    @Test func signUpWithConfirmationReportsIt() async {
        let session = AppSession(api: FakeAPI())
        await #expect(throws: CarpoolError(code: "confirmation_required")) {
            try await session.signUp(email: "neu@test.local", password: "geheim1")
        }
    }

    @Test func signInNormalizesEmail() async throws {
        let api = FakeAPI()
        try await AppSession(api: api).signIn(email: "  Papa@Test.local ", password: "x")
        #expect(api.calls == ["signIn papa@test.local"])
    }

    @Test func joinErrorIsPassedThrough() async {
        let session = AppSession(api: FakeAPI())
        await #expect(throws: CarpoolError(code: "invalid_invite_code")) {
            try await session.joinFamily(inviteCode: "XXX-XXX", firstName: "Lisa")
        }
    }
}

@MainActor
struct FamilyStoreTests {
    @Test func takeOffersUndoAndCallsServer() async throws {
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.papa)))
        let store = FamilyStore(member: Fixture.papa, api: api)
        await store.refresh()

        await store.take(Fixture.flitzer, now: Fixture.at(10))
        #expect(api.calls == ["take"])
        #expect(store.undoOffer?.text == "Flitzer gehört dir")
        #expect(store.actionError == nil)
    }

    @Test func failedTakeRestoresSnapshotAndShowsError() async throws {
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.papa),
                                takeError: CarpoolError(code: "car_busy")))
        let store = FamilyStore(member: Fixture.papa, api: api)
        await store.refresh()

        await store.take(Fixture.flitzer, now: Fixture.at(10))
        #expect(store.snapshot?.myRunningTrip == nil)
        #expect(store.undoOffer == nil)
        #expect(store.actionError?.message == "Das Auto ist gerade unterwegs.")

        store.dismissError()
        #expect(store.actionError == nil)
    }

    @Test func returnPassesFuelAndOffersUndo() async {
        let api = FakeAPI(.init(snapshot: Fixture.snapshot(me: Fixture.lisa)))
        let store = FamilyStore(member: Fixture.lisa, api: api)
        await store.refresh()

        await store.returnCar(Fixture.radieschen, fuel: FuelLevel(quarters: 2))
        #expect(api.calls == ["return 2"])
        #expect(store.undoOffer?.text == "Radieschen zurückgegeben")

        await store.undo()
        #expect(store.undoOffer == nil)
        #expect(api.calls == ["return 2", "undo"])
    }

    @Test func loadErrorIsKept() async {
        let store = FamilyStore(member: Fixture.papa, api: FakeAPI())
        await store.refresh()
        #expect(store.loadError?.code == "network")
    }
}
