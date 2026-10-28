/// The emoji each word finds, for the suggestion bar.
public struct EmojiCatalog: Sendable {
    private let byWord: [String: [String]]

    /// Reads the index (`emoji.txt`): each line is a word, a tab, and the emoji it finds, best first, or none.
    public init(text: String) {
        var byWord: [String: [String]] = [:]
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            byWord[String(line[..<tab])] = line[line.index(after: tab)...].split(separator: " ").map(String.init)
        }
        self.byWord = byWord
    }

    /// The emoji for a word typed in the text, for the suggestion bar: what the word finds, or else what its singular
    /// finds. A word the index gives no emoji ("with", "heard") finds none, even when its singular would.
    public func suggestions(for word: String, history: EmojiHistory, limit: Int = 3) -> [String] {
        let word = word.lowercased()
        guard word.count > 1 else { return [] }
        var forms = [word]
        if word.hasSuffix("s"), !word.hasSuffix("ss") {
            forms.append(String(word.dropLast()))
            let stem = word.dropLast(2)
            if word.hasSuffix("es"), ["s", "x", "z", "ch", "sh", "o"].contains(where: stem.hasSuffix) { forms.append(String(stem)) }
        }
        let found = forms.lazy.compactMap { byWord[$0] }.first ?? []
        return Array(ranked(found, history: history).prefix(limit))
    }

    /// Emoji you've used first, most used first, then everyone's order.
    private func ranked(_ shown: [String], history: EmojiHistory) -> [String] {
        let used = shown.compactMap { emoji in history.scores[emoji].map { (emoji, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        return used + shown.filter { history.scores[$0] == nil }
    }
}

/// The emoji you pick from the bar, which it offers first from then on. Each use counts for more than the ones before
/// it, so a new favorite climbs within a few uses while an old one fades only as you use others, never on a clock.
public struct EmojiHistory: Codable, Hashable, Sendable {
    public private(set) var scores: [String: Double] = [:]
    private var weight = 1.0

    static let growth = 1.1
    static let capacity = 60

    public init() {}

    public mutating func use(_ emoji: String) {
        scores[emoji, default: 0] += weight
        weight *= Self.growth
        if weight > 1e12 {
            scores = scores.mapValues { $0 / weight }
            weight = 1
        }
        if scores.count > Self.capacity, let least = scores.min(by: { $0.value < $1.value })?.key { scores[least] = nil }
    }
}
