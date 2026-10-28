import XCTest

final class CaptureTests: XCTestCase {
    func testHoldKeysForScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HEX_CAPTURE"] != nil)
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait"]
        app.launch()
        let g = key("g", in: app)
        XCTAssertTrue(g.waitForExistence(timeout: 10))
        if ProcessInfo.processInfo.environment["HEX_CAPTURE"] == "menu" {
            let numbers = key("numbers", in: app)
            let top = numbers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -85))
            numbers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 4, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 4)
            return
        }
        guard ProcessInfo.processInfo.environment["HEX_CAPTURE"] == "bar" else {
            g.press(forDuration: 4)
            key("e", in: app).press(forDuration: 6)
            return
        }
        for letter in "hel" { key(String(letter), in: app).tap() }
        let q = key("q", in: app).frame, p = key("p", in: app).frame
        let window = app.windows.firstMatch.frame
        for x in [q.minX + 30, window.width / 2, p.maxX - 30] {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: q.minY - 26)).press(forDuration: 4)
            for letter in "hel" { key(String(letter), in: app).tap() }
        }
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let hex = app.keys.matching(identifier: "hex.\(name)").firstMatch
        return hex.exists ? hex : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
