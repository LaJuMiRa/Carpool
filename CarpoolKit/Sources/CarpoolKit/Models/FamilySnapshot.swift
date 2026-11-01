import Foundation

/// Alles, was Übersicht und Kalender für eine Familie brauchen. Unveränderlich;
/// Änderungen liefern eine neue Kopie.
public struct FamilySnapshot: Sendable, Hashable {
    public let family: Family
    public let me: Member
    public let members: [Member]
    public let cars: [Car]
    /// Aktive Buchungen, die noch nicht vorbei sind.
    public let bookings: [Booking]

    public init(family: Family, me: Member, members: [Member], cars: [Car], bookings: [Booking]) {
        self.family = family
        self.me = me
        self.members = members
        self.cars = cars.sorted { $0.colorSlot < $1.colorSlot }
        self.bookings = bookings.sorted { $0.startsAt < $1.startsAt }
    }

    public func member(_ id: UUID) -> Member? { members.first { $0.id == id } }
    public func car(_ id: UUID) -> Car? { cars.first { $0.id == id } }

    public var myRunningTrip: Booking? {
        bookings.first { $0.isRunningTrip && $0.memberId == me.id }
    }

    public func runningTrip(for carID: UUID) -> Booking? {
        bookings.first { $0.isRunningTrip && $0.carId == carID }
    }

    /// Lokale Vorschau von „Nehmen", bis der Server bestätigt.
    public func applyingTake(carID: UUID, at date: Date) -> FamilySnapshot {
        guard let car = car(carID) else { return self }
        let ownReservation = bookings.first {
            $0.carId == carID && $0.memberId == me.id && $0.kind == .reservation && $0.status == .active
                && $0.startsAt <= date.addingTimeInterval(15 * 60) && ($0.endsAt ?? .distantFuture) > date
        }
        let trip = Booking(id: ownReservation?.id ?? UUID(), familyId: family.id, carId: carID, memberId: me.id,
                           startsAt: date, endsAt: nil, plannedEndsAt: ownReservation?.endsAt, kind: .trip,
                           fuelQuartersOnTake: car.fuelQuarters)
        let others = bookings.filter { $0.id != ownReservation?.id }
        return FamilySnapshot(family: family, me: me, members: members, cars: cars, bookings: others + [trip])
    }

    /// Lokale Vorschau von „Löschen".
    public func removing(_ bookingIDs: Set<UUID>) -> FamilySnapshot {
        FamilySnapshot(family: family, me: me, members: members, cars: cars,
                       bookings: bookings.filter { !bookingIDs.contains($0.id) })
    }

    /// Lokale Vorschau von „Zurückgeben".
    public func applyingReturn(carID: UUID, fuel: FuelLevel) -> FamilySnapshot {
        let remaining = bookings.filter { !($0.isRunningTrip && $0.carId == carID && $0.memberId == me.id) }
        let updatedCars = cars.map { $0.id == carID ? $0.with(fuelQuarters: fuel.quarters) : $0 }
        return FamilySnapshot(family: family, me: me, members: members, cars: updatedCars, bookings: remaining)
    }
}
