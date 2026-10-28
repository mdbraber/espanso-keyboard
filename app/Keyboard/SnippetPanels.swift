import EspansoKeyboardCore
import KeyboardUI
import UIKit

/// The panels the keyboard shows above its keys (espanso-keyboard, plan step 6): the snippets to pick from, and the
/// questions a snippet asks. While one is open the keys type into its field (`HexKeyboardViewController.keyCapture`).
class Panel: UIView {
    static let height: CGFloat = 236

    let title = UILabel()
    let close = UIButton(type: .system)
    /// What the keys typed into the panel's field.
    var field = "" { didSet { fieldChanged() } }
    var onClose: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.textColor = .secondaryLabel
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .tertiaryLabel
        close.accessibilityLabel = "Close"
        close.accessibilityIdentifier = "espanso.close"
        close.addAction(UIAction { [unowned self] _ in onClose() }, for: .touchUpInside)
        for view in [title, close] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            close.widthAnchor.constraint(equalToConstant: 36),
            close.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A key typed while the panel is open.
    func key(_ key: HexKeyboardViewController.CapturedKey) {
        switch key {
        case .text(let text): field += text
        case .delete: if !field.isEmpty { field.removeLast() }
        case .return: submit()
        }
    }

    func fieldChanged() {}
    func submit() {}

    /// A list below the title.
    func addList(_ list: UITableView) {
        list.translatesAutoresizingMaskIntoConstraints = false
        list.backgroundColor = .clear
        list.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            list.leadingAnchor.constraint(equalTo: leadingAnchor),
            list.trailingAnchor.constraint(equalTo: trailingAnchor),
            list.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

/// Every snippet the keyboard expands, to search and insert with a tap: favourites first, then each match file's.
final class SnippetPanel: Panel, UITableViewDataSource, UITableViewDelegate {
    private let snippets: [SnippetSummary]
    private let favourites: [String]
    private let usage: [String: EspansoShared.Usage]
    private let list = UITableView(frame: .zero, style: .plain)
    private var sections: [(title: String?, snippets: [SnippetSummary])] = []
    var onPick: (SnippetSummary) -> Void = { _ in }

    init(snippets: [SnippetSummary]) {
        self.snippets = snippets
        favourites = EspansoShared.favourites
        usage = EspansoShared.usage()
        super.init(frame: .zero)
        accessibilityIdentifier = "espanso.snippets"
        list.dataSource = self
        list.delegate = self
        addList(list)
        fieldChanged()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func fieldChanged() {
        title.text = field.isEmpty ? "Type to search snippets" : "Search: \(field)"
        title.textColor = field.isEmpty ? .secondaryLabel : .label
        if field.isEmpty {
            let favourite = favourites.compactMap { key in snippets.first { $0.triggers.first == key } }
            let byFile = Dictionary(grouping: snippets, by: \.file).sorted { $0.key < $1.key }
            sections = (favourite.isEmpty ? [] : [("Favourites", favourite)]) + byFile.map { ($0.key, $0.value) }
        } else {
            let found = snippets
                .compactMap { snippet in
                    Fuzzy.score(field, in: snippet.triggers + [snippet.label]).map { (snippet, $0 + min(usage[snippet.triggers[0]]?.count ?? 0, 10)) }
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
            sections = [(nil, found)]
        }
        list.reloadData()
    }

    override func submit() {
        if let first = sections.first?.snippets.first { onPick(first) }
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].snippets.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let snippet = sections[indexPath.section].snippets[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = snippet.triggers.joined(separator: "  ")
        content.textProperties.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        content.secondaryText = snippet.label
        content.secondaryTextProperties.numberOfLines = 1
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.accessibilityIdentifier = "espanso.snippet.\(snippet.triggers.first ?? "")"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        onPick(sections[indexPath.section].snippets[indexPath.row])
    }
}

/// A `choice` variable: pick one.
final class ChoicePanel: Panel, UITableViewDataSource, UITableViewDelegate {
    private let choices: [ChoiceItem]
    private let list = UITableView(frame: .zero, style: .plain)
    private var shown: [ChoiceItem] = []
    var onChoose: (ChoiceItem) -> Void = { _ in }

    init(choices: [ChoiceItem]) {
        self.choices = choices
        super.init(frame: .zero)
        accessibilityIdentifier = "espanso.choice"
        list.dataSource = self
        list.delegate = self
        addList(list)
        fieldChanged()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func fieldChanged() {
        title.text = field.isEmpty ? "Choose" : "Choose: \(field)"
        shown = field.isEmpty ? choices : choices
            .compactMap { choice in Fuzzy.score(field, in: choice.label).map { (choice, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        list.reloadData()
    }

    override func submit() {
        if let first = shown.first { onChoose(first) }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shown.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.cell()
        content.text = shown[indexPath.row].label
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.accessibilityIdentifier = "espanso.choice.\(shown[indexPath.row].id)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onChoose(shown[indexPath.row])
    }
}

/// A form: one row per field. The keys type into the selected text field; choice fields cycle with a tap.
final class FormPanel: Panel, UITableViewDataSource, UITableViewDelegate {
    private let layout: String
    private let fields: [FormField]
    private var values: [String: String]
    private var selected: Int
    private let list = UITableView(frame: .zero, style: .plain)
    private let insert = UIButton(configuration: .borderedProminent())
    var onSubmit: ([String: String]) -> Void = { _ in }

    init(layout: String, fields: [FormField]) {
        self.layout = layout
        self.fields = fields
        values = Dictionary(fields.map { ($0.name, $0.defaultValue) }, uniquingKeysWith: { first, _ in first })
        selected = fields.firstIndex { if case .text = $0.kind { true } else { false } } ?? 0
        super.init(frame: .zero)
        accessibilityIdentifier = "espanso.form"
        insert.configuration?.title = "Insert"
        insert.accessibilityIdentifier = "espanso.insert"
        insert.addAction(UIAction { [unowned self] _ in submit() }, for: .touchUpInside)
        insert.translatesAutoresizingMaskIntoConstraints = false
        addSubview(insert)
        NSLayoutConstraint.activate([
            insert.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            insert.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -6),
        ])
        list.dataSource = self
        list.delegate = self
        addList(list)
        field = values[fields.indices.contains(selected) ? fields[selected].name : ""] ?? ""
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The layout with the answers so far in place of `[[field]]`.
    private var filled: String {
        fields.reduce(layout) { text, field in
            let value = values[field.name] ?? ""
            return text.replacingOccurrences(of: "[[\(field.name)]]", with: value.isEmpty ? "…" : value)
        }
    }

    override func fieldChanged() {
        guard fields.indices.contains(selected), case .text = fields[selected].kind else { return }
        values[fields[selected].name] = field
        title.text = filled
        list.reloadData()
    }

    override func key(_ key: HexKeyboardViewController.CapturedKey) {
        if key == .return, fields.indices.contains(selected),
           case .text(let multiline) = fields[selected].kind, multiline {
            return field += "\n"
        }
        super.key(key)
    }

    /// Return moves to the next text field, and inserts after the last.
    override func submit() {
        let next = fields.indices.dropFirst(selected + 1).first { if case .text = fields[$0].kind { true } else { false } }
        if let next {
            select(next)
        } else {
            onSubmit(values)
        }
    }

    private func select(_ index: Int) {
        selected = index
        field = values[fields[index].name] ?? ""
        list.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { fields.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let field = fields[indexPath.row]
        var content = UIListContentConfiguration.valueCell()
        content.text = field.name
        let value = values[field.name] ?? ""
        switch field.kind {
        case .text:
            content.secondaryText = indexPath.row == selected ? value + "▏" : (value.isEmpty ? "—" : value)
            cell.accessoryType = .none
        case .choice:
            content.secondaryText = value.isEmpty ? "Choose…" : value
            cell.accessoryType = .disclosureIndicator
        }
        content.secondaryTextProperties.color = indexPath.row == selected ? .label : .secondaryLabel
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.accessibilityIdentifier = "espanso.field.\(field.name)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let field = fields[indexPath.row]
        switch field.kind {
        case .text:
            select(indexPath.row)
        case .choice(let options):
            guard !options.isEmpty else { return }
            let current = options.firstIndex(of: values[field.name] ?? "") ?? -1
            values[field.name] = options[(current + 1) % options.count]
            title.text = filled
            tableView.reloadData()
        }
    }
}
