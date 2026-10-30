import KeyboardCore
import KeyboardUI
import UIKit

final class SettingsViewController: UITableViewController {
    /// The main screen's items with settings of their own (espanso-keyboard). Each feature page starts with a switch that
    /// turns the feature off completely; its options show while it's on.
    enum Page {
        case keyboard, voice, sources, taps

        var title: String {
            switch self {
            case .keyboard: "Keyboard"
            case .voice: "Voice"
            case .sources: "Sources"
            case .taps: "Your Taps"
            }
        }
    }

    private enum Row {
        case toggle(String, WritableKeyPath<KeyboardSettings, Bool>)
        case oneHanded
        case language
        case keepMicOn
        case transcripts
        case source(Source)
        case addSource
        case reset
    }

    private struct Section {
        var title: String?
        var footer: String?
        var rows: [Row]
    }

    private var sections: [Section] {
        switch page {
        case .keyboard: keyboardSections
        case .voice:
            [Section(footer: "Off, the keyboard has no mic and Hex never uses the microphone.", rows: [.toggle("Voice Typing", \.voice)])]
                + (settings.voice ? [
                    Section(footer: Self.keepMicOnFooter, rows: [.keepMicOn]),
                    Section(footer: "Saves what you dictate, on this iPhone only, for the Transcripts tab.", rows: [.transcripts]),
                ] : [])
        case .sources:
            [Section(footer: "Off, Hex sends nothing to any source and shows no hints.", rows: [.toggle("Sources", \.sources)])]
                + (settings.sources ? [Section(footer: Self.sourcesFooter, rows: sources.map(Row.source) + [.addSource])] : [])
        case .taps:
            [Section(footer: "Hex learns where your thumbs land on each key, so autocorrect fits how you type. Off, it stops and forgets what it learned, and uses its standard idea of the keys.", rows: [.toggle("Learn My Taps", \.learnsTaps)])]
                + (settings.learnsTaps ? [Section(footer: "Lets the keyboard share what it learned with the Your Taps tab, with Allow Full Access on.", rows: [.toggle("Show Your Taps", \.sharesTaps)])] : [])
        }
    }

    private var keyboardSections: [Section] { [
        Section(footer: Self.oneHandedFooter, rows: [.oneHanded]),
        Section(footer: "Haptic Feedback needs Allow Full Access in Settings › General › Keyboard › Keyboards › Hex.", rows: [
            .toggle("Character Preview", \.characterPreview),
            .toggle("Haptic Feedback", \.haptics),
            .toggle("Sound", \.sound),
        ]),
        Section(title: "All Keyboards", footer: "Double tapping the space bar will insert a period followed by a space.", rows: [
            .toggle("Auto-Capitalization", \.autoCapitalization),
            .toggle("Auto-Correction", \.autoCorrection),
            .toggle("Enable Caps Lock", \.capsLock),
            .toggle("Smart Punctuation", \.smartPunctuation),
            .toggle("“.” Shortcut", \.periodShortcut),
        ]),
        Section(title: "Language", footer: Self.languageFooter, rows: [
            .language,
            .toggle("Predictive Text", \.predictiveText),
        ]),
        Section(footer: "Removes the words and typing habits Hex has learned from you.", rows: [.reset]),
    ] }

    private static let keepMicOnFooter = "After you dictate, Hex keeps the mic on this long. While it’s on, the mic beside the suggestions starts and stops dictating without leaving your app; hold it to turn the mic off. Nothing is recorded until you tap it."

    private static let sourcesFooter = "With Allow Full Access on, Hex sends each source the text of the field you’re typing in, except passwords and codes, and shows the hints it answers with above the keys. Tap a hint to hide it."

    private static let languageFooter = "Hold 123 to switch between English, Nederlands and both while you type; with both, Hex leans toward the language you’re writing. Hex expands your Text Replacements from Settings › General › Keyboard › Text Replacement."

    private static let oneHandedFooter = "Hold 123 and slide to move the keys toward one thumb."

    private let page: Page
    private var settings = SettingsStore.load()
    private var sources = SourceStore.load()

    init(page: Page = .keyboard) {
        self.page = page
        super.init(style: .insetGrouped)
        title = page.title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settings = SettingsStore.load()
        sources = SourceStore.load()
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch row(at: indexPath) {
        case .toggle, .source: false
        default: true
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case .source(let source) = row(at: indexPath) else { return nil }
        return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Delete") { [unowned self] _, _, done in
            sources.removeAll { $0 == source }
            SourceStore.save(sources)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            done(true)
        }])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch row(at: indexPath) {
        case .oneHanded:
            let choices = OneHanded.allCases.map { (value: $0, title: Self.title(of: $0)) }
            return show(ChoiceViewController(title: "One-Handed Keyboard", footer: "The keys move toward your thumb on an upright iPhone. Tap the arrow beside them to bring back the full keyboard.", choices: choices, choice: settings.oneHanded) {
                SettingsStore.set($0)
            }, sender: self)
        case .language:
            let choices = Language.allCases.map { (value: $0, title: $0.name) }
            return show(ChoiceViewController(title: "Language", footer: "Autocorrect, suggestions and predictions follow the language. Words Hex learns are kept per language; how you tap is shared.", choices: choices, choice: settings.language) {
                SettingsStore.set($0)
            }, sender: self)
        case .keepMicOn:
            let choices = Dictation.micChoices.map { (value: $0, title: Dictation.title(keepingMicOn: $0)) }
            return show(ChoiceViewController(title: "Keep Mic On", footer: Self.keepMicOnFooter, choices: choices, choice: SettingsStore.keepMicOn) {
                SettingsStore.keepMicOn = $0
                Listener.shared.keepMicOn()
            }, sender: self)
        case .addSource:
            tableView.deselectRow(at: indexPath, animated: true)
            return addSource()
        default:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let alert = UIAlertController(title: nil, message: "This deletes the words Hex learned from you and everything it learned about your taps.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Reset Dictionary", style: .destructive) { _ in MemoryStore.reset() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        cell.accessoryType = .none
        switch row(at: indexPath) {
        case .toggle(let title, let path):
            content.text = title
            let toggle = UISwitch()
            toggle.isOn = settings[keyPath: path]
            toggle.accessibilityIdentifier = title
            toggle.addAction(UIAction { [unowned self, unowned toggle] _ in
                settings[keyPath: path] = toggle.isOn
                SettingsStore.set(toggle.isOn, for: path)
                if !toggle.isOn, path == \.sharesTaps || path == \.learnsTaps { MemoryStore.removeSharedTouches() }
                if [\KeyboardSettings.voice, \.learnsTaps, \.sharesTaps].contains(path) {
                    NotificationCenter.default.post(name: .hexTabsChanged, object: nil)
                }
                if [\KeyboardSettings.voice, \.learnsTaps, \.sources].contains(path) { tableView.reloadData() }
            }, for: .valueChanged)
            cell.accessoryView = toggle
        case .oneHanded:
            content.text = "One-Handed Keyboard"
            content.secondaryText = Self.title(of: settings.oneHanded)
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        case .language:
            content.text = "Language"
            content.secondaryText = settings.language.name
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        case .transcripts:
            content.text = "Transcripts"
            let toggle = UISwitch()
            toggle.isOn = Transcripts.isKept
            toggle.accessibilityIdentifier = "Transcripts"
            toggle.addAction(UIAction { [unowned self, unowned toggle] _ in keepTranscripts(toggle.isOn, from: toggle) }, for: .valueChanged)
            cell.accessoryView = toggle
        case .keepMicOn:
            content.text = "Keep Mic On"
            content.secondaryText = Dictation.title(keepingMicOn: SettingsStore.keepMicOn)
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        case .source(let source):
            content = .subtitleCell()
            content.text = source.name
            content.secondaryText = source.url.absoluteString
            content.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryView = nil
        case .addSource:
            content.text = "Add Source…"
            content.textProperties.color = .tintColor
            cell.accessoryView = nil
        case .reset:
            content.text = "Reset Keyboard Dictionary"
            content.textProperties.color = .tintColor
            cell.accessoryView = nil
        }
        cell.contentConfiguration = content
        return cell
    }

    /// Switching Transcripts off offers to delete the ones kept so far (espanso-keyboard).
    private func keepTranscripts(_ kept: Bool, from toggle: UIView) {
        Transcripts.isKept = kept
        NotificationCenter.default.post(name: .hexTabsChanged, object: nil)
        let count = Transcripts.shared.all.count
        guard !kept, count > 0 else { return }
        let alert = UIAlertController(title: nil, message: "Hex has \(count) transcript\(count == 1 ? "" : "s") from earlier dictation.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete Transcripts", style: .destructive) { _ in
            Transcripts.shared.delete(Set(Transcripts.shared.all.map(\.id)))
        })
        alert.addAction(UIAlertAction(title: "Keep Them", style: .cancel))
        alert.popoverPresentationController?.sourceView = toggle
        present(alert, animated: true)
    }

    private func addSource() {
        let alert = UIAlertController(title: "Add Source", message: "A source is a service Hex tells what you type. It can answer with a hint above the keys.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Name" }
        alert.addTextField {
            $0.placeholder = "https://"
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
        }
        alert.addTextField {
            $0.placeholder = "Token (optional)"
            $0.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [unowned self, unowned alert] _ in
            let fields = alert.textFields?.map { $0.text?.trimmingCharacters(in: .whitespaces) ?? "" } ?? []
            guard let url = URL(string: fields[1]), Source.allows(url), !fields[0].isEmpty else { return }
            SourceStore.add(Source(name: fields[0], url: url, token: fields[2].isEmpty ? nil : fields[2]))
            sources = SourceStore.load()
            tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private static func title(of hand: OneHanded) -> String {
        switch hand {
        case .off: "Off"
        case .left: "Left"
        case .right: "Right"
        }
    }

    private func row(at indexPath: IndexPath) -> Row {
        sections[indexPath.section].rows[indexPath.row]
    }
}
