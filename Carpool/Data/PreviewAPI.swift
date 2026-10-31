#if DEBUG
import CarpoolKit
import Foundation

/// Beispiel-Familie für Xcode-Previews, ohne Netzwerk.
struct PreviewAPI: CarpoolAPI {
    static let familyID = UUID()
    static let lisa = Member(id: UUID(), familyId: familyID, userId: UUID(), firstName: "Lisa", short: "Li",
                             role: .member)
    static let mama = Member(id: UUID(), familyId: familyID, userId: nil, firstName: "Mama", short: "Ma",
                             role: .admin)
    static let jonas = Member(id: UUID(), familyId: familyID, userId: nil, firstName: "Jonas", short: "Jo",
                              role: .member)
    static let felix = Member(id: UUID(), familyId: familyID, userId: nil, firstName: "Felix", short: "Fe",
                              role: .member)

    func authChanges() -> AsyncStream<UUID?> { AsyncStream { $0.yield(nil) } }
    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String) async throws -> SignUpResult { .signedIn }
    func signOut() async throws {}
    func membership(userID: UUID) async throws -> Member? { nil }
    func createFamily(name: String, firstName: String) async throws {}
    func joinFamily(inviteCode: String, firstName: String) async throws {}
    func familyChanges(familyID: UUID) -> AsyncStream<Void> { AsyncStream { _ in } }
    func takeCar(_ carID: UUID) async throws -> TakeResult { TakeResult(bookingId: UUID(), fromReservation: false) }
    func returnCar(_ carID: UUID, fuel: FuelLevel) async throws {}
    func undoLastAction() async throws {}

    func snapshot(for member: Member) async throws -> FamilySnapshot {
        let id = Self.familyID
        let radieschen = Car(id: UUID(), familyId: id, make: "VW", model: "Golf", paint: "silber",
                             nickname: "Radieschen", colorSlot: 1, fuelQuarters: 3)
        let octavia = Car(id: UUID(), familyId: id, make: "Škoda", model: "Octavia", paint: "dunkelgrau",
                          nickname: nil, colorSlot: 2, fuelQuarters: 4)
        let flitzer = Car(id: UUID(), familyId: id, make: "Toyota", model: "Yaris", paint: "blau",
                          nickname: "Flitzer", colorSlot: 3, fuelQuarters: 2)
        let now = Date()
        let bookings = [
            Booking(id: UUID(), familyId: id, carId: octavia.id, memberId: Self.mama.id,
                    startsAt: now.addingTimeInterval(-7200), endsAt: nil, plannedEndsAt: now.addingTimeInterval(14400),
                    kind: .trip, fuelQuartersOnTake: 4),
            Booking(id: UUID(), familyId: id, carId: radieschen.id, memberId: Self.lisa.id,
                    startsAt: now.addingTimeInterval(-3000), endsAt: nil, kind: .trip, fuelQuartersOnTake: 3),
            Booking(id: UUID(), familyId: id, carId: flitzer.id, memberId: Self.felix.id,
                    startsAt: now.addingTimeInterval(10800), endsAt: now.addingTimeInterval(18000), kind: .reservation),
            Booking(id: UUID(), familyId: id, carId: radieschen.id, memberId: Self.jonas.id,
                    startsAt: now.addingTimeInterval(21600), endsAt: now.addingTimeInterval(28800), kind: .reservation)
        ]
        return FamilySnapshot(family: Family(id: id, name: "Familie Berger", inviteCode: "K7P-2QX"), me: member,
                              members: [Self.mama, Self.lisa, Self.jonas, Self.felix],
                              cars: [radieschen, octavia, flitzer], bookings: bookings)
    }
}
#endif
