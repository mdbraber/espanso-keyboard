import Foundation
import KeyboardUI

/// Where the app keeps its copy of the owner's Espanso folder for the keyboard (espanso-keyboard, plan step 5).
///
/// `<app group>/Espanso/` holds one folder per copy, named by a UUID, and `current`, a symbolic link to the copy in use.
/// The app fills a new folder and then points `current` at it with one `rename`, so the keyboard never sees half a copy.
nonisolated enum EspansoLibrary {
    static var root: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)?
            .appending(path: "Espanso", directoryHint: .isDirectory)
    }

    /// The copy in use, or nil before the first one (or without access to the app group).
    static var current: URL? {
        guard let root, let name = try? FileManager.default.destinationOfSymbolicLink(atPath: root.appending(path: "current").path)
        else { return nil }
        return root.appending(path: name, directoryHint: .isDirectory)
    }
}
