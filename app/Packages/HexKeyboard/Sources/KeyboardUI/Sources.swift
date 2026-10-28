import Foundation
import KeyboardCore
import UIKit

/// A service the keyboard tells what you type, which can answer with a hint over the suggestions (docs/sources.md).
nonisolated public struct Source: Codable, Hashable, Sendable {
    public var name: String
    public var url: URL
    public var token: String?

    public init(name: String, url: URL, token: String? = nil) {
        self.name = name
        self.url = url
        self.token = token
    }

    /// `hexkeyboard://source?name=…&url=…&token=…`, the link a source gives you to add it.
    public init?(link: URL) {
        guard link.scheme == "hexkeyboard", link.host() == "source",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let name = items.first(where: { $0.name == "name" })?.value, !name.isEmpty,
              let url = items.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)), Self.allows(url)
        else { return nil }
        self.init(name: name, url: url, token: items.first { $0.name == "token" }?.value)
    }

    /// iOS lets a keyboard reach `https` anywhere, and `http` only on the local network (`localhost`, `.local`).
    public static func allows(_ url: URL) -> Bool {
        url.scheme == "https" || url.scheme == "http" && url.host().map { $0 == "localhost" || $0.hasSuffix(".local") } == true
    }
}

/// The sources you added in the app, kept like every other setting.
public enum SourceStore {
    private static let key = "sources"

    public static func load(sharing: Bool = true) -> [Source] {
        (SettingsStore.value(forKey: key, sharing: sharing) as? Data).flatMap { try? JSONDecoder().decode([Source].self, from: $0) } ?? []
    }

    public static func save(_ sources: [Source]) {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        SettingsStore.set(data, forKey: key)
    }

    /// Adds `source`, in place of one with the same name.
    public static func add(_ source: Source) {
        save(load().filter { $0.name != source.name } + [source])
    }
}

/// Sends each source the field you're typing in and keeps the hint it answers with. The request is encoded and sent
/// off the main thread, and the next one waits for the answer, so a slow source never holds up a tap.
final class Sources {
    var onHint: () -> Void = {}
    private var sources: [Source] = []
    private var feeds: [SourceFeed] = []

    func reload() {
        let sources = SourceStore.load()
        guard sources != self.sources else { return }
        self.sources = sources
        feeds = sources.map { _ in SourceFeed() }
    }

    func observe(_ update: FieldUpdate) {
        for index in feeds.indices {
            feeds[index].observe(update)
            send(index)
        }
    }

    func hint(for field: String) -> String? {
        feeds.lazy.compactMap { $0.hint(for: field) }.first
    }

    func dismissHint() {
        feeds.indices.forEach { feeds[$0].dismissHint() }
    }

    private func send(_ index: Int) {
        guard let update = feeds[index].next() else { return }
        let source = sources[index]
        Task { [weak self] in
            let answer = await Self.post(update, to: source)
            self?.receive(answer, for: update, from: source, at: index)
        }
    }

    private func receive(_ answer: Answer?, for update: FieldUpdate, from source: Source, at index: Int) {
        guard sources.indices.contains(index), sources[index] == source else { return }
        if let answer { feeds[index].answered(update, hint: answer.hint) } else { feeds[index].failed(update) }
        onHint()
        send(index)
    }

    nonisolated private struct Request: Encodable {
        let field: String
        let before: String
        let after: String
        let by: String
        let kind: String
        let returnKey: String
        let at: String

        init(_ update: FieldUpdate) {
            field = update.field
            before = update.before
            after = update.after
            by = update.by.rawValue
            kind = "\(update.traits.kind)"
            returnKey = "\(update.traits.returnKind)"
            at = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(Date(timeIntervalSince1970: update.at))
        }
    }

    nonisolated private struct Answer: Decodable {
        var hint: String?
    }

    nonisolated private static let session = URLSession(configuration: .ephemeral)

    @concurrent nonisolated private static func post(_ update: FieldUpdate, to source: Source) async -> Answer? {
        var request = URLRequest(url: source.url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = source.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONEncoder().encode(Request(update))
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
        else { return nil }
        return data.isEmpty ? Answer() : try? JSONDecoder().decode(Answer.self, from: data)
    }
}

extension UITextDocumentProxy {
    /// `documentIdentifier` is declared nonnull but is nil until the keyboard has a field, and bridging nil traps.
    var field: String? {
        ((self as? NSObject)?.perform(#selector(getter: UITextDocumentProxy.documentIdentifier))?.takeUnretainedValue() as? NSUUID)?.uuidString
    }

    /// Fields whose text never goes to a source. iOS already swaps in its own keyboard for secure fields.
    var isPrivate: Bool {
        guard let content = textContentType ?? nil else { return false }
        return [.password, .newPassword, .oneTimeCode, .creditCardNumber, .creditCardSecurityCode].contains(content)
    }
}
