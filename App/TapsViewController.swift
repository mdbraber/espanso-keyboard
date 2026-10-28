import KeyboardCore
import KeyboardUI
import UIKit
import notify

final class TapsViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stats = UIStackView()
    private let modes = UISegmentedControl(items: ["Heat", "Aim", "Accuracy"])
    private let map = TapMapView()
    private let scale = HeatScale()
    private let legend = UILabel()
    private let detail = KeyDetailView()
    private let pullHeader = UILabel()
    private let pull = TapPullView()
    private let pullCaption = UILabel()
    private let missedHeader = UILabel()
    private let missed = UIStackView()
    private let empty = UILabel()
    private var touches = TouchModel()
    private var signature: String?
    private var observer: Int32 = 0

    private static let modeOrder: [TapMapView.Mode] = [.heat, .aim, .accuracy]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your Taps"
        view.backgroundColor = .systemBackground

        stats.axis = .vertical
        stats.spacing = 16

        modes.selectedSegmentIndex = 0
        modes.addAction(UIAction { [unowned self] _ in
            map.mode = Self.modeOrder[modes.selectedSegmentIndex]
            updateLegend()
        }, for: .valueChanged)

        map.onSelect = { [unowned self] aim in
            showDetail(aim)
        }

        legend.numberOfLines = 0
        legend.font = .preferredFont(forTextStyle: .footnote)
        legend.textColor = .secondaryLabel

        for header in [pullHeader, missedHeader] {
            header.font = .preferredFont(forTextStyle: .headline)
        }
        pullHeader.text = "How your thumbs pull"
        pullCaption.numberOfLines = 0
        pullCaption.font = .preferredFont(forTextStyle: .footnote)
        pullCaption.textColor = .secondaryLabel

        missedHeader.text = "Most missed"
        missed.axis = .vertical
        missed.spacing = 10

        empty.numberOfLines = 0
        empty.textAlignment = .center
        empty.font = .preferredFont(forTextStyle: .body)
        empty.textColor = .secondaryLabel
        empty.text = "Type with Hex anywhere, and your taps show up here each time the keyboard closes.\n\nHex needs Allow Full Access to share them with this app."

        let top = Self.column([stats, modes], spacing: 20)
        let bottom = Self.column([scale, legend, detail, pullHeader, pull, pullCaption, missedHeader, missed, empty], spacing: 12)
        bottom.setCustomSpacing(8, after: scale)
        bottom.setCustomSpacing(20, after: legend)
        bottom.setCustomSpacing(32, after: detail)
        bottom.setCustomSpacing(32, after: pullCaption)
        let stack = UIStackView(arrangedSubviews: [top, map, bottom])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(12, after: map)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.addSubview(stack)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])

        observer = MemoryStore.observeTouches { [weak self] in self?.reload() }
        NotificationCenter.default.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        updateLegend()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        reload()
        applyLaunchOptions()
    }

    deinit {
        notify_cancel(observer)
    }

    private static func column(_ views: [UIView], spacing: CGFloat) -> UIStackView {
        let column = UIStackView(arrangedSubviews: views)
        column.axis = .vertical
        column.spacing = spacing
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        return column
    }

    private func reload() {
        touches = MemoryStore.sharedTouches() ?? TouchModel()
        let layouts = touches.signatures.filter { LayoutContext(signature: $0.signature) != nil }
        if signature.map({ name in !layouts.contains { $0.signature == name } }) ?? true { signature = layouts.first?.signature }
        navigationItem.rightBarButtonItem = layouts.count > 1 ? UIBarButtonItem(title: "Layout", image: UIImage(systemName: "keyboard"), menu: UIMenu(children: layouts.map { layout in
            UIAction(title: Self.title(of: layout.signature), subtitle: "\(layout.taps.formatted()) taps", state: layout.signature == signature ? .on : .off) { [unowned self] _ in
                signature = layout.signature
                reload()
            }
        })) : nil
        let hasTaps = signature != nil
        [stats, modes, map, legend, pullHeader, pull, pullCaption, missedHeader, missed].forEach { $0.isHidden = !hasTaps }
        empty.isHidden = hasTaps
        detail.isHidden = true
        guard let signature, let context = LayoutContext(signature: signature) else { return updateLegend() }
        map.show(touches, on: context, screen: view.window?.windowScene?.screen.bounds.size ?? view.bounds.size)
        showStats()
        showPull()
        showMissed()
        showDetail(map.selected)
    }

    private func applyLaunchOptions() {
        if let mode = LaunchOptions.tapsMode {
            modes.selectedSegmentIndex = Self.modeOrder.firstIndex(of: mode) ?? 0
            map.mode = mode
        }
        if let label = LaunchOptions.tapsKey, let aim = map.aims.first(where: { $0.key.label == label }) { map.select(aim) }
        updateLegend()
        guard let target = LaunchOptions.tapsScroll else { return }
        view.layoutIfNeeded()
        let anchor: UIView = target == "detail" ? detail : missed
        let frame = anchor.convert(anchor.bounds, to: scroll)
        let bottom = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
        scroll.contentOffset.y = min(max(frame.minY - scroll.adjustedContentInset.top - 60, -scroll.adjustedContentInset.top), bottom)
    }

    private static func title(of signature: String) -> String {
        guard let context = LayoutContext(signature: signature) else { return signature }
        let device = context.device == .phone ? "iPhone" : "iPad"
        let hand = switch context.oneHanded {
        case .left: ", left hand"
        case .right: ", right hand"
        case .off: ""
        }
        return "\(device), \(context.isLandscape ? "landscape" : "portrait")\(hand)"
    }

    private func showStats() {
        let taps = map.aims.reduce(0) { $0 + $1.taps }
        let letters = map.aims.filter { $0.key.label != " " }
        let weight = Double(max(letters.reduce(0) { $0 + $1.taps }, 1))
        let onTarget = letters.reduce(0.0) { $0 + Double($1.taps) * $1.onTarget } / weight
        let drift = letters.reduce(0.0) { $0 + Double($1.taps) * hypot($1.drift.x, $1.drift.y) } / weight
        let recent = letters.flatMap { aim in aim.recent.map { $0.landed == aim.key } }
        let lately = recent.isEmpty ? nil : Double(recent.count(where: \.self)) / Double(recent.count)
        stats.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let tiles = [
            StatView(value: taps.formatted(), caption: "taps learned"),
            StatView(value: TapMapPalette.percent(onTarget), caption: "of your letter taps land on the key you meant"),
            StatView(value: lately.map { TapMapPalette.percent($0) } ?? "–", caption: "on target in your last \(recent.count.formatted()) letter taps"),
            StatView(value: String(format: "%.1f pt", drift), caption: "from a letter’s center to where you aim, on average"),
        ]
        for pair in [tiles[0...1], tiles[2...3]] {
            let row = UIStackView(arrangedSubviews: Array(pair))
            row.distribution = .fillEqually
            row.spacing = 12
            row.alignment = .top
            stats.addArrangedSubview(row)
        }
    }

    private func showPull() {
        let letters = map.aims.filter { $0.key.label != " " && $0.taps > 0 }
        guard let middle = letters.map(\.frame.midX).max().map({ ($0 + (letters.map(\.frame.midX).min() ?? 0)) / 2 }) else { return }
        pull.show(map.aims, keys: map.keys, size: map.keyboardSize)
        let sides = [("left", letters.filter { $0.frame.midX < middle }), ("right", letters.filter { $0.frame.midX >= middle })].map { name, aims in
            let taps = Double(max(aims.reduce(0) { $0 + $1.taps }, 1))
            let x = aims.reduce(0.0) { $0 + Double($1.taps) * $1.drift.x } / taps
            let y = aims.reduce(0.0) { $0 + Double($1.taps) * $1.drift.y } / taps
            return "On the \(name) half you tap \(Self.describe((x, y)))."
        }
        let space = map.aims.first { $0.key.label == " " && $0.taps >= 10 }.map { " You hit the space bar \(Self.describe($0.drift)) of its center." } ?? ""
        pullCaption.text = "Each arrow points from a letter’s center to where you really tap it, drawn \(Int(TapPullView.magnification))× longer so you can see it. "
            + sides.joined(separator: " ") + space
    }

    static func describe(_ drift: (x: Double, y: Double)) -> String {
        let parts = [
            abs(drift.x) >= 0.5 ? String(format: "%.1f pt %@", abs(drift.x), drift.x < 0 ? "left" : "right") : nil,
            abs(drift.y) >= 0.5 ? String(format: "%.1f pt %@", abs(drift.y), drift.y < 0 ? "high" : "low") : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "right on center" : parts.joined(separator: " and ")
    }

    private func showMissed() {
        missed.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let worst = map.aims.filter { $0.taps >= 10 }.sorted { $0.onTarget < $1.onTarget }.prefix(5)
        missedHeader.isHidden = worst.isEmpty
        for aim in worst {
            let row = MissRow(aim: aim, worst: 1 - (worst.first?.onTarget ?? 0))
            row.addAction(UIAction { [unowned self] _ in
                map.select(aim)
                scroll.scrollRectToVisible(map.convert(map.bounds, to: scroll).union(detail.convert(detail.bounds, to: scroll)), animated: true)
            }, for: .touchUpInside)
            missed.addArrangedSubview(row)
        }
    }

    private func showDetail(_ aim: Aim?) {
        detail.isHidden = aim == nil
        if let aim { detail.show(aim, keys: map.keys) }
        updateLegend()
    }

    private func updateLegend() {
        scale.isHidden = map.mode != .heat || signature == nil
        legend.text = switch (map.mode, map.selected) {
        case (.heat, nil):
            "Where your thumbs press: every key’s taps, spread the way they really land. Tap a key for a close-up."
        case (.heat, _?):
            "Where your thumbs press. Tap the outlined key again to go back."
        case (.aim, _):
            "Each dot is one of your recent taps. The ring holds half of all your taps for that key, and the line runs from the key’s center to where you really aim."
        case (.accuracy, nil):
            "How often a tap lands on the key you meant, judged by where it lands alone, before Hex looks at the word. Tap a key to see where its taps go."
        case (.accuracy, let aim?):
            "Where your taps for “\(TapMapPalette.name(of: aim.key))” land. Tap it again to go back."
        }
    }
}

/// The heat map's ramp, from the fewest taps to the most.
private final class HeatScale: UIView {
    private let ramp = HeatRamp()
    private let fewer = UILabel()
    private let more = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for (label, text) in [(fewer, "fewer taps"), (more, "more")] {
            label.text = text
            label.font = .preferredFont(forTextStyle: .caption2)
            label.textColor = .secondaryLabel
            label.setContentHuggingPriority(.required, for: .horizontal)
        }
        let row = UIStackView(arrangedSubviews: [fewer, ramp, more])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            ramp.heightAnchor.constraint(equalToConstant: 6),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Density from none to the most anywhere on the keyboard, colored as the heat map colors it.
private final class HeatRamp: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.setNeedsDisplay() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let isDark = traitCollection.userInterfaceStyle == .dark
        UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).addClip()
        TapMapPalette.backdrop.setFill()
        UIRectFill(bounds)
        for x in stride(from: 0, to: bounds.width, by: 1) {
            TapHeat.color(at: (Double(x) / Double(bounds.width)).squareRoot(), isDark: isDark).setFill()
            UIRectFill(CGRect(x: x, y: 0, width: 1, height: bounds.height))
        }
    }
}

private final class StatView: UIView {
    init(value: String, caption: String) {
        super.init(frame: .zero)
        let number = UILabel()
        number.text = value
        number.font = UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
        number.adjustsFontSizeToFitWidth = true
        number.minimumScaleFactor = 0.6
        let label = UILabel()
        label.text = caption
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [number, label])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class Keycap: UILabel {
    init(_ key: Key, size: CGFloat) {
        super.init(frame: .zero)
        text = TapMapPalette.name(of: key)
        textAlignment = .center
        font = .systemFont(ofSize: key.label?.count == 1 && key.label != " " ? size : size * 0.6)
        backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : .white }
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1 / 3
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// One key up close: how many taps, where you aim, its last taps around it, how its aim follows you, and where its
/// taps land.
private final class KeyDetailView: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ aim: Aim, keys: [(key: Key, frame: Rect)]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let name = TapMapPalette.name(of: aim.key)
        let cap = Keycap(aim.key, size: 24)
        let taps = UILabel()
        taps.text = aim.taps == 1 ? "1 tap" : "\(aim.taps.formatted()) taps"
        taps.font = .preferredFont(forTextStyle: .headline)
        let where_ = UILabel()
        let aimed = TapsViewController.describe(aim.drift)
        where_.text = aimed == "right on center" ? "You aim at its center." : "You aim \(aimed) of its center."
        where_.font = .preferredFont(forTextStyle: .subheadline)
        where_.textColor = .secondaryLabel
        where_.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [taps, where_])
        text.axis = .vertical
        text.spacing = 2
        let header = UIStackView(arrangedSubviews: [cap, text])
        header.spacing = 12
        header.alignment = .center
        NSLayoutConstraint.activate([cap.widthAnchor.constraint(equalToConstant: 44), cap.heightAnchor.constraint(equalToConstant: 48)])
        stack.addArrangedSubview(header)

        let closeUp = TapCloseUpView()
        closeUp.show(aim, keys: keys)
        stack.addArrangedSubview(closeUp)
        if !aim.recent.isEmpty {
            let hits = aim.recent.count(where: { $0.landed == aim.key })
            let strays = Dictionary(grouping: aim.recent.compactMap { $0.landed == aim.key ? nil : $0.landed }, by: \.self)
                .sorted { $0.value.count > $1.value.count }
                .map { "\(TapMapPalette.name(of: $0.key)) \($0.value.count)" }
            stack.addArrangedSubview(Self.legend([
                (.hit, tintColor, "\(hits) of your last \(aim.recent.count) landed on \(name)"),
                (.miss, TapMapPalette.miss, strays.isEmpty ? "none landed elsewhere" : "elsewhere: " + strays.joined(separator: ", ")),
            ]))
        }
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        stack.addArrangedSubview(Self.title("How \(name) follows you"))
        let memories = [("all \(aim.taps.formatted()) taps", 0), ("about the last 30", 1), ("about the last 3", 2)]
        stack.addArrangedSubview(WeightBar(weights: aim.memories.map(\.weight)))
        stack.addArrangedSubview(Self.legend(memories.map { label, index in
            (.memory(index), .label, "\(label) \(TapMapPalette.percent(aim.memories[index].weight))")
        } + [(.aim, tintColor, "where \(name) aims: their blend")]))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        stack.addArrangedSubview(Self.title("Where \(name)’s taps land"))
        let shares = Self.folded(aim)
        stack.addArrangedSubview(ShareBar(shares: shares))
        let lands = UILabel()
        lands.numberOfLines = 0
        lands.font = .preferredFont(forTextStyle: .footnote)
        lands.textColor = .secondaryLabel
        lands.text = shares.map { "\($0.name) \(TapMapPalette.percent($0.share))" }.joined(separator: " · ")
        stack.addArrangedSubview(lands)
    }

    private static func title(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        return label
    }

    /// Glyphs drawn as the close-up draws them, each beside what it marks.
    private static func legend(_ items: [(glyph: TapGlyph, color: UIColor, text: String)]) -> UIStackView {
        let rows = items.map { item in
            let glyph = UIImageView(image: item.glyph.image(color: item.color, surface: .secondarySystemBackground))
            glyph.setContentHuggingPriority(.required, for: .horizontal)
            let label = UILabel()
            label.text = item.text
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = .secondaryLabel
            let row = UIStackView(arrangedSubviews: [glyph, label])
            row.spacing = 8
            row.alignment = .center
            return row
        }
        let column = UIStackView(arrangedSubviews: rows)
        column.axis = .vertical
        column.spacing = 4
        return column
    }

    /// The key itself, its three biggest misses, and the rest as one.
    private static func folded(_ aim: Aim) -> [(name: String, share: Double, isTarget: Bool)] {
        let misses = aim.landing.filter { $0.key != aim.key }
        var shares = [(name: TapMapPalette.name(of: aim.key), share: aim.onTarget, isTarget: true)]
        shares += misses.prefix(3).filter { $0.share >= 0.005 }.map { (TapMapPalette.name(of: $0.key), $0.share, false) }
        let rest = 1 - shares.reduce(0) { $0 + $1.share }
        if rest >= 0.005 { shares.append(("other", rest, false)) }
        return shares
    }
}

/// How much the key's aim leans on each memory, all taps first, in one bar.
private final class WeightBar: UIView {
    private let weights: [Double]

    init(weights: [Double]) {
        self.weights = weights
        super.init(frame: .zero)
        isOpaque = false
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 12).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let gap: CGFloat = 2
        let available = bounds.width - gap * CGFloat(weights.count - 1)
        var x: CGFloat = 0
        for (index, weight) in weights.enumerated() {
            let width = max(available * weight, 3)
            UIColor.label.withAlphaComponent([0.75, 0.45, 0.22][index]).setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: 0, width: min(width, bounds.width - x), height: bounds.height), cornerRadius: 4).fill()
            x += width + gap
        }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont(descriptor: fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]]), size: 0)
    }
}

private final class ShareBar: UIView {
    private let shares: [(name: String, share: Double, isTarget: Bool)]

    init(shares: [(name: String, share: Double, isTarget: Bool)]) {
        self.shares = shares
        super.init(frame: .zero)
        isOpaque = false
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 12).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let gap: CGFloat = 2
        let available = bounds.width - gap * CGFloat(shares.count - 1)
        var x: CGFloat = 0
        for (index, item) in shares.enumerated() {
            let width = max(available * item.share, 3)
            let segment = CGRect(x: x, y: 0, width: min(width, bounds.width - x), height: bounds.height)
            (item.isTarget ? tintColor : TapMapPalette.miss.withAlphaComponent(index == shares.count - 1 && item.name == "other" ? 0.4 : 0.85))?.setFill()
            UIBezierPath(roundedRect: segment, cornerRadius: 4).fill()
            x += width + gap
        }
    }
}

/// A key that often misses: where its stray taps go, and how many stray.
private final class MissRow: UIControl {
    init(aim: Aim, worst: Double) {
        super.init(frame: .zero)
        let miss = 1 - aim.onTarget
        let neighbor = aim.landing.first { $0.key != aim.key }
        let cap = Keycap(aim.key, size: 18)
        cap.isUserInteractionEnabled = false
        let arrow = UILabel()
        arrow.text = neighbor.map { "mostly onto \(TapMapPalette.name(of: $0.key))" } ?? ""
        arrow.font = .preferredFont(forTextStyle: .subheadline)
        arrow.textColor = .secondaryLabel
        let value = UILabel()
        value.text = "\(TapMapPalette.percent(miss)) miss"
        value.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        value.setContentHuggingPriority(.required, for: .horizontal)
        let track = MissTrack(fraction: miss / worst)
        let middle = UIStackView(arrangedSubviews: [arrow, track])
        middle.axis = .vertical
        middle.spacing = 6
        let row = UIStackView(arrangedSubviews: [cap, middle, value])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            cap.widthAnchor.constraint(equalToConstant: 34), cap.heightAnchor.constraint(equalToConstant: 38),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(TapMapPalette.name(of: aim.key)), \(TapMapPalette.percent(miss)) miss, \(arrow.text ?? "")"
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.5 : 1 } }
}

/// How much of a key's taps stray, against a full track for the key that strays most.
private final class MissTrack: UIView {
    private let fraction: Double

    init(fraction: Double) {
        self.fraction = fraction
        super.init(frame: .zero)
        isOpaque = false
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        UIColor.tertiarySystemFill.setFill()
        UIBezierPath(roundedRect: bounds, cornerRadius: 3).fill()
        TapMapPalette.miss.setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: max(bounds.width * fraction, 6), height: bounds.height), cornerRadius: 3).fill()
    }
}
