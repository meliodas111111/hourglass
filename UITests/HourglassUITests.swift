import XCTest

/// Main user journeys. The app is launched with `-uiTesting`: clean data, no ads, no permission primer.
final class HourglassUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testStartPauseResumeStop() {
        let primary = app.buttons["primaryButton"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.tap()

        let pause = app.buttons["pauseButton"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        pause.tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 2))
        pause.tap()                                   // resume
        XCTAssertFalse(app.staticTexts["Paused"].exists)

        app.buttons["stopButton"].tap()
        XCTAssertTrue(app.buttons["primaryButton"].label.contains("Start"))
    }

    func testShortestTimerFinishes() {
        app.buttons["timeLabel"].tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 0).waitForExistence(timeout: 3))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "0")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: "0")
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: "5")
        app.buttons["setDuration"].tap()

        app.buttons["primaryButton"].tap()
        XCTAssertTrue(app.staticTexts["finishedLabel"].waitForExistence(timeout: 9), "5-second timer must finish")
        XCTAssertTrue(app.buttons["primaryButton"].label.contains("Restart"))
    }

    func testDurationBelowMinimumIsRejected() {
        app.buttons["timeLabel"].tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 0).waitForExistence(timeout: 3))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "0")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: "0")
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: "3")
        XCTAssertFalse(app.buttons["setDuration"].isEnabled)
    }

    func testStartSequenceFromLibrary() {
        app.buttons["libraryButton"].tap()
        let row = app.descendants(matching: .any)["libraryRow-Pomodoro"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        let phase = app.staticTexts["phaseLabel"]
        XCTAssertTrue(phase.waitForExistence(timeout: 3))
        XCTAssertTrue(phase.label.contains("1/8"))
    }

    func testZenModeHidesAndRestoresControls() {
        app.buttons["zenButton"].tap()
        XCTAssertFalse(app.buttons["primaryButton"].waitForExistence(timeout: 1))
        app.otherElements["hourglass"].tap()
        XCTAssertTrue(app.buttons["primaryButton"].waitForExistence(timeout: 2))
    }

    func testLockedThemeOpensPaywall() {
        app.buttons["themesButton"].tap()
        let jade = app.buttons["theme-jade"]
        XCTAssertTrue(jade.waitForExistence(timeout: 3))
        jade.tap()
        XCTAssertTrue(app.buttons["buySupporter"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["restorePurchases"].exists)
    }

    /// Launch performance (cold start) — run on device for meaningful numbers.
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) { XCUIApplication().launch() }
    }
}
