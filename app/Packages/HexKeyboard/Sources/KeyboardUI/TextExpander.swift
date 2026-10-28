/// Snippet expansion hooked into typing (added for espanso-keyboard). `HexKeyboardViewController` tells it what the
/// keyboard typed and applies what it answers, so this package needs nothing from the expander's implementation.
public protocol TextExpander: AnyObject {
    /// Text the keyboard just wrote, already in the field. Returns an expansion when it completes a trigger.
    func typed(_ text: String) -> TextExpansion?
    /// Backspace, before the keyboard deletes. A returned expansion (an undo) replaces the delete.
    func backspace() -> TextExpansion?
    /// The text changed in a way that isn't typing: forget the trigger in progress.
    func reset()
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
