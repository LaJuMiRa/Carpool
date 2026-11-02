import SwiftUI

/// Motiv des App-Icons: das Schlüsselbrett aus dem Splash auf Papier, 1024 × 1024.
/// Das Brett läuft über den Rand, damit die Schlüssel auch klein gut lesbar bleiben.
/// Hell/Dunkel folgen der Umgebung (`colorScheme`).
public struct AppIconArtwork: View {
    public static let side: CGFloat = 1024

    /// Tinted-Variante: Graustufen ohne Hintergrund; iOS färbt sie selbst ein.
    private let tinted: Bool

    public init(tinted: Bool = false) {
        self.tinted = tinted
    }

    public var body: some View {
        KeyBoardScene()
            .frame(height: 104, alignment: .top)
            .scaleEffect(3.4)
            .frame(width: Self.side, height: Self.side)
            .grayscale(tinted ? 1 : 0)
            .background(tinted ? Color.clear : Color.paper)
    }
}

#Preview {
    AppIconArtwork().scaleEffect(0.3)
}
