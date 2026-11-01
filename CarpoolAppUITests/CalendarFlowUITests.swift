import XCTest

/// Kalender und Reservieren mit der Beispiel-Familie (`-previewFamily`, ohne Netzwerk, als Lisa):
/// Konflikt im Formular → Tauschen → Morgen → Übernehmen → Warnung ohne Ersatzauto.
final class CalendarFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-previewFamily"]
        app.launch()
    }

    @MainActor
    func testReserveWithConflictSwapAndDisplace() throws {
        app.tabBars.buttons["Kalender"].tap()
        XCTAssertTrue(app.staticTexts["Heute"].waitForExistence(timeout: 5))
        attachScreenshot("Kalender")

        app.buttons["calendar.reserve"].tap()
        let submit = app.buttons["reserve.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))

        // Octavia fährt gerade Mama: Hinweis im Formular, Button gesperrt.
        app.buttons["reserve.car.Octavia"].tap()
        let swap = app.buttons["reserve.swap.Flitzer"]
        XCTAssertTrue(swap.waitForExistence(timeout: 5))
        XCTAssertEqual(submit.label, "Octavia ist belegt")
        XCTAssertFalse(submit.isEnabled)
        attachScreenshot("Konflikt im Formular")

        swap.tap()
        XCTAssertTrue(waitFor(submit, label: "Reservieren"))
        XCTAssertTrue(submit.isEnabled)

        // Morgen hat Felix Flitzer; Lisa ist Hauptnutzerin und darf übernehmen.
        app.buttons["Morgen"].tap()
        let displace = app.buttons["reserve.displace"]
        XCTAssertTrue(displace.waitForExistence(timeout: 5))
        attachScreenshot("Konflikt als Hauptnutzerin")

        displace.tap()
        XCTAssertTrue(app.staticTexts["Felix’ Buchung übernehmen?"].waitForExistence(timeout: 5))
        attachScreenshot("Übernehmen bestätigen")
        app.buttons["displace.confirm"].tap()

        XCTAssertTrue(app.staticTexts["Kein Ersatzauto frei"].waitForExistence(timeout: 5))
        attachScreenshot("Warnung ohne Ersatzauto")
        app.buttons["displace.confirm"].tap()

        XCTAssertTrue(app.buttons["calendar.reserve"].waitForExistence(timeout: 5))
        XCTAssertFalse(submit.exists, "Formular ist nach dem Reservieren geschlossen")
    }

    private func waitFor(_ element: XCUIElement, label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5) == .completed
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
