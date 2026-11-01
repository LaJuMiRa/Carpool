import Foundation

/// Gemeldeter Schaden (`damages`). Offen, solange `resolvedAt` nil ist.
public struct Damage: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let familyId: UUID
    public let carId: UUID
    public let reportedBy: UUID?
    public let description: String
    /// Pfad im Bucket `damage-photos`: `<family_id>/<datei>`.
    public let photoPath: String?
    public let drivable: Bool
    public let createdAt: Date
    public let resolvedAt: Date?

    public init(id: UUID, familyId: UUID, carId: UUID, reportedBy: UUID?, description: String,
                photoPath: String? = nil, drivable: Bool, createdAt: Date, resolvedAt: Date? = nil) {
        self.id = id
        self.familyId = familyId
        self.carId = carId
        self.reportedBy = reportedBy
        self.description = description
        self.photoPath = photoPath
        self.drivable = drivable
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    public var isOpen: Bool { resolvedAt == nil }

    enum CodingKeys: String, CodingKey {
        case id, description, drivable
        case familyId = "family_id"
        case carId = "car_id"
        case reportedBy = "reported_by"
        case photoPath = "photo_path"
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }
}

/// Neuer Schaden; Familie und Melder setzt das Backend.
public struct DamageReport: Sendable, Equatable {
    /// Höchstlänge laut Datenbank.
    public static let maxDescription = 1000

    public let carID: UUID
    public let description: String
    public let drivable: Bool
    /// JPEG-Daten des Fotos.
    public let photo: Data?

    public init(carID: UUID, description: String, drivable: Bool, photo: Data?) {
        self.carID = carID
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.drivable = drivable
        self.photo = photo
    }

    public var isValid: Bool { !description.isEmpty && description.count <= Self.maxDescription }
}

/// Eigene Einstellungen (`settings`). Jede Benachrichtigung ist abschaltbar.
public struct MemberSettings: Codable, Sendable, Hashable {
    /// Auto-Icon laufender Fahrten im Kalender.
    public enum CarAnimation: String, Codable, Sendable, CaseIterable {
        case once, loop, off

        public var title: String {
            switch self {
            case .once: "Einmal"
            case .loop: "Dauerhaft"
            case .off: "Aus"
            }
        }
    }

    /// Splash mit Schlüsselbrett.
    public enum LaunchAnimation: String, Codable, Sendable, CaseIterable {
        case first, always

        public var title: String {
            switch self {
            case .first: "Erster Start"
            case .always: "Immer"
            }
        }
    }

    public let memberId: UUID
    public var notifyCarFree: Bool
    public var notifyBookingDisplaced: Bool
    public var notifyReservationSoon: Bool
    public var notifyReturnOverdue: Bool
    public var notifyServicePickerl: Bool
    public var calendarCarAnimation: CarAnimation
    public var launchAnimation: LaunchAnimation

    public init(memberId: UUID, notifyCarFree: Bool = true, notifyBookingDisplaced: Bool = true,
                notifyReservationSoon: Bool = true, notifyReturnOverdue: Bool = true,
                notifyServicePickerl: Bool = true, calendarCarAnimation: CarAnimation = .once,
                launchAnimation: LaunchAnimation = .first) {
        self.memberId = memberId
        self.notifyCarFree = notifyCarFree
        self.notifyBookingDisplaced = notifyBookingDisplaced
        self.notifyReservationSoon = notifyReservationSoon
        self.notifyReturnOverdue = notifyReturnOverdue
        self.notifyServicePickerl = notifyServicePickerl
        self.calendarCarAnimation = calendarCarAnimation
        self.launchAnimation = launchAnimation
    }

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case notifyCarFree = "notify_car_free"
        case notifyBookingDisplaced = "notify_booking_displaced"
        case notifyReservationSoon = "notify_reservation_soon"
        case notifyReturnOverdue = "notify_return_overdue"
        case notifyServicePickerl = "notify_service_pickerl"
        case calendarCarAnimation = "calendar_car_animation"
        case launchAnimation = "launch_animation"
    }
}

/// Eingaben für „Auto hinzufügen" / „Auto bearbeiten" (nur Admins).
public struct CarInput: Sendable, Equatable {
    public let make: String
    public let model: String
    public let paint: String
    public let nickname: String?
    public let plate: String?
    public let primaryMemberId: UUID?
    /// Tage als „yyyy-MM-dd".
    public let pickerlUntil: String?
    public let serviceDue: String?
    public let odometerKm: Int?

    public init(make: String, model: String, paint: String, nickname: String? = nil, plate: String? = nil,
                primaryMemberId: UUID? = nil, pickerlUntil: String? = nil, serviceDue: String? = nil,
                odometerKm: Int? = nil) {
        self.make = make.trimmingCharacters(in: .whitespaces)
        self.model = model.trimmingCharacters(in: .whitespaces)
        self.paint = paint.trimmingCharacters(in: .whitespaces)
        self.nickname = Self.optional(nickname)
        self.plate = Self.optional(plate)?.uppercased()
        self.primaryMemberId = primaryMemberId
        self.pickerlUntil = pickerlUntil
        self.serviceDue = serviceDue
        self.odometerKm = odometerKm
    }

    /// Längen laut Datenbank.
    public var isValid: Bool {
        (1...40).contains(make.count) && (1...40).contains(model.count) && (1...40).contains(paint.count)
            && (nickname?.count ?? 1) <= 30 && (plate?.count ?? 1) <= 15 && (odometerKm ?? 0) >= 0
    }

    private static func optional(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
