import XCTest

final class PruvaUITests: XCTestCase {
    @MainActor func testTargetEditorValidatesAndUpdatesCourse() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["edit-course-target"].tap()
        let distance = app.textFields["target-second"]
        XCTAssertTrue(distance.waitForExistence(timeout: 3))
        distance.tap()
        if let value = distance.value as? String {
            distance.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        distance.typeText("0")
        app.buttons["save-course-target"].tap()
        XCTAssertTrue(app.staticTexts["target-error"].waitForExistence(timeout: 3))
        distance.tap()
        distance.typeText(XCUIKeyboardKey.delete.rawValue + "1250")
        app.buttons["save-course-target"].tap()
        XCTAssertTrue(app.buttons["edit-course-target"].waitForExistence(timeout: 3))
        app.buttons["edit-course-target"].tap()
        XCTAssertTrue(distance.waitForExistence(timeout: 3))
        XCTAssertEqual(distance.value as? String, "1250")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Focused target editor"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testWrittenVoiceCommandShowsModelAdvice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        app.launch()
        let input = app.textFields["voice-command-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertTrue(input.isHittable)
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        input.typeText("Rüzgâr açtı")
        app.buttons["voice-submit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["voice-advice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["KONTRAYI KORU"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Voice command advice"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testScenarioAndDecisionJournal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
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
        let scenario = XCTAttachment(screenshot: app.screenshot())
        scenario.name = "Scenario overview"
        scenario.lifetime = .keepAlways
        add(scenario)
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
