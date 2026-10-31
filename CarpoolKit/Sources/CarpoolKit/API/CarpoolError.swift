import Auth
import Foundation
import PostgREST

/// Fehler mit festem Code (siehe CLAUDE.md, „Fehlercodes") und deutschem Nutzertext.
public struct CarpoolError: Error, Equatable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }

    public var message: String { Self.messages[code] ?? Self.messages["unknown"]! }

    /// Nutzertexte: Du-Form, kurz, ohne Ausrufezeichen.
    static let messages: [String: String] = [
        "network": "Keine Verbindung. Versuch es gleich noch einmal.",
        "unknown": "Das hat nicht geklappt. Versuch es noch einmal.",
        "invalid_credentials": "E-Mail oder Passwort stimmt nicht.",
        "email_not_confirmed": "Bitte bestätige zuerst deine E-Mail.",
        "email_exists": "Für diese E-Mail gibt es schon ein Konto.",
        "weak_password": "Das Passwort braucht mindestens 6 Zeichen.",
        "invalid_email": "Diese E-Mail-Adresse ist ungültig.",
        "confirmation_required": "Wir haben dir eine E-Mail geschickt. Bestätige sie und melde dich dann an.",
        "not_authenticated": "Bitte melde dich an.",
        "not_a_member": "Du bist noch in keiner Familie.",
        "already_member": "Du bist schon in einer Familie.",
        "invalid_invite_code": "Diesen Einladungscode gibt es nicht.",
        "name_taken": "Diesen Namen gibt es in der Familie schon.",
        "admin_required": "Das dürfen nur Admins.",
        "car_not_found": "Dieses Auto gibt es nicht mehr.",
        "car_busy": "Das Auto ist gerade unterwegs.",
        "car_reserved": "Das Auto ist gerade für jemand anderen reserviert.",
        "already_driving": "Du fährst schon ein anderes Auto.",
        "no_running_trip": "Du hast gerade keine Fahrt.",
        "invalid_fuel": "Bitte wähle einen Tankstand.",
        "nothing_to_undo": "Rückgängig ist nicht mehr möglich.",
        "undo_expired": "Rückgängig ist nicht mehr möglich."
    ]

    public static func from(_ error: any Error) -> CarpoolError {
        switch error {
        case let error as CarpoolError:
            return error
        case let error as PostgrestError:
            return CarpoolError(code: messages[error.message] != nil ? error.message : "unknown")
        case let error as AuthError:
            return CarpoolError(code: authCode(error.errorCode.rawValue))
        case is URLError:
            return CarpoolError(code: "network")
        default:
            return CarpoolError(code: "unknown")
        }
    }

    static func authCode(_ raw: String) -> String {
        switch raw {
        case "invalid_credentials", "email_not_confirmed", "weak_password": raw
        case "user_already_exists", "email_exists": "email_exists"
        case "validation_failed", "email_address_invalid": "invalid_email"
        default: "unknown"
        }
    }
}
