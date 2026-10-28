import KeyboardArbiter
import OSLog
import UIKit

/// The app the keyboard is typing in, so voice typing can send you back to it. iOS stopped telling keyboards since
/// 26.4, but the view controller still holds its host's process ID, and UIKit's keyboard arbiter, once switched on
/// (`KeyboardArbiter`), names the app it is serving with that app's process ID, sometimes an app you already left. So
/// each name is kept under its process ID, only until the keyboard next appears, when the host can change, and the host
/// is the name kept under the host's ID or none. Dictus found and measured this (getdictus/dictus-ios#538, MIT). None of
/// it is API: a missing step answers nil.
enum KeyboardHost {
    nonisolated static let log = Logger(subsystem: "com.shahidy.hexkeyboard", category: "voice")
    private static var names: [Int: String] = [:]

    static func appeared() {
        names = [:]
        HexEnableKeyboardArbiter()
        if let client, value(client, "connection") == nil, client.responds(to: NSSelectorFromString("startConnection")) {
            client.perform(NSSelectorFromString("startConnection"))
        }
        harvest()
    }

    /// Keeps the app the arbiter names now.
    static func harvest() {
        guard let state = client.flatMap({ value($0, "currentClientState") }) as? NSObject,
              let name = value(state, "sourceBundleIdentifier") as? String, !name.isEmpty,
              let id = (value(state, "processIdentifier") as? NSNumber)?.intValue, id > 0
        else { return }
        names[id] = name
    }

    static func app(of keyboard: UIInputViewController) -> String? {
        harvest()
        let id = (value(keyboard, "_hostProcessIdentifier") as? NSNumber)?.intValue ?? 0
        let app = names[id]
        log.notice("host \(id) is \(app ?? "unknown", privacy: .public) of \(names.count) known")
        return app
    }

    private static var client: NSObject? {
        let shared = NSSelectorFromString("automaticSharedArbiterClient")
        guard let type = NSClassFromString("_UIKeyboardArbiterClient") as AnyObject?, type.responds(to: shared) else { return nil }
        return type.perform(shared)?.takeUnretainedValue() as? NSObject
    }

    private static func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
}
