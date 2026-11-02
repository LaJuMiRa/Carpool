import AppIntents
import CarpoolKit
import Foundation

/// Tankstand für Kurzbefehl und Siri: ¼, ½, ¾, voll.
enum TankLevel: Int, AppEnum {
    case quarter = 1, half, threeQuarters, full

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tankstand"
    static let caseDisplayRepresentations: [TankLevel: DisplayRepresentation] = [
        .quarter: "¼", .half: "½", .threeQuarters: "¾", .full: "voll"
    ]

    var fuel: FuelLevel { FuelLevel(quarters: rawValue) }
}

/// Kurzbefehl „Auto zurückgeben" (F09): gibt das Auto zurück, das ich gerade fahre,
/// und fragt nur nach dem Tankstand. Läuft im Prozess der App, ohne sie zu öffnen.
struct ReturnCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Auto zurückgeben"
    static let description = IntentDescription("Gibt das Auto zurück, das du gerade fährst. Fragt nur nach dem Tankstand.")
    static let openAppWhenRun = false

    @Parameter(title: "Tankstand")
    var tank: TankLevel?

    static var parameterSummary: some ParameterSummary {
        Summary("Auto zurückgeben, Tank \(\.$tank)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let backend = try await IntentBackend.connect()
        let snapshot = try await backend.snapshot()
        let text = TimeText(family: snapshot.family)
        guard let trip = OverviewState(snapshot: snapshot, now: .now, timeText: text).myTrip else {
            return .result(dialog: "Du fährst gerade kein Auto.")
        }
        let level: TankLevel
        if let tank {
            level = tank
        } else {
            level = try await $tank.requestValue("Wie voll ist der Tank von \(trip.car.title)?")
        }
        try await backend.run { try await $0.returnCar(trip.car.id, fuel: level.fuel) }
        if let fresh = try? await backend.snapshot() {
            await QuickAccessSync.update(fresh)
        }
        return .result(dialog: "\(trip.car.title) zurückgegeben.")
    }
}

/// Siri-Sätze und Eintrag in der Kurzbefehle-App.
struct CarpoolShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ReturnCarIntent(),
                    phrases: [
                        "Auto zurückgeben mit \(.applicationName)",
                        "\(.applicationName) Auto zurückgeben",
                        "Mit \(.applicationName) zurückgeben"
                    ],
                    shortTitle: "Auto zurückgeben",
                    systemImageName: "car.side")
    }
}

/// Zugang zum Backend für Kurzbefehle: gespeicherte Anmeldung, eigene Mitgliedschaft.
@MainActor
struct IntentBackend {
    let api: any CarpoolAPI
    let member: Member

    static func connect() async throws -> IntentBackend {
        guard let api = AppSession.live()?.api else { throw IntentMessage("Carpool ist nicht eingerichtet.") }
        guard let userID = await api.currentUserID() else {
            throw IntentMessage("Melde dich zuerst in der App an.")
        }
        let member = try await guarded { try await api.membership(userID: userID) }
        guard let member else { throw IntentMessage("Tritt zuerst in der App einer Familie bei.") }
        return IntentBackend(api: api, member: member)
    }

    func snapshot() async throws -> FamilySnapshot {
        try await run { [member] in try await $0.snapshot(for: member) }
    }

    func run<T>(_ body: (any CarpoolAPI) async throws -> T) async throws -> T {
        try await Self.guarded { try await body(api) }
    }

    /// Fehler des Backends als verständlicher Satz für Siri.
    private static func guarded<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw IntentMessage(CarpoolError.from(error).message)
        }
    }
}

/// Fehler, den Siri bzw. Kurzbefehle als Satz vorlesen.
struct IntentMessage: Error, CustomLocalizedStringResourceConvertible {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var localizedStringResource: LocalizedStringResource { "\(text)" }
}
