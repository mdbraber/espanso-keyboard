import EspansoKeyboardCore
import UIKit
import UniformTypeIdentifiers

/// Picks the Espanso folder in iCloud Drive and shows the keyboard's copy of it: the snippets it expands, grouped by
/// match file, and Espanso's warnings (espanso-keyboard, plan steps 5 and 6).
final class EspansoViewController: UITableViewController, UIDocumentPickerDelegate, UISearchResultsUpdating {
    private enum Row: Hashable {
        case enabled, button, folder, reload, warning(String), snippet(Int32), file(String)
    }

    private struct Section {
        var title: String?
        var footer: String?
        var rows: [Row]
    }

    private var summary = EspansoImport.lastSummary
    private var failure: String?
    private var copying = false
    private let search = UISearchController()
    private var query: String { search.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? "" }
    /// The keyboard's copy, loaded here too for the details and previews.
    private var engine: EspansoEngine?
    private var snippets: [Int32: SnippetSummary] = [:]
    private var usage: [String: EspansoShared.Usage] = [:]

    /// The last copy in one line, for the Espanso section in Keyboard Settings.
    static var summary: String {
        guard let summary = EspansoImport.lastSummary else { return "Hex types your Espanso snippets. Choose the folder you sync through iCloud Drive." }
        let off = EspansoShared.isEnabled ? "" : " Expanding is off."
        return "\(summary.snippets) snippets, copied \(summary.date.formatted(date: .abbreviated, time: .shortened)).\(off)"
    }

    init() {
        super.init(style: .insetGrouped)
        title = "Espanso Snippets"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search Snippets"
        navigationItem.searchController = search
        let add = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [unowned self] _ in addSnippet() })
        add.accessibilityLabel = "Add Snippet"
        navigationItem.rightBarButtonItem = add
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !copying { summary = EspansoImport.lastSummary }
        loadEngine()
    }

    func updateSearchResults(for searchController: UISearchController) {
        tableView.reloadData()
    }

    /// Loads the current copy, for its snippets' details; usage counts are read again too.
    private func loadEngine() {
        if let folder = EspansoLibrary.current {
            engine = try? EspansoEngine(configFolder: folder.path, scriptRunner: JavaScriptCoreScriptRunner())
            engine?.setClipboard(clipboard: AppClipboard())
        }
        snippets = Dictionary((engine?.search(query: "") ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        usage = EspansoShared.usage()
        navigationItem.rightBarButtonItem?.isEnabled = EspansoImport.sourceFolder != nil
        tableView.reloadData()
    }

    private var sections: [Section] {
        var sections = [
            Section(footer: "When Expand Snippets is off, Hex types your triggers as they are; the snippets button above the keys still works. Snippets Button shows or hides that button.", rows: [.enabled, .button]),
            Section(footer: folderFooter, rows: [.folder, .reload]),
        ]
        let all = snippets.values.sorted { ($0.file, $0.triggers[0]) < ($1.file, $1.triggers[0]) }
        if query.isEmpty {
            // One page per match file, so a long folder doesn't make one endless list.
            let files = Set(all.map(\.file)).sorted()
            if !files.isEmpty { sections.append(Section(title: "Files", rows: files.map(Row.file))) }
            let warnings = summary?.warnings ?? []
            if !warnings.isEmpty { sections.append(Section(title: "Warnings", rows: warnings.map(Row.warning))) }
        } else {
            let found = all
                .compactMap { snippet in Fuzzy.score(query, in: snippet.triggers + [snippet.label]).map { (snippet, $0) } }
                .sorted { $0.1 > $1.1 }
                .map { Row.snippet($0.0.id) }
            sections.append(Section(title: found.isEmpty ? "No Snippets Found" : "Snippets", rows: found))
        }
        return sections
    }

    private var folderFooter: String {
        if copying { return "Copying…" }
        if let failure { return "Not copied: \(failure)" }
        guard let summary else {
            return "Choose the Espanso folder you sync through iCloud Drive, the one with config and match in it. The keyboard uses a copy, made again each time you open Hex or tap Reload."
        }
        let date = summary.date.formatted(date: .abbreviated, time: .shortened)
        return "\(summary.snippets) snippets, copied \(date). The copy is made again each time you open Hex or tap Reload."
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        switch sections[indexPath.section].rows[indexPath.row] {
        case .enabled:
            content.text = "Expand Snippets"
            let toggle = UISwitch()
            toggle.isOn = EspansoShared.isEnabled
            toggle.accessibilityIdentifier = "Expand Snippets"
            toggle.addAction(UIAction { [unowned toggle] _ in EspansoShared.isEnabled = toggle.isOn }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .button:
            content.text = "Snippets Button"
            let toggle = UISwitch()
            toggle.isOn = EspansoShared.showsButton
            toggle.accessibilityIdentifier = "Snippets Button"
            toggle.addAction(UIAction { [unowned toggle] _ in EspansoShared.showsButton = toggle.isOn }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .folder:
            content.text = "Espanso Folder"
            content.secondaryText = summary?.folderName ?? EspansoImport.rememberedFolder?.lastPathComponent ?? "Choose…"
            cell.accessoryType = .disclosureIndicator
        case .reload:
            content = .cell()
            content.text = "Reload"
            content.textProperties.color = .tintColor
            if EspansoImport.sourceFolder == nil || copying {
                content.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
            }
        case .warning(let warning):
            content = .subtitleCell()
            content.text = warning
            content.textProperties.font = .preferredFont(forTextStyle: .footnote)
            cell.selectionStyle = .none
        case .snippet(let id):
            if let snippet = snippets[id] { content = SnippetListViewController.content(for: snippet, usage: usage) }
            cell.accessoryType = .disclosureIndicator
        case .file(let file):
            content.text = file
            content.secondaryText = "\(snippets.values.count { $0.file == file })"
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .folder:
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            picker.delegate = self
            picker.directoryURL = EspansoImport.rememberedFolder
            present(picker, animated: true)
        case .reload:
            guard let folder = EspansoImport.sourceFolder, !copying else { return }
            copy(from: folder)
        case .snippet(let id):
            guard let engine, let snippet = snippets[id] else { return }
            navigationController?.pushViewController(SnippetViewController(snippet: snippet, engine: engine), animated: true)
        case .file(let file):
            guard let engine else { return }
            let inFile = snippets.values.filter { $0.file == file }.sorted { $0.triggers[0] < $1.triggers[0] }
            navigationController?.pushViewController(SnippetListViewController(file: file, snippets: inFile, engine: engine), animated: true)
        case .enabled, .button, .warning:
            break
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let folder = urls.first else { return }
        do {
            try EspansoImport.remember(folder)
        } catch {
            failure = describe(error)
            return tableView.reloadData()
        }
        copy(from: folder)
    }

    private func addSnippet() {
        navigationController?.pushViewController(NewSnippetViewController(), animated: true)
    }

    /// Copies off the main thread: files iCloud Drive hasn't downloaded yet take a while.
    private func copy(from folder: URL) {
        copying = true
        failure = nil
        tableView.reloadData()
        Task {
            let result = await Task.detached { Result { try EspansoImport.copy(from: folder) } }.value
            copying = false
            switch result {
            case .success(let summary): self.summary = summary
            case .failure(let error): failure = describe(error)
            }
            loadEngine()
        }
    }
}

/// The clipboard for `clipboard` variables in previews.
final class AppClipboard: Clipboard {
    func text() -> String? {
        UIPasteboard.general.string
    }
}
