import XCTest

/// Plan step 6 through the real keyboard and app (espanso-keyboard): suggestions, the snippet panel, questions, the
/// on/off switch, favourites, usage counts, copying, and adding and editing snippets. See `EspansoTestCase`.
final class FeatureTests: EspansoTestCase {
    // MARK: Keyboard

    func testTheSuggestionBarCompletesATrigger() {
        type(";ji")
        let suggestion = app.descendants(matching: .any).matching(NSPredicate(format: "label == ';jitsi'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "the bar offers ;jitsi")
        suggestion.tap()
        wait("the snippet replaced what was typed") { self.text.hasPrefix("https://meet.jit.si/mdb-") }
    }

    func testTheSnippetPanelSearchesWithTheKeysAndInserts() {
        app.buttons["hex.snippets"].tap()
        XCTAssertTrue(app.otherElements["espanso.snippets"].waitForExistence(timeout: 5), "the panel opens")
        type("koffie")
        XCTAssertEqual(text, "", "the keys type into the panel, not the field")
        tap("return")
        wait("return inserts the best match") { self.text == "koffie" }
        XCTAssertFalse(app.otherElements["espanso.snippets"].exists, "and closes the panel")
    }

    func testAChoiceAsksInAPanel() {
        type(";pick")
        let peer = app.cells["espanso.choice.peer"]
        XCTAssertTrue(peer.waitForExistence(timeout: 5), "the choices show")
        peer.tap()
        wait("the answer expands the snippet") { self.text == "peer" }
    }

    func testAFormAsksForItsFields() {
        type(";form")
        XCTAssertTrue(app.otherElements["espanso.form"].waitForExistence(timeout: 5), "the form shows")
        type("anna")
        app.buttons["espanso.insert"].tap()
        wait("the answers fill the snippet") { self.text == "Hoi anna, tot morgen!" }
    }

    func testASnippetWinsOverATextReplacement() throws {
        try addTextReplacement(shortcut: "brb", phrase: "BRB from Text Replacement")
        app.launch()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10))
        type("ok brb ")
        XCTAssertEqual(text, "Ok be right back ")
    }

    /// Adds a Text Replacement in Settings › General › Keyboard, as Hex's `SuggestionTests` do.
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

    // MARK: App

    /// Opens Keyboard Settings › Espanso Snippets.
    private func openEspanso() {
        app.cells.staticTexts["Keyboard Settings"].firstMatch.tap()
        let espanso = app.cells.staticTexts["Espanso Snippets"].firstMatch
        XCTAssertTrue(espanso.waitForExistence(timeout: 5))
        espanso.tap()
    }

    /// Back to Hex's home screen and its Try It field.
    private func backToTryIt() {
        app.tabBars.buttons["Hex"].tap()
        app.tabBars.buttons["Hex"].tap()
        app.textViews.firstMatch.tap()
        XCTAssertTrue(key("space").waitForExistence(timeout: 5))
        onNumbers = false
    }

    /// Opens a match file's page, then one of its snippets.
    private func openSnippet(_ trigger: String, in file: String = "base.yml") {
        openFile(file)
        let row = app.cells.staticTexts[trigger].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(trigger) is listed")
        // The keyboard may still cover the lower rows.
        for _ in 0..<4 where !row.isHittable { app.tables.firstMatch.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars[trigger].waitForExistence(timeout: 5), "\(trigger) opens")
    }

    private func openFile(_ file: String) {
        let row = app.cells.staticTexts[file].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(file) is listed")
        for _ in 0..<4 where !row.isHittable { app.tables.firstMatch.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars[file].waitForExistence(timeout: 5), "\(file) opens")
    }

    func testExpandingCanBeTurnedOff() {
        openEspanso()
        app.switches["Expand Snippets"].tap()
        backToTryIt()
        type(";hi")
        XCTAssertEqual(text, ";hi")
    }

    func testTheListGroupsByFileAndCountsUse() {
        type(";hi")
        XCTAssertEqual(text, "Hoi daar")
        openEspanso()
        XCTAssertFalse(app.cells.staticTexts[";hi"].exists, "the main screen lists files, not snippets")
        openFile("base.yml")
        XCTAssertTrue(app.cells.staticTexts[";today"].exists, "the file's page lists its snippets")
        let used = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'used 1×'")).firstMatch
        XCTAssertTrue(used.waitForExistence(timeout: 5), "the keyboard counted the expansion")
    }

    func testTheDetailScreenPreviewsAndCopies() {
        openEspanso()
        openSnippet(";dear")
        XCTAssertTrue(app.staticTexts["Dear ,"].exists, "the preview leaves out the cursor marker")
        app.cells.staticTexts["Copy Result"].tap()
        XCTAssertTrue(app.cells.staticTexts["Copied"].waitForExistence(timeout: 5))
    }

    func testAFavouriteComesFirstInThePanel() {
        openEspanso()
        openSnippet(";nest")
        app.switches["Favourite"].tap()
        backToTryIt()
        app.buttons["hex.snippets"].tap()
        let first = app.otherElements["espanso.snippets"].cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.identifier, "espanso.snippet.;nest")
    }

    func testANewSnippetIsSavedAndExpands() throws {
        openEspanso()
        app.buttons["Add Snippet"].tap()
        app.textFields["espanso.new.trigger"].tap()
        type(";nieuw")
        let replace = app.textViews["espanso.new.replace"]
        replace.tap()
        onNumbers = false
        type("nieuw snippet")
        let typed = try XCTUnwrap(replace.value as? String)
        XCTAssertEqual(typed.lowercased(), "nieuw snippet")
        app.buttons["Save"].tap()
        openSnippetAfterSave(";nieuw")

        let file = try String(contentsOf: Self.scratch.appending(path: "match/iphone.yml"), encoding: .utf8)
        XCTAssertEqual(file, "matches:\n  - trigger: \";nieuw\"\n    replace: \"\(typed)\"\n")
        backToTryIt()
        type(";nieuw")
        XCTAssertEqual(text, typed)
    }

    /// After saving, the new file is listed with the snippet on its page.
    private func openSnippetAfterSave(_ trigger: String) {
        XCTAssertTrue(app.cells.staticTexts["iphone.yml"].waitForExistence(timeout: 10), "iphone.yml is listed")
        openFile("iphone.yml")
        XCTAssertTrue(app.cells.staticTexts[trigger].waitForExistence(timeout: 5), "the new snippet is on its page")
    }

    func testEditingSavesOnlyThatSnippet() throws {
        let file = Self.scratch.appending(path: "match/base.yml")
        let before = try String(contentsOf: file, encoding: .utf8)
        openEspanso()
        openSnippet(";hi")
        let edit = app.cells.staticTexts["Edit Snippet"]
        for _ in 0..<4 where !edit.isHittable { app.tables.firstMatch.swipeUp() }
        edit.tap()
        let yaml = app.textViews["espanso.yaml"]
        XCTAssertTrue(yaml.waitForExistence(timeout: 5))
        XCTAssertEqual(yaml.value as? String, "  - trigger: \";hi\"\n    replace: \"{{greeting}} daar\"")
        app.buttons["Save"].tap()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 3), "saving it unchanged succeeds")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), before, "and leaves the file as it was")
    }
}
