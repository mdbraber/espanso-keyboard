import Foundation

/// Fuzzy search for snippets (espanso-keyboard, plan step 6): `jts` finds `;jitsi`.
nonisolated enum Fuzzy {
    /// How well `query` matches `text`, or nil when its characters don't all appear in `text` in order. Case and accents
    /// don't matter. Higher is better: the text containing the query whole, matches at the start or at the start of a
    /// word, and characters next to each other count more.
    static func score(_ query: String, in text: String) -> Int? {
        let query = Array(fold(query).filter { !$0.isWhitespace })
        let text = Array(fold(text))
        guard !query.isEmpty else { return 0 }
        var score = 0
        var index = 0
        var previous = -2
        for character in query {
            guard let found = text[index...].firstIndex(of: character) else { return nil }
            score += 1
            if found == previous + 1 { score += 4 }
            if found == 0 { score += 6 } else if !text[found - 1].isLetter && !text[found - 1].isNumber { score += 3 }
            previous = found
            index = found + 1
        }
        if fold(text.map(String.init).joined()).contains(fold(query.map(String.init).joined())) { score += 20 }
        return score - text.count / 8
    }

    /// The best score of `query` in any of `texts`.
    static func score(_ query: String, in texts: [String]) -> Int? {
        texts.compactMap { score(query, in: $0) }.max()
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
