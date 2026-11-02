import XCTest

/// Einstellungen „Konto löschen" (nur Bestätigung, Beispiel-Familie löscht nichts) und Kalender-„+" in Hell/Dunkel.
final class AccountUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    func testDeleteAccountAsksForConfirmation() throws {
        app.launchArguments = ["-previewFamily"]
        app.launch()
        app.tabBars.buttons["Mitglieder"].tap()
        app.buttons["members.settings"].tap()
        let delete = app.buttons["settings.deleteAccount"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        // Erst ganz nach unten scrollen und ausschwingen lassen: ein Tippen während des Nachschwingens
        // stoppt nur das Scrollen.
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        delete.tap()
        let alert = app.alerts["Konto löschen?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.buttons["Konto löschen"].exists)
        attachScreenshot("Konto löschen bestätigen")
        alert.buttons["Abbrechen"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testReserveButtonInLightAndDark() throws {
        for mode in ["light", "dark"] {
            app.launchArguments = ["-previewFamily", "-appearance", mode]
            app.launch()
            app.tabBars.buttons["Kalender"].tap()
            XCTAssertTrue(app.buttons["calendar.reserve"].waitForExistence(timeout: 5))
            attachScreenshot("Kalender \(mode)")
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
