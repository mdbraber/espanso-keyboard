import XCTest

/// Espanso snippets through the real keyboard (espanso-keyboard, plan step 4), with the test snippets from
/// fixtures/espanso/ bundled in the keyboard. Run through scripts/test-keyboard.sh, which makes Hex the active keyboard.
final class SnippetTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait"]
        app.launch()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
    }

    private var text: String { app.textViews.firstMatch.value as? String ?? "" }

    func testTodayExpandsToTheDate() {
        type(";today")
        let today = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        XCTAssertEqual(text, today)
    }

    func testJitsiRunsItsScript() {
        type(";jitsi")
        let prefix = "https://meet.jit.si/mdb-"
        XCTAssertTrue(text.hasPrefix(prefix), text)
        XCTAssertEqual(text.count, prefix.count + 10, text)
    }

    func testBackspaceRightAfterAnExpansionUndoesIt() {
        type(";hi")
        XCTAssertEqual(text, "Hoi daar")
        tap("delete")
        XCTAssertEqual(text, ";hi")
    }

    func testCursorHintPutsTheCaretInside() {
        type(";dear")
        type("x")
        XCTAssertEqual(text, "Dear x,")
    }

    func testWordTriggerExpandsAfterASpace() {
        type("ok brb ")
        XCTAssertEqual(text, "Ok be right back ")
    }

    func testOrdinaryTypingIsUnchanged() {
        type("hello world  next")
        XCTAssertEqual(text, "Hello world. Next")
    }

    // MARK: Typing

    private var onNumbers = false

    /// Taps each character's key, switching between the letters and numbers layers as needed.
    private func type(_ string: String) {
        for character in string {
            let name = character == " " ? "space" : String(character)
            let needsNumbers = !(character.isLetter || character == " ")
            if needsNumbers != onNumbers {
                tap(needsNumbers ? "numbers" : "letters")
                onNumbers = needsNumbers
            }
            tap(name)
            if character == " " { onNumbers = false }  // Space returns to letters.
        }
    }

    private func tap(_ name: String) {
        let key = key(name)
        XCTAssertTrue(key.waitForExistence(timeout: 5), "no \(name) key")
        key.tap()
    }

    private func key(_ name: String) -> XCUIElement {
        let hex = app.keys.matching(identifier: "hex.\(name)").firstMatch
        return hex.exists ? hex : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
