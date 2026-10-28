import KeyboardUI

final class KeyboardViewController: HexKeyboardViewController {
    override func viewDidLoad() {
        expander = EspansoExpander.bundled()
        super.viewDidLoad()
    }
}
