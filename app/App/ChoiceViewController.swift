import UIKit

/// A setting with a few values, picked from a checked list as in Settings.
final class ChoiceViewController<Value: Equatable>: UITableViewController {
    private let choices: [(value: Value, title: String)]
    private let footer: String
    private let pick: (Value) -> Void
    private var choice: Value

    init(title: String, footer: String, choices: [(value: Value, title: String)], choice: Value, pick: @escaping (Value) -> Void) {
        self.choices = choices
        self.footer = footer
        self.choice = choice
        self.pick = pick
        super.init(style: .insetGrouped)
        self.title = title
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "choice")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { choices.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { footer }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "choice", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = choices[indexPath.row].title
        cell.contentConfiguration = content
        cell.accessoryType = choices[indexPath.row].value == choice ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        choice = choices[indexPath.row].value
        pick(choice)
        for cell in tableView.visibleCells {
            guard let row = tableView.indexPath(for: cell)?.row else { continue }
            cell.accessoryType = choices[row].value == choice ? .checkmark : .none
        }
    }
}
