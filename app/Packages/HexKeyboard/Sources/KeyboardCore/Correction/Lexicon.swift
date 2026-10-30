/// A word list with frequencies, stored as a flat trie in one byte array so it loads without parsing.
///
/// Layout: an 8-byte header (`HXL1`, node count) then 8 bytes per node, children of a node contiguous and in
/// order: letter, word log-probability, subtree log-mass, flags (last sibling, capitalized), first child index.
/// Probabilities are stored as `-ln p` in tenths of a nat (0 means "not a word").
///
/// Words are stored without accents, so taps decode over the same 27 letters in every language. A word spelled with
/// accents ("ideeën" at "ideeen") has the spelled flag, and its spelling sits in a table after the nodes: a u32 count,
/// then per word its node (u32) and the offset of its lowercase spelling (u32), sorted by node, then the spellings,
/// each ending in 0. Lexicons without accents (English) end after the nodes.
public final class Lexicon: Sendable {
    public let bytes: [UInt8]

    static let header: [UInt8] = Array("HXL1".utf8)
    static let alphabet = 27

    let nodeCount: Int
    private let spellingCount: Int
    private let spellings: Int

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 16, Array(bytes[0..<4]) == Self.header else { return nil }
        let nodeCount = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
        let table = 8 + nodeCount * 8
        guard bytes.count >= table else { return nil }
        self.bytes = bytes
        self.nodeCount = nodeCount
        spellingCount = bytes.count >= table + 4 ? Self.u32(bytes, table) : 0
        spellings = table + 4
        guard spellingCount == 0 || bytes.count >= spellings + spellingCount * 8 else { return nil }
    }

    public var wordCount: Int {
        (0..<nodeCount).count { logWord(Node($0)) != nil }
    }

    struct Node: Hashable {
        let index: Int
        init(_ index: Int) { self.index = index }
        var offset: Int { 8 + index * 8 }
    }

    var root: Node { Node(0) }

    func letter(_ node: Node) -> UInt8 { bytes[node.offset] }

    func logWord(_ node: Node) -> Double? {
        let q = bytes[node.offset + 1]
        return q == 0 ? nil : -Double(q) / 10
    }

    func logMass(_ node: Node) -> Double { -Double(bytes[node.offset + 2]) / 10 }

    func isCapitalized(_ node: Node) -> Bool { bytes[node.offset + 3] & 2 != 0 }

    func isSpelled(_ node: Node) -> Bool { bytes[node.offset + 3] & 4 != 0 }

    /// The word's lowercase spelling with its accents, from the table after the nodes.
    func spelling(_ node: Node) -> String? {
        var low = 0, high = spellingCount
        while low < high {
            let middle = (low + high) / 2
            let at = spellings + middle * 8
            let found = Self.u32(bytes, at)
            if found == node.index {
                let start = spellings + spellingCount * 8 + Self.u32(bytes, at + 4)
                let end = bytes[start...].firstIndex(of: 0) ?? bytes.endIndex
                return String(decoding: bytes[start..<end], as: UTF8.self)
            }
            if found < node.index { low = middle + 1 } else { high = middle }
        }
        return nil
    }

    func children(_ node: Node) -> Children {
        let o = node.offset + 4
        let first = Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
        return Children(lexicon: self, first: first)
    }

    func child(_ node: Node, _ letter: UInt8) -> Node? {
        children(node).first { self.letter($0) == letter }
    }

    func node(for word: some StringProtocol) -> Node? {
        var node = root
        for letter in Self.letters(word) {
            guard let next = child(node, letter) else { return nil }
            node = next
        }
        return node
    }

    public func logProbability(of word: some StringProtocol) -> Double? {
        node(for: word).flatMap(logWord)
    }

    /// The word as the lexicon spells it ("I'm" for "im", "ideeën" for "ideeen"), if it is one. A word whose stored
    /// spelling has no accents keeps the ones it was typed with ("één").
    public func canonical(_ word: some StringProtocol) -> String? {
        guard let node = node(for: word), logWord(node) != nil else { return nil }
        let lower = (isSpelled(node) ? spelling(node) : nil) ?? String(word).lowercased().replacing("’", with: "'")
        return isCapitalized(node) ? lower.prefix(1).uppercased() + lower.dropFirst() : lower
    }

    struct Children: Sequence, IteratorProtocol {
        let lexicon: Lexicon
        var upcoming: Int

        init(lexicon: Lexicon, first: Int) {
            self.lexicon = lexicon
            self.upcoming = first
        }

        mutating func next() -> Node? {
            guard upcoming != 0 else { return nil }
            let node = Node(upcoming)
            upcoming = lexicon.bytes[node.offset + 3] & 1 != 0 ? 0 : upcoming + 1
            return node
        }
    }

    /// One letter per character, lowercase and without accents ("Ideeën" → "ideeen"); 0 for a character outside the
    /// alphabet, which no word has.
    static func letters(_ word: some StringProtocol) -> [UInt8] {
        word.map { character in
            if character == "’" { return 39 }
            guard let first = character.unicodeScalars.first else { return 0 }
            let base = first.isASCII ? UInt8(first.value) : accents[first] ?? 0
            guard character.unicodeScalars.dropFirst().allSatisfy({ (0x300...0x36F).contains($0.value) }) else { return 0 }
            let letter = fold(base)
            return index(of: letter) != nil ? letter : 0
        }
    }

    /// The word lowercase without accents, other characters kept ("7pm" stays apart from "8pm"): what tells two
    /// candidates apart.
    static func key(_ word: some StringProtocol) -> String {
        String(zip(word, letters(word)).map { character, letter in letter == 0 ? Character(character.lowercased()) : Character(UnicodeScalar(letter)) })
    }

    /// Whether the word has a letter the alphabet holds only without its accent.
    static func hasAccents(_ word: some StringProtocol) -> Bool {
        word.unicodeScalars.contains { !$0.isASCII && $0 != "’" }
    }

    private static let accents: [Unicode.Scalar: UInt8] = {
        let bases = ["a": "àáâãäåāăą", "c": "çćĉċč", "e": "èéêëēĕėęě", "g": "ĝğġģ", "i": "ìíîïĩīĭįı", "l": "ł",
                     "n": "ñńņň", "o": "òóôõöøōŏő", "s": "śŝşš", "u": "ùúûüũūŭůűų", "y": "ýÿŷ", "z": "źżž"]
        var table: [Unicode.Scalar: UInt8] = [:]
        for (base, accented) in bases {
            for scalar in accented.unicodeScalars {
                table[scalar] = base.utf8.first!
                for upper in String(scalar).uppercased().unicodeScalars where upper != scalar { table[upper] = base.utf8.first! - 32 }
            }
        }
        return table
    }()

    private static func u32(_ bytes: [UInt8], _ at: Int) -> Int {
        Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
    }

    static func fold(_ byte: UInt8) -> UInt8 {
        switch byte {
        case 65...90: byte + 32
        default: byte
        }
    }

    static func index(of letter: UInt8) -> Int? {
        switch letter {
        case 97...122: Int(letter - 97)
        case 39: 26
        default: nil
        }
    }

    static func letter(at index: Int) -> UInt8 { index == 26 ? 39 : UInt8(97 + index) }

    static let labels = (0..<alphabet).map { String(UnicodeScalar(letter(at: $0))) }
}

extension Lexicon {
    /// Builds a lexicon from word counts. Words are folded to lowercase, keeping a leading capital ("I", "English")
    /// when that's how they're spelled, and stored without accents with their spelling kept. Spellings that differ
    /// only in accents ("een", "één") share a word, spelled the way the commoner one is. Words with a letter outside
    /// a–z, the apostrophe and their accented forms are skipped.
    public convenience init(counts: some Sequence<(word: String, count: Double)>) {
        let entries = counts.filter { entry in
            entry.count > 0 && !entry.word.isEmpty && !Self.letters(entry.word).contains(0)
        }
        let total = entries.reduce(0) { $0 + $1.count }
        let root = Building()
        for (word, count) in entries {
            var node = root
            let p = count / total
            node.mass += p
            for letter in Self.letters(word) {
                let next = node.children[letter] ?? Building()
                node.children[letter] = next
                node = next
                node.mass += p
            }
            node.probability += p
            if word.first?.isUppercase == true { node.capitalized = true }
            if p > node.spelledProbability {
                node.spelledProbability = p
                node.spelling = Self.hasAccents(word) ? word.lowercased() : nil
            }
        }

        func quantize(_ p: Double) -> UInt8 {
            p <= 0 ? 0 : UInt8(min(max((-Math.log(p) * 10).rounded(), 1), 255))
        }
        var order: [(node: Building, letter: UInt8, last: Bool)] = [(root, 0, true)]
        var firstChild: [Int] = []
        var cursor = 0
        while cursor < order.count {
            let node = order[cursor].node
            let letters = node.children.keys.sorted()
            firstChild.append(letters.isEmpty ? 0 : order.count)
            for (i, letter) in letters.enumerated() { order.append((node.children[letter]!, letter, i == letters.count - 1)) }
            cursor += 1
        }
        var bytes = Self.header
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: order.count >> shift)) }
        func append(_ value: Int) {
            for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        for (index, entry) in order.enumerated() {
            let flags: UInt8 = (entry.last ? 1 : 0) | (entry.node.capitalized ? 2 : 0) | (entry.node.spelling != nil ? 4 : 0)
            bytes += [entry.letter, quantize(entry.node.probability), quantize(min(entry.node.mass, 1)), flags]
            append(firstChild[index])
        }
        let spelled = order.indices.compactMap { index in order[index].node.spelling.map { (index, $0) } }
        if !spelled.isEmpty {
            append(spelled.count)
            var text: [UInt8] = []
            for (index, spelling) in spelled {
                append(index)
                append(text.count)
                text += Array(spelling.utf8) + [0]
            }
            bytes += text
        }
        self.init(bytes: bytes)!
    }
}

extension Lexicon: CandidateSource {
    public func isWord(_ word: String) -> Bool {
        logProbability(of: word) != nil
    }

    public func guesses(for word: TypedWord) -> [String] {
        Corrector(source: self).ranked(word).filter { !$0.isCompletion && !$0.isLiteral }.map(\.word)
    }

    public func completions(for prefix: String) -> [String] {
        mostFrequent(count: 3, startingWith: prefix).filter { $0.count > prefix.count }
    }

    public func mostFrequent(count: Int, startingWith prefix: String = "") -> [String] {
        guard let start = node(for: prefix) else { return [] }
        var heap = Heap<(node: Node, spelling: [UInt8], terminal: Bool)>()
        heap.push((start, Self.letters(prefix), false), priority: logMass(start))
        var words: [String] = []
        while words.count < count, let (node, spelling, terminal) = heap.pop() {
            if terminal {
                words.append(canonical(String(decoding: spelling, as: UTF8.self)) ?? "")
                continue
            }
            if let word = logWord(node) { heap.push((node, spelling, true), priority: word) }
            for child in children(node) { heap.push((child, spelling + [letter(child)], false), priority: logMass(child)) }
        }
        return words
    }
}

private final class Building {
    var children: [UInt8: Building] = [:]
    var probability = 0.0
    var mass = 0.0
    var capitalized = false
    var spelling: String?
    var spelledProbability = 0.0
}
