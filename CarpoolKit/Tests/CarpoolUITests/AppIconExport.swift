import SwiftUI
import Testing
@testable import CarpoolUI

/// Erzeugt das App-Icon (Schlüsselbrett aus dem Splash) in Hell, Dunkel und Tinted.
/// Nur auf Wunsch: `TEST_RUNNER_EXPORT_APP_ICON=$PWD/../Carpool/Resources/Assets.xcassets/AppIcon.appiconset xcodebuild test … -only-testing:CarpoolUITests/AppIconExport`
@MainActor
@Suite("App-Icon")
struct AppIconExport {
    nonisolated static let target = ProcessInfo.processInfo.environment["EXPORT_APP_ICON"]

    @Test(.enabled(if: target != nil))
    func export() throws {
        let folder = URL(fileURLWithPath: Self.target!)
        let variants: [(name: String, scheme: ColorScheme, tinted: Bool)] = [
            ("AppIcon.png", .light, false), ("AppIcon-Dark.png", .dark, false), ("AppIcon-Tinted.png", .dark, true)
        ]
        for variant in variants {
            let artwork = AppIconArtwork(tinted: variant.tinted).environment(\.colorScheme, variant.scheme)
            let renderer = ImageRenderer(content: artwork)
            renderer.scale = 1
            // App Store verlangt das helle Icon ohne Alphakanal; Tinted braucht Transparenz.
            renderer.isOpaque = !variant.tinted
            let image = try #require(renderer.uiImage)
            let data = try #require(image.pngData())
            try data.write(to: folder.appendingPathComponent(variant.name))
        }
    }
}
