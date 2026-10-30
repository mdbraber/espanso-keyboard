import KeyboardUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        LaunchOptions.resetSettingsIfAsked()
        LaunchOptions.applyOneHanded()
        EspansoImport.copyIfAsked()
        let home = HomeViewController()
        let all = [
            UITab(title: "Hex", image: UIImage(systemName: "keyboard"), identifier: "home") { _ in Self.navigation(home) },
            UITab(title: "Transcripts", image: UIImage(systemName: "waveform"), identifier: "transcripts") { _ in TranscriptsView.controller() },
            UITab(title: "Your Taps", image: UIImage(systemName: "hand.tap"), identifier: "taps") { _ in Self.navigation(TapsViewController()) },
        ]
        let tabs = UITabBarController(tabs: Self.shown(all))
        NotificationCenter.default.addObserver(forName: .hexTabsChanged, object: nil, queue: .main) { [weak tabs] _ in
            MainActor.assumeIsolated {
                guard let tabs, tabs.tabs.map(\.identifier) != Self.shown(all).map(\.identifier) else { return }
                tabs.setTabs(Self.shown(all), animated: false)
            }
        }
        tabs.selectedTab = tabs.tab(forIdentifier: LaunchOptions.tab)
        window.rootViewController = tabs
        if LaunchOptions.settings { home.showSettings(LaunchOptions.settingsPage) }
        window.makeKeyAndVisible()
        self.window = window
        open(options.urlContexts)
    }

    /// Each time Hex comes to the front, the keyboard gets a fresh copy of the Espanso folder (espanso-keyboard).
    func sceneDidBecomeActive(_ scene: UIScene) {
        EspansoImport.reloadInBackground()
        // Privacy may have changed in the Settings app.
        let settings = SettingsStore.load()
        if !settings.learnsTaps || !settings.sharesTaps { MemoryStore.removeSharedTouches() }
        NotificationCenter.default.post(name: .hexTabsChanged, object: nil)
    }

    /// The tabs to show: Transcripts and Your Taps go when Keyboard Settings › Privacy switches them off
    /// (espanso-keyboard).
    private static func shown(_ all: [UITab]) -> [UITab] {
        all.filter { tab in
            switch tab.identifier {
            case "transcripts": SettingsStore.load().voice && Transcripts.isKept
            case "taps": SettingsStore.load().learnsTaps && SettingsStore.load().sharesTaps
            default: true
            }
        }
    }

    private static func navigation(_ root: UIViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = true
        return navigation
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        open(contexts)
    }

    private func open(_ contexts: Set<UIOpenURLContext>) {
        if let source = contexts.lazy.compactMap({ Source(link: $0.url) }).first { return offer(source) }
        guard let request = contexts.lazy.compactMap({ Dictation.Request($0.url) }).first, let root = window?.rootViewController else { return }
        Task { await listen(thenOpen: request.host) }
        guard !(root.presentedViewController is DictationViewController) else { return }
        root.dismiss(animated: false)
        let dictation = DictationViewController()
        dictation.modalPresentationStyle = .fullScreen
        root.present(dictation, animated: false)
    }

    /// Starts listening while Hex is in front, the only place iOS lets a recording begin, then reopens the app you were typing in.
    private func listen(thenOpen host: String?) async {
        let asked = Date.now
        await Listener.shared.start()
        guard Listener.shared.state == .listening else {
            return HostApp.log.notice("not listening after \(Date.now.timeIntervalSince(asked), format: .fixed(precision: 2))s")
        }
        let opened = if let host { await HostApp.open(host) } else { false }
        HostApp.log.notice("back to \(host ?? "none", privacy: .public) \(opened ? "opened" : "failed", privacy: .public) after \(Date.now.timeIntervalSince(asked), format: .fixed(precision: 2))s")
    }

    /// A source's link asks before Hex starts telling it what you type.
    private func offer(_ source: Source) {
        let alert = UIAlertController(
            title: "Add “\(source.name)”?",
            message: "With Allow Full Access on, Hex will send \(source.url.host() ?? "it") the text of the field you’re typing in, except passwords and codes, and show the hints it answers with above the keys.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in SourceStore.add(source) })
        window?.rootViewController?.present(alert, animated: true)
    }
}

extension Notification.Name {
    /// Voice Typing, Transcripts, Learn My Taps or Show Your Taps changed (espanso-keyboard).
    static let hexTabsChanged = Notification.Name("HexTabsChanged")
}
