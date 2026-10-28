import UIKit
import UniformTypeIdentifiers

/// Picks the Espanso folder in iCloud Drive and shows the keyboard's copy of it: the snippets it expands and
/// Espanso's warnings (espanso-keyboard, plan step 5).
final class EspansoViewController: UITableViewController, UIDocumentPickerDelegate, UISearchResultsUpdating {
    private enum Row: Hashable {
        case folder, reload, warning(String), snippet(EspansoImport.Snippet)
    }

    private struct Section {
        var title: String?
        var rows: [Row]
    }

    private var summary = EspansoImport.lastSummary
    private var failure: String?
    private var copying = false
    private let search = UISearchController()
    private var query: String { search.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? "" }

    /// The last copy in one line, for the Espanso section in Keyboard Settings.
    static var summary: String {
        guard let summary = EspansoImport.lastSummary else { return "Hex types your Espanso snippets. Choose the folder you sync through iCloud Drive." }
        return "\(summary.snippets) snippets, copied \(summary.date.formatted(date: .abbreviated, time: .shortened))."
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
    }

    func updateSearchResults(for searchController: UISearchController) {
        tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !copying { summary = EspansoImport.lastSummary }
        tableView.reloadData()
    }

    private var sections: [Section] {
        var sections = [Section(rows: [.folder, .reload])]
        let snippets = (summary?.items ?? []).filter(matchesQuery)
        if !snippets.isEmpty { sections.append(Section(title: "Snippets", rows: snippets.map(Row.snippet))) }
        let warnings = summary?.warnings ?? []
        if !warnings.isEmpty, query.isEmpty { sections.append(Section(title: "Warnings", rows: warnings.map(Row.warning))) }
        return sections
    }

    private func matchesQuery(_ snippet: EspansoImport.Snippet) -> Bool {
        query.isEmpty || ([snippet.label] + snippet.triggers).contains { $0.localizedCaseInsensitiveContains(query) }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        if copying { return "Copying…" }
        if let failure { return "Not copied: \(failure)" }
        guard let summary else {
            return "Choose the Espanso folder you sync through iCloud Drive, the one with config and match in it. The keyboard uses a copy, made again each time you open Hex or tap Reload."
        }
        let date = summary.date.formatted(date: .abbreviated, time: .shortened)
        return "\(summary.snippets) snippets, copied \(date). The copy is made again each time you open Hex or tap Reload."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        cell.accessoryType = .none
        cell.selectionStyle = .default
        switch sections[indexPath.section].rows[indexPath.row] {
        case .folder:
            content.text = "Espanso Folder"
            content.secondaryText = summary?.folderName ?? EspansoImport.rememberedFolder?.lastPathComponent ?? "Choose…"
            cell.accessoryType = .disclosureIndicator
        case .reload:
            content = .cell()
            content.text = "Reload"
            content.textProperties.color = .tintColor
            if EspansoImport.rememberedFolder == nil || copying {
                content.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
            }
        case .warning(let warning):
            content = .subtitleCell()
            content.text = warning
            content.textProperties.font = .preferredFont(forTextStyle: .footnote)
            cell.selectionStyle = .none
        case .snippet(let snippet):
            content = .subtitleCell()
            content.text = snippet.triggers.joined(separator: "  ")
            content.textProperties.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
            content.secondaryText = snippet.label
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.numberOfLines = 2
            cell.selectionStyle = .none
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
            guard let folder = EspansoImport.rememberedFolder, !copying else { return }
            copy(from: folder)
        case .warning, .snippet:
            break
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let folder = urls.first else { return }
        do {
            try EspansoImport.remember(folder)
        } catch {
            failure = error.localizedDescription
            return tableView.reloadData()
        }
        copy(from: folder)
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
            case .failure(let error): failure = error.localizedDescription
            }
            tableView.reloadData()
        }
    }
}
