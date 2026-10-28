import EspansoKeyboardCore
import Foundation

/// Adds and edits snippets in the owner's Espanso folder in iCloud Drive (espanso-keyboard, plan step 6, item 6; see
/// docs/decisions.md). A change is tried on a scratch copy first and written only if Espanso loads it without new
/// warnings; then the keyboard's copy is made again.
nonisolated enum EspansoEditor {
    /// New snippets go here, as Espanso on the Mac loads every file in `match/`.
    static let newSnippetsFile = "iphone.yml"

    enum Failure: LocalizedError {
        case noFolder
        case notFound(String)
        case rejected([String])

        var errorDescription: String? {
            switch self {
            case .noFolder: "Choose your Espanso folder first."
            case .notFound(let trigger): "\(trigger) isn't in its file any more. Reload and try again."
            case .rejected(let warnings): "Espanso can't load it: \(warnings.joined(separator: "\n"))"
            }
        }
    }

    /// Adds a snippet to `match/iphone.yml`.
    @discardableResult
    static func add(trigger: String, replace: String, label: String?, word: Bool) throws -> EspansoImport.Summary {
        try change(file: newSnippetsFile) { text in
            appendSnippet(file: text, trigger: trigger, replace: replace, label: label, word: word)
        }
    }

    /// The snippet's lines as they are in its file.
    static func block(of snippet: SnippetSummary) throws -> String {
        let text = try read(file: snippet.file)
        guard let block = snippetBlock(file: text, key: snippet.triggers[0]) else { throw Failure.notFound(snippet.triggers[0]) }
        return block
    }

    /// Replaces the snippet's lines with `block`.
    @discardableResult
    static func replace(_ snippet: SnippetSummary, with block: String) throws -> EspansoImport.Summary {
        try change(file: snippet.file) { text in
            guard let edited = replaceSnippet(file: text, key: snippet.triggers[0], block: block) else {
                throw Failure.notFound(snippet.triggers[0])
            }
            return edited
        }
    }

    // MARK: Files

    private static func matchFile(_ name: String) throws -> URL {
        guard let folder = EspansoImport.sourceFolder else { throw Failure.noFolder }
        return folder.appending(path: "match").appending(path: name)
    }

    /// The file's text, or empty for a file that doesn't exist yet.
    private static func read(file name: String) throws -> String {
        let url = try matchFile(name)
        return try EspansoImport.accessing(url.deletingLastPathComponent().deletingLastPathComponent()) {
            var coordinationError: NSError?
            var result: Result<String, Error> = .success("")
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                guard FileManager.default.fileExists(atPath: readable.path) else { return }
                result = Result { try String(contentsOf: readable, encoding: .utf8) }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }
    }

    /// Reads the file, changes its text, checks the result on a scratch copy, writes it and copies the folder again.
    private static func change(file name: String, _ edit: (String) throws -> String) throws -> EspansoImport.Summary {
        let url = try matchFile(name)
        let text = try read(file: name)
        let edited = try edit(text)
        try check(edited, as: name)
        try EspansoImport.accessing(url.deletingLastPathComponent().deletingLastPathComponent()) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writable in
                do { try edited.write(to: writable, atomically: true, encoding: .utf8) } catch { writeError = error }
            }
            if let error = coordinationError ?? writeError { throw error }
        }
        return try EspansoImport.reload()
    }

    /// Loads the keyboard's copy with `text` as match file `name`, and refuses warnings the copy doesn't already have.
    private static func check(_ text: String, as name: String) throws {
        let files = FileManager.default
        let scratch = files.temporaryDirectory.appending(path: "espanso-check-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? files.removeItem(at: scratch) }
        if let current = EspansoLibrary.current {
            try files.copyItem(at: current, to: scratch)
        } else {
            try files.createDirectory(at: scratch.appending(path: "config"), withIntermediateDirectories: true)
            try "".write(to: scratch.appending(path: "config/default.yml"), atomically: true, encoding: .utf8)
        }
        let before = warnings(in: scratch)
        let file = scratch.appending(path: "match").appending(path: name)
        try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        let after = try EspansoEngine(configFolder: scratch.path, scriptRunner: JavaScriptCoreScriptRunner()).warnings()
            .map { $0.replacingOccurrences(of: scratch.path + "/", with: "") }
        let new = after.filter { !before.contains($0) }
        if !new.isEmpty { throw Failure.rejected(new) }
    }

    private static func warnings(in folder: URL) -> [String] {
        let engine = try? EspansoEngine(configFolder: folder.path, scriptRunner: JavaScriptCoreScriptRunner())
        return (engine?.warnings() ?? []).map { $0.replacingOccurrences(of: folder.path + "/", with: "") }
    }
}
