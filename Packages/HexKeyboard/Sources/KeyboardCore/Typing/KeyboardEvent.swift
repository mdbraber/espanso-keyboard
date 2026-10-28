public enum KeyboardEvent: Hashable, Sendable {
    case down(Key, tapCount: Int)
    case up(Key)
    case type(Key, Tap)
    case slide(String)
    case trigger(Key)
    case cursor(offset: Int)
    case oneHanded(OneHanded)
    /// A hand picked from the layer key's menu. The key switched layers as it went down, so the letters come back.
    case pick(OneHanded)
    /// Text that dictation heard.
    case dictated(String)
}
