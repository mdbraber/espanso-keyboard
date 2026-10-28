/// What Hex has learned about you: the words you keep, what follows what, and where your thumbs land.
public struct TypingMemory: Codable, Hashable, Sendable {
    public private(set) var counts: [String: Int] = [:]
    public private(set) var kept: Set<String> = []
    public private(set) var following: [String: [String: Int]] = [:]
    public private(set) var total = 0
    public private(set) var spacesAfterSpace = 0
    public private(set) var keysAfterSpace = 0
    public var touches = TouchModel()

    static let capacity = 20_000

    public init() {}

    public mutating func record(_ word: String, after previous: String?) {
        counts[word, default: 0] += 1
        total += 1
        if let previous { following[previous, default: [:]][word, default: 0] += 1 }
        if counts.count > Self.capacity { forgetRarest() }
    }

    public mutating func forget(_ word: String, after previous: String?) {
        guard let count = counts[word] else { return }
        counts[word] = count > 1 ? count - 1 : nil
        total -= 1
        if let previous, let next = following[previous]?[word] { following[previous]?[word] = next > 1 ? next - 1 : nil }
    }

    /// Counts what you type right after a space, so a second space (the "." shortcut) is as likely as you make it.
    public mutating func recordAfterSpace(isSpace: Bool) {
        keysAfterSpace += 1
        if isSpace { spacesAfterSpace += 1 }
    }

    mutating func unrecordSpaceAfterSpace(keepingKey: Bool) {
        spacesAfterSpace -= 1
        if !keepingKey { keysAfterSpace -= 1 }
    }

    public mutating func keep(_ word: String) {
        kept.insert(word.lowercased())
    }

    public func isKept(_ word: String) -> Bool {
        kept.contains(word.lowercased())
    }

    func count(of word: String) -> Int {
        counts[word, default: 0] + (word.first?.isLowercase == true ? counts[word.prefix(1).uppercased() + word.dropFirst(), default: 0] : 0)
    }

    func count(of word: String, after previous: String) -> (count: Int, total: Int, types: Int) {
        guard let next = following[previous] else { return (0, 0, 0) }
        let capitalized = word.first?.isLowercase == true ? next[word.prefix(1).uppercased() + word.dropFirst(), default: 0] : 0
        return (next[word, default: 0] + capitalized, next.values.reduce(0, +), next.count)
    }

    func completions(for prefix: String) -> [String] {
        let lower = prefix.lowercased()
        return counts
            .filter { $0.key.count > prefix.count && $0.key.lowercased().hasPrefix(lower) && ($0.value > 1 || isKept($0.key)) }
            .sorted(by: Self.frequent)
            .map(\.key)
    }

    var familiar: some Sequence<String> {
        counts.lazy.filter { $0.value > 1 || self.isKept($0.key) }.map(\.key)
    }

    func predictions(after previous: String) -> [String] {
        (following[previous] ?? [:]).filter { $0.value > 1 }.sorted(by: Self.frequent).map(\.key)
    }

    private mutating func forgetRarest() {
        counts = counts.filter { $0.value > 1 || isKept($0.key) }
        total = counts.values.reduce(0, +)
        following = following.compactMapValues { next in
            let frequent = next.filter { $0.value > 1 }
            return frequent.isEmpty ? nil : frequent
        }
    }

    private static func frequent(_ a: (key: String, value: Int), _ b: (key: String, value: Int)) -> Bool {
        a.value != b.value ? a.value > b.value : a.key < b.key
    }
}
