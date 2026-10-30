/// The language Hex corrects and predicts in: its own word list, next words and learned words (espanso-keyboard).
public enum Language: String, Hashable, Sendable, CaseIterable, Codable {
    case english = "en", dutch = "nl"

    /// As the language calls itself, the way Apple names keyboards.
    public var name: String {
        switch self {
        case .english: "English"
        case .dutch: "Nederlands"
        }
    }

    /// Short, for the layer key's menu.
    public var code: String { rawValue.uppercased() }
}
