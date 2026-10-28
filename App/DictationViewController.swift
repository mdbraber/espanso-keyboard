import KeyboardUI
import UIKit

/// What the app shows while the keyboard's voice typing listens: you go back to your app and keep talking, and the
/// keyboard's mic ends it, or Done here.
final class DictationViewController: UIViewController {
    private let orb = UIView()
    private let status = UILabel()
    private let hint = UILabel()
    private let done = UIButton(configuration: .prominentGlass())
    private let cancel = UIButton(configuration: .glass())
    private var hasListened = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        orb.backgroundColor = .tintColor
        orb.layer.cornerRadius = 48
        status.font = .preferredFont(forTextStyle: .largeTitle).bold
        status.textAlignment = .center
        status.numberOfLines = 0
        hint.font = .preferredFont(forTextStyle: .body)
        hint.textColor = .secondaryLabel
        hint.textAlignment = .center
        hint.numberOfLines = 0
        done.configuration?.title = "Done"
        done.addAction(UIAction { _ in Task { await Listener.shared.finish() } }, for: .touchUpInside)
        cancel.configuration?.title = "Cancel"
        cancel.addAction(UIAction { _ in Task { await Listener.shared.cancel() } }, for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [cancel, done])
        buttons.spacing = 12
        buttons.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [status, hint, buttons])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(32, after: hint)
        [orb, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            orb.widthAnchor.constraint(equalToConstant: 96),
            orb.heightAnchor.constraint(equalToConstant: 96),
            orb.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            orb.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -48),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 60),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            buttons.heightAnchor.constraint(equalToConstant: 50),
        ])

        Listener.shared.onChange = { [weak self] in self?.refresh() }
        Listener.shared.onLevel = { [weak self] level in
            UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                let scale = 1 + min(CGFloat(level) * 8, 0.6)
                self?.orb.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
        refresh()
    }

    private func refresh() {
        let current = Dictation.status
        if Listener.shared.state != .idle { hasListened = true }
        switch Listener.shared.state {
        case .listening:
            status.text = "Listening"
            hint.text = "Go back to your app and keep talking. Swipe right along the bottom edge, or tap the app's name in the top corner. Tap the red mic beside the suggestions when you're finished."
        case .transcribing:
            status.text = "Writing it down"
            hint.text = "It'll be typed where you were."
        case .idle:
            if let failure = current.failure {
                status.text = "Couldn't listen"
                hint.text = failure
            } else if hasListened {
                return dismiss(animated: false)
            }
        }
        done.isHidden = Listener.shared.state != .listening
        cancel.isHidden = Listener.shared.state == .idle
    }
}

private extension UIFont {
    var bold: UIFont { UIFont(descriptor: fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor, size: 0) }
}
