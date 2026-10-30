public struct KeyboardSettings: Hashable, Sendable {
    public var autoCapitalization = true
    public var autoCorrection = true
    public var capsLock = true
    public var smartPunctuation = true
    public var periodShortcut = true
    public var predictiveText = true
    public var characterPreview = true
    public var haptics = true
    public var sound = true
    public var oneHanded = OneHanded.off
    public var language = Language.english
    /// Whether the keyboard shares where your taps land with the app's Your Taps (espanso-keyboard). Autocorrect learns
    /// from them either way.
    public var sharesTaps = true

    public init() {}
}
