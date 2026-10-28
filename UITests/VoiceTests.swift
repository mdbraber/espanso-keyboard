import XCTest

/// The bar's mic against a stand-in for the app (`scripts/voicetest` holds the microphone lock and answers the
/// keyboard's signals the way `Listener` does), since a simulator can't record for the real one.
final class VoiceTests: XCTestCase {
    func testTheBarsMicStartsStopsAndTurnsOffDictationInPlace() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let shots = environment["HEX_SHOTS"] else { throw XCTSkip("Run through scripts/voicetest") }
        continueAfterFailure = false
        try allowFullAccess()

        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait", "-HexOneHanded", "off"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
        for letter in "pizza" { key(String(letter), in: app).tap() }

        let mic = app.buttons["hex.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5), "the mic is always beside the suggestions")
        XCTAssertTrue(wait(for: mic, label: "Dictate", value: "Mic On"), "it says when the app keeps the microphone on")
        let emoji = app.keys.matching(identifier: "hex.suggestion.emoji.0").firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 3), "the word's emoji sit beside the mic")
        XCTAssertLessThan(emoji.frame.maxX, mic.frame.minX + 1)
        try shot("\(shots)-on")

        mic.tap()
        XCTAssertTrue(wait(for: mic, label: "Stop Dictating", value: nil), "tapping the mic starts listening without opening the app")
        Thread.sleep(forTimeInterval: 3)
        try shot("\(shots)-listening")

        mic.tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(wait { (field.value as? String ?? "").hasSuffix("hello from the mic") }, "tapping it again types what was heard")
        XCTAssertTrue(wait(for: mic, label: "Dictate", value: "Mic On"))
        try shot("\(shots)-typed")

        mic.press(forDuration: 0.8)
        XCTAssertTrue(wait(for: mic, label: "Dictate", value: nil), "holding the mic turns the microphone off and leaves the mic in place")
        try shot("\(shots)-off")
    }

    private func wait(for element: XCUIElement, label: String, value: String?) -> Bool {
        wait { element.exists && element.label == label && (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } == value }
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
