import EspansoKeyboardCore
import Foundation
import KeyboardUI
import UIKit
import os

/// Espanso snippets for Hex's typing, through the Rust core (espanso-keyboard).
final class EspansoExpander: TextExpander {
    static let log = Logger(subsystem: "espanso-keyboard", category: "expander")
    private let engine: EspansoEngine
    /// Shows questions and the snippet panel, and applies what they produce.
    weak var host: KeyboardViewController?
    /// Off: typing doesn't expand and nothing is suggested; the snippet panel still works.
    var isEnabled = true
    /// Every snippet the keyboard can expand, for the panel; Text Replacements give way to their triggers.
    let snippets: [SnippetSummary]
    private let triggers: Set<String>

    /// Loads the app's copy of the Espanso folder (`EspansoLibrary`).
    init?(folder: URL) {
        do {
            engine = try EspansoEngine(configFolder: folder.path, scriptRunner: JavaScriptCoreScriptRunner())
        } catch {
            Self.log.error("loading \(folder.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        engine.setClipboard(clipboard: PasteboardClipboard())
        for warning in engine.warnings() { Self.log.warning("\(warning, privacy: .public)") }
        snippets = engine.search(query: "")
        triggers = Set(snippets.filter { !$0.isRegex }.flatMap(\.triggers).map { $0.lowercased() })
        Self.log.info("loaded \(self.snippets.count) snippets from \(folder.lastPathComponent, privacy: .public)")
    }

    // MARK: TextExpander

    func typed(_ text: String) -> TextExpansion? {
        guard isEnabled else { return nil }
        return finish(engine.typeText(text: text))
    }

    func backspace() -> TextExpansion? {
        guard isEnabled else { return nil }
        return engine.backspace().map(TextExpansion.init)
    }

    func reset() {
        engine.reset()
    }

    func completions(before: String) -> [TextCompletion] {
        guard isEnabled else { return [] }
        return engine.complete(before: String(before.suffix(64))).map {
            TextCompletion(title: $0.trigger, id: Int($0.id), typed: Int($0.typed))
        }
    }

    func accept(_ completion: TextCompletion) -> TextExpansion? {
        finish(engine.insertSnippet(id: Int32(completion.id), deleteCount: UInt32(completion.typed)))
    }

    func reserves(_ shortcut: String) -> Bool {
        isEnabled && triggers.contains(shortcut.lowercased())
    }

    var hasSnippets: Bool { !snippets.isEmpty }

    func showSnippets() {
        host?.showSnippetPanel()
    }

    // MARK: Panels

    /// The expansion of a snippet picked in the panel, inserted at the caret.
    func insert(_ id: Int32) -> TextExpansion? {
        finish(engine.insertSnippet(id: id, deleteCount: 0))
    }

    func answer(_ answer: Answer) -> TextExpansion? {
        finish(engine.answer(answer: answer))
    }

    func cancelPrompt() {
        engine.cancelPrompt()
    }

    /// Counts a finished expansion, or hands a question to the host; logs why a trigger didn't expand.
    private func finish(_ expansion: Expansion?) -> TextExpansion? {
        if let expansion {
            EspansoShared.recordUse(of: expansion.snippet)
            return TextExpansion(expansion)
        }
        if let prompt = engine.prompt() {
            host?.ask(prompt, expander: self)
        } else if let error = engine.lastError() {
            Self.log.error("not expanded: \(error, privacy: .public)")
        }
        return nil
    }
}

/// The clipboard for `clipboard` variables. Reading it needs Full Access.
private final class PasteboardClipboard: Clipboard {
    func text() -> String? {
        UIPasteboard.general.string
    }
}

extension TextExpansion {
    init(_ expansion: Expansion) {
        self.init(
            deleteCount: Int(expansion.deleteCount), insert: expansion.insert, cursorOffset: Int(expansion.cursorOffset))
    }
}
