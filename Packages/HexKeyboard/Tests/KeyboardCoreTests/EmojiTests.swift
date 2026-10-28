import Testing
@testable import KeyboardCore

struct EmojiTests {
    let catalog = EmojiCatalog(text: """
    dog\t🐶 🐕 🌭
    doe\t🦌
    does\t
    love\t❤️ 😍 💕
    pizza\t🍕
    box\t📦
    with\t
    """)

    @Test func theBarFindsAWordsEmojiOrItsSingulars() {
        #expect(catalog.suggestions(for: "Pizza", history: EmojiHistory()) == ["🍕"])
        #expect(catalog.suggestions(for: "dogs", history: EmojiHistory()) == ["🐶", "🐕", "🌭"])
        #expect(catalog.suggestions(for: "boxes", history: EmojiHistory()) == ["📦"])
        #expect(catalog.suggestions(for: "love", history: EmojiHistory(), limit: 2) == ["❤️", "😍"])
        #expect(catalog.suggestions(for: "with", history: EmojiHistory()).isEmpty)
        #expect(catalog.suggestions(for: "does", history: EmojiHistory()).isEmpty, "a word that finds none doesn't fall back to its singular")
        #expect(catalog.suggestions(for: "piz", history: EmojiHistory()).isEmpty, "the bar wants the whole word")
    }

    @Test func theBarOffersWhatYouPickFirstAndRecentPicksOutweighOlderOnes() {
        var history = EmojiHistory()
        history.use("🐕")
        #expect(catalog.suggestions(for: "dog", history: history) == ["🐕", "🐶", "🌭"])
        for _ in 0 ..< 3 { history.use("🌭") }
        #expect(catalog.suggestions(for: "dog", history: history) == ["🌭", "🐕", "🐶"])
        for _ in 0 ..< 4 { history.use("🐕") }
        #expect(catalog.suggestions(for: "dog", history: history) == ["🐕", "🌭", "🐶"])
    }

    @Test func anEmojiFromTheBarTakesTheWordsPlaceOrFollowsIt() {
        var engine = TypingEngine()
        engine.emojiCatalog = catalog
        let document = TestDocument()
        engine.type("i love pizza", in: document)
        #expect(engine.emojiSuggestions == ["🍕"])
        engine.accept(emoji: "🍕", in: document)
        #expect(document.text == "i love 🍕 ")
        #expect(engine.emojiSuggestions.isEmpty)
        #expect(engine.emojiHistory.scores["🍕"] != nil)
        engine.type("my dog ", in: document)
        #expect(engine.emojiSuggestions.first == "🐶", "a word just typed still offers its emoji")
        engine.accept(emoji: "🐶", in: document)
        #expect(document.text == "i love 🍕 my dog 🐶 ")
        engine.type("you", in: document)
        #expect(engine.emojiSuggestions.isEmpty)
    }

    @Test func dictationJoinsWhatsThereWithASpace() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.handle(.dictated("Hello there."), in: document)
        #expect(document.text == "Hello there.")
        engine.handle(.dictated("How are you?"), in: document)
        #expect(document.text == "Hello there. How are you?")
    }
}
