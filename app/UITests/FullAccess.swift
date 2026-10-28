import XCTest

extension XCTestCase {
    /// Settings › General › Keyboard › Keyboards › Hex › Allow Full Access.
    func allowFullAccess() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        let rows = ["General", "Keyboard", "Keyboards"].map { settings.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", $0)).firstMatch }
        for row in rows + [settings.cells["com.shahidy.hexkeyboard.keyboard"]] {
            XCTAssertTrue(row.waitForExistence(timeout: 10), "Settings shows \(row)")
            var swipes = 0
            while !row.isHittable && swipes < 8 {
                settings.swipeUp()
                swipes += 1
            }
            row.tap()
        }
        let access = settings.switches["Allow Full Access"].firstMatch
        XCTAssertTrue(access.waitForExistence(timeout: 10))
        if access.value as? String != "1" {
            access.switches.firstMatch.tap()
            let allow = settings.alerts.buttons["Allow"].firstMatch
            if allow.waitForExistence(timeout: 5) { allow.tap() }
        }
        let on = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in access.value as? String == "1" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 10), .completed, "Full Access is on")
        settings.terminate()
    }
}
