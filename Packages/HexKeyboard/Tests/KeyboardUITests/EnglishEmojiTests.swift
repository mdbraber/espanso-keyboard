import Testing
import KeyboardCore
@testable import KeyboardUI

@MainActor
struct EnglishEmojiTests {
    func bar(_ word: String) -> [String] {
        EmojiCatalog.english.suggestions(for: word, history: EmojiHistory())
    }

    @Test func wordsFindTheirEmojiFirst() {
        #expect(bar("pizza").first == "🍕")
        #expect(bar("Love").first == "❤️")
        #expect(bar("dogs").first == "🐶")
        #expect(bar("laughing").first == "😂")
        #expect(bar("latte").first == "☕")
        #expect(bar("birthday").first == "🎂")
        #expect(bar("thanks").first == "🙏")
    }

    @Test func wordsThatHoldASentenceTogetherOrMeanSomethingElseFindNone() {
        for word in ["with", "the", "you", "does", "heard", "table", "order", "fine"] {
            #expect(bar(word).isEmpty, "\(word)")
        }
    }
}
