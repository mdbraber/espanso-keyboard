import XCTest

/// Each feature on Hex's main screen has a switch that turns it off completely; its options show only while it's on
/// (espanso-keyboard).
final class FeatureSwitchTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-HexResetSettings", "YES", "-HexFocus", "YES"]
        app.launch()
    }

    private func open(_ item: String) {
        let cell = app.cells.staticTexts[item].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), item)
        cell.tap()
    }

    private func back() {
        app.navigationBars.buttons.firstMatch.tap()
    }

    private func flip(_ name: String) {
        let toggle = app.switches[name]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), name)
        toggle.tap()
        let keep = app.buttons["Keep Them"]
        if keep.waitForExistence(timeout: 1) { keep.tap() }
    }

    /// Whether the keyboard, brought up in the Try It field, shows its mic.
    private func keyboardHasMic() -> Bool {
        app.textViews["Try Hex"].tap()
        XCTAssertTrue(app.keys["hex.space"].waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
        return app.descendants(matching: .any)["hex.mic"].waitForExistence(timeout: 2)
    }

    func testVoiceOffTakesAwayTheMicAndTranscripts() {
        XCTAssertTrue(keyboardHasMic())
        open("Voice")
        XCTAssertTrue(app.switches["Transcripts"].waitForExistence(timeout: 5))
        flip("Voice Typing")
        XCTAssertFalse(app.switches["Transcripts"].exists, "options go with the feature")
        XCTAssertFalse(app.cells.staticTexts["Keep Mic On"].exists)
        XCTAssertFalse(app.tabBars.buttons["Transcripts"].exists)
        back()
        XCTAssertTrue(app.cells.staticTexts["Off"].exists, "the main screen says it's off")
        XCTAssertFalse(keyboardHasMic())

        open("Voice")
        flip("Voice Typing")
        XCTAssertTrue(app.switches["Transcripts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Transcripts"].exists)
        flip("Transcripts")
        XCTAssertFalse(app.tabBars.buttons["Transcripts"].exists)
        flip("Transcripts")
        XCTAssertTrue(app.tabBars.buttons["Transcripts"].exists)
    }

    func testTapsSourcesAndEspansoSwitchOffWithTheirOptions() {
        open("Your Taps")
        XCTAssertTrue(app.switches["Show Your Taps"].waitForExistence(timeout: 5))
        flip("Learn My Taps")
        XCTAssertFalse(app.switches["Show Your Taps"].exists)
        XCTAssertFalse(app.tabBars.buttons["Your Taps"].exists)
        flip("Learn My Taps")
        XCTAssertTrue(app.tabBars.buttons["Your Taps"].waitForExistence(timeout: 2))
        back()

        open("Sources")
        XCTAssertTrue(app.cells.staticTexts["Add Source…"].waitForExistence(timeout: 5))
        flip("Sources")
        XCTAssertFalse(app.cells.staticTexts["Add Source…"].exists)
        flip("Sources")
        back()

        open("Espanso Snippets")
        XCTAssertTrue(app.switches["Expand While Typing"].waitForExistence(timeout: 5))
        flip("Espanso Snippets")
        XCTAssertFalse(app.switches["Expand While Typing"].exists)
        flip("Espanso Snippets")
        XCTAssertTrue(app.switches["Expand While Typing"].waitForExistence(timeout: 5))
    }
}
