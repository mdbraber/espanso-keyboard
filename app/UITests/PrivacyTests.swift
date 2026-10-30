import XCTest

/// Keyboard Settings › Privacy hides Transcripts and Your Taps (espanso-keyboard).
final class PrivacyTests: XCTestCase {
    func testSwitchingOffHidesTheirTabs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-HexResetSettings", "YES", "-HexSettings", "YES"]
        app.launch()
        let transcriptsTab = app.tabBars.buttons["Transcripts"], tapsTab = app.tabBars.buttons["Your Taps"]
        XCTAssertTrue(transcriptsTab.waitForExistence(timeout: 5))
        XCTAssertTrue(tapsTab.exists)

        for name in ["Keep Transcripts", "Show Your Taps"] {
            let toggle = app.switches[name]
            while !toggle.isHittable { app.swipeUp() }
            XCTAssertEqual(toggle.value as? String, "1", "\(name) starts on")
            toggle.tap()
            let keep = app.buttons["Keep Them"]
            if keep.waitForExistence(timeout: 1) { keep.tap() }
            XCTAssertEqual(toggle.value as? String, "0")
        }
        XCTAssertFalse(transcriptsTab.exists)
        XCTAssertFalse(tapsTab.exists)

        app.terminate()
        app.launchArguments = ["-HexSettings", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Hex"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Transcripts"].exists, "stays hidden after a relaunch")

        for name in ["Keep Transcripts", "Show Your Taps"] {
            let toggle = app.switches[name]
            while !toggle.isHittable { app.swipeUp() }
            toggle.tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Transcripts"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.tabBars.buttons["Your Taps"].exists)
    }
}
