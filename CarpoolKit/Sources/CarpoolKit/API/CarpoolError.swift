import Auth
import Foundation
import PostgREST
import Storage

/// Fehler mit festem Code (siehe CLAUDE.md, „Fehlercodes") und deutschem Nutzertext.
public struct CarpoolError: Error, Equatable, Sendable {
    public let code: String
    /// Eigener Text statt des Standardtexts (z. B. wer das Auto beim Verlängern blockiert).
    public let detail: String?

    public init(code: String, detail: String? = nil) {
        self.code = code
        self.detail = detail
    }

    public var message: String { detail ?? Self.messages[code] ?? Self.messages["unknown"]! }

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
        "too_many_attempts": "Zu viele falsche Codes. Versuch es in 15 Minuten noch einmal.",
        "cannot_remove_self": "Du kannst dich nicht selbst entfernen.",
        "member_driving": "Das geht erst, wenn das Auto zurückgegeben ist.",
        "transfer_admin_first": "Mach zuerst jemand anderen zum Admin, dann kannst du dein Konto löschen.",
        "not_editable": "Diese Buchung lässt sich nicht mehr ändern.",
        "name_taken": "Diesen Namen gibt es in der Familie schon.",
        "admin_required": "Das dürfen nur Admins.",
        "invalid_name": "Der Name braucht mindestens 2 Zeichen, das Kürzel genau 2.",
        "last_admin": "Die Familie braucht mindestens einen Admin.",
        "member_not_in_family": "Diese Person gehört nicht zur Familie.",
        "photo_upload": "Das Foto ließ sich nicht hochladen. Versuch es noch einmal.",
        "photo_load": "Das Foto lässt sich gerade nicht laden.",
        "car_not_found": "Dieses Auto gibt es nicht mehr.",
        "car_busy": "Das Auto ist gerade unterwegs.",
        "car_reserved": "Das Auto ist gerade für jemand anderen reserviert.",
        "already_driving": "Du fährst schon ein anderes Auto.",
        "no_running_trip": "Du hast gerade keine Fahrt.",
        "invalid_fuel": "Bitte wähle einen Tankstand.",
        "invalid_range": "Das Ende muss nach dem Beginn liegen.",
        "starts_in_past": "Der Beginn liegt in der Vergangenheit.",
        "range_too_long": "Du kannst höchstens 14 Tage am Stück reservieren.",
        "invalid_rrule": "Diese Wiederholung geht nicht.",
        "invalid_until": "Das Ende der Wiederholung liegt vor dem Beginn.",
        "series_must_end_same_day": "Wiederholte Reservierungen müssen am selben Tag enden.",
        "no_occurrences": "In diesem Zeitraum gibt es keinen passenden Termin.",
        "conflict_retry": "Jemand war schneller. Schau noch einmal nach.",
        "booking_not_found": "Diese Buchung gibt es nicht mehr.",
        "not_owner": "Das ist nicht deine Buchung.",
        "not_cancellable": "Diese Buchung lässt sich nicht mehr löschen.",
        "not_displaceable": "Diese Buchung kannst du nicht übernehmen.",
        "nothing_to_undo": "Rückgängig ist nicht mehr möglich.",
        "undo_expired": "Rückgängig ist nicht mehr möglich."
    ]

    public static func from(_ error: any Error) -> CarpoolError {
        switch error {
        case let error as CarpoolError:
            return error
        case let error as PostgrestError:
            return CarpoolError(code: messages[error.message] != nil ? error.message : "unknown")
        case is StorageError:
            return CarpoolError(code: "photo_upload")
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
