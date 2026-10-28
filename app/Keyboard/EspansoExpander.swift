import EspansoKeyboardCore
import Foundation
import KeyboardUI
import os

/// Espanso snippets for Hex's typing, through the Rust core (espanso-keyboard).
final class EspansoExpander: TextExpander {
    private static let log = Logger(subsystem: "espanso-keyboard", category: "expander")
    private let engine: EspansoEngine

    /// Loads the app's copy of the Espanso folder (`EspansoLibrary`).
    convenience init?(folder: URL) {
        do {
            let engine = try EspansoEngine(configFolder: folder.path, scriptRunner: JavaScriptCoreScriptRunner())
            for warning in engine.warnings() { Self.log.warning("\(warning, privacy: .public)") }
            Self.log.info("loaded \(engine.search(query: "").count) snippets from \(folder.lastPathComponent, privacy: .public)")
            self.init(engine: engine)
        } catch {
            Self.log.error("loading \(folder.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
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
