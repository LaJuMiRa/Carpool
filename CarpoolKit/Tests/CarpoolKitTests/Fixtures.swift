import Foundation
import Synchronization
@testable import CarpoolKit

/// Beispiel-Familie wie in den Mockups, Zeiten an einem festen Tag in Wien.
enum Fixture {
    static let vienna = TimeZone(identifier: "Europe/Vienna")!
    static let text = TimeText(timeZone: vienna)

    /// Freitag, 30.10.2026, hh:mm in Wien.
    static func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        var components = DateComponents(year: 2026, month: 10, day: 30 + dayOffset, hour: hour, minute: minute)
        components.timeZone = vienna
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    static let familyID = UUID()
    static let family = Family(id: familyID, name: "Familie Berger", inviteCode: "K7P-2QX")
    static let papa = member("Papa", role: .admin)
    static let mama = member("Mama", role: .admin)
    static let lisa = member("Lisa")
    static let jonas = member("Jonas")
    static let felix = member("Felix")

    static let radieschen = Car(id: UUID(), familyId: familyID, make: "VW", model: "Golf", paint: "silber",
                                nickname: "Radieschen", colorSlot: 1, fuelQuarters: 3)
    static let octavia = Car(id: UUID(), familyId: familyID, make: "Škoda", model: "Octavia",
                             paint: "dunkelgrau", nickname: nil, colorSlot: 2, fuelQuarters: 4)
    static let flitzer = Car(id: UUID(), familyId: familyID, make: "Toyota", model: "Yaris", paint: "blau",
                             nickname: "Flitzer", colorSlot: 3, fuelQuarters: 2)

    /// Heute: Mama fährt Octavia bis 17:30, Lisa fährt Radieschen seit 09:12,
    /// Felix hat Flitzer 14:00–19:00, Jonas Radieschen 18:00–22:00.
    static func bookings() -> [Booking] {
        [
            Booking(id: UUID(), familyId: familyID, carId: octavia.id, memberId: mama.id, startsAt: at(8),
                    endsAt: nil, plannedEndsAt: at(17, 30), kind: .trip, fuelQuartersOnTake: 4),
            Booking(id: UUID(), familyId: familyID, carId: radieschen.id, memberId: lisa.id,
                    startsAt: at(9, 12), endsAt: nil, kind: .trip, fuelQuartersOnTake: 3),
            Booking(id: UUID(), familyId: familyID, carId: flitzer.id, memberId: felix.id, startsAt: at(14),
                    endsAt: at(19), kind: .reservation),
            Booking(id: UUID(), familyId: familyID, carId: radieschen.id, memberId: jonas.id, startsAt: at(18),
                    endsAt: at(22), kind: .reservation)
        ]
    }

    static func snapshot(me: Member, bookings: [Booking] = bookings()) -> FamilySnapshot {
        FamilySnapshot(family: family, me: me, members: [papa, mama, lisa, jonas, felix],
                       cars: [flitzer, radieschen, octavia], bookings: bookings)
    }

    private static func member(_ name: String, role: Member.Role = .member) -> Member {
        Member(id: UUID(), familyId: familyID, userId: UUID(), firstName: name,
               short: String(name.prefix(2)), role: role)
    }
}

/// Fake-Backend mit einstellbaren Antworten.
final class FakeAPI: CarpoolAPI, Sendable {
    struct State {
        var snapshot: FamilySnapshot?
        var membership: Member?
        var takeError: CarpoolError?
        var returnError: CarpoolError?
        var calls: [String] = []
    }

    let state: Mutex<State>
    let auth: AsyncStream<UUID?>
    let authContinuation: AsyncStream<UUID?>.Continuation

    init(_ state: State = State()) {
        self.state = Mutex(state)
        (auth, authContinuation) = AsyncStream.makeStream()
    }

    var calls: [String] { state.withLock { $0.calls } }

    func authChanges() -> AsyncStream<UUID?> { auth }
    func signIn(email: String, password: String) async throws { record("signIn \(email)") }
    func signUp(email: String, password: String) async throws -> SignUpResult {
        record("signUp")
        return .confirmationRequired
    }
    func signOut() async throws { record("signOut") }
    func membership(userID: UUID) async throws -> Member? { state.withLock { $0.membership } }
    func createFamily(name: String, firstName: String) async throws {
        record("createFamily \(name) \(firstName)")
        state.withLock { $0.membership = Fixture.papa }
    }
    func joinFamily(inviteCode: String, firstName: String) async throws {
        record("joinFamily \(inviteCode) \(firstName)")
        throw CarpoolError(code: "invalid_invite_code")
    }
    func snapshot(for member: Member) async throws -> FamilySnapshot {
        guard let snapshot = state.withLock({ $0.snapshot }) else { throw CarpoolError(code: "network") }
        return snapshot
    }
    func familyChanges(familyID: UUID) -> AsyncStream<Void> { AsyncStream { _ in } }
    func takeCar(_ carID: UUID) async throws -> TakeResult {
        record("take")
        if let error = state.withLock({ $0.takeError }) { throw error }
        return TakeResult(bookingId: UUID(), fromReservation: false)
    }
    func returnCar(_ carID: UUID, fuel: FuelLevel) async throws {
        record("return \(fuel.quarters)")
        if let error = state.withLock({ $0.returnError }) { throw error }
    }
    func undoLastAction() async throws { record("undo") }

    private func record(_ call: String) {
        state.withLock { $0.calls.append(call) }
    }
}
