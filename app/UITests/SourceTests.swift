import XCTest

/// A source through the real keyboard, against `scripts/source.py` (it hints at any text with "hate" in it), added
/// through a source's link the way a real one is.
final class SourceTests: XCTestCase {
    func testASourceSeesWhatYouTypeAndItsHintStandsInForTheSuggestions() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let source = environment["HEX_SOURCE"], let shots = environment["HEX_SHOTS"] else {
            throw XCTSkip("Run through scripts/sourcetest")
        }
        continueAfterFailure = false
        try allowFullAccess()

        let linked = XCUIApplication()
        var link = URLComponents(string: "hexkeyboard://source")!
        link.queryItems = [URLQueryItem(name: "name", value: "Test"), URLQueryItem(name: "url", value: source)]
        linked.open(link.url!)
        let add = linked.alerts.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the link asks before adding the source")
        try shot("\(shots)-offer")
        add.tap()
        linked.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
        type("i hate", in: app)
        let hint = app.descendants(matching: .any).matching(identifier: "hex.notice").firstMatch
        XCTAssertTrue(wait { hint.exists && hint.label == "Careful" }, "the source's hint stands in for the suggestions")
        try shot("\(shots)-hint")

        hint.tap()
        XCTAssertTrue(wait { !hint.exists }, "tapping the hint hides it")
        type(" it", in: app)
        let suggestion = app.descendants(matching: .any).matching(identifier: "hex.suggestion.0").firstMatch
        XCTAssertTrue(wait { suggestion.exists && suggestion.isHittable }, "the suggestions are back")
        XCTAssertFalse(hint.exists, "the same hint stays hidden")
        try shot("\(shots)-dismissed")
    }

    private func type(_ text: String, in app: XCUIApplication) {
        for character in text { key(character == " " ? "space" : String(character), in: app).tap() }
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    private func shot(_ path: String) throws {
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path + ".png"))
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let hex = app.keys.matching(identifier: "hex.\(name)").firstMatch
        return hex.exists ? hex : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
