import Testing
@testable import KeyboardCore

/// Words with accents (Dutch): stored without them, spelled with them (espanso-keyboard).
struct AccentTests {
    let lexicon = Lexicon(counts: [
        ("een", 9000), ("één", 400), ("ik", 9000), ("heb", 5000), ("geen", 3000), ("idee", 2000), ("ideeën", 300),
        ("België", 200), ("geïnteresseerd", 100), ("zo'n", 500), ("café", 300), ("cafe", 10), ("de", 9000),
    ].map { (word: $0.0, count: Double($0.1)) })

    private func correct(_ text: String, _ corrector: Corrector) -> String? {
        let grid = KeyGrid.standard
        let taps = Lexicon.letters(text).map { letter -> Tap in
            let label = String(UnicodeScalar(letter))
            let frame = grid.frame(of: label)!
            return Tap(x: frame.midX, y: frame.midY, key: label)
        }
        return corrector.correction(for: TypedWord(text, taps: text.count == taps.count && !Lexicon.hasAccents(text) ? taps : [], previous: nil))
    }

    @Test func foldsAccentsAndCase() {
        #expect(Lexicon.letters("Ideeën") == Array("ideeen".utf8))
        #expect(Lexicon.letters("zo’n") == Array("zo'n".utf8))
        #expect(Lexicon.letters("e\u{301}") == Array("e".utf8))
        #expect(Lexicon.letters("straße").contains(0))
    }

    @Test func spellsWordsWithTheirAccents() {
        #expect(lexicon.canonical("ideeen") == "ideeën")
        #expect(lexicon.canonical("ideeën") == "ideeën")
        #expect(lexicon.canonical("belgie") == "België")
        #expect(lexicon.canonical("cafe") == "café")
        #expect(lexicon.canonical("een") == "een")
        #expect(lexicon.canonical("één") == "één")
        #expect(lexicon.isWord("geinteresseerd"))
        #expect(lexicon.wordCount == 11, "één shares een, café shares cafe")
    }

    @Test func survivesARoundTripThroughBytes() {
        let copy = Lexicon(bytes: lexicon.bytes)!
        #expect(copy.canonical("geinteresseerd") == "geïnteresseerd")
        #expect(Lexicon(bytes: testLexicon.bytes)!.canonical("i'm") == "I'm")
    }

    @Test func addsAccentsWhenTypedWithout() {
        let corrector = Corrector(source: lexicon)
        #expect(correct("ideeen", corrector) == "ideeën")
        #expect(correct("Ideeen", corrector) == "Ideeën")
        #expect(correct("belgie", corrector) == "België")
        #expect(correct("geinteresseerd", corrector) == "geïnteresseerd")
        #expect(correct("een", corrector) == nil)
        #expect(correct("idee", corrector) == nil)
    }

    @Test func keepsAccentsYouTyped() {
        let corrector = Corrector(source: lexicon)
        #expect(correct("één", corrector) == nil)
        #expect(correct("ideeën", corrector) == nil)
        #expect(corrector.misspellings(in: "ik heb één idee") == [])
    }

    @Test func completesToTheAccentedSpelling() {
        #expect(lexicon.completions(for: "idee").contains("ideeën"))
        #expect(lexicon.completions(for: "geint") == ["geïnteresseerd"])
    }
}
