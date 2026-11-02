import Foundation

public enum SignUpResult: Sendable, Equatable {
    case signedIn
    /// E-Mail-Bestätigung im Supabase-Projekt eingeschaltet.
    case confirmationRequired
}

public struct TakeResult: Codable, Sendable, Equatable {
    public let bookingId: UUID
    public let fromReservation: Bool

    public init(bookingId: UUID, fromReservation: Bool) {
        self.bookingId = bookingId
        self.fromReservation = fromReservation
    }

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case fromReservation = "from_reservation"
    }
}

/// Zugang zum Backend. Keine Geschäftslogik: nur lesen und RPCs aufrufen.
public protocol CarpoolAPI: Sendable {
    /// Liefert die aktuelle Nutzer-ID (nil = abgemeldet), zuerst den gespeicherten Stand.
    func authChanges() -> AsyncStream<UUID?>
    /// Angemeldete Nutzer-ID, Sitzung bei Bedarf erneuert (für Kurzbefehle ohne laufende App).
    func currentUserID() async -> UUID?
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String) async throws -> SignUpResult
    func signOut() async throws

    func membership(userID: UUID) async throws -> Member?
    func createFamily(name: String, firstName: String) async throws
    func joinFamily(inviteCode: String, firstName: String) async throws

    func snapshot(for member: Member) async throws -> FamilySnapshot
    /// Meldet jede Änderung an Buchungen, Autos, Mitgliedern oder Schäden der Familie.
    func familyChanges(familyID: UUID) -> AsyncStream<Void>

    func takeCar(_ carID: UUID) async throws -> TakeResult
    func returnCar(_ carID: UUID, fuel: FuelLevel) async throws
    func undoLastAction() async throws

    /// Prüft eine Reservierung, ohne zu buchen (Hinweis im Formular).
    func checkReservation(_ request: ReservationRequest) async throws -> ReservationResult
    func reserve(_ request: ReservationRequest, displace: Bool, acceptNoReplacement: Bool) async throws
        -> ReservationResult
    /// Autos, die im ganzen Zeitraum frei sind.
    func freeCars(from start: Date, to end: Date) async throws -> [Car]
    func displace(bookingID: UUID, acceptNoReplacement: Bool) async throws -> DisplaceResult
    /// Eigene Reservierung stornieren; liefert die Zahl stornierter Termine.
    @discardableResult
    func cancelBooking(_ bookingID: UUID, wholeSeries: Bool) async throws -> Int

    // Mitglieder und Familie
    /// Eigener Vorname und Kürzel.
    func updateName(memberID: UUID, firstName: String, short: String) async throws
    /// Rolle ändern (nur Admins; der letzte Admin bleibt Admin).
    func setRole(_ role: Member.Role, memberID: UUID) async throws
    func renameFamily(_ familyID: UUID, name: String) async throws
    /// Neuer Einladungscode (Admin).
    func regenerateInviteCode() async throws -> String

    // Autos (nur Admins)
    func addCar(_ input: CarInput, familyID: UUID) async throws
    func updateCar(_ carID: UUID, input: CarInput) async throws
    func archiveCar(_ carID: UUID) async throws

    // Schäden
    func reportDamage(_ report: DamageReport, familyID: UUID) async throws
    func resolveDamage(_ damageID: UUID) async throws
    func damagePhoto(path: String) async throws -> Data

    // Einstellungen
    func settings(memberID: UUID) async throws -> MemberSettings
    func updateSettings(_ settings: MemberSettings) async throws

    // Push
    /// Gerätetoken (Hex) für Push-Nachrichten an dieses Gerät anmelden.
    func registerDevice(token: String) async throws
    func unregisterDevice(token: String) async throws
}
