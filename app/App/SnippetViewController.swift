import EspansoKeyboardCore
import UIKit

/// One snippet: its triggers, file, text and variables, a preview of what it types now, copying that, marking it a
/// favourite, how often it was used, and editing it (espanso-keyboard, plan step 6, items 1, 6, 9, 11 and 12).
final class SnippetViewController: UITableViewController, UITextFieldDelegate {
    private enum Row: Hashable {
        case trigger(String), file, text, variable(String), example, preview, copy, favourite, usage, edit
    }

    private let snippet: SnippetSummary
    private let engine: EspansoEngine
    private var preview = ""
    private var copied = false
    /// For a regex snippet: an example of its trigger, which gives the preview its groups.
    private var example = ""
    private let exampleField = UITextField()
    private var key: String { snippet.triggers[0] }

    init(snippet: SnippetSummary, engine: EspansoEngine) {
        self.snippet = snippet
        self.engine = engine
        super.init(style: .insetGrouped)
        title = snippet.triggers[0]
        preview = render()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// What the snippet types now. A regex snippet's groups come from what is typed, so it needs an example.
    private func render() -> String {
        do {
            guard snippet.isRegex else { return try engine.preview(id: snippet.id) }
            guard !example.isEmpty else { return "Type an example of the trigger above to see what it types." }
            return try engine.previewTyped(id: snippet.id, typed: example)
        } catch {
            return "Can't render it: \(describe(error))"
        }
    }

    private var canCopy: Bool { !snippet.isRegex || !example.isEmpty }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        exampleField.placeholder = "Example, as you'd type it"
        exampleField.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        exampleField.autocapitalizationType = .none
        exampleField.autocorrectionType = .no
        exampleField.smartQuotesType = .no
        exampleField.smartDashesType = .no
        exampleField.clearButtonMode = .whileEditing
        exampleField.accessibilityIdentifier = "espanso.example"
        exampleField.delegate = self
        // Leaving Hex with the field still active must not leave the keyboard paused in other apps.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.view.endEditing(true) } }
        exampleField.addAction(UIAction { [unowned self] _ in exampleChanged() }, for: .editingChanged)
    }

    // The keyboard is Hex: it would expand the example. It doesn't while the field is being edited.
    func textFieldDidBeginEditing(_ textField: UITextField) { EspansoShared.isPaused = true }
    func textFieldDidEndEditing(_ textField: UITextField) { EspansoShared.isPaused = false }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        EspansoShared.isPaused = false
    }

    /// Renders again for the new example, updating only the preview rows so the field keeps the keyboard.
    private func exampleChanged() {
        example = exampleField.text ?? ""
        preview = render()
        copied = false
        let rows = sections.enumerated().flatMap { section, content in
            content.rows.enumerated().compactMap { row, kind in
                kind == .preview || kind == .copy ? IndexPath(row: row, section: section) : nil
            }
        }
        tableView.reconfigureRows(at: rows)
    }

    private var sections: [(title: String?, footer: String?, rows: [Row])] {
        var sections: [(String?, String?, [Row])] = [
            (snippet.isRegex ? "Regex" : snippet.triggers.count == 1 ? "Trigger" : "Triggers", nil, snippet.triggers.map(Row.trigger)),
            ("Text", nil, [.text]),
        ]
        if !snippet.vars.isEmpty { sections.append(("Variables", nil, snippet.vars.map(Row.variable))) }
        if snippet.isRegex {
            sections.append(("Preview", "The regex’s groups come from the example; questions take their first choice or default.", [.example, .preview, .copy]))
        } else {
            sections.append(("Preview", "Questions take their first choice or default here.", [.preview, .copy]))
        }
        sections.append((nil, nil, [.favourite, .usage, .file]))
        if EspansoImport.sourceFolder != nil {
            sections.append((nil, "Changes go to \(snippet.file) in your Espanso folder, so Espanso on the Mac gets them too.", [.edit]))
        }
        return sections
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.cell()
        let mono = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .none
        switch sections[indexPath.section].rows[indexPath.row] {
        case .trigger(let trigger):
            content.text = trigger
            content.textProperties.font = mono
        case .text:
            content.text = snippet.replace
            content.textProperties.font = mono
        case .variable(let name):
            content.text = name
            content.textProperties.font = mono
        case .example:
            cell.contentConfiguration = nil
            exampleField.translatesAutoresizingMaskIntoConstraints = false
            if exampleField.superview !== cell.contentView {
                exampleField.removeFromSuperview()
                cell.contentView.addSubview(exampleField)
                let margins = cell.contentView.layoutMarginsGuide
                NSLayoutConstraint.activate([
                    exampleField.topAnchor.constraint(equalTo: margins.topAnchor),
                    exampleField.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
                    exampleField.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
                    exampleField.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
                    exampleField.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
                ])
            }
            return cell
        case .preview:
            content.text = preview
            content.textProperties.color = .secondaryLabel
        case .copy:
            content.text = copied ? "Copied" : "Copy Result"
            content.textProperties.color = canCopy ? .tintColor : .secondaryLabel
            cell.selectionStyle = canCopy ? .default : .none
        case .favourite:
            content.text = "Favourite"
            let toggle = UISwitch()
            toggle.isOn = EspansoShared.favourites.contains(key)
            toggle.accessibilityIdentifier = "Favourite"
            toggle.addAction(UIAction { [key] _ in EspansoShared.toggleFavourite(key) }, for: .valueChanged)
            cell.accessoryView = toggle
            content.secondaryText = "First in the keyboard's snippet list"
        case .usage:
            content = .valueCell()
            content.text = "Used"
            if let usage = EspansoShared.usage()[key] {
                content.secondaryText = "\(usage.count)×, last \(usage.last.formatted(.relative(presentation: .named)))"
            } else {
                content.secondaryText = "Not yet on this iPhone"
            }
        case .file:
            content = .valueCell()
            content.text = "File"
            content.secondaryText = snippet.file
        case .edit:
            content.text = "Edit Snippet"
            content.textProperties.color = .tintColor
            cell.selectionStyle = .default
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .copy:
            guard canCopy else { return }
            preview = render()
            UIPasteboard.general.string = preview
            copied = true
            tableView.reloadData()
        case .edit:
            do {
                let block = try EspansoEditor.block(of: snippet)
                navigationController?.pushViewController(SnippetEditorViewController(snippet: snippet, block: block), animated: true)
            } catch {
                showError(error)
            }
        default:
            break
        }
    }
}

/// Edits a snippet's lines as they are in its file: everything Espanso allows, and nothing else in the file changes.
final class SnippetEditorViewController: UIViewController {
    private let snippet: SnippetSummary
    private let text = UITextView()

    init(snippet: SnippetSummary, block: String) {
        self.snippet = snippet
        super.init(nibName: nil, bundle: nil)
        title = "Edit \(snippet.triggers[0])"
        text.text = block
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        text.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        text.autocapitalizationType = .none
        text.autocorrectionType = .no
        text.smartQuotesType = .no
        text.smartDashesType = .no
        text.accessibilityIdentifier = "espanso.yaml"
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            text.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            text.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .save, primaryAction: UIAction { [unowned self] _ in save() })
    }

    private func save() {
        do {
            try EspansoEditor.replace(snippet, with: text.text)
            navigationController?.popToRootViewController(animated: true)
        } catch {
            showError(error)
        }
    }
}

/// A new snippet, saved to match/iphone.yml in the Espanso folder.
final class NewSnippetViewController: UITableViewController {
    private let trigger = UITextField()
    private let replace = UITextView()
    private let label = UITextField()
    private let word = UISwitch()

    init() {
        super.init(style: .insetGrouped)
        title = "New Snippet"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        trigger.placeholder = ";trigger"
        trigger.accessibilityIdentifier = "espanso.new.trigger"
        replace.font = .preferredFont(forTextStyle: .body)
        replace.backgroundColor = .clear
        replace.accessibilityIdentifier = "espanso.new.replace"
        label.placeholder = "Optional"
        label.accessibilityIdentifier = "espanso.new.label"
        for field in [trigger, label] {
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .save, primaryAction: UIAction { [unowned self] _ in save() })
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Trigger", "Text", "Label", nil][section]
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 1: "Espanso variables such as {{date}} work if the snippet defines them; add those by editing it afterwards."
        case 3: "Saved to match/\(EspansoEditor.newSnippetsFile) in your Espanso folder, so Espanso on the Mac gets it too."
        default: nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.selectionStyle = .none
        let view: UIView
        switch indexPath.section {
        case 0: view = trigger
        case 1: view = replace
        case 2: view = label
        default:
            var content = UIListContentConfiguration.cell()
            content.text = "Whole Words Only"
            cell.contentConfiguration = content
            cell.accessoryView = word
            return cell
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(view)
        let margins = cell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: margins.topAnchor),
            view.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: indexPath.section == 1 ? 88 : 24),
        ])
        return cell
    }

    private func save() {
        let trigger = trigger.text ?? ""
        guard !trigger.isEmpty, !replace.text.isEmpty else {
            return showError(message: "A snippet needs a trigger and a text.")
        }
        do {
            try EspansoEditor.add(trigger: trigger, replace: replace.text, label: label.text, word: word.isOn)
            navigationController?.popViewController(animated: true)
        } catch {
            showError(error)
        }
    }
}

extension UIViewController {
    func showError(_ error: Error) {
        showError(message: describe(error))
    }

    func showError(message: String) {
        let alert = UIAlertController(title: "Not Saved", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
