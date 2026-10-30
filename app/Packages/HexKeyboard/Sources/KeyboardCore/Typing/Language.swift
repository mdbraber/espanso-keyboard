/// The language Hex corrects and predicts in: its own word list, next words and learned words (espanso-keyboard).
public enum Language: String, Hashable, Sendable, CaseIterable, Codable {
    case english = "en", dutch = "nl"
    /// Both at once, leaning toward the one you're writing, as Apple's multilingual keyboards do.
    case both = "en+nl"

    /// As the language calls itself, the way Apple names keyboards.
    public var name: String {
        switch self {
        case .english: "English"
        case .dutch: "Nederlands"
        case .both: "English & Nederlands"
        }
    }

    /// Short, for the layer key's menu and the space bar's corner.
    public var code: String { self == .both ? "EN-NL" : rawValue.uppercased() }

    /// The single languages it's made of.
    public var parts: [Language] { self == .both ? [.english, .dutch] : [self] }
}
