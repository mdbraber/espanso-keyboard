import AVFoundation
import KeyboardUI
import Speech
import UIKit

/// The microphone and the transcriber behind the keyboard's voice typing. It transcribes on the iPhone as you speak
/// (Apple's SpeechTranscriber, the iOS 26 model, not the older one behind the system's dictation key), so when you're
/// done only the last words are left to finish. After you dictate it keeps the microphone on for as long as Keep Mic On
/// says, so the keyboard can start the next dictation (`start`) without opening the app, which is the only place iOS
/// lets a recording begin.
@MainActor final class Listener {
    static let shared = Listener()

    private let engine = AVAudioEngine()
    private let feed = Feed()
    private var micLock: Int32?
    private var micOff: Task<Void, Never>?
    private var analyzer: SpeechAnalyzer?
    private var heard: Task<String, any Error>?
    private var tokens: [Int32] = []
    private var started = Date.now
    private var listened: Double = 0
    private(set) var state = Dictation.State.idle
    var onChange: (() -> Void)?
    var onLevel: ((Float) -> Void)?

    private init() {
        tokens = [
            Dictation.observe(.finish) { Task { await Listener.shared.finish() } },
            Dictation.observe(.start) {
                guard Listener.shared.micLock != nil else { return }
                Task { await Listener.shared.start() }
            },
            Dictation.observe(.stop) { Task { await Listener.shared.turnMicOff() } },
        ]
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            guard note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { await Listener.shared.turnMicOff() }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            Task { @MainActor in
                guard !Listener.shared.engine.isRunning else { return }
                await Listener.shared.turnMicOff()
            }
        }
    }

    /// Returns once the microphone is recording, the one step iOS allows only in the foreground; the transcriber
    /// gets ready in the background and catches up on what was said meanwhile.
    func start() async {
        guard state == .idle else { return }
        micOff?.cancel()
        set(.listening)
        started = .now
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw Failure.microphone }
            let (module, heard) = try await Self.transcriber()
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw Failure.language }
            let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
            self.heard = heard
            try openMic()
            if state == .listening {
                guard feed.start(from: engine.inputNode.outputFormat(forBus: 0), to: format, into: input) else { throw Failure.language }
            } else {
                input.finish()
            }
            Task { await analyze(stream, with: module) }
        } catch {
            await fail(error)
        }
    }

    private func analyze(_ stream: AsyncStream<AnalyzerInput>, with module: any SpeechModule) async {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await request.downloadAndInstall() }
            let analyzer = SpeechAnalyzer(modules: [module])
            self.analyzer = analyzer
            try await analyzer.start(inputSequence: stream)
            switch state {
            case .transcribing: await deliver(analyzer)
            case .idle:
                await analyzer.cancelAndFinishNow()
                reset()
            case .listening: break
            }
            keepMicOn()
        } catch {
            await fail(error)
        }
    }

    private func fail(_ error: any Error) async {
        feed.stop()
        closeMic()
        await analyzer?.cancelAndFinishNow()
        reset()
        set(.idle, failure: (error as? Failure)?.description ?? error.localizedDescription)
    }

    /// Stops listening and hands the keyboard everything heard, once the transcriber is up if it isn't yet.
    func finish() async {
        guard state == .listening else { return }
        feed.stop()
        listened = Date.now.timeIntervalSince(started)
        set(.transcribing)
        keepMicOn()
        if let analyzer { await deliver(analyzer) }
    }

    private func deliver(_ analyzer: SpeechAnalyzer) async {
        let background = UIApplication.shared.beginBackgroundTask()
        defer { UIApplication.shared.endBackgroundTask(background) }
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = (try await heard?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            set(.idle, heard: text)
            Transcripts.shared.add(text, at: started, seconds: listened, typed: true)
        } catch {
            set(.idle, failure: error.localizedDescription)
        }
        reset()
    }

    /// Types nothing. What was said while listening is still written down, for Transcripts.
    func cancel() async {
        guard state != .idle else { return }
        feed.stop()
        let (analyzer, heard, started, wasListening) = (analyzer, heard, started, state == .listening)
        reset()
        set(.idle)
        keepMicOn()
        guard wasListening, Transcripts.isKept, let analyzer, let heard else {
            await analyzer?.cancelAndFinishNow()
            heard?.cancel()
            return
        }
        let background = UIApplication.shared.beginBackgroundTask()
        defer { UIApplication.shared.endBackgroundTask(background) }
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        guard let text = try? await heard.value.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        Transcripts.shared.add(text, at: started, seconds: Date.now.timeIntervalSince(started), typed: false)
    }

    /// Starts Keep Mic On's countdown over, or turns the microphone off now when it's Off.
    func keepMicOn() {
        micOff?.cancel()
        guard micLock != nil, state != .listening else { return }
        let seconds = SettingsStore.keepMicOn
        guard seconds > 0 else { return closeMic() }
        guard seconds != Dictation.micForever else { return }
        micOff = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, state != .listening else { return }
            closeMic()
        }
    }

    /// You held the keyboard's mic, another app took the microphone (a call), or the route changed under the engine:
    /// keep what was heard, and leave the microphone off so the next dictation opens the app and starts it afresh.
    func turnMicOff() async {
        guard micLock != nil else { return }
        await finish()
        closeMic()
    }

    private func reset() {
        analyzer = nil
        heard = nil
    }

    private func set(_ state: Dictation.State, heard: String? = nil, failure: String? = nil) {
        self.state = state
        Dictation.publish(Dictation.Status(state: state, heard: heard.flatMap { $0.isEmpty ? nil : $0 }, failure: failure))
        onChange?()
    }

    /// Mixes with whatever else is playing, so music keeps going while you talk.
    private func openMic() throws {
        guard micLock == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
        let node = engine.inputNode
        node.installTap(onBus: 0, bufferSize: 4096, format: node.outputFormat(forBus: 0), block: Self.tap(feed) { level in
            Dictation.publish(level: level)
            Task { @MainActor in Listener.shared.onLevel?(level) }
        })
        engine.prepare()
        do {
            try engine.start()
        } catch {
            node.removeTap(onBus: 0)
            throw error
        }
        micLock = Dictation.lockMic() ?? -1
        Dictation.send(.changed)
    }

    private func closeMic() {
        micOff?.cancel()
        micOff = nil
        guard let micLock else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if micLock >= 0 { Dictation.unlockMic(micLock) }
        self.micLock = nil
        Dictation.send(.changed)
    }

    /// Runs on the audio thread: hands each buffer to the dictation in progress, if there is one, and says how loud it was.
    nonisolated private static func tap(_ feed: Feed, level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            guard feed.yield(buffer) else { return }
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for index in 0 ..< frames { sum += samples[index] * samples[index] }
                level((sum / Float(frames)).squareRoot())
            }
        }
    }

    /// The newer SpeechTranscriber where the iPhone has it, else the dictation model with punctuation.
    private static func transcriber() async throws -> (any SpeechModule, Task<String, any Error>) {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            return (module, Task {
                var text = ""
                for try await result in module.results where result.isFinal { text += String(result.text.characters) }
                return text
            })
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else { throw Failure.language }
        let module = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [], attributeOptions: [])
        return (module, Task {
            var text = ""
            for try await result in module.results where result.isFinal { text += String(result.text.characters) }
            return text
        })
    }

    private enum Failure: Error, CustomStringConvertible {
        case microphone, language

        var description: String {
            switch self {
            case .microphone: "Hex needs the microphone. Turn it on in Settings › Apps › Hex."
            case .language: "Voice typing doesn't support this iPhone's language yet."
            }
        }
    }
}

/// Where the microphone's buffers go: to the dictation in progress, converted to the transcriber's format, or nowhere
/// while the microphone is only being kept on. The audio thread reads it and the main thread swaps it, under a lock.
nonisolated private final class Feed: @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var format: AVAudioFormat?
    private var input: AsyncStream<AnalyzerInput>.Continuation?

    func start(from natural: AVAudioFormat, to format: AVAudioFormat, into input: AsyncStream<AnalyzerInput>.Continuation) -> Bool {
        guard let converter = AVAudioConverter(from: natural, to: format) else { return false }
        lock.withLock {
            self.converter = converter
            self.format = format
            self.input = input
        }
        return true
    }

    func stop() {
        let input = lock.withLock {
            let input = self.input
            converter = nil
            format = nil
            self.input = nil
            return input
        }
        input?.finish()
    }

    /// Whether a dictation took the buffer.
    func yield(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.withLock {
            guard let converter, let format, let input else { return false }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return false }
            nonisolated(unsafe) var fed = false
            converter.convert(to: converted, error: nil) { _, status in
                status.pointee = fed ? .noDataNow : .haveData
                defer { fed = true }
                return fed ? nil : buffer
            }
            input.yield(AnalyzerInput(buffer: converted))
            return true
        }
    }
}
