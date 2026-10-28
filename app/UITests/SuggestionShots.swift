import XCTest

final class SuggestionShots: XCTestCase {
    func testTypeAndShoot() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let prefix = environment["HEX_SHOTS"] else { throw XCTSkip("Run through scripts/shots") }
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10))

        let steps = (environment["HEX_STEPS"].flatMap { $0.isEmpty ? nil : $0 } ?? "empty:|hel:hel|helo:o|helo-space: |delete:⌫|clear:⌫⌫⌫⌫⌫⌫|omw:omw|omw-space: ").split(separator: "|")
        for step in steps {
            let parts = step.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            for character in parts[1] {
                switch character {
                case " ": key("space", in: app).tap()
                case "⌫": key("delete", in: app).tap()
                default: key(String(character), in: app).tap()
                }
            }
            Thread.sleep(forTimeInterval: 1.2)
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try png.write(to: URL(fileURLWithPath: "\(prefix)-\(parts[0]).png"))
        }
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let hex = app.keys.matching(identifier: "hex.\(name)").firstMatch
        return hex.exists ? hex : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
