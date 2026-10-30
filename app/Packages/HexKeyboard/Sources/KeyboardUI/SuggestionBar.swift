import UIKit
import KeyboardCore

/// Apple's three suggestions, the last one giving way to emoji when the word has some, and a mic at the right end that
/// starts and stops dictation.
final class SuggestionBar: UIView {
    /// Taps this close to the keys go to neither the bar nor the keys, so a tap meant for a key never picks a word.
    static let gap: CGFloat = 6

    var onSelect: (Suggestion) -> Void = { _ in }
    var onEmoji: (String) -> Void = { _ in }
    var onMic: () -> Void = {}
    var onMicHold: () -> Void = {}
    var onNotice: () -> Void = {}
    /// A snippets button at the left end, opening the app's snippet panel (espanso-keyboard).
    var onSnippets: () -> Void = {}
    var showsSnippets = false {
        didSet { if showsSnippets != oldValue { snippets.isHidden = !showsSnippets; setNeedsLayout() } }
    }
    /// The mic, unless Voice Typing is off (espanso-keyboard).
    var showsMic = true {
        didSet { if showsMic != oldValue { mic.isHidden = !showsMic; setNeedsLayout(); refreshDividers() } }
    }
    var maximumSlotWidth = CGFloat.infinity { didSet { setNeedsLayout() } }
    /// Where the keys end, so the mic's pill lines up with the last key.
    var keyInset: CGFloat = 0 { didSet { if keyInset != oldValue { setNeedsLayout() } } }
    /// Room above the suggestions, so the bar never meets the top of the keyboard in apps that draw no strip above it.
    var topPadding: CGFloat = 0 { didSet { if topPadding != oldValue { setNeedsLayout() } } }

    private let slots = (0..<3).map { SuggestionSlot(index: $0) }
    private let dividers = (0..<3).map { _ in UIView() }
    private var emoji: [EmojiPick] = []
    private let mic = MicButton()
    private let snippets = UIButton(type: .system)
    private let notice = UILabel()
    private var enabled = true
    private var noticed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        for slot in slots {
            slot.addAction(UIAction { [unowned self, unowned slot] _ in
                if let suggestion = slot.suggestion { onSelect(suggestion) }
            }, for: .touchUpInside)
            slot.onHighlight = { [unowned self] in refreshDividers() }
            addSubview(slot)
        }
        dividers.forEach(addSubview)
        mic.addAction(UIAction { [unowned self] _ in onMic() }, for: .touchUpInside)
        mic.onHold = { [unowned self] in onMicHold() }
        mic.onHighlight = { [unowned self] in refreshDividers() }
        addSubview(mic)
        snippets.setImage(UIImage(systemName: "text.insert", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        snippets.accessibilityIdentifier = "hex.snippets"
        snippets.accessibilityLabel = "Snippets"
        snippets.isHidden = true
        snippets.addAction(UIAction { [unowned self] _ in onSnippets() }, for: .touchUpInside)
        addSubview(snippets)
        notice.isHidden = true
        notice.font = .systemFont(ofSize: 15)
        notice.textAlignment = .center
        notice.adjustsFontSizeToFitWidth = true
        notice.minimumScaleFactor = 0.7
        notice.lineBreakMode = .byTruncatingTail
        notice.accessibilityIdentifier = "hex.notice"
        notice.isUserInteractionEnabled = true
        notice.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapNotice)))
        addSubview(notice)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ suggestions: [Suggestion], emoji: [String], enabled: Bool, theme: KeyboardTheme) {
        self.enabled = enabled
        for (index, slot) in slots.enumerated() {
            slot.configure(suggestions.indices.contains(index) ? suggestions[index] : nil, theme: theme)
        }
        if emoji != self.emoji.map(\.emoji) {
            self.emoji.forEach { $0.removeFromSuperview() }
            self.emoji = emoji.enumerated().map { index, emoji in
                let pick = EmojiPick(emoji: emoji, index: index)
                pick.addAction(UIAction { [unowned self] _ in onEmoji(emoji) }, for: .touchUpInside)
                pick.onHighlight = { [unowned self] in refreshDividers() }
                addSubview(pick)
                return pick
            }
            setNeedsLayout()
        }
        self.emoji.forEach { $0.theme = theme }
        snippets.tintColor = theme.candidate.ui
        dividers.forEach { $0.backgroundColor = theme.candidateDivider.ui }
        refresh()
    }

    /// `notice` (why voice couldn't start, or a source's hint) stands in for the suggestions. Tapping it dismisses it.
    func update(mic: MicButton.Phase, notice: String?, theme: KeyboardTheme) {
        self.mic.show(mic, theme: theme)
        self.notice.text = notice
        self.notice.textColor = theme.candidate.ui
        noticed = notice != nil
        refresh()
    }

    func hear(_ level: Float) {
        mic.hear(level)
    }

    @objc private func tapNotice() {
        onNotice()
    }

    private func refresh() {
        notice.isHidden = !noticed
        slots.forEach { $0.isHidden = !enabled || noticed }
        emoji.forEach { $0.isHidden = !enabled || noticed }
        if !emoji.isEmpty { slots[slots.count - 1].isHidden = true }
        refreshDividers()
    }

    /// A divider shows only between two things shown without a pill.
    private func refreshDividers() {
        func hidesDivider(_ index: Int, leading: Bool) -> Bool {
            if index == slots.count { return !showsMic || mic.showsPill }
            if index == slots.count - 1, let pick = leading ? emoji.first : emoji.last { return pick.isHidden || pick.isHighlighted }
            return slots[index].isHidden || slots[index].showsPill
        }
        for (index, divider) in dividers.enumerated() {
            divider.isHidden = hidesDivider(index, leading: false) || hidesDivider(index + 1, leading: true)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        point.y < bounds.height - Self.gap && super.point(inside: point, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        let content = bounds.inset(by: UIEdgeInsets(top: topPadding, left: 0, bottom: 0, right: 0))
        let mic = CGRect(x: bounds.width - keyInset + MicButton.pillInset - MicButton.width, y: content.minY, width: MicButton.width, height: content.height)
        let end = showsMic ? mic.minX : bounds.width
        // The snippets button mirrors the mic at the left end; the slots share what's between.
        let begin = showsSnippets ? keyInset - MicButton.pillInset + MicButton.width : 0
        snippets.frame = CGRect(x: begin - MicButton.width, y: content.minY, width: MicButton.width, height: content.height)
        let width = min((end - begin) / CGFloat(slots.count), maximumSlotWidth)
        let start = max(begin, min(bounds.midX - width * CGFloat(slots.count) / 2, end - width * CGFloat(slots.count)))
        for (index, slot) in slots.enumerated() {
            let minX = (start + CGFloat(index) * width).rounded(scale: scale)
            let maxX = (start + CGFloat(index + 1) * width).rounded(scale: scale)
            slot.frame = CGRect(x: minX, y: content.minY, width: maxX - minX, height: content.height)
        }
        self.mic.frame = mic
        let last = slots[slots.count - 1].frame
        let pitch = min(last.width / CGFloat(max(emoji.count, 1)), EmojiPick.pitch)
        let first = last.midX - pitch * CGFloat(emoji.count) / 2
        for (index, pick) in emoji.enumerated() {
            let left = (first + CGFloat(index) * pitch).rounded(scale: scale)
            let glyph = CGRect(x: left, y: 0, width: (first + CGFloat(index + 1) * pitch).rounded(scale: scale) - left, height: content.height)
            let minX = index == 0 ? last.minX : glyph.minX
            let maxX = index == emoji.count - 1 ? last.maxX : glyph.maxX
            pick.frame = CGRect(x: minX, y: content.minY, width: maxX - minX, height: content.height)
            pick.glyph = glyph.offsetBy(dx: -pick.frame.minX, dy: 0)
        }
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(x: slots[index].frame.maxX - 1, y: content.midY - 12, width: 1, height: 24)
        }
        notice.frame = CGRect(x: max(12, begin), y: content.minY, width: end - max(12, begin) - 4, height: content.height)
    }
}

/// The bar's mic: a glyph, filled while the app keeps the microphone on, and a red pill whose bars move with your voice
/// while it listens. Tap to start or stop, hold to turn the microphone off.
final class MicButton: UIControl {
    enum Phase { case off, on, listening, transcribing }

    static let width: CGFloat = 52
    static let pillInset: CGFloat = 8 / 3
    static let pillHeight: CGFloat = 30

    var onHold: () -> Void = {}
    var onHighlight: () -> Void = {}
    private(set) var phase = Phase.off
    var showsPill: Bool { !pill.isHidden }
    private let pill = UIView()
    private let glyph = UIImageView()
    private let bars = (0..<5).map { _ in UIView() }
    private var levels = [CGFloat](repeating: 0, count: 5)
    private var theme = KeyboardTheme.lightCurrent

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hex.mic"
        isAccessibilityElement = true
        accessibilityTraits = .button
        pill.isUserInteractionEnabled = false
        glyph.isUserInteractionEnabled = false
        glyph.contentMode = .center
        addSubview(pill)
        addSubview(glyph)
        for bar in bars {
            bar.isUserInteractionEnabled = false
            bar.backgroundColor = .white
            pill.addSubview(bar)
        }
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
        hold.minimumPressDuration = 0.5
        addGestureRecognizer(hold)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            refresh()
            onHighlight()
        }
    }

    func show(_ phase: Phase, theme: KeyboardTheme) {
        if phase != .listening { levels = levels.map { _ in 0 } }
        self.phase = phase
        self.theme = theme
        accessibilityLabel = phase == .on || phase == .off ? "Dictate" : "Stop Dictating"
        accessibilityValue = phase == .on ? "Mic On" : nil
        refresh()
    }

    /// Each level the app publishes enters on the right and pushes the older ones left, so the bars trace your voice.
    func hear(_ level: Float) {
        guard phase == .listening else { return }
        let decibels = 20 * log10(max(level, 1e-6))
        levels = Array(levels.dropFirst()) + [CGFloat(min(max((decibels + 55) / 40, 0), 1))]
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
            self.layoutBars()
        }
    }

    private func refresh() {
        let recording = phase == .listening || phase == .transcribing
        glyph.image = UIImage(systemName: phase == .on ? "mic.fill" : "mic", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        glyph.isHidden = recording
        glyph.tintColor = theme.candidate.ui
        bars.forEach { $0.isHidden = !recording }
        pill.isHidden = !recording && !isHighlighted
        pill.backgroundColor = recording ? UIColor.systemRed : theme.candidatePill.ui
        pill.alpha = phase == .transcribing ? 0.5 : isHighlighted && recording ? 0.8 : 1
        setNeedsLayout()
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        cancelTracking(with: nil)
        isHighlighted = false
        onHold()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = bounds.insetBy(dx: Self.pillInset, dy: max((bounds.height - Self.pillHeight) / 2, 0))
        pill.layer.cornerRadius = pill.bounds.height / 2
        glyph.frame = bounds
        layoutBars()
    }

    private func layoutBars() {
        let scale = traitCollection.displayScale
        let width: CGFloat = 3
        let gap: CGFloat = 3
        let total = CGFloat(bars.count) * width + CGFloat(bars.count - 1) * gap
        let tallest = min(pill.bounds.height - 10, 18)
        for (index, bar) in bars.enumerated() {
            let height = (width + (tallest - width) * levels[index]).rounded(scale: scale)
            let x = ((pill.bounds.width - total) / 2 + CGFloat(index) * (width + gap)).rounded(scale: scale)
            bar.frame = CGRect(x: x, y: ((pill.bounds.height - height) / 2).rounded(scale: scale), width: width, height: height)
            bar.layer.cornerRadius = width / 2
        }
    }
}

/// One emoji in the bar's last slot: a tap types it in place of the word. The outer ones also take the slot's
/// margins, so the whole slot answers a tap.
private final class EmojiPick: UIControl {
    static let pitch: CGFloat = 44
    let emoji: String
    var glyph = CGRect.zero { didSet { setNeedsLayout() } }
    var onHighlight: () -> Void = {}
    var theme = KeyboardTheme.lightCurrent { didSet { pill.backgroundColor = theme.candidatePill.ui } }
    private let label = UILabel()
    private let pill = UIView()

    init(emoji: String, index: Int) {
        self.emoji = emoji
        super.init(frame: .zero)
        accessibilityIdentifier = "hex.suggestion.emoji.\(index)"
        accessibilityLabel = emoji
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        pill.isUserInteractionEnabled = false
        pill.isHidden = true
        label.text = emoji
        label.font = .systemFont(ofSize: 24)
        label.textAlignment = .center
        addSubview(pill)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            pill.isHidden = !isHighlighted
            onHighlight()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = glyph.insetBy(dx: MicButton.pillInset, dy: 0)
        pill.layer.cornerRadius = min(pill.bounds.width, pill.bounds.height) / 2
        label.frame = glyph
    }
}

private final class SuggestionSlot: UIControl {
    private(set) var suggestion: Suggestion?
    var onHighlight: () -> Void = {}
    private let label = UILabel()
    private let pill = UIView()
    private var theme = KeyboardTheme.lightCurrent

    init(index: Int) {
        super.init(frame: .zero)
        accessibilityIdentifier = "hex.suggestion.\(index)"
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        pill.isUserInteractionEnabled = false
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 17)
        addSubview(pill)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Apple's pills stop 8px (@3x) short of each slot's edge, so neighbors sit 16px apart and the outer ones keep
    /// clear of the keyboard's edge (iOS 27 simulator, held suggestions).
    private static let pillInset: CGFloat = 8 / 3

    var showsPill: Bool { suggestion != nil && (suggestion?.kind == .correction || isHighlighted) }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            refresh()
            onHighlight()
        }
    }

    func configure(_ suggestion: Suggestion?, theme: KeyboardTheme) {
        self.suggestion = suggestion
        self.theme = theme
        label.text = suggestion?.title
        accessibilityLabel = suggestion?.text
        refresh()
        setNeedsLayout()
    }

    private func refresh() {
        pill.isHidden = !showsPill
        pill.backgroundColor = theme.candidatePill.ui
        label.textColor = showsPill ? theme.candidateHighlighted.ui : theme.candidate.ui
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = bounds.insetBy(dx: Self.pillInset, dy: 0)
        pill.layer.cornerRadius = bounds.height / 2
        guard let font = label.font else { return }
        let baseline = (bounds.midY + font.capHeight / 2).rounded(scale: traitCollection.displayScale)
        let width = min(label.intrinsicContentSize.width, bounds.width - 8)
        label.frame = CGRect(x: (bounds.width - width) / 2, y: baseline - font.ascender, width: width, height: font.lineHeight)
    }
}

extension CGFloat {
    func rounded(scale: CGFloat) -> CGFloat { (self * scale).rounded() / scale }
}
