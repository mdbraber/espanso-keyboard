import Foundation
import KeyboardUI

final class KeyboardViewController: HexKeyboardViewController {
    /// The copy of the Espanso folder the expander was loaded from.
    private var loaded: URL?

    override func viewDidLoad() {
        loadSnippets()
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        loadSnippets()
        super.viewWillAppear(animated)
    }

    /// Loads the app's current copy of the Espanso folder when it isn't the one loaded (espanso-keyboard, plan step 5).
    private func loadSnippets() {
        let current = EspansoLibrary.current
        guard current != loaded || (current != nil && expander == nil) else { return }
        loaded = current
        expander = current.flatMap(EspansoExpander.init(folder:))
    }
}
