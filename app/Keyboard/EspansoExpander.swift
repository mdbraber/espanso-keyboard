import EspansoKeyboardCore
import Foundation
import KeyboardUI
import os

/// Espanso snippets for Hex's typing, through the Rust core (espanso-keyboard).
final class EspansoExpander: TextExpander {
    private static let log = Logger(subsystem: "espanso-keyboard", category: "expander")
    private let engine: EspansoEngine

    /// Loads the Espanso folder bundled with the keyboard. Plan step 5 replaces this with the companion app's copy in
    /// the app group.
    static func bundled() -> EspansoExpander? {
        guard let folder = Bundle.main.url(forResource: "espanso", withExtension: nil) else {
            log.error("no espanso folder in the keyboard bundle")
            return nil
        }
        do {
            let engine = try EspansoEngine(configFolder: folder.path, scriptRunner: JavaScriptCoreScriptRunner())
            for warning in engine.warnings() { log.warning("\(warning, privacy: .public)") }
            return EspansoExpander(engine: engine)
        } catch {
            log.error("loading \(folder.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private init(engine: EspansoEngine) {
        self.engine = engine
    }

    func typed(_ text: String) -> TextExpansion? {
        let expansion = engine.typeText(text: text)
        if expansion == nil, let error = engine.lastError() {
            Self.log.error("not expanded: \(error, privacy: .public)")
        }
        return expansion.map(TextExpansion.init)
    }

    func backspace() -> TextExpansion? {
        engine.backspace().map(TextExpansion.init)
    }

    func reset() {
        engine.reset()
    }
}

private extension TextExpansion {
    init(_ expansion: Expansion) {
        self.init(
            deleteCount: Int(expansion.deleteCount), insert: expansion.insert, cursorOffset: Int(expansion.cursorOffset))
    }
}
