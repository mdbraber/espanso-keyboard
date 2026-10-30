import UIKit
import KeyboardCore

/// The panel a held key opens, picked by sliding: a key's accents, or the layer key's one-handed layouts and languages.
final class AlternatesView: UIView {
    private let panel = UIView()
    private let highlight = UIView()
    private var labels: [UILabel] = []
    private var highlightHeight: CGFloat = 0
    private let padding: CGFloat = 10
    private var labelColor = UIColor.black
    private var selectedLabelColor = UIColor.white
    private(set) var selection = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        panel.layer.cornerCurve = .continuous
        panel.layer.shadowOffset = CGSize(width: 0, height: 2)
        panel.layer.shadowRadius = 8
        panel.layer.shadowOpacity = 1
        highlight.layer.cornerCurve = .continuous
        addSubview(panel)
        panel.addSubview(highlight)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `selected` sits right above `key`, so letting go without sliding picks it.
    func show(_ options: [String], selected: Int, over key: CGRect, in area: CGRect, metrics: KeyboardMetrics, theme: KeyboardTheme) {
        let font = KeyboardFont.letter(metrics.letterSize)
        let cell = CGSize(width: key.width + 4, height: key.height * 1.57)
        present(options.map { NSAttributedString(string: $0, attributes: [.font: font]) }, selected: selected, cell: cell,
                highlightHeight: key.height + 4, over: key, in: area, metrics: metrics, theme: theme)
    }

    enum MenuChoice {
        case symbol(String), text(String)
    }

    func show(menu choices: [MenuChoice], selected: Int, over key: CGRect, in area: CGRect, metrics: KeyboardMetrics, theme: KeyboardTheme) {
        let configuration = UIImage.SymbolConfiguration(pointSize: metrics.symbolSize, weight: .regular)
        let font = UIFont.systemFont(ofSize: metrics.labelSize, weight: .regular)
        let images = choices.map { choice in
            switch choice {
            case .symbol(let name):
                NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: name, withConfiguration: configuration) ?? UIImage()))
            case .text(let text):
                NSAttributedString(string: text, attributes: [.font: font])
            }
        }
        let cell = CGSize(width: 50, height: key.height + 18)
        present(images, selected: selected, cell: cell, highlightHeight: key.height + 2, over: key, in: area, metrics: metrics, theme: theme)
    }

    private func present(_ contents: [NSAttributedString], selected: Int, cell: CGSize, highlightHeight: CGFloat, over key: CGRect, in area: CGRect, metrics: KeyboardMetrics, theme: KeyboardTheme) {
        labels.forEach { $0.removeFromSuperview() }
        let width = cell.width * CGFloat(contents.count) + padding * 2
        let x = key.midX - padding - cell.width * (CGFloat(selected) + 0.5)
        frame = CGRect(x: min(max(x, area.minX + 7), area.maxX - width - 7), y: max(key.minY - cell.height - 3, area.minY + 1), width: width, height: cell.height)
        self.highlightHeight = highlightHeight
        panel.frame = bounds
        panel.layer.cornerRadius = metrics.cornerRadius * 2
        panel.layer.shadowPath = UIBezierPath(roundedRect: panel.bounds, cornerRadius: panel.layer.cornerRadius).cgPath
        panel.backgroundColor = theme.key.ui
        panel.layer.shadowColor = theme.shadow.ui.cgColor
        highlight.backgroundColor = theme.selection.ui
        highlight.layer.cornerRadius = metrics.cornerRadius * 1.25
        labelColor = theme.label.ui
        selectedLabelColor = theme.selectionLabel.ui
        labels = contents.enumerated().map { index, content in
            let label = UILabel(frame: CGRect(x: padding + CGFloat(index) * cell.width, y: 0, width: cell.width, height: cell.height))
            label.attributedText = content
            label.textAlignment = .center
            panel.addSubview(label)
            return label
        }
        isHidden = false
        select(selected)
    }

    func track(_ point: CGPoint) {
        guard !labels.isEmpty else { return }
        let width = (bounds.width - padding * 2) / CGFloat(labels.count)
        select(min(max(Int((point.x - frame.minX - padding) / width), 0), labels.count - 1))
    }

    func hide() {
        isHidden = true
        labels.forEach { $0.removeFromSuperview() }
        labels = []
    }

    private func select(_ index: Int) {
        selection = index
        for (other, label) in labels.enumerated() {
            label.textColor = other == index ? selectedLabelColor : labelColor
        }
        let cell = labels[index].frame
        highlight.frame = CGRect(x: cell.minX, y: cell.midY - highlightHeight / 2, width: cell.width, height: highlightHeight)
    }
}
