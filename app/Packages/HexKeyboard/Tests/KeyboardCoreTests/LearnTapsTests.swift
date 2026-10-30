import Testing
@testable import KeyboardCore

/// Learn My Taps (espanso-keyboard): off, typing teaches the touch model nothing.
struct LearnTapsTests {
    private func typed(learning: Bool) -> TouchModel {
        var engine = TypingEngine()
        engine.corrector = Corrector(source: testLexicon)
        engine.settings.learnsTaps = learning
        let document = TestDocument()
        engine.documentChanged(document)
        let grid = KeyGrid.standard
        for character in "hello world the job " {
            let label = String(character)
            if character == " " { engine.perform(.space, in: document); continue }
            let frame = grid.frame(of: label)!
            engine.perform(.character(label), in: document, tap: Tap(x: frame.midX + 3, y: frame.midY + 4, key: label))
        }
        engine.endSession()
        return engine.corrector!.memory.touches
    }

    @Test func learnsOnlyWhenOn() {
        #expect(typed(learning: true) != TouchModel())
        #expect(typed(learning: false) == TouchModel())
    }
}
