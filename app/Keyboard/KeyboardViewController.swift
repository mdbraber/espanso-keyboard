import EspansoKeyboardCore
import Foundation
import KeyboardUI

final class KeyboardViewController: HexKeyboardViewController {
    /// The copy of the Espanso folder the expander was loaded from.
    private var loaded: URL?
    private var espanso: EspansoExpander? { expander as? EspansoExpander }

    override func viewDidLoad() {
        loadSnippets()
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        loadSnippets()
        espanso?.isEnabled = EspansoShared.isEnabled
        espanso?.showsButton = EspansoShared.showsButton
        closePanel()
        super.viewWillAppear(animated)
    }

    /// Loads the app's current copy of the Espanso folder when it isn't the one loaded (espanso-keyboard, plan step 5).
    private func loadSnippets() {
        let current = EspansoShared.isOn ? EspansoLibrary.current : nil
        guard current != loaded || (current != nil && expander == nil) else { return }
        loaded = current
        let expander = current.flatMap(EspansoExpander.init(folder:))
        expander?.host = self
        expander?.isEnabled = EspansoShared.isEnabled
        expander?.showsButton = EspansoShared.showsButton
        self.expander = expander
    }

    // MARK: Panels (plan step 6)

    func showSnippetPanel() {
        guard let espanso else { return }
        let panel = SnippetPanel(snippets: espanso.snippets)
        panel.onPick = { [unowned self] snippet in
            closePanel()
            if let expansion = espanso.insert(snippet.id) { applyExpansion(expansion) }
        }
        open(panel)
    }

    /// Asks a snippet's question; the answer may lead to another question, or to the expansion.
    func ask(_ prompt: Prompt, expander: EspansoExpander) {
        let panel: Panel
        switch prompt {
        case .choice(let choices):
            let choice = ChoicePanel(choices: choices)
            choice.onChoose = { [unowned self] in answer(.choice(id: $0.id), expander: expander) }
            panel = choice
        case .form(let layout, let fields):
            let form = FormPanel(layout: layout, fields: fields)
            form.onSubmit = { [unowned self] in answer(.form(values: $0), expander: expander) }
            panel = form
        }
        panel.onClose = { [unowned self] in
            expander.cancelPrompt()
            closePanel()
        }
        // Asked while Hex is applying a key: show the panel once that is done.
        DispatchQueue.main.async { [self] in open(panel) }
    }

    private func answer(_ answer: Answer, expander: EspansoExpander) {
        closePanel()
        if let expansion = expander.answer(answer) { applyExpansion(expansion) }
    }

    private func open(_ panel: Panel) {
        panel.onClose = { [unowned self, onClose = panel.onClose] in
            onClose()
            closePanel()
        }
        keyCapture = { [weak panel] in panel?.key($0) }
        showPanel(panel, height: Panel.height)
    }

    private func closePanel() {
        keyCapture = nil
        showPanel(nil)
    }
}
