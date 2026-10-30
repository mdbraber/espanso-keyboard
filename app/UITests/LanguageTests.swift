import XCTest

/// Switching to Dutch from the layer key's menu (espanso-keyboard).
final class LanguageTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOneHanded", "off", "-HexLanguage", "en", "-HexOrientation", "portrait"]
        app.launch()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
    }

    override func tearDown() {
        app.terminate()
        app.launchArguments = ["-HexLanguage", "en"]
        app.launch()
    }

    private var field: XCUIElement { app.textViews.firstMatch }

    private func key(_ name: String) -> XCUIElement {
        app.keys.matching(identifier: "hex.\(name)").firstMatch
    }

    /// The menu holds ←, keyboard, →, EN, NL and EN-NL, 50 points each from x = 17.
    private func holdNumbersAndPick(atX x: CGFloat) {
        let numbers = key("numbers")
        let pick = numbers.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - numbers.frame.minX, dy: -35))
        numbers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1, thenDragTo: pick)
    }

    private func type(_ text: String) {
        for character in text { key(character == " " ? "space" : String(character)).tap() }
    }

    func testDutchFromTheMenuAddsAccentsAndEnglishComesBack() {
        holdNumbersAndPick(atX: 242)
        XCTAssertTrue(key("q").waitForExistence(timeout: 2), "picking a language brings the letters back")
        type("goede ideeen ")
        XCTAssertEqual(field.value as? String, "Goede ideeën ")

        holdNumbersAndPick(atX: 192)
        XCTAssertTrue(key("q").waitForExistence(timeout: 2))
        type("teh ")
        XCTAssertEqual(field.value as? String, "Goede ideeën the ")
    }

    func testBothLanguagesFromTheMenuFollowWhatYouWrite() {
        holdNumbersAndPick(atX: 292)
        XCTAssertTrue(key("q").waitForExistence(timeout: 2))
        type("ik heb goede ideeen ")
        XCTAssertEqual(field.value as? String, "Ik heb goede ideeën ")
        type("and i think teh ")
        XCTAssertEqual(field.value as? String, "Ik heb goede ideeën and I think the ")
    }
}
