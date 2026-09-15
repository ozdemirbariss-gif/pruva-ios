import XCTest

final class PruvaUITests: XCTestCase {
    @MainActor func testScenarioAndDecisionJournal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["Parkur seç"].waitForExistence(timeout: 10))
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Tactician overview"
        overview.lifetime = .keepAlways
        add(overview)
        XCTAssertTrue(app.buttons["tab-Senaryolar"].exists)
        app.buttons["tab-Senaryolar"].tap()
        XCTAssertTrue(app.staticTexts["SENARYO SEÇ"].exists)
        app.buttons["scenario-persistentHeader"].tap()
        XCTAssertTrue(app.staticTexts["scenario-decision"].exists)
        app.buttons["tab-Seyir"].tap()
        for _ in 0..<6 {
            if app.buttons["save-decision"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["save-decision"].isHittable)
        app.buttons["save-decision"].tap()
        app.buttons["tab-Seyir defteri"].tap()
        XCTAssertTrue(app.staticTexts["1 KAYIT"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Decision journal"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testCrossLegPresetKeepsOriginalMark() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["tab-Senaryolar"].tap()
        let carousel = app.scrollViews["scenario-carousel"]
        for _ in 0..<3 {
            if app.buttons["scenario-downwind"].isHittable { break }
            carousel.swipeLeft()
        }
        app.buttons["scenario-downwind"].tap()
        XCTAssertEqual(app.staticTexts["scenario-distance"].label.filter(\.isNumber), "1882")
        if !app.buttons["scenario-finalApproach"].isHittable { carousel.swipeLeft() }
        app.buttons["scenario-finalApproach"].tap()
        XCTAssertEqual(app.staticTexts["scenario-distance"].label.filter(\.isNumber), "293")
        XCTAssertEqual(app.staticTexts["scenario-decision"].label, "Son yaklaşımı koru")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Scenario lab"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testMapAndRoleControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["Navigatör"].waitForExistence(timeout: 10))
        app.buttons["Navigatör"].tap()
        XCTAssertTrue(app.staticTexts["VMC · HEDEF"].exists)
        app.buttons["Harita katmanları"].tap()
        XCTAssertTrue(app.switches["Layline ve belirsizlik bandı"].waitForExistence(timeout: 3))
        let layerToggle = app.switches["Layline ve belirsizlik bandı"]
        let previousValue = layerToggle.value as? String
        // SwiftUI exposes the entire Form row as a switch. Hit its trailing
        // control; tapping the label in the row's center does not change it.
        layerToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertNotEqual(layerToggle.value as? String, previousValue)
        app.buttons["Bitti"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Navigator"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
