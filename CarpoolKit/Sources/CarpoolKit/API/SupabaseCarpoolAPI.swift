import Foundation
import OSLog
import Supabase

/// `CarpoolAPI` über supabase-swift.
public final class SupabaseCarpoolAPI: CarpoolAPI {
    private let client: SupabaseClient

    public init(config: SupabaseConfig) {
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(
                auth: .init(storage: KeychainLocalStorage(), emitLocalSessionAsInitialSession: true)
            )
        )
    }

    // MARK: Anmeldung

    public func currentUserID() async -> UUID? {
        try? await client.auth.session.user.id
    }

    public func authChanges() -> AsyncStream<UUID?> {
        let auth = client.auth
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in auth.authStateChanges {
                    switch event {
                    case .initialSession:
                        continuation.yield(session.flatMap { $0.isExpired ? nil : $0.user.id })
                    case .signedIn, .signedOut, .userDeleted:
                        continuation.yield(session?.user.id)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func signIn(email: String, password: String) async throws {
        try await call { try await client.auth.signIn(email: email, password: password) }
    }

    public func signUp(email: String, password: String) async throws -> SignUpResult {
        let response = try await call { try await client.auth.signUp(email: email, password: password) }
        return response.session == nil ? .confirmationRequired : .signedIn
    }

    public func signOut() async throws {
        try await call { try await client.auth.signOut() }
    }

    public func deleteAccount() async throws {
        try await call { try await client.rpc("delete_account").execute() }
        // Der Nutzer existiert serverseitig nicht mehr: nur noch die lokale Sitzung verwerfen.
        try? await client.auth.signOut(scope: .local)
    }

    // MARK: Familie

    public func membership(userID: UUID) async throws -> Member? {
        let rows: [Member] = try await call {
            try await client.from("members").select().eq("user_id", value: userID).limit(1).execute().value
        }
        return rows.first
    }

    public func createFamily(name: String, firstName: String) async throws {
        try await call {
            try await client.rpc("create_family", params: ["p_family_name": name, "p_first_name": firstName])
                .execute()
        }
    }

    public func joinFamily(inviteCode: String, firstName: String) async throws {
        struct Response: Decodable {
            let ok: Bool
            let reason: String?
        }
        let response: Response = try await call {
            try await client.rpc("join_family", params: ["p_invite_code": inviteCode, "p_first_name": firstName])
                .execute().value
        }
        // Falscher Code kommt als Antwort (damit das Backend Fehlversuche zählen kann).
        if !response.ok { throw CarpoolError(code: response.reason ?? "unknown") }
    }

    public func snapshot(for member: Member) async throws -> FamilySnapshot {
        let now = ISO8601DateFormatter().string(from: Date())
        return try await call {
            async let family: Family = client.from("families").select().eq("id", value: member.familyId)
                .single().execute().value
            async let members: [Member] = client.from("members").select().order("first_name").execute().value
            async let cars: [Car] = client.from("cars").select().eq("archived", value: false)
                .order("color_slot").execute().value
            async let bookings: [Booking] = client.from("bookings").select()
                .eq("status", value: "active")
                .or("ends_at.is.null,ends_at.gt.\(now)")
                .order("starts_at")
                .execute().value
            async let damages: [Damage] = client.from("damages").select().is("resolved_at", value: nil)
                .order("created_at", ascending: false).execute().value
            let all = try await members
            // Eigener Eintrag frisch aus der Datenbank (Name, Kürzel, Rolle können sich geändert haben).
            return try await FamilySnapshot(family: family, me: all.first { $0.id == member.id } ?? member,
                                            members: all, cars: cars, bookings: bookings, damages: damages)
        }
    }

    public func familyChanges(familyID: UUID) -> AsyncStream<Void> {
        let client = client
        return AsyncStream { continuation in
            let task = Task {
                let channel = client.channel("family-\(familyID.uuidString)")
                let streams = ["bookings", "cars", "members", "damages"].map { table in
                    channel.postgresChange(AnyAction.self, schema: "public", table: table,
                                           filter: .eq("family_id", value: familyID.uuidString))
                }
                do {
                    try await channel.subscribeWithError()
                } catch {
                    continuation.finish()
                    return
                }
                await withTaskGroup(of: Void.self) { group in
                    for stream in streams {
                        group.addTask {
                            for await _ in stream { continuation.yield() }
                        }
                    }
                }
                await client.removeChannel(channel)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Belegung

    public func takeCar(_ carID: UUID) async throws -> TakeResult {
        try await call {
            try await client.rpc("take_car", params: ["p_car_id": carID]).execute().value
        }
    }

    public func returnCar(_ carID: UUID, fuel: FuelLevel) async throws {
        struct Params: Encodable {
            let p_fuel_quarters: Int
            let p_car_id: UUID
        }
        try await call {
            try await client.rpc("return_car", params: Params(p_fuel_quarters: fuel.quarters, p_car_id: carID))
                .execute()
        }
    }

    // MARK: Push

    public func registerDevice(token: String) async throws {
        try await call {
            try await client.rpc("register_device", params: ["p_platform": "ios", "p_token": token]).execute()
        }
    }

    public func unregisterDevice(token: String) async throws {
        try await call { try await client.rpc("unregister_device", params: ["p_token": token]).execute() }
    }

    public func undoLastAction() async throws {
        try await call { try await client.rpc("undo_last_action").execute() }
    }

    // MARK: Reservieren

    /// Parameter von `reserve`/`check_reservation`; nil-Werte fehlen im JSON, dann gelten die Standardwerte.
    private struct ReserveParams: Encodable {
        let p_car_id: UUID
        let p_starts_at: String
        let p_ends_at: String
        let p_rrule: String?
        let p_until: String?
        let p_displace: Bool?
        let p_accept_no_replacement: Bool?
        let p_booking_id: UUID?

        init(_ request: ReservationRequest, displace: Bool? = nil, acceptNoReplacement: Bool? = nil) {
            p_car_id = request.carID
            p_starts_at = Self.timestamp(request.startsAt)
            p_ends_at = Self.timestamp(request.endsAt)
            p_rrule = request.rrule
            p_until = request.until
            p_displace = displace
            p_accept_no_replacement = acceptNoReplacement
            p_booking_id = request.bookingID
        }

        static func timestamp(_ date: Date) -> String {
            date.formatted(.iso8601)
        }
    }

    public func checkReservation(_ request: ReservationRequest) async throws -> ReservationResult {
        try await call {
            try await client.rpc("check_reservation", params: ReserveParams(request)).execute().value
        }
    }

    public func reserve(_ request: ReservationRequest, displace: Bool, acceptNoReplacement: Bool) async throws
        -> ReservationResult {
        try await call {
            if let bookingID = request.bookingID {
                struct Params: Encodable {
                    let p_booking_id: UUID
                    let p_car_id: UUID
                    let p_starts_at: String
                    let p_ends_at: String
                    let p_displace: Bool
                    let p_accept_no_replacement: Bool
                }
                let params = Params(p_booking_id: bookingID, p_car_id: request.carID,
                                    p_starts_at: ReserveParams.timestamp(request.startsAt),
                                    p_ends_at: ReserveParams.timestamp(request.endsAt),
                                    p_displace: displace, p_accept_no_replacement: acceptNoReplacement)
                return try await client.rpc("update_booking", params: params).execute().value
            }
            return try await client.rpc("reserve", params: ReserveParams(request, displace: displace,
                                                                         acceptNoReplacement: acceptNoReplacement))
                .execute().value
        }
    }

    public func freeCars(from start: Date, to end: Date, ignoring bookingID: UUID?) async throws -> [Car] {
        struct Params: Encodable {
            let p_starts_at: String
            let p_ends_at: String
            let p_booking_id: UUID?
        }
        return try await call {
            try await client.rpc("free_cars", params: Params(p_starts_at: ReserveParams.timestamp(start),
                                                             p_ends_at: ReserveParams.timestamp(end),
                                                             p_booking_id: bookingID))
                .execute().value
        }
    }

    public func extendBooking(_ bookingID: UUID, to end: Date) async throws -> ReservationResult {
        struct Params: Encodable {
            let p_booking_id: UUID
            let p_ends_at: String
        }
        return try await call {
            try await client.rpc("extend_booking", params: Params(p_booking_id: bookingID,
                                                                  p_ends_at: ReserveParams.timestamp(end)))
                .execute().value
        }
    }

    public func transferBooking(_ bookingID: UUID, to memberID: UUID) async throws {
        struct Params: Encodable {
            let p_booking_id: UUID
            let p_member_id: UUID
        }
        try await call {
            try await client.rpc("transfer_booking", params: Params(p_booking_id: bookingID, p_member_id: memberID))
                .execute()
        }
    }

    public func history(from start: Date, to end: Date) async throws -> [Booking] {
        let now = Date()
        return try await call {
            try await client.from("bookings").select()
                .in("status", values: ["active", "completed"])
                .lt("starts_at", value: ReserveParams.timestamp(end))
                .gt("ends_at", value: ReserveParams.timestamp(start))
                .lte("ends_at", value: ReserveParams.timestamp(now))
                .order("starts_at")
                .execute().value
        }
    }

    public func displace(bookingID: UUID, acceptNoReplacement: Bool) async throws -> DisplaceResult {
        struct Params: Encodable {
            let p_booking_id: UUID
            let p_accept_no_replacement: Bool
        }
        struct Response: Decodable {
            let ok: Bool
            let replacement_found: Bool?
        }
        let response: Response = try await call {
            try await client.rpc("displace", params: Params(p_booking_id: bookingID,
                                                            p_accept_no_replacement: acceptNoReplacement))
                .execute().value
        }
        return response.ok ? .displaced(replacementFound: response.replacement_found ?? false) : .noReplacement
    }

    @discardableResult
    public func cancelBooking(_ bookingID: UUID, wholeSeries: Bool) async throws -> Int {
        struct Params: Encodable {
            let p_booking_id: UUID
            let p_whole_series: Bool
        }
        struct Response: Decodable {
            let cancelled_count: Int
        }
        let response: Response = try await call {
            try await client.rpc("cancel_booking", params: Params(p_booking_id: bookingID,
                                                                  p_whole_series: wholeSeries))
                .execute().value
        }
        return response.cancelled_count
    }

    // MARK: Mitglieder und Familie

    public func updateName(memberID: UUID, firstName: String, short: String) async throws {
        try await call {
            try await client.from("members").update(["first_name": firstName, "short": short])
                .eq("id", value: memberID).execute()
        }
    }

    public func setRole(_ role: Member.Role, memberID: UUID) async throws {
        try await call {
            try await client.from("members").update(["role": role.rawValue]).eq("id", value: memberID).execute()
        }
    }

    public func removeMember(_ memberID: UUID) async throws {
        try await call { try await client.rpc("remove_member", params: ["p_member_id": memberID]).execute() }
    }

    public func renameFamily(_ familyID: UUID, name: String) async throws {
        try await call {
            try await client.from("families").update(["name": name]).eq("id", value: familyID).execute()
        }
    }

    public func regenerateInviteCode() async throws -> String {
        try await call { try await client.rpc("regenerate_invite_code").execute().value }
    }

    // MARK: Autos

    /// Zeile für `cars`; leere optionale Felder werden ausdrücklich als null geschickt.
    private struct CarRowParams: Encodable {
        let input: CarInput
        let familyID: UUID?

        enum CodingKeys: String, CodingKey {
            case make, model, paint, nickname, plate
            case familyId = "family_id"
            case primaryMemberId = "primary_member_id"
            case pickerlUntil = "pickerl_until"
            case serviceDue = "service_due"
            case odometerKm = "odometer_km"
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(familyID, forKey: .familyId)
            try container.encode(input.make, forKey: .make)
            try container.encode(input.model, forKey: .model)
            try container.encode(input.paint, forKey: .paint)
            try container.encode(input.nickname, forKey: .nickname)
            try container.encode(input.plate, forKey: .plate)
            try container.encode(input.primaryMemberId, forKey: .primaryMemberId)
            try container.encode(input.pickerlUntil, forKey: .pickerlUntil)
            try container.encode(input.serviceDue, forKey: .serviceDue)
            try container.encode(input.odometerKm, forKey: .odometerKm)
        }
    }

    public func addCar(_ input: CarInput, familyID: UUID) async throws {
        try await call {
            try await client.from("cars").insert(CarRowParams(input: input, familyID: familyID)).execute()
        }
    }

    public func updateCar(_ carID: UUID, input: CarInput) async throws {
        try await call {
            try await client.from("cars").update(CarRowParams(input: input, familyID: nil))
                .eq("id", value: carID).execute()
        }
    }

    public func archiveCar(_ carID: UUID) async throws {
        try await call {
            try await client.from("cars").update(["archived": true]).eq("id", value: carID).execute()
        }
    }

    // MARK: Schäden

    static let damageBucket = "damage-photos"
    static let logger = Logger(subsystem: "at.rauscher.carpool", category: "api")

    public func reportDamage(_ report: DamageReport, familyID: UUID) async throws {
        struct Row: Encodable {
            let car_id: UUID
            let description: String
            let drivable: Bool
            let photo_path: String?
        }
        var path: String?
        if let photo = report.photo {
            let name = "\(familyID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            try await call {
                try await client.storage.from(Self.damageBucket)
                    .upload(name, data: photo, options: FileOptions(contentType: "image/jpeg"))
            }
            path = name
        }
        let row = Row(car_id: report.carID, description: report.description, drivable: report.drivable,
                      photo_path: path)
        try await call { try await client.from("damages").insert(row).execute() }
    }

    public func resolveDamage(_ damage: Damage) async throws {
        struct Row: Encodable {
            let resolved_at: String
            let photo_path: String?
        }
        try await call {
            try await client.from("damages").update(Row(resolved_at: Date().formatted(.iso8601), photo_path: nil))
                .eq("id", value: damage.id).execute()
        }
        guard let path = damage.photoPath else { return }
        // Der Schaden ist erledigt; ein liegengebliebenes Foto ist kein Fehler für die Person.
        do {
            _ = try await client.storage.from(Self.damageBucket).remove(paths: [path])
        } catch {
            Self.logger.error("Schadenfoto \(path, privacy: .public) nicht gelöscht: \(error.localizedDescription)")
        }
    }

    public func damagePhoto(path: String) async throws -> Data {
        try await call { try await client.storage.from(Self.damageBucket).download(path: path) }
    }

    // MARK: Einstellungen

    public func settings(memberID: UUID) async throws -> MemberSettings {
        try await call {
            try await client.from("settings").select().eq("member_id", value: memberID).single().execute().value
        }
    }

    public func updateSettings(_ settings: MemberSettings) async throws {
        struct Row: Encodable {
            let notify_car_free: Bool
            let notify_booking_displaced: Bool
            let notify_reservation_soon: Bool
            let notify_return_overdue: Bool
            let notify_service_pickerl: Bool
            let calendar_car_animation: String
            let launch_animation: String
        }
        let row = Row(notify_car_free: settings.notifyCarFree,
                      notify_booking_displaced: settings.notifyBookingDisplaced,
                      notify_reservation_soon: settings.notifyReservationSoon,
                      notify_return_overdue: settings.notifyReturnOverdue,
                      notify_service_pickerl: settings.notifyServicePickerl,
                      calendar_car_animation: settings.calendarCarAnimation.rawValue,
                      launch_animation: settings.launchAnimation.rawValue)
        try await call {
            try await client.from("settings").update(row).eq("member_id", value: settings.memberId).execute()
        }
    }

    // MARK: Fehler

    /// Übersetzt jeden Fehler in einen `CarpoolError`.
    @discardableResult
    private func call<T>(_ body: () async throws -> T) async throws(CarpoolError) -> T {
        do {
            return try await body()
        } catch {
            throw CarpoolError.from(error)
        }
    }
}
