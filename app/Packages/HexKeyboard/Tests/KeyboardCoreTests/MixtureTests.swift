import Testing
@testable import KeyboardCore

/// Two languages at once, weighed by what you're writing (espanso-keyboard).
struct MixtureTests {
    private static func lexicon(_ counts: [(String, Double)]) -> Lexicon {
        Lexicon(counts: counts.map { (word: $0.0, count: $0.1) })
    }

    let english = lexicon([("the", 900), ("is", 500), ("door", 40), ("want", 60), ("we", 300), ("have", 200), ("time", 80), ("tie", 10)])
    let dutch = lexicon([("de", 900), ("is", 600), ("door", 300), ("want", 100), ("we", 400), ("hebben", 200), ("tijd", 80), ("te", 500)])

    private func corrector() -> Corrector {
        Corrector(source: english, mixing: [(lexicon: dutch, phrases: nil)])
    }

    @Test func startsEvenAndLeansTowardTheLanguageWritten() {
        let corrector = corrector()
        #expect(corrector.mixture.parts.map(\.weight) == [0.5, 0.5])
        corrector.weigh(before: "we hebben de tijd ")
        #expect(corrector.mixture.parts[1].weight > 0.9)
        corrector.weigh(before: "we have the time ")
        #expect(corrector.mixture.parts[0].weight > 0.9)
    }

    @Test func wordsBothLanguagesHaveDecideLittle() {
        let corrector = corrector()
        corrector.weigh(before: "is door want we ")
        #expect(corrector.mixture.parts.allSatisfy { $0.weight < 0.9 })
    }

    @Test func neverRulesALanguageOut() {
        let corrector = corrector()
        corrector.weigh(before: "we hebben de tijd de tijd de tijd ")
        #expect(corrector.mixture.parts[0].weight >= Mixture.floor)
    }

    @Test func theWordBeingTypedDoesntCount() {
        let corrector = corrector()
        corrector.weigh(before: "we have the time hebb")
        #expect(corrector.mixture.parts[0].weight > 0.9)
    }

    @Test func knowsEitherLanguagesWords() {
        let corrector = corrector()
        #expect(corrector.misspellings(in: "the hebben tijd time") == [])
        #expect(corrector.correction(for: TypedWord("hebben")) == nil)
        #expect(corrector.correction(for: TypedWord("time")) == nil)
    }

    @Test func oneLanguageIsUnchanged() {
        let alone = Corrector(source: english)
        #expect(alone.mixture.parts.count == 1)
        alone.weigh(before: "we hebben de tijd ")
        #expect(alone.mixture.parts[0].weight == 1)
    }
}
