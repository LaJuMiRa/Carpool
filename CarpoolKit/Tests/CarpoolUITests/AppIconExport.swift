import SwiftUI
import Testing
@testable import CarpoolUI

/// Erzeugt das App-Icon (Schlüsselbrett aus dem Splash) in Hell und Dunkel.
/// Nur auf Wunsch: `TEST_RUNNER_EXPORT_APP_ICON=$PWD/../Carpool/Resources/Assets.xcassets/AppIcon.appiconset xcodebuild test … -only-testing:CarpoolUITests/AppIconExport`
@MainActor
@Suite("App-Icon")
struct AppIconExport {
    nonisolated static let target = ProcessInfo.processInfo.environment["EXPORT_APP_ICON"]

    @Test(.enabled(if: target != nil))
    func export() throws {
        let folder = URL(fileURLWithPath: Self.target!)
        for (name, scheme) in [("AppIcon.png", ColorScheme.light), ("AppIcon-Dark.png", .dark)] {
            let renderer = ImageRenderer(content: AppIconArtwork().environment(\.colorScheme, scheme))
            renderer.scale = 1
            renderer.isOpaque = true // App Store verlangt Icons ohne Alphakanal
            let image = try #require(renderer.uiImage)
            let data = try #require(image.pngData())
            try data.write(to: folder.appendingPathComponent(name))
        }
    }
}
