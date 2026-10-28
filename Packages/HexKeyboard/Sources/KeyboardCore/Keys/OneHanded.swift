/// Apple's One-Handed Keyboard: on an upright iPhone the keys narrow toward one thumb and leave a margin on the other side.
public enum OneHanded: String, Hashable, Sendable, CaseIterable {
    case off, left, right
}

extension OneHanded {
    /// Left to right, as the hands sit in the layer menu.
    public static let menuOrder: [OneHanded] = [.left, .off, .right]
}
