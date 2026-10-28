import EspansoKeyboardCore
import UIKit

/// The snippets of one match file, searchable, each opening its detail screen (espanso-keyboard).
final class SnippetListViewController: UITableViewController, UISearchResultsUpdating {
    private let snippets: [SnippetSummary]
    private let engine: EspansoEngine
    private let search = UISearchController()
    private var usage: [String: EspansoShared.Usage] = [:]

    init(file: String, snippets: [SnippetSummary], engine: EspansoEngine) {
        self.snippets = snippets
        self.engine = engine
        super.init(style: .insetGrouped)
        title = file
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A snippet's row: its triggers, then its label and how often it was used.
    static func content(for snippet: SnippetSummary, usage: [String: EspansoShared.Usage]) -> UIListContentConfiguration {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = snippet.triggers.joined(separator: "  ")
        content.textProperties.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        let used = usage[snippet.triggers[0]].map { " · used \($0.count)×" } ?? ""
        content.secondaryText = snippet.label + used
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        return content
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search \(title ?? "")"
        navigationItem.searchController = search
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        usage = EspansoShared.usage()
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        tableView.reloadData()
    }

    private var shown: [SnippetSummary] {
        let query = search.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !query.isEmpty else { return snippets }
        return snippets
            .compactMap { snippet in Fuzzy.score(query, in: snippet.triggers + [snippet.label]).map { (snippet, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shown.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.contentConfiguration = Self.content(for: shown[indexPath.row], usage: usage)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(SnippetViewController(snippet: shown[indexPath.row], engine: engine), animated: true)
    }
}
