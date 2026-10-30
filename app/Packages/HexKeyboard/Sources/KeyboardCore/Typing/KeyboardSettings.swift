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
    /// Features you can switch off completely (espanso-keyboard): voice typing (the bar's mic), learning where your
    /// taps land (off forgets it), and sending text to sources.
    public var voice = true
    public var learnsTaps = true
    public var sources = true
    /// Whether the keyboard shares where your taps land with the app's Your Taps, while it learns them.
    public var sharesTaps = true

    public init() {}
}
