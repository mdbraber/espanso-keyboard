import Foundation
import KeyboardCore
import notify

/// Keeps what the keyboard learns in the extension's own container, since without Full Access it can't write to the
/// App Group. The app resets it by sharing a new reset token through `SettingsStore`; the keyboard starts over when the
/// token it sees differs from the one its memory was saved under.
/// With Full Access the keyboard also shares its touch model through the group, for the app to show.
public enum MemoryStore {
    private struct Saved: Codable {
        var resets: Int
        var memory: TypingMemory
    }

    private static let resetsKey = "memoryResets"
    private static let touchesChanged = "com.shahidy.hexkeyboard.touches"

    /// English keeps Hex's file; each other language has its own (espanso-keyboard).
    private static func url(_ language: Language) -> URL {
        URL.applicationSupportDirectory.appending(path: language == .english ? "typing-memory.json" : "typing-memory-\(language.rawValue).json")
    }

    private static var sharedTouchesURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)?.appending(path: "touches.json")
    }

    private static var resets: Int? { SettingsStore.value(forKey: resetsKey, sharing: false) as? Int }

    /// The words learned in `language`, with where your taps land from whichever language was saved last: the
    /// keys are the same in every language (espanso-keyboard).
    static func load(_ language: Language = .english) -> TypingMemory {
        var memory = saved(language) ?? TypingMemory()
        let latest = Language.allCases.max { modified($0) < modified($1) }
        if let latest, latest != language, let touches = saved(latest)?.touches { memory.touches = touches }
        return memory
    }

    private static func saved(_ language: Language) -> TypingMemory? {
        guard let saved = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: url(language))), saved.resets == resets ?? saved.resets else { return nil }
        return saved.memory
    }

    private static func modified(_ language: Language) -> Date {
        (try? url(language).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    static func save(_ memory: TypingMemory, language: Language = .english, sharing: Bool) {
        let url = url(language)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Saved(resets: resets ?? 0, memory: memory)).write(to: url, options: .atomic)
        guard sharing, let sharedTouchesURL, (try? JSONEncoder().encode(memory.touches).write(to: sharedTouchesURL, options: .atomic)) != nil else { return }
        notify_post(touchesChanged)
    }

    private static var emojiURL: URL {
        URL.applicationSupportDirectory.appending(path: "emoji-history.json")
    }

    static func loadEmoji() -> EmojiHistory {
        (try? JSONDecoder().decode(EmojiHistory.self, from: Data(contentsOf: emojiURL))) ?? EmojiHistory()
    }

    static func save(_ emoji: EmojiHistory) {
        try? FileManager.default.createDirectory(at: emojiURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(emoji).write(to: emojiURL, options: .atomic)
    }

    public static func reset() {
        SettingsStore.set(Int.random(in: 1 ... .max), forKey: resetsKey)
        if let sharedTouchesURL { try? FileManager.default.removeItem(at: sharedTouchesURL) }
        notify_post(touchesChanged)
    }

    /// Deletes the touches the keyboard shared, when Your Taps is switched off (espanso-keyboard).
    public static func removeSharedTouches() {
        if let sharedTouchesURL { try? FileManager.default.removeItem(at: sharedTouchesURL) }
        notify_post(touchesChanged)
    }

    /// Where your taps land, as the keyboard last shared it.
    public static func sharedTouches() -> TouchModel? {
        sharedTouchesURL.flatMap { try? JSONDecoder().decode(TouchModel.self, from: Data(contentsOf: $0)) }
    }

    /// Calls `handler` on the main queue each time the keyboard shares new touches, until the token is cancelled.
    public static func observeTouches(_ handler: @escaping @MainActor @Sendable () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(touchesChanged, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return token
    }
}
