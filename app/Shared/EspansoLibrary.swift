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

/// Settings and records the app and the keyboard share through the app group (espanso-keyboard, plan step 6). Snippets
/// are named by their first trigger (or regex), which stays the same across copies.
nonisolated enum EspansoShared {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SettingsStore.appGroup) }

    /// Whether typing expands snippets; the snippet panel works either way.
    static var isEnabled: Bool {
        get { defaults?.object(forKey: "EspansoEnabled") as? Bool ?? true }
        set { defaults?.set(newValue, forKey: "EspansoEnabled") }
    }

    /// Whether the suggestion bar shows the snippets button.
    static var showsButton: Bool {
        get { defaults?.object(forKey: "EspansoButton") as? Bool ?? true }
        set { defaults?.set(newValue, forKey: "EspansoButton") }
    }

    /// Set by the app while you type an example of a trigger, so the keyboard doesn't expand it there.
    static var isPaused: Bool {
        get { defaults?.bool(forKey: "EspansoPaused") ?? false }
        set { defaults?.set(newValue, forKey: "EspansoPaused") }
    }

    /// Favourite snippets, first in the keyboard's snippet panel.
    static var favourites: [String] {
        get { defaults?.stringArray(forKey: "EspansoFavourites") ?? [] }
        set { defaults?.set(newValue, forKey: "EspansoFavourites") }
    }

    static func toggleFavourite(_ snippet: String) {
        var favourites = favourites
        if let index = favourites.firstIndex(of: snippet) { favourites.remove(at: index) } else { favourites.append(snippet) }
        self.favourites = favourites
    }

    struct Usage: Codable, Hashable {
        var count: Int
        var last: Date
    }

    private static var usageFile: URL? { EspansoLibrary.root?.appending(path: "usage.json") }

    /// How often each snippet expanded, counted by the keyboard on this iPhone.
    static func usage() -> [String: Usage] {
        guard let file = usageFile, let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: Usage].self, from: data)) ?? [:]
    }

    /// Counts one expansion. The keyboard can write the app group only with Full Access; without it this does nothing.
    static func recordUse(of snippet: String) {
        guard !snippet.isEmpty, let file = usageFile else { return }
        var usage = usage()
        usage[snippet, default: Usage(count: 0, last: .now)].count += 1
        usage[snippet]?.last = .now
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(usage).write(to: file, options: .atomic)
    }
}
