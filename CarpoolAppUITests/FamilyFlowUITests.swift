import XCTest

/// Auto-Detail, Schaden melden, Mitglieder, Einstellungen und Auto hinzufügen mit der Beispiel-Familie
/// (`-previewFamily`, ohne Netzwerk, als Lisa mit Admin-Rechten).
final class FamilyFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-previewFamily"]
        app.launch()
    }

    @MainActor
    func testCarDetailAndDamageReport() throws {
        let card = app.descendants(matching: .any).matching(identifier: "car.Radieschen").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()

        let report = app.buttons["detail.reportDamage"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Kratzer Stoßstange hinten"].exists)
        attachScreenshot("Auto-Detail")
        app.swipeUp()
        attachScreenshot("Auto-Detail unten")
        app.swipeDown()

        report.tap()
        let text = app.textViews["damage.description"].exists
            ? app.textViews["damage.description"] : app.textFields["damage.description"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("Delle Tür links")
        attachScreenshot("Schaden melden")
        app.buttons["damage.submit"].tap()
        XCTAssertTrue(report.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMembersSettingsAndAddCar() throws {
        app.tabBars.buttons["Mitglieder"].tap()
        XCTAssertTrue(app.staticTexts["Familie Berger"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["fährt gerade Octavia"].exists)
        attachScreenshot("Mitglieder")

        app.buttons["members.settings"].tap()
        XCTAssertTrue(app.buttons["settings.addCar"].waitForExistence(timeout: 5))
        attachScreenshot("Einstellungen")
        app.swipeUp()
        attachScreenshot("Einstellungen unten")
        app.swipeDown()

        app.buttons["settings.addCar"].tap()
        let name = app.textFields["car.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("BMW X3")
        app.buttons["schwarz"].tap()
        attachScreenshot("Auto hinzufügen")
        app.buttons["car.save"].tap()
        XCTAssertTrue(app.buttons["settings.addCar"].waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
