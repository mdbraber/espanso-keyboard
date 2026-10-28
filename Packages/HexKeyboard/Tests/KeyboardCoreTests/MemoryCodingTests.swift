import Foundation
import Testing
@testable import KeyboardCore

struct MemoryCodingTests {
    @Test func memorySavedBeforeRecentTapsStillLoads() throws {
        var memory = TypingMemory()
        memory.touches.learn([TapSample(tap: Tap(x: 7.6, y: 2.5, key: "m"), intended: "m")], on: .standard)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(memory)) as? [String: Any])
        var touches = try #require(json["touches"] as? [String: Any])
        #expect(touches["recent"] != nil)
        touches["recent"] = nil
        json["touches"] = touches
        let loaded = try JSONDecoder().decode(TypingMemory.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(loaded.touches.taps(for: "m", on: .standard) == 1)
        #expect(loaded.touches.aims(on: .standard).first { $0.key.label == "m" }?.recent.isEmpty == true)
    }

    @Test func keysSavedBeforeTheyRememberedRecentAimStillLoad() throws {
        var memory = TypingMemory()
        memory.touches.learn((0..<40).map { _ in TapSample(tap: Tap(x: 7.3, y: 2.5, key: "m"), intended: "m") }, on: .standard)
        let center = memory.touches.center(of: "m", on: .standard)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(memory)) as? [String: Any])
        var touches = try #require(json["touches"] as? [String: Any])
        var layouts = try #require(touches["layouts"] as? [String: [String: [String: Any]]])
        let m = try #require(layouts["standard"]?["m"])
        #expect(m["now"] != nil)
        layouts["standard"]?["m"] = m["all"] as? [String: Any]
        touches["layouts"] = layouts
        json["touches"] = touches
        let loaded = try JSONDecoder().decode(TypingMemory.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(loaded.touches.taps(for: "m", on: .standard) == 40)
        let loadedCenter = loaded.touches.center(of: "m", on: .standard)
        #expect(abs(loadedCenter.x - center.x) < 0.01 && abs(loadedCenter.y - center.y) < 0.01)
    }
}
