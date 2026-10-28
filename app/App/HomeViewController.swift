import UIKit

final class HomeViewController: UITableViewController {
    private enum Row {
        case status, field, settings, fullAccess
    }

    private struct Section {
        var title: String?
        var footer: String?
        var rows: [Row]
    }

    private let sections = [
        Section(footer: "Hex only goes online to reach the sources you add in Keyboard Settings. Without one, what you type and say stays on this iPhone.", rows: [.status]),
        Section(title: "Try It", rows: [.field]),
        Section(footer: "Full Access lets Hex play haptics, type what you say, and show you where your taps land.", rows: [.settings, .fullAccess]),
    ]

    private let field = UITextView()
    private let fieldCell = UITableViewCell()
    private var isAdded = HomeViewController.keyboardIsAdded

    /// The keyboards in Settings › General › Keyboard › Keyboards, read from the global defaults iOS keeps them in.
    private static var keyboardIsAdded: Bool {
        (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] ?? []).contains((Bundle.main.bundleIdentifier ?? "") + ".keyboard")
    }

    init() {
        super.init(style: .insetGrouped)
        title = "Hex"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .always
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(StatusCell.self, forCellReuseIdentifier: "status")
        tableView.keyboardDismissMode = .interactive

        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .clear
        field.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        field.accessibilityLabel = "Try Hex"
        LaunchOptions.configure(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        fieldCell.selectionStyle = .none
        fieldCell.contentView.addSubview(field)
        let margins = fieldCell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: fieldCell.contentView.topAnchor),
            field.bottomAnchor.constraint(equalTo: fieldCell.contentView.bottomAnchor),
            field.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            field.heightAnchor.constraint(equalToConstant: 120),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let orientation = LaunchOptions.orientation {
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
        if LaunchOptions.focus { field.becomeFirstResponder() }
    }

    @objc private func refreshStatus() {
        let added = Self.keyboardIsAdded
        guard added != isAdded else { return }
        isAdded = added
        tableView.reconfigureRows(at: [IndexPath(row: 0, section: 0)])
    }

    func showSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: false)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        row(at: indexPath) != .field
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch row(at: indexPath) {
        case .status, .fullAccess: UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        case .settings: navigationController?.pushViewController(SettingsViewController(), animated: true)
        case .field: break
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch row(at: indexPath) {
        case .field:
            return fieldCell
        case .status:
            let cell = tableView.dequeueReusableCell(withIdentifier: "status", for: indexPath) as! StatusCell
            cell.show(isAdded: isAdded)
            return cell
        case .settings, .fullAccess:
            break
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.cell()
        cell.accessoryType = .disclosureIndicator
        if row(at: indexPath) == .settings {
            content.image = UIImage(systemName: "gearshape")
            content.text = "Keyboard Settings"
        } else {
            content.image = UIImage(systemName: "lock.open")
            content.text = "Allow Full Access"
        }
        cell.contentConfiguration = content
        return cell
    }

    private func row(at indexPath: IndexPath) -> Row {
        sections[indexPath.section].rows[indexPath.row]
    }
}

/// Hex's mark beside whether the keyboard is turned on, like the account card atop Settings.
private final class StatusCell: UITableViewCell {
    private let mark = HexMark()
    private let name = UILabel()
    private let state = UILabel()
    private let symbol = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        name.text = "Hex Keyboard"
        name.font = .preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        name.adjustsFontForContentSizeCategory = true
        state.font = .preferredFont(forTextStyle: .subheadline)
        state.adjustsFontForContentSizeCategory = true
        state.numberOfLines = 0
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline)
        symbol.setContentHuggingPriority(.required, for: .horizontal)
        symbol.setContentCompressionResistancePriority(.required, for: .horizontal)
        let line = UIStackView(arrangedSubviews: [symbol, state])
        line.spacing = 5
        line.alignment = .firstBaseline
        let text = UIStackView(arrangedSubviews: [name, line])
        text.axis = .vertical
        text.spacing = 3
        let row = UIStackView(arrangedSubviews: [mark, text])
        row.spacing = 16
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 64),
            mark.heightAnchor.constraint(equalTo: mark.widthAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            row.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(isAdded: Bool) {
        accessoryType = isAdded ? .none : .disclosureIndicator
        symbol.image = UIImage(systemName: isAdded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        symbol.tintColor = isAdded ? .systemGreen : .systemOrange
        state.text = isAdded ? "Turned on" : "Turn it on in Settings › Keyboards"
        state.textColor = isAdded ? .secondaryLabel : .label
    }
}

/// The app icon's mark, drawn: a hexagon around five keys, white on near-black in light and dark.
private final class HexMark: UIView {
    private let outline = CAShapeLayer()
    private let keys = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        layer.backgroundColor = UIColor(white: 0.07, alpha: 1).cgColor
        layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        outline.fillColor = nil
        outline.strokeColor = UIColor.white.cgColor
        outline.lineJoin = .round
        keys.fillColor = UIColor.white.cgColor
        layer.addSublayer(outline)
        layer.addSublayer(keys)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = bounds.width
        layer.cornerRadius = side * 0.225
        layer.borderWidth = traitCollection.userInterfaceStyle == .dark ? 1 / traitCollection.displayScale : 0
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = side * 0.31
        let hexagon = UIBezierPath()
        for corner in 0 ..< 6 {
            let angle = CGFloat(corner) * .pi / 3 - .pi / 2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            corner == 0 ? hexagon.move(to: point) : hexagon.addLine(to: point)
        }
        hexagon.close()
        outline.path = hexagon.cgPath
        outline.lineWidth = side * 0.055
        let key = side * 0.052
        let gap = side * 0.082
        let path = UIBezierPath()
        for (row, count) in [3, 2].enumerated() {
            for column in 0 ..< count {
                let x = center.x + (CGFloat(column) - CGFloat(count - 1) / 2) * gap - key / 2
                let y = center.y + (CGFloat(row) - 0.5) * gap - key / 2
                path.append(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: key, height: key), cornerRadius: key * 0.22))
            }
        }
        keys.path = path.cgPath
    }
}

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        UIFont(descriptor: fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor, size: 0)
    }
}
