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
