import XCTest

/// Types through the real extension with synthesized HID touches at a fixed rate and checks every letter lands. The
/// simulator turns overlapping paths into one finger that slides between keys, so each finger lifts before the next
/// lands here; `TouchReplayTests` covers overlapping fingers.
final class FastTypingTests: XCTestCase {
    private var app: XCUIApplication!

    private static let passage = """
    noticing that some letters miss when typing very fast at least one letter per word testing should ensure it can \
    handle inputs of two hundred words per minute sustained but ideally should not even trip up with one thousand \
    how much processing is happening in between letters
    """

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexResetSettings", "YES"]
        app.launch()
        XCTAssertTrue(app.keys["hex.space"].waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
    }

    func test200WordsPerMinuteSustained() throws {
        try type(Self.passage, wordsPerMinute: 200, dwell: 0.04)
    }

    func test1000WordsPerMinute() throws {
        try type(Self.passage, wordsPerMinute: 1000, dwell: 0.006)
    }

    private func type(_ text: String, wordsPerMinute: Double, dwell: Double) throws {
        let centers = keyCenters(for: Set(text))
        let interval = 60 / (wordsPerMinute * 5)
        let before = value
        let record = XCSynthesizedEventRecord(name: "\(Int(wordsPerMinute)) wpm", interfaceOrientation: .portrait)
        for (index, character) in text.enumerated() {
            let down = 0.05 + Double(index) * interval
            let path = XCPointerEventPath(forTouchAt: centers[character]!, offset: down)
            path.liftUp(atOffset: down + dwell)
            record.add(path)
        }
        try record.synthesize()
        let typed = settled(), expected = before + Self.capitalizingFirst(text, after: before)
        XCTAssertEqual(typed, expected, Self.difference(typed, expected))
    }

    private func keyCenters(for characters: Set<Character>) -> [Character: CGPoint] {
        Dictionary(uniqueKeysWithValues: characters.map { character in
            let key = app.keys["hex.\(character == " " ? "space" : String(character))"]
            XCTAssertTrue(key.exists, "no key for \(character)")
            return (character, CGPoint(x: key.frame.midX, y: key.frame.midY))
        })
    }

    private var value: String { app.textViews.firstMatch.value as? String ?? "" }

    private func settled() -> String {
        var last = value
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = value
            if now == last { return now }
            last = now
        }
        return last
    }

    private static func capitalizingFirst(_ text: String, after before: String) -> String {
        guard before.isEmpty, let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func difference(_ typed: String, _ expected: String) -> String {
        let a = typed.split(separator: " "), b = expected.split(separator: " ")
        let wrong = zip(a, b).filter { $0 != $1 }.map { "\($1)→\($0)" }
        return "\(wrong.count) of \(b.count) words differ (\(a.count) typed): \(wrong.prefix(20).joined(separator: ", "))"
    }
}
