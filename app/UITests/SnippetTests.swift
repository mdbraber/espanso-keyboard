import XCTest

/// Espanso snippets through the real keyboard (espanso-keyboard, plan steps 4 and 5). See `EspansoTestCase`.
final class SnippetTests: EspansoTestCase {
    func testTodayExpandsToTheDate() {
        type(";today")
        // Local time, as Espanso's date variable uses (the ISO 8601 style would be UTC).
        let today = Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
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
        XCTAssertTrue(app.staticTexts["ui-espanso"].exists, "the folder’s name")
        XCTAssertTrue(app.cells.staticTexts["base.yml"].exists, "the match files are listed")

        let search = app.searchFields["Search Snippets"].firstMatch
        if !search.exists { app.swipeDown() }  // The search field shows when the list is pulled down.
        search.tap()
        search.typeText("koffie")
        XCTAssertTrue(app.staticTexts[";café"].waitForExistence(timeout: 5), "searching finds a snippet by its text")
        XCTAssertFalse(app.staticTexts[";today"].exists, "and hides the others")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }
}
