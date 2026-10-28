import XCTest

final class TypingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES"]
        app.launch()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
    }

    private var field: XCUIElement { app.textViews.firstMatch }

    private func tap(_ name: String) {
        key(name).tap()
    }

    private func type(_ text: String) {
        for character in text {
            tap(character == " " ? "space" : String(character))
        }
    }

    func testTypesSentenceWithAutocapAndDoubleSpacePeriod() {
        type("hello world  next")
        XCTAssertEqual(field.value as? String, "Hello world. Next")
    }

    func testDeleteAndNumbers() {
        type("ab")
        tap("delete")
        tap("numbers")
        tap("4")
        tap("2")
        tap("space")
        type("go")
        XCTAssertEqual(field.value as? String, "A42 go")
    }

    func testCapsLockWithDoubleTap() {
        key("shift").doubleTap()
        type("abc")
        XCTAssertEqual(field.value as? String, "ABC")
    }

    func testReturnStartsNewCapitalizedLine() {
        type("hi")
        tap("return")
        type("yo")
        XCTAssertEqual(field.value as? String, "Hi\nYo")
    }

    func testLongPressShowsAccents() {
        let e = key("e")
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1, thenDragTo: e.coordinate(withNormalizedOffset: CGVector(dx: -0.7, dy: -0.9)))
        XCTAssertEqual(field.value as? String, "É")
    }

    func testSlidingFromNumbersTypesAndComesBack() {
        let numbers = key("numbers")
        let target = key("q").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        numbers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2, thenDragTo: target)
        type("a")
        XCTAssertEqual(field.value as? String, "1a")
    }

    func testSpaceBarMovesCursor() {
        type("abc")
        let space = key("space").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        space.press(forDuration: 1, thenDragTo: space.withOffset(CGVector(dx: -20, dy: 0)))
        type("x")
        XCTAssertEqual(field.value as? String, "Axbc")
    }

    func testHoldingDeleteSpeedsUpToWords() {
        let sentence = "the quick brown fox jumps over the lazy dog"
        type(sentence)
        key("delete").press(forDuration: 3)
        let remaining = (field.value as? String ?? "").count
        XCTAssertLessThanOrEqual(remaining, sentence.count - 20)
    }

    func testFlickDownTypesSecondaryOnPad() throws {
        try XCTSkipUnless(key("tab").exists, "Flicks are an iPad layout feature")
        let q = key("q").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        q.press(forDuration: 0.05, thenDragTo: q.withOffset(CGVector(dx: 0, dy: 30)))
        XCTAssertEqual(field.value as? String, "1")
    }

    func testSmartPunctuationCurlsApostrophes() {
        type("its")
        tap("delete")
        tap("numbers")
        tap("'")
        type("s")
        XCTAssertEqual(field.value as? String, "It’s")
    }

    private func key(_ name: String) -> XCUIElement {
        app.keys.matching(identifier: "hex.\(name)").firstMatch
    }
}
