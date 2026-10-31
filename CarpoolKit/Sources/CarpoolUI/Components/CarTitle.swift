import SwiftUI

/// Anzeigenamen eines Autos nach den Regeln aus CLAUDE.md.
public struct CarNaming: Sendable, Hashable {
    public let make: String
    public let model: String
    public let nickname: String?

    public init(make: String, model: String, nickname: String?) {
        self.make = make
        self.model = model
        let trimmed = nickname?.trimmingCharacters(in: .whitespaces)
        self.nickname = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Groß: Spitzname, sonst Modell.
    public var title: String { nickname ?? model }

    /// Klein darunter: Marke + Modell.
    public var subtitle: String { "\(make) \(model)" }

    /// Für VoiceOver: Spitzname + Modell.
    public var spokenName: String {
        nickname.map { "\($0), \(make) \(model)" } ?? "\(make) \(model)"
    }
}

/// Spitzname groß, Modell klein darunter.
public struct CarTitle: View {
    public enum Size { case regular, large }

    private let naming: CarNaming
    private let size: Size
    private let showsSubtitle: Bool

    public init(_ naming: CarNaming, size: Size = .regular, showsSubtitle: Bool = true) {
        self.naming = naming
        self.size = size
        self.showsSubtitle = showsSubtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(naming.title)
                .font(size == .large ? .title2.bold() : .headline)
                .kerning(size == .large ? -0.4 : 0)
                .foregroundStyle(Color.ink)
            if showsSubtitle {
                Text(naming.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }
}

/// Detail-Titel: `Golf – „Radieschen"`, Spitzname kursiv.
public struct CarDetailTitle: View {
    private let naming: CarNaming

    public init(_ naming: CarNaming) {
        self.naming = naming
    }

    public var body: some View {
        title
            .font(.title.bold())
            .kerning(-0.6)
            .accessibilityLabel(naming.spokenName)
    }

    private var title: Text {
        guard let nickname = naming.nickname else {
            return Text(naming.model).foregroundStyle(Color.ink)
        }
        let model = Text(naming.model).foregroundStyle(Color.ink)
        let dash = Text(" – ").foregroundStyle(Color.inkMuted)
        let nick = Text("„\(nickname)\u{201C}").italic().foregroundStyle(Color.ink)
        return Text("\(model)\(dash)\(nick)")
    }
}
