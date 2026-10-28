/// Snippet expansion hooked into typing (added for espanso-keyboard). `HexKeyboardViewController` tells it what the
/// keyboard typed and applies what it answers, so this package needs nothing from the expander's implementation.
public protocol TextExpander: AnyObject {
    /// Text the keyboard just wrote, already in the field. Returns an expansion when it completes a trigger.
    func typed(_ text: String) -> TextExpansion?
    /// Backspace, before the keyboard deletes. A returned expansion (an undo) replaces the delete.
    func backspace() -> TextExpansion?
    /// The text changed in a way that isn't typing: forget the trigger in progress.
    func reset()
    /// Snippets the text before the caret has begun to type, best first, for the suggestion bar.
    func completions(before: String) -> [TextCompletion]
    /// The expansion for an accepted completion, replacing its typed start.
    func accept(_ completion: TextCompletion) -> TextExpansion?
    /// Whether a Text Replacement with this shortcut should give way to a snippet.
    func reserves(_ shortcut: String) -> Bool
    /// Whether the suggestion bar shows the snippets button.
    var hasSnippets: Bool { get }
    /// The snippets button was tapped.
    func showSnippets()
}

public extension TextExpander {
    func completions(before: String) -> [TextCompletion] { [] }
    func accept(_ completion: TextCompletion) -> TextExpansion? { nil }
    func reserves(_ shortcut: String) -> Bool { false }
    var hasSnippets: Bool { false }
    func showSnippets() {}
}

/// A snippet offered in the suggestion bar: `title` is shown and identifies it.
public struct TextCompletion: Hashable, Sendable {
    public var title: String
    public var id: Int
    public var typed: Int

    public init(title: String, id: Int, typed: Int) {
        self.title = title
        self.id = id
        self.typed = typed
    }
}

/// An edit at the caret: delete `deleteCount` characters, insert `insert`, then move the caret `cursorOffset`
/// characters left.
public struct TextExpansion: Hashable, Sendable {
    public var deleteCount: Int
    public var insert: String
    public var cursorOffset: Int

    public init(deleteCount: Int, insert: String, cursorOffset: Int) {
        self.deleteCount = deleteCount
        self.insert = insert
        self.cursorOffset = cursorOffset
    }
}
