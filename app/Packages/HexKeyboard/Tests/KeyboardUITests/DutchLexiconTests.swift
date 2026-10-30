import Testing
import KeyboardCore
@testable import KeyboardUI

/// nl.lexicon and nl.phrases through the corrector and the engine (espanso-keyboard).
@MainActor
struct DutchLexiconTests {
    private let corrector = Corrector(source: Lexicon.dutch, phrases: .dutch)

    private func correct(_ word: String, after previous: String? = nil) -> String? {
        let grid = KeyGrid.standard
        let taps = word.map { letter in
            let frame = grid.frame(of: String(letter))!
            return Tap(x: frame.midX, y: frame.midY, key: String(letter))
        }
        return corrector.correction(for: TypedWord(word, taps: taps, previous: previous))
    }

    private func typed(_ text: String) -> String {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .sentences))
        engine.corrector = corrector
        let document = Document()
        engine.documentChanged(document)
        let grid = KeyGrid.standard
        for character in text {
            let label = String(character).lowercased()
            if character == " " {
                engine.perform(.space, in: document)
            } else if let frame = grid.frame(of: label) {
                engine.perform(.character(label), in: document, tap: Tap(x: frame.midX, y: frame.midY, key: label))
            } else {
                engine.perform(.character(label), in: document)
            }
        }
        return document.text
    }

    @Test func everydayDutchTypesWithoutCorrections() {
        #expect(typed("ik heb geen idee ") == "Ik heb geen idee ")
        #expect(typed("hoe gaat het met je ") == "Hoe gaat het met je ")
        #expect(typed("zo'n mooie dag vandaag ") == "Zo'n mooie dag vandaag ")
        #expect(typed("ok dat is goed ") == "Ok dat is goed ")
        for word in ["ook", "een", "niet", "wel", "maar", "jij", "u", "fiets", "gezellig", "lekker", "morgen"] {
            #expect(correct(word) == nil, "\(word)")
        }
    }

    @Test func accentsComeBack() {
        #expect(correct("ideeen") == "ideeën")
        #expect(correct("geinteresseerd") == "geïnteresseerd")
        #expect(correct("cafe") == "café")
        #expect(correct("belgie") == "België")
        #expect(typed("goede ideeen ") == "Goede ideeën ")
    }

    @Test func fixesSlips() {
        #expect(correct("nirt") == "niet")
        #expect(correct("gezelig") == "gezellig")
        #expect(correct("misschein") == "misschien")
    }

    @Test func predictsWhatFollows() {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        engine.corrector = corrector
        let document = Document()
        engine.documentChanged(document)
        for character in "dank" { engine.perform(.character(String(character)), in: document) }
        engine.perform(.space, in: document)
        #expect(engine.suggestions.map(\.text).contains("je"))
    }

    @Test func capitalizesNames() {
        #expect(Lexicon.dutch.canonical("nederland") == "Nederland")
        #expect(Lexicon.dutch.canonical("amsterdam") == "Amsterdam")
        #expect(Lexicon.dutch.canonical("ik") == "ik")
    }
}
