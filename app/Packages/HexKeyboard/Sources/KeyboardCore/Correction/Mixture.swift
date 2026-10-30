/// The languages a corrector knows, each with its word list, next words and a weight: how much the words before the
/// caret say you're writing in it. With one language everything goes straight to its lexicon and phrases, so a
/// one-language corrector ranks exactly as before. With two, P(word) = Σ weight × P(word | language), the way Apple's
/// multilingual keyboards lean toward the language you're typing (espanso-keyboard).
public struct Mixture: Sendable {
    public struct Part: Sendable {
        public let lexicon: Lexicon
        public let phrases: Phrases?
        public internal(set) var weight: Double

        public init(lexicon: Lexicon, phrases: Phrases?, weight: Double = 1) {
            self.lexicon = lexicon
            self.phrases = phrases
            self.weight = weight
        }
    }

    public private(set) var parts: [Part]

    /// How many words before the caret decide the weights, and how much less each earlier one counts.
    static let window = 12
    static let decay = 0.8
    /// Every language keeps at least this share, so a sentence can switch.
    static let floor = 0.05
    /// P(word) for a word a language doesn't have, when telling languages apart.
    static let unknownLogProbability = Math.log(1e-7)

    public init(_ parts: [Part]) {
        let total = parts.reduce(0) { $0 + $1.weight }
        self.parts = parts.map { var part = $0; part.weight = parts.count == 1 ? 1 : $0.weight / total; return part }
    }

    var isMixed: Bool { parts.count > 1 }

    func isWord(_ word: some StringProtocol) -> Bool {
        parts.contains { $0.lexicon.logProbability(of: word) != nil }
    }

    /// Σ weight × P(word | language), nil when no language has the word.
    func logProbability(of word: some StringProtocol) -> Double? {
        guard isMixed else { return parts[0].lexicon.logProbability(of: word) }
        var p = 0.0, known = false
        for part in parts {
            guard let logP = part.lexicon.logProbability(of: word) else { continue }
            known = true
            p += part.weight * Math.exp(logP)
        }
        return known ? Math.log(p) : nil
    }

    /// The spelling of the language that most likely means the word.
    func canonical(_ word: some StringProtocol) -> String? {
        guard isMixed else { return parts[0].lexicon.canonical(word) }
        let best = parts.compactMap { part in part.lexicon.logProbability(of: word).map { (part, Math.log(part.weight) + $0) } }
            .max { $0.1 < $1.1 }
        return best?.0.lexicon.canonical(word)
    }

    func mostFrequent(count: Int) -> [String] {
        guard isMixed else { return parts[0].lexicon.mostFrequent(count: count) }
        let scored = parts.flatMap { part in
            part.lexicon.mostFrequent(count: count).map { ($0, part.weight * Math.exp(part.lexicon.logProbability(of: $0) ?? -.infinity)) }
        }
        var seen: Set<String> = []
        return scored.sorted { $0.1 > $1.1 }.map(\.0).filter { seen.insert($0.lowercased()).inserted }.prefix(count).map { $0 }
    }

    /// The next words the corpora write most often, the likelier language first.
    func next(after previous: String?, earlier: String?) -> [String] {
        parts.sorted { $0.weight > $1.weight }.flatMap { part in
            (part.phrases?.next(after: previous, earlier: earlier) ?? []).map { part.lexicon.canonical($0) ?? $0 }
        }
    }

    func phraseProbability(of word: String, after previous: String?, earlier: String?, below: Double) -> Double {
        guard isMixed else { return parts[0].phrases?.probability(of: word, after: previous, earlier: earlier, below: below) ?? below }
        return parts.reduce(0) { total, part in
            total + part.weight * (part.phrases?.probability(of: word, after: previous, earlier: earlier, below: below) ?? below)
        }
    }

    var hasPhrases: Bool { parts.contains { $0.phrases != nil } }

    /// Σ weight × the probability mass of words starting with `prefix`, for the key map.
    func mass(startingWith prefix: some StringProtocol) -> Double {
        parts.reduce(0) { total, part in
            total + (part.lexicon.node(for: prefix).map { part.weight * Math.exp(part.lexicon.logMass($0)) } ?? 0)
        }
    }

    /// Σ weight × P(word ends here), for the key map's space.
    func ending(_ prefix: some StringProtocol) -> Double {
        parts.reduce(0) { total, part in
            total + (part.lexicon.node(for: prefix).flatMap(part.lexicon.logWord).map { part.weight * Math.exp($0) } ?? 0)
        }
    }

    /// Weighs the languages by the words before the caret (oldest first): each language's evidence is the sum of
    /// log P(word | language) over the last `window` words, the later ones counting more. Without words the weights
    /// stay as they are.
    mutating func weigh(by words: [String]) {
        guard isMixed else { return }
        let recent = words.suffix(Self.window).reversed()
        guard !recent.isEmpty else { return }
        let evidence = parts.map { part in
            recent.enumerated().reduce(0.0) { total, item in
                total + Math.exp(Math.log(Self.decay) * Double(item.offset)) * (part.lexicon.logProbability(of: item.element) ?? Self.unknownLogProbability)
            }
        }
        let top = evidence.max() ?? 0
        let raw = evidence.map { Math.exp($0 - top) }
        let total = raw.reduce(0, +)
        let share = 1 - Self.floor * Double(parts.count)
        for index in parts.indices { parts[index].weight = Self.floor + share * raw[index] / total }
    }
}
