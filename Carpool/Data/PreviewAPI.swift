#if DEBUG
import CarpoolKit
import Foundation

/// Beispiel-Familie für Xcode-Previews und den Start mit `-previewFamily`, ohne Netzwerk.
/// Lisa ist Hauptnutzerin von Flitzer. Konflikte werden grob nachgestellt (nur für die Vorschau).
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

    static let radieschen = Car(id: UUID(), familyId: familyID, make: "VW", model: "Golf", paint: "silber",
                                nickname: "Radieschen", colorSlot: 1, fuelQuarters: 3)
    static let octavia = Car(id: UUID(), familyId: familyID, make: "Škoda", model: "Octavia", paint: "dunkelgrau",
                             nickname: nil, colorSlot: 2, fuelQuarters: 4)
    static let flitzer = Car(id: UUID(), familyId: familyID, make: "Toyota", model: "Yaris", paint: "blau",
                             nickname: "Flitzer", primaryMemberId: lisa.id, colorSlot: 3, fuelQuarters: 2)
    static let start = Date()

    static let bookings: [Booking] = {
        let now = start
        let tomorrow10 = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0,
                                               of: now.addingTimeInterval(86_400)) ?? now
        return [
            Booking(id: UUID(), familyId: familyID, carId: octavia.id, memberId: mama.id,
                    startsAt: now.addingTimeInterval(-7200), endsAt: nil, plannedEndsAt: now.addingTimeInterval(14400),
                    kind: .trip, fuelQuartersOnTake: 4),
            Booking(id: UUID(), familyId: familyID, carId: radieschen.id, memberId: lisa.id,
                    startsAt: now.addingTimeInterval(-3000), endsAt: nil, kind: .trip, fuelQuartersOnTake: 3),
            Booking(id: UUID(), familyId: familyID, carId: flitzer.id, memberId: felix.id,
                    startsAt: now.addingTimeInterval(10800), endsAt: now.addingTimeInterval(18000), kind: .reservation),
            Booking(id: UUID(), familyId: familyID, carId: radieschen.id, memberId: jonas.id,
                    startsAt: now.addingTimeInterval(21600), endsAt: now.addingTimeInterval(28800), kind: .reservation),
            Booking(id: UUID(), familyId: familyID, carId: flitzer.id, memberId: felix.id,
                    startsAt: tomorrow10, endsAt: tomorrow10.addingTimeInterval(6 * 3600), kind: .reservation,
                    seriesId: UUID())
        ]
    }()

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

    func checkReservation(_ request: ReservationRequest) async throws -> ReservationResult {
        let conflicts = conflicts(car: request.carID, from: request.startsAt, to: request.endsAt)
        guard !conflicts.isEmpty else { return .success }
        let free = [Self.radieschen, Self.octavia, Self.flitzer]
            .filter { $0.id != request.carID && self.conflicts(car: $0.id, from: request.startsAt,
                                                                to: request.endsAt).isEmpty }
        return ReservationResult(ok: false, reason: .conflict, conflicts: conflicts, freeCarIds: free.map(\.id))
    }

    func reserve(_ request: ReservationRequest, displace: Bool, acceptNoReplacement: Bool) async throws
        -> ReservationResult {
        let result = try await checkReservation(request)
        if result.ok { return result }
        if displace && !acceptNoReplacement {
            return ReservationResult(ok: false, reason: .noReplacement, conflicts: result.conflicts)
        }
        return displace ? .success : result
    }

    func freeCars(from start: Date, to end: Date) async throws -> [Car] {
        [Self.radieschen, Self.octavia, Self.flitzer].filter { conflicts(car: $0.id, from: start, to: end).isEmpty }
    }

    func displace(bookingID: UUID, acceptNoReplacement: Bool) async throws -> DisplaceResult {
        acceptNoReplacement ? .displaced(replacementFound: false) : .noReplacement
    }

    func cancelBooking(_ bookingID: UUID, wholeSeries: Bool) async throws -> Int { 1 }

    func snapshot(for member: Member) async throws -> FamilySnapshot {
        FamilySnapshot(family: Family(id: Self.familyID, name: "Familie Berger", inviteCode: "K7P-2QX"), me: member,
                       members: [Self.mama, Self.lisa, Self.jonas, Self.felix],
                       cars: [Self.radieschen, Self.octavia, Self.flitzer], bookings: Self.bookings)
    }

    private func conflicts(car: UUID, from start: Date, to end: Date) -> [ReservationConflict] {
        Self.bookings.filter { booking in
            let bookingEnd = booking.endsAt ?? max(booking.plannedEndsAt ?? Date(), Date())
            return booking.carId == car && booking.startsAt < end && bookingEnd > start
        }.map { booking in
            let member = [Self.mama, Self.lisa, Self.jonas, Self.felix].first { $0.id == booking.memberId }
            return ReservationConflict(booking: booking, firstName: member?.firstName ?? "Jemand",
                                       canDisplace: booking.kind == .reservation && booking.carId == Self.flitzer.id
                                           && booking.startsAt > Date())
        }
    }
}
#endif
