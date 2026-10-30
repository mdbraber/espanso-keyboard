import Foundation
import KeyboardCore

extension Lexicon {
    static let english: Lexicon = {
        let url = Bundle.module.url(forResource: "en", withExtension: "lexicon")!
        return Lexicon(bytes: [UInt8](try! Data(contentsOf: url, options: .alwaysMapped)))!
    }()
}

extension Phrases {
    static let english: Phrases = {
        let url = Bundle.module.url(forResource: "en", withExtension: "phrases")!
        return Phrases(bytes: [UInt8](try! Data(contentsOf: url, options: .alwaysMapped)))!
    }()
}

extension EmojiCatalog {
    nonisolated static let english: EmojiCatalog = {
        let url = Bundle.module.url(forResource: "emoji", withExtension: "txt")!
        return EmojiCatalog(text: try! String(contentsOf: url, encoding: .utf8))
    }()
}

// Dutch (espanso-keyboard): nl.lexicon and nl.phrases are built by scripts/lexicon-nl and scripts/phrases-nl.
extension Lexicon {
    static let dutch: Lexicon = {
        let url = Bundle.module.url(forResource: "nl", withExtension: "lexicon")!
        return Lexicon(bytes: [UInt8](try! Data(contentsOf: url, options: .alwaysMapped)))!
    }()

    static func `for`(_ language: Language) -> Lexicon {
        switch language {
        case .english, .both: english
        case .dutch: dutch
        }
    }
}

extension Phrases {
    static let dutch: Phrases = {
        let url = Bundle.module.url(forResource: "nl", withExtension: "phrases")!
        return Phrases(bytes: [UInt8](try! Data(contentsOf: url, options: .alwaysMapped)))!
    }()

    static func `for`(_ language: Language) -> Phrases {
        switch language {
        case .english, .both: english
        case .dutch: dutch
        }
    }
}

extension EmojiCatalog {
    nonisolated static let dutch: EmojiCatalog = {
        let url = Bundle.module.url(forResource: "emoji-nl", withExtension: "txt")!
        return EmojiCatalog(text: try! String(contentsOf: url, encoding: .utf8))
    }()

    nonisolated static func `for`(_ language: Language) -> EmojiCatalog {
        language == .dutch ? dutch : english
    }
}

extension Corrector {
    /// A corrector for the language; for both, English and Dutch mixed by what you're writing.
    public static func `for`(_ language: Language) -> Corrector {
        let parts = language.parts
        return Corrector(source: Lexicon.for(parts[0]), phrases: .for(parts[0]),
                         mixing: parts.dropFirst().map { (lexicon: Lexicon.for($0), phrases: Phrases.for($0)) })
    }
}
