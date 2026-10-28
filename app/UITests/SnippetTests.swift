import XCTest

/// Espanso snippets through the real keyboard (espanso-keyboard, plan steps 4 and 5). Hex copies the test snippets
/// in fixtures/espanso/ into the app group at launch (`-EspansoImport`), as it copies the owner's folder, and the
/// keyboard loads that copy. Run through scripts/test-keyboard.sh, which makes Hex the active keyboard.
final class SnippetTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait", "-EspansoImport", Self.fixture]
        app.launch()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
    }

    /// fixtures/espanso/, from this file's place in the repository.
    private static let fixture = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "fixtures/espanso").path

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

    func testRegexTriggerUsesItsNamedGroup() {
        type(";heyAnna!")
        XCTAssertEqual(text, "Hey Anna!")
    }

    func testOrdinaryTypingIsUnchanged() {
        type("hello world  next")
        XCTAssertEqual(text, "Hello world. Next")
    }

    func testTheEspansoScreenShowsTheCopy() throws {
        app.cells.staticTexts["Keyboard Settings"].firstMatch.tap()
        let espanso = app.cells.staticTexts["Espanso Snippets"].firstMatch
        XCTAssertTrue(espanso.waitForExistence(timeout: 5), "Keyboard Settings has an Espanso section")
        let sources = app.staticTexts["SOURCES"].firstMatch
        if sources.exists { XCTAssertLessThan(espanso.frame.minY, sources.frame.minY, "Espanso comes before Sources") }
        espanso.tap()
        let footer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'snippets, copied'")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 5), "the screen shows how many snippets were copied")
        XCTAssertTrue(app.staticTexts["espanso"].exists, "the folder's name")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
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
            if character.isUppercase {
                tap("shift")
                tap(name.lowercased())
            } else {
                tap(name)
            }
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
