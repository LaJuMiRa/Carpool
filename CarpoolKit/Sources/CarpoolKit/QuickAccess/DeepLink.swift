import Foundation

/// Sprungziele aus Widgets, Live-Aktivität und Push-Nachrichten (`carpool://…`).
public enum DeepLink: Sendable, Hashable {
    case overview
    /// Rückgabe-Sheet für die eigene Fahrt.
    case returnCar
    case calendar
    case car(UUID)

    public static let scheme = "carpool"

    public var url: URL {
        switch self {
        case .overview: URL(string: "\(Self.scheme)://overview")!
        case .returnCar: URL(string: "\(Self.scheme)://return")!
        case .calendar: URL(string: "\(Self.scheme)://calendar")!
        case .car(let id): URL(string: "\(Self.scheme)://car/\(id.uuidString.lowercased())")!
        }
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host() {
        case "overview": self = .overview
        case "return": self = .returnCar
        case "calendar": self = .calendar
        case "car":
            guard let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)) else { return nil }
            self = .car(id)
        default: return nil
        }
    }

    /// Ziel einer Push-Nachricht nach ihrer Art (`notifications.kind`).
    public init(notificationKind kind: String?, carID: UUID?) {
        switch kind {
        case "return_overdue": self = .returnCar
        case "booking_displaced", "reservation_soon", "series_occurrence_skipped": self = .calendar
        case "service_pickerl": self = carID.map(DeepLink.car) ?? .overview
        default: self = .overview
        }
    }
}

/// Gerätetoken für APNs als Hex-Text, wie ihn `register_device` erwartet.
public enum PushToken {
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}
