import Testing
import KeyboardCore
@testable import KeyboardUI

/// emoji-nl.txt, built by scripts/emoji-nl.py (espanso-keyboard).
@MainActor
struct DutchEmojiTests {
    func bar(_ word: String) -> [String] {
        EmojiCatalog.dutch.suggestions(for: word, history: EmojiHistory())
    }

    @Test func wordsFindTheirEmojiFirst() {
        #expect(bar("hond").contains("🐶"))
        #expect(bar("honden").contains("🐶"))
        #expect(bar("hart").first == "❤️")
        #expect(bar("liefde").first == "❤️")
        #expect(bar("koffie").first == "☕")
        #expect(bar("pizza").first == "🍕")
        #expect(bar("bedankt").first == "🙏")
        #expect(bar("huilen").first == "😭")
        #expect(bar("boot").contains("⛵"))
    }

    @Test func wordsThatHoldASentenceTogetherOrMeanSomethingElseFindNone() {
        for word in ["die", "de", "het", "een", "één", "wet", "pink", "kind", "trouwens", "dag", "engels", "bomen"] {
            #expect(bar(word).isEmpty, "\(word)")
        }
    }
}
