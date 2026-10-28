import XCTest

final class SuggestionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexResetSettings", "YES"]
    }

    private func launch() {
        app.launch()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
    }

    private var field: XCUIElement { app.textViews.firstMatch }
    private var text: String { field.value as? String ?? "" }

    func testAutocorrectsOnSpaceAndOffersRevertAfterDelete() {
        launch()
        type("helo")
        let correction = suggestion(1)
        XCTAssertEqual(suggestion(0).label, "Helo")
        XCTAssertNotEqual(correction.label, "")
        let corrected = correction.label
        tap("space")
        XCTAssertEqual(text, corrected + " ")
        tap("delete")
        XCTAssertEqual(text, corrected)
        XCTAssertEqual(suggestion(0).label, "Helo")
        suggestion(0).tap()
        XCTAssertEqual(text, "Helo ")
        type("helo ")
        XCTAssertEqual(text, "Helo helo ")
    }

    func testTappingASuggestionReplacesTheWord() {
        launch()
        type("hel")
        let choice = suggestion(2).label
        suggestion(2).tap()
        XCTAssertEqual(text, choice + " ")
    }

    func testExpandsTextReplacements() throws {
        try addTextReplacement(shortcut: "omw", phrase: "On my way!")
        launch()
        type("omw")
        XCTAssertEqual(suggestion(1).label, "On my way!")
        tap("space")
        XCTAssertEqual(text, "On my way! ")
    }

    func testAutoCorrectionSettingIsSharedWithTheKeyboard() {
        app.launchArguments += ["-HexSettings", "YES"]
        app.launch()
        let toggle = app.switches["Auto-Correction"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.navigationBars.buttons.firstMatch.tap()
        field.tap()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10))
        type("helo ")
        XCTAssertEqual(text, "Helo ")
    }

    private func addTextReplacement(shortcut: String, phrase: String) throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let back = settings.buttons.matching(identifier: "BackButton").firstMatch
        while back.waitForExistence(timeout: 2) { tapCenter(back) }
        tapCenter(settings.buttons["General"].firstMatch)
        tapCenter(settings.buttons["Keyboard"].firstMatch)
        tapCenter(settings.descendants(matching: .any).matching(identifier: "USER_DICTIONARY").firstMatch)
        if settings.staticTexts[shortcut].waitForExistence(timeout: 2) { return settings.terminate() }
        settings.buttons["Add"].firstMatch.tap()
        let fields = settings.textFields
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5))
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText(phrase)
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText(shortcut)
        settings.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(settings.staticTexts[shortcut].waitForExistence(timeout: 5))
        settings.terminate()
    }

    private func tapCenter(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func suggestion(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "hex.suggestion.\(index)").firstMatch
    }

    private func tap(_ name: String) {
        key(name).tap()
    }

    private func type(_ text: String) {
        for character in text {
            tap(character == " " ? "space" : String(character))
        }
    }

    private func key(_ name: String) -> XCUIElement {
        app.keys.matching(identifier: "hex.\(name)").firstMatch
    }
}
