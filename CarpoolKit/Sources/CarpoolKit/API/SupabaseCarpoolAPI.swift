import Foundation
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
        try await call {
            try await client.rpc("join_family", params: ["p_invite_code": inviteCode, "p_first_name": firstName])
                .execute()
        }
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
            return try await FamilySnapshot(family: family, me: member, members: members, cars: cars,
                                            bookings: bookings)
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

        init(_ request: ReservationRequest, displace: Bool? = nil, acceptNoReplacement: Bool? = nil) {
            p_car_id = request.carID
            p_starts_at = Self.timestamp(request.startsAt)
            p_ends_at = Self.timestamp(request.endsAt)
            p_rrule = request.rrule
            p_until = request.until
            p_displace = displace
            p_accept_no_replacement = acceptNoReplacement
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
            try await client.rpc("reserve", params: ReserveParams(request, displace: displace,
                                                                  acceptNoReplacement: acceptNoReplacement))
                .execute().value
        }
    }

    public func freeCars(from start: Date, to end: Date) async throws -> [Car] {
        try await call {
            try await client.rpc("free_cars", params: ["p_starts_at": ReserveParams.timestamp(start),
                                                       "p_ends_at": ReserveParams.timestamp(end)])
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
