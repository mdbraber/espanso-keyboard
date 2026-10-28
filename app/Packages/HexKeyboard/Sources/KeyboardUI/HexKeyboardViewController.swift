import UIKit
import KeyboardCore

open class HexKeyboardViewController: UIInputViewController {
    open var hapticsEnabled: Bool { hasFullAccess && engine.settings.haptics }
    /// Snippet expansion, if the app provides one (espanso-keyboard). Set before `viewDidLoad`.
    public var expander: TextExpander?

    private let keyboardView = KeyboardView()
    private var dictation = Dictation.Status()
    private var micIsOn = false
    private var dictationTokens: [Int32] = []
    private let suggestionBar = SuggestionBar()
    private lazy var document = ProxyDocument { [unowned self] in textDocumentProxy }
    private var engine = TypingEngine()
    private lazy var barHeightConstraint = suggestionBar.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keyboardHeightConstraint = keyboardView.heightAnchor.constraint(equalToConstant: 0)
    private var deleteRepeat: DeleteRepeat?
    private let haptics = KeyHaptics()
    private let sources = Sources()

    override open func loadView() {
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .default)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        [suggestionBar, keyboardView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        keyboardHeightConstraint.priority = .required - 1
        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor),
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHeightConstraint,
            keyboardView.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardHeightConstraint,
        ])
        suggestionBar.onMic = { [unowned self] in toggleVoice() }
        suggestionBar.onNotice = { [unowned self] in
            if dictation.failure != nil { return clearFailure() }
            sources.dismissHint()
            render()
        }
        sources.onHint = { [unowned self] in render() }
        suggestionBar.onMicHold = { [unowned self] in
            feedback(.other)
            Dictation.send(.stop)
        }
        engine.defersSuggestions = true
        keyboardView.onEvent = { [unowned self] in handle($0) }
        suggestionBar.onSelect = { [unowned self] in
            feedback(.input)
            engine.accept($0, in: document)
            expander?.reset()
            render()
        }
        suggestionBar.onEmoji = { [unowned self] in
            feedback(.input)
            engine.accept(emoji: $0, in: document)
            expander?.reset()
            render()
        }
        engine.corrector = Corrector(source: Lexicon.english, phrases: .english)
        Task { [weak self] in
            let catalog = await Task.detached(priority: .userInitiated) { EmojiCatalog.english }.value
            self?.engine.emojiCatalog = catalog
            self?.engine.suggestionsChanged()
            self?.render()
        }
        keyboardView.resolve = { [unowned self] grid, point in engine.key(atX: point.x, y: point.y, in: grid) }
        keyboardView.onGrid = { [unowned self] in engine.use($0) }
        keyboardView.globeTarget = { [unowned self] control in
            control.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.render() }
        if hasFullAccess { sources.reload() }
        syncWithDocument()
    }

    override open func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        render()
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        TouchTrace.shared.layout(view)
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        KeyboardHost.appeared()
        engine.settings = SettingsStore.load(sharing: hasFullAccess)
        engine.corrector?.memory = MemoryStore.load()
        engine.emojiHistory = MemoryStore.loadEmoji()
        if hasFullAccess, dictationTokens.isEmpty {
            dictationTokens = [
                Dictation.observe(.changed) { [weak self] in self?.dictationChanged() },
                Dictation.observeLevel { [weak self] in self?.suggestionBar.hear($0) },
            ]
            dictationChanged()
        }
        engine.suggestionsChanged()
        keyboardView.characterPreview = engine.settings.characterPreview
        if hasFullAccess { sources.reload() }
        expander?.reset()
        syncWithDocument()
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if hapticsEnabled { haptics.start() }
        stopSystemGesturesDelayingTouches()
        TouchTrace.shared.watch(view.window)
        Task { [weak self] in
            guard let lexicon = await self?.requestSupplementaryLexicon() else { return }
            self?.engine.corrector?.learn(lexicon)
            self?.engine.suggestionsChanged()
            self?.render()
        }
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        engine.endSession()
        haptics.stop()
        TouchTrace.shared.flush()
        if let memory = engine.corrector?.memory { MemoryStore.save(memory, sharing: hasFullAccess) }
        MemoryStore.save(engine.emojiHistory)
        dictationTokens.forEach(Dictation.stopObserving)
        dictationTokens = []
    }

    override open func selectionDidChange(_ textInput: UITextInput?) {
        KeyboardHost.harvest()
        syncWithDocument()
    }

    override open func textDidChange(_ textInput: UITextInput?) {
        KeyboardHost.harvest()
        syncWithDocument()
    }

    private func syncWithDocument() {
        engine.update(InputTraits(textDocumentProxy))
        let known = engine.text.before.count
        let report = engine.documentChanged(document)
        if report == .changed {
            tellSources(.app)
            expander?.reset()
        }
        TouchTrace.shared.record(report, host: textDocumentProxy.documentContextBeforeInput?.count ?? 0, known: known)
        render()
    }

    private var screenSize: CGSize {
        view.window?.windowScene?.screen.bounds.size ?? view.bounds.size
    }

    private var device: DeviceClass {
        let shortSide = min(screenSize.width, screenSize.height)
        guard traitCollection.userInterfaceIdiom == .pad else { return shortSide >= 600 ? .compactPad : .phone }
        return shortSide >= 1000 ? .largePad : shortSide < 800 ? .compactPad : .pad
    }

    private var mic: MicButton.Phase {
        switch dictation.state {
        case .listening: .listening
        case .transcribing: .transcribing
        case .idle: micIsOn ? .on : .off
        }
    }

    /// What a source sees: the field's text as the keyboard knows it, with Full Access, outside password and code fields.
    private func tellSources(_ author: FieldUpdate.Author) {
        guard hasFullAccess, !textDocumentProxy.isPrivate, let field = textDocumentProxy.field else { return }
        sources.observe(FieldUpdate(
            field: field, before: engine.text.before, after: engine.text.after ?? "", by: author, traits: engine.traits,
            at: Date().timeIntervalSince1970
        ))
    }

    private var hint: String? {
        guard hasFullAccess, let field = textDocumentProxy.field else { return nil }
        return sources.hint(for: field)
    }

    private func render() {
        tellSources(.keyboard)
        let device = device
        let context = engine.layout(on: device, showsGlobe: needsInputModeSwitchKey, isLandscape: screenSize.width > screenSize.height)
        let layout = Layouts.layout(for: context)
        let metrics = KeyboardMetrics.for(device, width: screenSize.width, height: screenSize.height, style: .current, oneHanded: context.oneHanded)
        keyboardView.menu = (context.menuKey(in: layout), context.menu, context.oneHanded)
        keyboardView.update(layout: layout, signature: context.signature, metrics: metrics, faces: engine.faces(on: device), theme: theme)
        suggestionBar.maximumSlotWidth = device == .phone ? .infinity : 154.5
        suggestionBar.keyInset = metrics.sideInset
        suggestionBar.topPadding = device == .phone ? 10 : 0
        suggestionBar.update(mic: mic, notice: dictation.failure ?? hint, theme: theme)
        renderSuggestions()

        let height = metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
        if keyboardHeightConstraint.constant != height { keyboardHeightConstraint.constant = height }
        let bar = (device == .phone ? 38 : 36) + suggestionBar.topPadding
        if barHeightConstraint.constant != bar { barHeightConstraint.constant = bar }
    }

    private var theme: KeyboardTheme {
        KeyboardTheme.current(for: traitCollection, appearance: textDocumentProxy.keyboardAppearance)
    }

    private var ranking = false

    private func renderSuggestions() {
        guard engine.suggestionsAreStale else {
            return suggestionBar.update(engine.suggestions, emoji: engine.emojiSuggestions, enabled: engine.showsSuggestions, theme: theme)
        }
        guard !ranking, let job = engine.suggestionJob() else { return }
        ranking = true
        Task.detached(priority: .userInitiated) { [weak self] in
            var job = job
            job.run()
            await self?.finish(job)
        }
    }

    private func finish(_ job: SuggestionJob) {
        ranking = false
        engine.finish(job)
        renderSuggestions()
    }

    private func handle(_ event: KeyboardEvent) {
        switch event {
        case .down(let key, _):
            feedback(Self.haptic(for: key))
            if key.action == .delete { startDeleteRepeat() }
            if dictation.failure != nil { clearFailure() }
        case .up(let key) where key.action == .delete:
            deleteRepeat = nil
        case .trigger(let key) where key.action == .dismiss:
            return dismissKeyboard()
        case .trigger(let key) where key.action == .nextKeyboard:
            return advanceToNextInputMode()
        case .type:
            TouchTrace.shared.mark("typed")
        case .oneHanded(let hand), .pick(let hand):
            SettingsStore.set(hand, sharing: hasFullAccess)
        default:
            break
        }
        let before = engine.text.before
        if case .down(let key, _) = event, key.action == .delete, let undo = expander?.backspace() {
            return apply(undo)
        }
        if engine.handle(event, in: document) { render() }
        followEdit(from: before, by: Edit(event))
    }

    /// What a keyboard event did to the text, for the expander.
    private enum Edit {
        case typing, deleting, other

        init(_ event: KeyboardEvent) {
            switch event {
            case .type, .slide, .trigger: self = .typing
            case .down(let key, _) where key.action == .delete: self = .deleting
            default: self = .other
            }
        }
    }

    /// Tells the expander how the keyboard's edit changed the text before the caret. Text added at the caret is typing;
    /// a single character deleted is the backspace it already knows of. When the edit also replaced earlier text
    /// (autocorrect, a smart dash), the trigger in progress no longer matches the field, so the expander starts over
    /// from the added text.
    private func followEdit(from old: String, by edit: Edit) {
        guard let expander else { return }
        let new = engine.text.before
        guard new != old else { return }
        switch edit {
        case .other:
            expander.reset()
        case .deleting:
            if !(new.count == old.count - 1 && old.hasPrefix(new)) { expander.reset() }
        case .typing:
            let kept = zip(old, new).prefix { $0 == $1 }.count
            if kept < old.count { expander.reset() }
            if let expansion = expander.typed(String(new.dropFirst(kept))) { apply(expansion) }
        }
    }

    /// Applies an expansion through the engine, so its copy of the text stays the field's. A delete reaching past the
    /// text the keyboard knows can't be checked, so the expansion is dropped.
    private func apply(_ expansion: TextExpansion) {
        guard expansion.deleteCount <= engine.text.before.count else {
            expander?.reset()
            return
        }
        engine.replace(expansion.deleteCount, with: expansion.insert, movingBack: expansion.cursorOffset, in: document)
        render()
    }

    /// Stops a dictation in progress, so what was heard is typed. Otherwise starts one: in place while the app keeps the
    /// microphone on, or by opening the app, since a keyboard can't use the microphone and iOS starts a recording only
    /// in an app in front. Apps can't be opened from a keyboard through public API, so this goes through the responder
    /// chain to the host's UIApplication, as voice keyboards do.
    private func toggleVoice() {
        guard hasFullAccess else {
            dictation = Dictation.Status(failure: "Voice needs Allow Full Access in Settings › Apps › Hex › Keyboards")
            return render()
        }
        switch dictation.state {
        case .listening: return Dictation.send(.finish)
        case .transcribing: return
        case .idle: break
        }
        if dictation.failure != nil { clearFailure() }
        micIsOn = Dictation.micIsOn
        if micIsOn { return Dictation.send(.start) }
        render()
        var responder: UIResponder? = self
        while let next = responder {
            if let application = next as? UIApplication { return application.open(Dictation.Request(host: KeyboardHost.app(of: self)).url) }
            responder = next.next
        }
    }

    /// The app listened, or stopped: type what it heard, once. Listening without the app's microphone lock was left by
    /// an app that ended mid-dictation.
    private func dictationChanged() {
        var status = Dictation.status
        if let heard = status.heard {
            status.heard = nil
            Dictation.publish(status)
            engine.handle(.dictated(heard), in: document)
        }
        micIsOn = Dictation.micIsOn
        if status.state == .listening, !micIsOn { status.state = .idle }
        dictation = status
        render()
    }

    private func clearFailure() {
        dictation.failure = nil
        if hasFullAccess { Dictation.publish(dictation) }
        render()
    }

    private func startDeleteRepeat() {
        deleteRepeat = DeleteRepeat { [unowned self] words in
            let before = engine.text.before
            if words { engine.deleteWord(in: document) } else { engine.perform(.delete, in: document) }
            followEdit(from: before, by: words ? .other : .deleting)
            feedback(words ? .deletionRapid : .deletionRepeat)
            render()
        }
    }

    private func stopSystemGesturesDelayingTouches() {
        view.window?.gestureRecognizers?.forEach {
            $0.delaysTouchesBegan = false
            $0.delaysTouchesEnded = false
        }
    }

    private func feedback(_ haptic: KeyHaptics.Kind) {
        if engine.settings.sound { UIDevice.current.playInputClick() }
        if hapticsEnabled { haptics.play(haptic) }
    }

    private static func haptic(for key: Key) -> KeyHaptics.Kind {
        switch key.action {
        case .character: .input
        case .space, .return, .tab: .separator
        case .delete: .deletion
        default: .other
        }
    }
}

private extension Corrector {
    func learn(_ lexicon: UILexicon) {
        let entries = lexicon.entries
        setReplacements(entries.filter { $0.userInput != $0.documentText }.map { ($0.userInput, $0.documentText) })
        setNames(entries.filter { $0.userInput == $0.documentText }.map(\.documentText))
    }
}
