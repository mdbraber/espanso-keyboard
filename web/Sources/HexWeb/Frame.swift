import JavaScriptKit
import KeyboardCore

@JS struct Cap {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var face: String
    var label: String
    var secondary: String?
    var secondaryDimmed: Bool
    var align: String
    var prominent: Bool
    var action: String
    var isInput: Bool
    var typed: String?
    var shown: String?
    var alternates: [String]
}

@JS struct Chip {
    var text: String
    var correction: Bool
}

@JS struct Look {
    var keyHeight: Double
    var cornerRadius: Double
    var letterSize: Double
    var labelSize: Double
    var secondarySize: Double
    var symbolSize: Double
    var letterOffset: Double
    var edgeInsetX: Double
    var edgeInsetY: Double
    var textBaselineInset: Double
    var letterBaselineInset: Double
    var secondaryCapTop: Double
    var pairSize: Double
    var pairCapTop: Double
    var pairBaselineRatio: Double
    var dimsKeyUnderAccents: Bool
    var key: String
    var keyPressed: String
    var label: String
    var secondaryLabel: String
    var prominent: String
    var prominentLabel: String
    var selection: String
    var selectionLabel: String
    var shadow: String
    var candidate: String
    var candidateHighlighted: String
    var candidatePill: String
    var candidateDivider: String
}

@JS struct Frame {
    var layout: String
    var width: Double
    var height: Double
    var showsSuggestions: Bool
    var caps: [Cap]
    var chips: [Chip]
    var look: Look
}

extension Look {
    init(metrics m: KeyboardMetrics, theme t: KeyboardTheme, style: KeyboardStyle) {
        self.init(
            keyHeight: m.keyHeight, cornerRadius: m.cornerRadius, letterSize: m.letterSize, labelSize: m.labelSize,
            secondarySize: m.secondarySize, symbolSize: m.symbolSize, letterOffset: m.letterOffset,
            edgeInsetX: m.edgeInset.width, edgeInsetY: m.edgeInset.height, textBaselineInset: m.textBaselineInset,
            letterBaselineInset: m.letterBaselineInset, secondaryCapTop: m.secondaryCapTop, pairSize: m.pairSize,
            pairCapTop: m.pairCapTop, pairBaselineRatio: m.pairBaselineRatio, dimsKeyUnderAccents: style.dimsKeyUnderAccents,
            key: t.key.css, keyPressed: t.keyPressed.css, label: t.label.css, secondaryLabel: t.secondaryLabel.css,
            prominent: t.prominent.css, prominentLabel: t.prominentLabel.css, selection: t.selection.css,
            selectionLabel: t.selectionLabel.css, shadow: t.shadow.css, candidate: t.candidate.css,
            candidateHighlighted: t.candidateHighlighted.css, candidatePill: t.candidatePill.css, candidateDivider: t.candidateDivider.css
        )
    }
}

extension RGBA {
    var css: String {
        let channel = { (value: Double) in Int((value * 255).rounded()) }
        return "rgb(\(channel(red)) \(channel(green)) \(channel(blue)) / \(alpha))"
    }
}

extension KeyFace.Content {
    var kind: String {
        switch self {
        case .letter: "letter"
        case .text: "text"
        case .smallText: "smallText"
        case .symbol: "symbol"
        case .none: "none"
        }
    }

    var value: String {
        switch self {
        case .letter(let text), .text(let text), .smallText(let text), .symbol(let text): text
        case .none: ""
        }
    }
}

extension KeyFace.Alignment {
    var name: String {
        switch self {
        case .center: "center"
        case .bottomLeading: "leading"
        case .bottomTrailing: "trailing"
        }
    }
}

extension KeyAction {
    var name: String {
        switch self {
        case .character: "character"
        case .space: "space"
        case .delete: "delete"
        case .shift: "shift"
        case .capsLock: "capsLock"
        case .return: "return"
        case .tab: "tab"
        case .layer: "layer"
        case .nextKeyboard: "nextKeyboard"
        case .dismiss: "dismiss"
        }
    }
}
