import XCTest

/// Schnellzugriff mit der Beispiel-Familie (`-previewFamily`, Lisa fährt Radieschen):
/// Widget-Vorschau, Kurzbefehl-Seite und Deep Links aus Widgets und Live-Aktivität.
final class QuickAccessFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-previewFamily"]
        app.launch()
    }

    @MainActor
    func testWidgetAndShortcutScreens() throws {
        app.tabBars.buttons["Mitglieder"].tap()
        app.buttons["members.settings"].tap()
        let widgets = app.buttons["Widgets"]
        XCTAssertTrue(widgets.waitForExistence(timeout: 5))
        app.swipeUp()
        attachScreenshot("Einstellungen Schnellzugriff")

        widgets.tap()
        XCTAssertTrue(app.buttons["Radieschen zurückgeben"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Jonas nimmt Radieschen"].exists)
        attachScreenshot("Widgets")
        app.swipeUp()
        attachScreenshot("Live-Aktivität")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["Kurzbefehle und Siri"].tap()
        XCTAssertTrue(app.navigationBars["Kurzbefehle und Siri"].waitForExistence(timeout: 5))
        attachScreenshot("Kurzbefehle")
    }

    @MainActor
    func testDeepLinksOpenReturnAndCalendar() throws {
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "car.Radieschen").firstMatch
            .waitForExistence(timeout: 5))
        app.tabBars.buttons["Kalender"].tap()

        app.open(URL(string: "carpool://return")!)
        XCTAssertTrue(app.staticTexts["Radieschen zurückgeben"].waitForExistence(timeout: 5))
        attachScreenshot("Rückgabe aus Widget")
        app.swipeDown(velocity: .fast)

        app.open(URL(string: "carpool://calendar")!)
        XCTAssertTrue(app.tabBars.buttons["Kalender"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Kalender"].isSelected)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
