import XCTest

final class SettingsAppTests: XCTestCase {
    func testSettingsAppSharesSwitchesWithHex() throws {
        let hex = XCUIApplication()
        hex.launchArguments = ["-HexResetSettings", "YES", "-HexSettings", "YES"]
        hex.launch()
        let inHex = hex.switches["Character Preview"]
        XCTAssertTrue(inHex.waitForExistence(timeout: 5))
        XCTAssertEqual(inHex.value as? String, "1")
        hex.terminate()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let back = settings.buttons.matching(identifier: "BackButton").firstMatch
        while back.waitForExistence(timeout: 2) { back.tap() }
        let apps = settings.buttons["Apps"].firstMatch
        while !apps.isHittable { settings.swipeUp() }
        apps.tap()
        let entry = settings.buttons["Hex"].firstMatch
        while !entry.isHittable { settings.swipeUp() }
        entry.tap()
        let inSettings = settings.switches["Character Preview"]
        XCTAssertTrue(inSettings.waitForExistence(timeout: 5))
        if let path = ProcessInfo.processInfo.environment["HEX_SETTINGS_SHOT"] {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
        inSettings.switches.firstMatch.tap()
        XCTAssertEqual(inSettings.value as? String, "0")
        settings.terminate()

        hex.launchArguments = ["-HexSettings", "YES"]
        hex.launch()
        XCTAssertTrue(inHex.waitForExistence(timeout: 5))
        XCTAssertEqual(inHex.value as? String, "0")
    }

    func testKeepMicOnIsPickedInHexAndShownInSettings() throws {
        let hex = XCUIApplication()
        hex.launchArguments = ["-HexResetSettings", "YES", "-HexSettings", "YES"]
        hex.launch()
        let row = hex.cells.containing(.staticText, identifier: "Keep Mic On").firstMatch
        while !row.isHittable { hex.swipeUp() }
        XCTAssertTrue(row.staticTexts["5 Minutes"].exists)
        try shot(hex, "keep-mic-on-row")
        row.tap()
        XCTAssertTrue(hex.navigationBars["Keep Mic On"].waitForExistence(timeout: 5))
        hex.staticTexts["1 Minute"].tap()
        XCTAssertTrue(hex.cells.containing(.staticText, identifier: "1 Minute").firstMatch.isSelected)
        try shot(hex, "keep-mic-on-choices")
        hex.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.staticTexts["1 Minute"].waitForExistence(timeout: 5))
        hex.terminate()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let back = settings.buttons.matching(identifier: "BackButton").firstMatch
        while back.waitForExistence(timeout: 2) { back.tap() }
        let apps = settings.buttons["Apps"].firstMatch
        while !apps.isHittable { settings.swipeUp() }
        apps.tap()
        let entry = settings.buttons["Hex"].firstMatch
        while !entry.isHittable { settings.swipeUp() }
        entry.tap()
        XCTAssertTrue(settings.switches["Character Preview"].waitForExistence(timeout: 5))
        let inSettings = settings.staticTexts["Keep Mic On"]
        while !inSettings.isHittable { settings.swipeUp() }
        XCTAssertTrue(settings.descendants(matching: .any).matching(NSPredicate(format: "label == '1 Minute' OR value == '1 Minute'")).firstMatch.exists)
        try shot(settings, "keep-mic-on-settings")
        settings.terminate()
    }

    private func shot(_ app: XCUIApplication, _ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["HEX_SHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }
}
