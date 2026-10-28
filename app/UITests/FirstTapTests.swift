import XCTest

/// Single taps through the real extension, the way a finger lands: right after the keyboard opens, and anywhere on a
/// key's share of the keyboard, gaps between keys included.
final class FirstTapTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexResetSettings", "YES"]
    }

    func testFirstTapAfterTheKeyboardOpensTypes() throws {
        for attempt in 0..<4 {
            app.launch()
            let key = app.keys["hex.q"]
            XCTAssertTrue(key.waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
            try tap(at: CGPoint(x: key.frame.midX, y: key.frame.midY))
            XCTAssertEqual(settled(), "Q", "attempt \(attempt)")
            app.terminate()
        }
    }

    func testTapsBetweenKeysType() throws {
        app.launch()
        let q = app.keys["hex.q"], w = app.keys["hex.w"], a = app.keys["hex.a"], b = app.keys["hex.b"], space = app.keys["hex.space"]
        XCTAssertTrue(q.waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
        let points = [
            ("between q and w", CGPoint(x: (q.frame.maxX + w.frame.minX) / 2, y: q.frame.midY)),
            ("just above q", CGPoint(x: q.frame.midX, y: q.frame.minY - 3)),
            ("between q and a", CGPoint(x: a.frame.midX, y: (q.frame.maxY + a.frame.minY) / 2)),
            ("between b and space", CGPoint(x: b.frame.midX, y: (b.frame.maxY + space.frame.minY) / 2)),
        ]
        for (name, point) in points {
            let before = settled().count
            try tap(at: point)
            XCTAssertEqual(settled().count, before + 1, "a tap \(name) typed nothing")
        }
    }

    private func tap(at point: CGPoint) throws {
        let record = XCSynthesizedEventRecord(name: "tap", interfaceOrientation: .portrait)
        let path = XCPointerEventPath(forTouchAt: point, offset: 0)
        path.liftUp(atOffset: 0.06)
        record.add(path)
        try record.synthesize()
    }

    private var value: String { app.textViews.firstMatch.value as? String ?? "" }

    private func settled() -> String {
        var last = value
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = value
            if now == last { return now }
            last = now
        }
        return last
    }
}
