import Foundation

/// Letzter Stand der Familie im gemeinsamen App-Group-Ordner, damit Widgets ihn ohne
/// Netzwerk und ohne Anmeldung lesen können. Die App schreibt, die Widgets lesen.
public struct SharedSnapshotStore: Sendable {
    public static let appGroup = "group.at.rauscher.carpool"
    static let fileName = "family-snapshot.json"

    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appending(path: Self.fileName)
    }

    /// Speicher im App-Group-Container; nil, wenn die App Group fehlt (z. B. falsch signiert).
    public static var shared: SharedSnapshotStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map(SharedSnapshotStore.init(directory:))
    }

    public func save(_ snapshot: FamilySnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Nil, wenn nichts gespeichert ist oder die Datei nicht lesbar ist.
    public func load() -> FamilySnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(FamilySnapshot.self, from: data)
    }

    /// Beim Abmelden: Widgets zeigen danach nichts mehr von der Familie.
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
