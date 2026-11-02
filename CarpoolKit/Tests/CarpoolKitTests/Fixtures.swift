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
        /// Antworten von `check_reservation` bzw. `reserve`, der Reihe nach (letzte bleibt stehen).
        var checkResults: [ReservationResult] = [.success]
        var reserveResults: [ReservationResult] = [.success]
        var freeCars: [Car] = []
        var displaceResults: [DisplaceResult] = [.displaced(replacementFound: true)]
        var history: [Booking] = []
        var requests: [ReservationRequest] = []
        var settings: MemberSettings?
        var writeError: CarpoolError?
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
    func deleteAccount() async throws { try write("deleteAccount") }
    func currentUserID() async -> UUID? { state.withLock { $0.membership?.userId } }
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

    func checkReservation(_ request: ReservationRequest) async throws -> ReservationResult {
        record("check")
        return state.withLock { $0.requests.append(request); return Self.next(&$0.checkResults) }
    }
    func reserve(_ request: ReservationRequest, displace: Bool, acceptNoReplacement: Bool) async throws
        -> ReservationResult {
        record("reserve displace=\(displace) accept=\(acceptNoReplacement)")
        return state.withLock { $0.requests.append(request); return Self.next(&$0.reserveResults) }
    }
    func freeCars(from start: Date, to end: Date, ignoring bookingID: UUID?) async throws -> [Car] {
        state.withLock { $0.freeCars }
    }
    func extendBooking(_ bookingID: UUID, to end: Date) async throws -> ReservationResult {
        record("extend")
        return state.withLock { Self.next(&$0.reserveResults) }
    }
    func transferBooking(_ bookingID: UUID, to memberID: UUID) async throws { try write("transfer") }
    func history(from start: Date, to end: Date) async throws -> [Booking] {
        record("history")
        return state.withLock { $0.history }
    }
    func displace(bookingID: UUID, acceptNoReplacement: Bool) async throws -> DisplaceResult {
        record("displace accept=\(acceptNoReplacement)")
        return state.withLock { Self.next(&$0.displaceResults) }
    }
    func cancelBooking(_ bookingID: UUID, wholeSeries: Bool) async throws -> Int {
        record("cancel series=\(wholeSeries)")
        return 1
    }

    func updateName(memberID: UUID, firstName: String, short: String) async throws {
        try write("name \(firstName) \(short)")
    }
    func setRole(_ role: Member.Role, memberID: UUID) async throws { try write("role \(role.rawValue)") }
    func removeMember(_ memberID: UUID) async throws { try write("removeMember") }
    func renameFamily(_ familyID: UUID, name: String) async throws { try write("family \(name)") }
    func regenerateInviteCode() async throws -> String {
        try write("code")
        return "NEU-123"
    }
    func addCar(_ input: CarInput, familyID: UUID) async throws { try write("addCar \(input.make) \(input.model)") }
    func updateCar(_ carID: UUID, input: CarInput) async throws { try write("updateCar \(input.model)") }
    func archiveCar(_ carID: UUID) async throws { try write("archiveCar") }
    func reportDamage(_ report: DamageReport, familyID: UUID) async throws {
        try write("damage \(report.description) photo=\(report.photo != nil)")
    }
    func resolveDamage(_ damage: Damage) async throws { try write("resolve") }
    func damagePhoto(path: String) async throws -> Data { Data() }
    func settings(memberID: UUID) async throws -> MemberSettings {
        state.withLock { $0.settings } ?? MemberSettings(memberId: memberID)
    }
    func updateSettings(_ settings: MemberSettings) async throws {
        try write("settings \(settings.calendarCarAnimation.rawValue)")
    }

    func registerDevice(token: String) async throws { record("register \(token)") }
    func unregisterDevice(token: String) async throws { record("unregister \(token)") }

    private func write(_ call: String) throws {
        record(call)
        if let error = state.withLock({ $0.writeError }) { throw error }
    }

    private static func next<T>(_ queue: inout [T]) -> T {
        queue.count > 1 ? queue.removeFirst() : queue[0]
    }

    private func record(_ call: String) {
        state.withLock { $0.calls.append(call) }
    }
}
