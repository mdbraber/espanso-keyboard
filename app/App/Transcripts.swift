import Foundation
import Observation

struct Transcript: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var seconds: Double
    /// False when you tapped ✕: kept here, never typed.
    var typed: Bool

    var words: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// Every dictation the app transcribed, newest first, in one JSON line each in the app's own container. Nothing leaves
/// the iPhone: the keyboard never reads it and the app has no network code.
@Observable final class Transcripts {
    static let shared = Transcripts()

    private(set) var all: [Transcript] = []
    @ObservationIgnored private let url = URL.applicationSupportDirectory.appending(path: "transcripts.jsonl")

    private init() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        all = data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(Transcript.self, from: $0) }.reversed()
    }

    func add(_ text: String, at date: Date, seconds: Double, typed: Bool) {
        guard !text.isEmpty else { return }
        let transcript = Transcript(date: date, text: text, seconds: seconds, typed: typed)
        all.insert(transcript, at: 0)
        guard let line = try? JSONEncoder().encode(transcript) else { return }
        do {
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd()
            try file.write(contentsOf: line + [UInt8(ascii: "\n")])
        } catch {
            save()
        }
    }

    func delete(_ ids: Set<Transcript.ID>) {
        all.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        let lines = all.reversed().compactMap { try? encoder.encode($0) + [UInt8(ascii: "\n")] }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(lines.joined()).write(to: url, options: .atomic)
    }
}
