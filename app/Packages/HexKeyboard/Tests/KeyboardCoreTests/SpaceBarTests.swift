import Testing
@testable import KeyboardCore

/// The space bar names the language by its code beside "hex", in the corner (espanso-keyboard).
struct SpaceBarTests {
    private func face(_ language: Language?) -> KeyFace {
        var context = KeyFaceContext(device: .phone, layer: .letters, kind: .text, shift: .off, returnKind: .default, returnEnabled: true)
        context.language = language
        return KeyFace(Key(.space), trailing: false, context: context)
    }

    @Test func showsTheLanguageCodeBesideHex() {
        #expect(face(.english).corner == "hex · EN")
        #expect(face(.dutch).corner == "hex · NL")
        #expect(face(.both).corner == "hex · EN-NL")
        #expect(face(nil).corner == "hex")
        #expect(face(.both).content == .none, "the bar itself stays blank")
    }
}
