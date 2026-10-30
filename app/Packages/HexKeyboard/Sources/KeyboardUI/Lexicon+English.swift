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
        case .english: english
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
        case .english: english
        case .dutch: dutch
        }
    }
}
