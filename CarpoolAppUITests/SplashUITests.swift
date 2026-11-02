import XCTest

/// Splash (F01) mit `-splashHold` erzwungen (Endstand 8 s), darunter die Beispiel-Familie.
final class SplashUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-splashHold", "-previewFamily"]
        app.launch()
    }

    @MainActor
    func testSplashEndsByItself() throws {
        let splash = app.descendants(matching: .any)["splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 5))
        attachScreenshot("Splash")
        XCTAssertTrue(splash.waitForNonExistence(timeout: 12))
        XCTAssertTrue(app.tabBars.buttons["Autos"].isHittable)
    }

    @MainActor
    func testTapSkipsSplash() throws {
        let splash = app.descendants(matching: .any)["splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 5))
        splash.tap()
        XCTAssertTrue(splash.waitForNonExistence(timeout: 2))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
