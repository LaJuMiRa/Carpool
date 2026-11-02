import Foundation

/// Spiegel der Tabellen in Supabase. Zeiten als UTC-`Date`, Tage (`date`) als ISO-String.

public struct Family: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let inviteCode: String
    public let timeZone: String

    public init(id: UUID, name: String, inviteCode: String, timeZone: String = "Europe/Vienna") {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.timeZone = timeZone
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case timeZone = "time_zone"
    }
}

public struct Member: Codable, Sendable, Hashable, Identifiable {
    public enum Role: String, Codable, Sendable {
        case admin, member
    }

    public let id: UUID
    public let familyId: UUID
    public let userId: UUID?
    public let firstName: String
    public let short: String
    public let role: Role
    /// Von einem Admin entfernt; bleibt für vergangene Buchungen erhalten.
    public let removedAt: Date?

    public init(id: UUID, familyId: UUID, userId: UUID?, firstName: String, short: String, role: Role,
                removedAt: Date? = nil) {
        self.id = id
        self.familyId = familyId
        self.userId = userId
        self.firstName = firstName
        self.short = short
        self.role = role
        self.removedAt = removedAt
    }

    public var isRemoved: Bool { removedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, short, role
        case familyId = "family_id"
        case userId = "user_id"
        case firstName = "first_name"
        case removedAt = "removed_at"
    }
}

public struct Car: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let familyId: UUID
    public let make: String
    public let model: String
    public let paint: String
    public let nickname: String?
    public let plate: String?
    public let primaryMemberId: UUID?
    public let colorSlot: Int
    public let imageUrl: String?
    public let fuelQuarters: Int
    public let pickerlUntil: String?
    public let serviceDue: String?
    public let odometerKm: Int?
    public let archived: Bool

    public init(id: UUID, familyId: UUID, make: String, model: String, paint: String, nickname: String?,
                plate: String? = nil, primaryMemberId: UUID? = nil, colorSlot: Int, imageUrl: String? = nil,
                fuelQuarters: Int, pickerlUntil: String? = nil, serviceDue: String? = nil,
                odometerKm: Int? = nil, archived: Bool = false) {
        self.id = id
        self.familyId = familyId
        self.make = make
        self.model = model
        self.paint = paint
        self.nickname = nickname
        self.plate = plate
        self.primaryMemberId = primaryMemberId
        self.colorSlot = colorSlot
        self.imageUrl = imageUrl
        self.fuelQuarters = fuelQuarters
        self.pickerlUntil = pickerlUntil
        self.serviceDue = serviceDue
        self.odometerKm = odometerKm
        self.archived = archived
    }

    /// Spitzname, sonst Modell.
    public var title: String { nickname ?? model }
    public var fuel: FuelLevel { FuelLevel(quarters: fuelQuarters) }

    public func with(fuelQuarters: Int) -> Car {
        Car(id: id, familyId: familyId, make: make, model: model, paint: paint, nickname: nickname, plate: plate,
            primaryMemberId: primaryMemberId, colorSlot: colorSlot, imageUrl: imageUrl,
            fuelQuarters: fuelQuarters, pickerlUntil: pickerlUntil, serviceDue: serviceDue,
            odometerKm: odometerKm, archived: archived)
    }

    enum CodingKeys: String, CodingKey {
        case id, make, model, paint, nickname, plate, archived
        case familyId = "family_id"
        case primaryMemberId = "primary_member_id"
        case colorSlot = "color_slot"
        case imageUrl = "image_url"
        case fuelQuarters = "fuel_quarters"
        case pickerlUntil = "pickerl_until"
        case serviceDue = "service_due"
        case odometerKm = "odometer_km"
    }
}

public struct Booking: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case reservation, trip
    }

    public enum Status: String, Codable, Sendable {
        case active, completed, cancelled, displaced
    }

    public let id: UUID
    public let familyId: UUID
    public let carId: UUID
    public let memberId: UUID
    public let startsAt: Date
    public let endsAt: Date?
    public let plannedEndsAt: Date?
    public let kind: Kind
    public let seriesId: UUID?
    public let status: Status
    public let fuelQuartersOnTake: Int?

    public init(id: UUID, familyId: UUID, carId: UUID, memberId: UUID, startsAt: Date, endsAt: Date?,
                plannedEndsAt: Date? = nil, kind: Kind, seriesId: UUID? = nil, status: Status = .active,
                fuelQuartersOnTake: Int? = nil) {
        self.id = id
        self.familyId = familyId
        self.carId = carId
        self.memberId = memberId
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.plannedEndsAt = plannedEndsAt
        self.kind = kind
        self.seriesId = seriesId
        self.status = status
        self.fuelQuartersOnTake = fuelQuartersOnTake
    }

    /// Laufende Fahrt: aktiv und ohne Ende.
    public var isRunningTrip: Bool { kind == .trip && status == .active && endsAt == nil }

    /// Aktive Reservierung, die `date` umfasst.
    public func isReservation(covering date: Date) -> Bool {
        guard kind == .reservation, status == .active, let endsAt else { return false }
        return startsAt <= date && date < endsAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, status
        case familyId = "family_id"
        case carId = "car_id"
        case memberId = "member_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case plannedEndsAt = "planned_ends_at"
        case seriesId = "series_id"
        case fuelQuartersOnTake = "fuel_quarters_on_take"
    }
}
