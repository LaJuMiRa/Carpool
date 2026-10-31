import XCTest

/// Kernablauf gegen das echte Backend: Nehmen → Rückgängig → Nehmen → Zurückgeben.
/// Braucht ein Testkonto ohne laufende Fahrt, dessen Familie das Auto „Radieschen" frei hat:
/// `TEST_RUNNER_DEV_EMAIL=… TEST_RUNNER_DEV_PASSWORD=… xcodebuild test …`
final class CoreFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["DEV_EMAIL"], let password = environment["DEV_PASSWORD"] else {
            throw XCTSkip("DEV_EMAIL/DEV_PASSWORD nicht gesetzt")
        }
        app = XCUIApplication()
        app.launchEnvironment = ["DEV_EMAIL": email, "DEV_PASSWORD": password]
        app.launch()
    }

    @MainActor
    func testTakeUndoTakeReturn() throws {
        let take = app.buttons["take.Radieschen"]
        XCTAssertTrue(take.waitForExistence(timeout: 15), "Radieschen ist nicht frei")
        take.tap()

        XCTAssertTrue(app.staticTexts["Radieschen gehört dir"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trip.return"].exists)
        attachScreenshot("Nach dem Nehmen")

        app.buttons["undo"].tap()
        XCTAssertTrue(take.waitForExistence(timeout: 5), "Rückgängig hat die Fahrt nicht zurückgenommen")

        take.tap()
        let returnButton = app.buttons["trip.return"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 5))
        returnButton.tap()

        XCTAssertTrue(app.staticTexts["Radieschen zurückgeben"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["Tankstand"].exists || app.adjustableElements["Tankstand"].exists)
        attachScreenshot("Rückgabe-Sheet")
        app.buttons["return.confirm"].tap()

        XCTAssertTrue(app.staticTexts["Radieschen zurückgegeben"].waitForExistence(timeout: 5))
        XCTAssertTrue(take.waitForExistence(timeout: 5))
        attachScreenshot("Nach der Rückgabe")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIApplication {
    var adjustableElements: XCUIElementQuery { descendants(matching: .slider) }
}
