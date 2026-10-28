import EspansoKeyboardCore
import Foundation
import os

/// Copies the owner's Espanso folder, picked once in iCloud Drive, into the app group for the keyboard
/// (espanso-keyboard, plan step 5). See `EspansoLibrary` for the layout.
nonisolated enum EspansoImport {
    /// The folders Espanso reads, copied as they are.
    static let folders = ["config", "match", "scripts"]

    struct Summary: Codable, Hashable {
        var folderName: String
        var snippets: Int
        var warnings: [String]
        var date: Date
        /// The snippets the keyboard expands; missing from copies made before it was added.
        var items: [Snippet]?
    }

    /// One snippet as Espanso's search bar shows it.
    struct Snippet: Codable, Hashable {
        var triggers: [String]
        var label: String
    }

    enum Failure: LocalizedError {
        case noAppGroup
        case noFolder
        /// The picked folder has no `config` folder; `contents` is what it does have.
        case notEspanso(folder: String, contents: [String])
        /// Espanso couldn't load the copy.
        case load(String)

        var errorDescription: String? {
            switch self {
            case .noAppGroup: "The app group isn't available, so the keyboard can't get a copy."
            case .noFolder: "Choose your Espanso folder first."
            case .notEspanso(let folder, let contents):
                "“\(folder)” has no config folder, so it isn't an Espanso folder. Pick the one with config and match in it. "
                    + (contents.isEmpty ? "“\(folder)” looks empty." : "“\(folder)” has: \(contents.joined(separator: ", ")).")
            case .load(let message): "Espanso couldn't load it: \(message)."
            }
        }
    }

    private static let log = Logger(subsystem: "espanso-keyboard", category: "import")
    private static let bookmarkKey = "EspansoFolderBookmark"
    private static let summaryKey = "EspansoLastCopy"

    // MARK: The picked folder

    static func remember(_ folder: URL) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        UserDefaults.standard.set(try folder.bookmarkData(), forKey: bookmarkKey)
    }

    /// The picked folder, from its bookmark; renewed when iOS reports it stale.
    static var rememberedFolder: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale { try? remember(folder) }
        return folder
    }

    /// The folder copies are made from and edits go to: the picked folder, or in Debug builds the one given with
    /// `-EspansoImport`.
    static var sourceFolder: URL? {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "EspansoImport") {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        #endif
        return rememberedFolder
    }

    /// Runs `body` with access to `folder`, which a picked folder needs.
    static func accessing<T>(_ folder: URL, _ body: () throws -> T) rethrows -> T {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// What the last successful copy found.
    static var lastSummary: Summary? {
        UserDefaults.standard.data(forKey: summaryKey).flatMap { try? JSONDecoder().decode(Summary.self, from: $0) }
    }

    // MARK: Copying

    /// Copies the remembered folder again off the main thread, if one was picked.
    static func reloadInBackground() {
        // Nothing in Hex is being edited as it comes to the front: the keyboard expands again.
        EspansoShared.isPaused = false
        guard rememberedFolder != nil else { return }
        Task.detached(priority: .utility) {
            do { try reload() } catch { log.error("copy failed: \(describe(error), privacy: .public)") }
        }
    }

    /// `-EspansoImport <folder>` copies that folder at launch, for the UI tests (Debug builds only). It also turns
    /// expanding on and clears favourites and usage counts, so each test starts the same.
    static func copyIfAsked() {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "EspansoImport") else { return }
        EspansoShared.isEnabled = true
        EspansoShared.isPaused = false
        EspansoShared.favourites = []
        if let root = EspansoLibrary.root { try? FileManager.default.removeItem(at: root.appending(path: "usage.json")) }
        do { try copy(from: URL(filePath: path, directoryHint: .isDirectory)) } catch {
            log.error("copy of \(path, privacy: .public) failed: \(describe(error), privacy: .public)")
        }
        #endif
    }

    /// Copies the remembered folder again.
    @discardableResult
    static func reload() throws -> Summary {
        guard let folder = sourceFolder else { throw Failure.noFolder }
        return try copy(from: folder)
    }

    /// Copies `config/`, `match/` and `scripts/` from `source` into a new folder in the app group, loads it as the
    /// keyboard will to check it and collect Espanso's warnings, then makes it the current copy.
    @discardableResult
    static func copy(from source: URL) throws -> Summary {
        guard let root = EspansoLibrary.root else { throw Failure.noAppGroup }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let files = FileManager.default
        guard files.fileExists(atPath: source.appending(path: "config").path) else {
            let contents = (try? files.contentsOfDirectory(atPath: source.path)) ?? []
            throw Failure.notEspanso(folder: source.lastPathComponent, contents: contents.sorted())
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let name = UUID().uuidString
        let copy = root.appending(path: name, directoryHint: .isDirectory)
        do {
            for folder in folders {
                let from = source.appending(path: folder, directoryHint: .isDirectory)
                guard files.fileExists(atPath: from.path) else { continue }
                try copyFolder(from, to: copy.appending(path: folder, directoryHint: .isDirectory))
            }
            let engine: EspansoEngine
            do {
                engine = try EspansoEngine(configFolder: copy.path, scriptRunner: JavaScriptCoreScriptRunner())
            } catch EspansoError.Load(let message) {
                throw Failure.load(message)
            }
            let snippets = engine.search(query: "").map { Snippet(triggers: $0.triggers, label: $0.label) }
            let summary = Summary(
                folderName: source.lastPathComponent, snippets: snippets.count,
                warnings: engine.warnings(), date: Date(), items: snippets)
            try makeCurrent(name, in: root)
            removeOldCopies(in: root, keeping: name)
            UserDefaults.standard.set(try JSONEncoder().encode(summary), forKey: summaryKey)
            return summary
        } catch {
            try? files.removeItem(at: copy)
            throw error
        }
    }

    /// Copies a folder's files one by one, each through a file coordinator so iCloud Drive downloads it first.
    private static func copyFolder(_ source: URL, to destination: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try files.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) {
            var name = item.lastPathComponent
            var item = item
            // A file iCloud Drive hasn't downloaded may show as ".name.icloud".
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
                item = source.appending(path: name)
                try? files.startDownloadingUbiquitousItem(at: item)
            } else if name.hasPrefix(".") {
                continue
            }
            let target = destination.appending(path: name)
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try copyFolder(item, to: target)
                continue
            }
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: item, options: [], error: &coordinationError) { readable in
                do { try files.copyItem(at: readable, to: target) } catch { copyError = error }
            }
            if let error = coordinationError ?? copyError { throw error }
        }
    }

    /// Points `current` at `name` in one step: a new link renamed over the old one.
    private static func makeCurrent(_ name: String, in root: URL) throws {
        let link = root.appending(path: "current")
        let next = root.appending(path: "current-\(name)")
        try FileManager.default.createSymbolicLink(atPath: next.path, withDestinationPath: name)
        guard rename(next.path, link.path) == 0 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            try? FileManager.default.removeItem(at: next)
            throw error
        }
    }

    /// Keeps the new copy and the one before it, which a keyboard still open may be reading scripts from.
    private static func removeOldCopies(in root: URL, keeping name: String) {
        let files = FileManager.default
        let copies = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let old = copies
            .filter { $0.lastPathComponent != name && UUID(uuidString: $0.lastPathComponent) != nil }
            .sorted { creation($0) > creation($1) }
            .dropFirst()
        for copy in old { try? files.removeItem(at: copy) }
    }

    private static func creation(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}
