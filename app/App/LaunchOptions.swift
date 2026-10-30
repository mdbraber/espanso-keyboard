import KeyboardCore
import KeyboardUI
import UIKit

enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    private static func integer(_ key: String) -> Int? {
        defaults.string(forKey: key).flatMap { Int($0) }
    }

    static var focus: Bool { defaults.bool(forKey: "HexFocus") }
    static var settings: Bool { defaults.bool(forKey: "HexSettings") }
    /// The tab the app opens on: `-HexTab transcripts`, or `-HexTaps YES` for Your Taps.
    static var tab: String { defaults.bool(forKey: "HexTaps") ? "taps" : defaults.string(forKey: "HexTab") ?? "home" }
    static var tapsMode: TapMapView.Mode? {
        switch defaults.string(forKey: "HexTapsMode") {
        case "heat": .heat
        case "aim": .aim
        case "accuracy": .accuracy
        default: nil
        }
    }
    static var tapsScroll: String? { defaults.string(forKey: "HexTapsScroll") }
    static var tapsKey: String? { defaults.string(forKey: "HexTapsKey") }
    static var orientation: UIInterfaceOrientationMask? {
        switch defaults.string(forKey: "HexOrientation") {
        case "landscape": .landscapeRight
        case "portrait": .portrait
        default: nil
        }
    }

    static func resetSettingsIfAsked() {
        guard defaults.bool(forKey: "HexResetSettings") else { return }
        SettingsStore.reset()
        MemoryStore.reset()
        Transcripts.isKept = true
    }

    static func applyOneHanded() {
        if let hand = defaults.string(forKey: "HexOneHanded").flatMap(OneHanded.init) { SettingsStore.set(hand) }
        if let language = defaults.string(forKey: "HexLanguage").flatMap(Language.init) { SettingsStore.set(language) }
    }

    static func configure(_ field: UITextView) {
        if let value = integer("HexKeyboardType").flatMap(UIKeyboardType.init) { field.keyboardType = value }
        if let value = integer("HexReturnKey").flatMap(UIReturnKeyType.init) { field.returnKeyType = value }
        if let text = defaults.string(forKey: "HexText") { field.text = text }
    }
}
