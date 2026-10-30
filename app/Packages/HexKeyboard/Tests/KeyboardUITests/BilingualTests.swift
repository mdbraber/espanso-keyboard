import Testing
import KeyboardCore
@testable import KeyboardUI

/// English and Dutch at once through the engine, with the real word lists (espanso-keyboard).
@MainActor
struct BilingualTests {
    private func typed(_ text: String, after start: String = "") -> String {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        engine.corrector = Corrector.for(.both)
        let document = Document()
        document.insert(start)
        engine.documentChanged(document)
        let grid = KeyGrid.standard
        for character in text {
            let label = String(character)
            if character == " " {
                engine.perform(.space, in: document)
            } else if let frame = grid.frame(of: label) {
                engine.perform(.character(label), in: document, tap: Tap(x: frame.midX, y: frame.midY, key: label))
            } else {
                engine.perform(.character(label), in: document)
            }
        }
        return String(document.text.dropFirst(start.count))
    }

    @Test func eitherLanguageTypesWithoutCorrections() {
        #expect(typed("ik heb geen idee wat je bedoelt ") == "ik heb geen idee wat je bedoelt ")
        #expect(typed("i have no idea what you mean ") == "I have no idea what you mean ")
        #expect(typed("we gaan morgen naar de stad ") == "we gaan morgen naar de stad ")
        #expect(typed("we are going to the city tomorrow ") == "we are going to the city tomorrow ")
    }

    @Test func correctsInTheLanguageBeingWritten() {
        #expect(typed("teh ", after: "I think that ") == "the ")
        #expect(typed("nirt ", after: "ik weet het ") == "niet ")
        #expect(typed("ideeen ", after: "dat zijn goede ") == "ideeën ")
    }

    @Test func switchesWithinAMessage() {
        #expect(typed("thanks see you tomorrow ", after: "ik kom morgen langs. ") == "thanks see you tomorrow ")
    }

    @Test func predictsInTheLanguageBeingWritten() {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        engine.corrector = Corrector.for(.both)
        let document = Document()
        engine.documentChanged(document)
        for character in "ik heb het niet gezien dank " { engine.perform(character == " " ? .space : .character(String(character)), in: document) }
        #expect(engine.suggestions.map(\.text).contains("je"))
    }
}
