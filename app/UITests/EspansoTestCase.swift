import XCTest

/// The keyboard with the test snippets (espanso-keyboard). Each test copies fixtures/espanso/ to build/ui-espanso/ and
/// launches Hex with `-EspansoImport` pointing there: Hex copies it into the app group, as it copies the owner's folder,
/// the keyboard loads that copy, and edits made in a test go to the scratch folder. Run through
/// scripts/test-keyboard.sh, which makes Hex the active keyboard.
class EspansoTestCase: XCTestCase {
    var app: XCUIApplication!

    /// The repository, from this file's place in it.
    static let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static let scratch = repository.appending(path: "build/ui-espanso")

    override func setUpWithError() throws {
        continueAfterFailure = false
        let files = FileManager.default
        try? files.removeItem(at: Self.scratch)
        try files.createDirectory(at: Self.scratch.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: Self.repository.appending(path: "fixtures/espanso"), to: Self.scratch)
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait", "-EspansoImport", Self.scratch.path]
        app.launch()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
    }

    var text: String { app.textViews.firstMatch.value as? String ?? "" }

    func wait(_ what: String, timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, what)
    }

    // MARK: Typing

    var onNumbers = false

    /// Taps each character's key, switching between the letters and numbers layers as needed.
    func type(_ string: String) {
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

    func tap(_ name: String) {
        let key = key(name)
        XCTAssertTrue(key.waitForExistence(timeout: 5), "no \(name) key")
        key.tap()
    }

    func key(_ name: String) -> XCUIElement {
        let hex = app.keys.matching(identifier: "hex.\(name)").firstMatch
        return hex.exists ? hex : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
