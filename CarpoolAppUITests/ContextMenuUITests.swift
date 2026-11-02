import XCTest

/// Kontextmenüs mit der Beispiel-Familie (`-previewFamily`, Lisa fährt Radieschen, Lisa ist Admin):
/// Verlängern der eigenen Fahrt, gestrige Fahrt im Kalender, Mitglied entfernen.
final class ContextMenuUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-previewFamily"]
        app.launch()
    }

    @MainActor
    func testExtendOwnTripAndSeeYesterday() throws {
        app.tabBars.buttons["Kalender"].tap()
        let ownTrip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Du, Radieschen")).firstMatch
        XCTAssertTrue(ownTrip.waitForExistence(timeout: 5))
        ownTrip.press(forDuration: 1)
        let extend = app.buttons["Verlängern"]
        XCTAssertTrue(extend.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Bearbeiten"].exists, "Fahrten lassen sich nur verlängern")
        attachScreenshot("Kontextmenü Fahrt")
        extend.tap()
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bis ")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()

        // Gestern: Jonas ist mit Octavia gefahren (abgeschlossene Fahrt aus dem Verlauf).
        let today = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", heute,")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 3))
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        if calendar.component(.weekday, from: Date()) == 2 {  // Montag: gestern liegt in der Vorwoche
            let start = today.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 220, dy: 0)))
        }
        let short = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][calendar.component(.weekday, from: yesterday) - 1]
        let label = "\(short) \(calendar.component(.day, from: yesterday)),"
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch.tap()
        let pastTrip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Jonas, Octavia")).firstMatch
        XCTAssertTrue(pastTrip.waitForExistence(timeout: 5))
        attachScreenshot("Kalender")
    }

    @MainActor
    func testAdminCanRemoveMember() throws {
        app.tabBars.buttons["Mitglieder"].tap()
        let jonas = app.staticTexts["Jonas"]
        XCTAssertTrue(jonas.waitForExistence(timeout: 5))
        jonas.press(forDuration: 1)
        let remove = app.buttons["Aus der Familie entfernen"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        attachScreenshot("Kontextmenü Mitglied")
        remove.tap()
        XCTAssertTrue(app.alerts["Jonas entfernen?"].waitForExistence(timeout: 3))
        attachScreenshot("Entfernen bestätigen")
        app.alerts.buttons["Abbrechen"].tap()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
