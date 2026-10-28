/// One text field as a source sees it: the text around the caret, who changed it last, what kind of field it is, and
/// when it was this way.
public struct FieldUpdate: Hashable, Sendable {
    public enum Author: String, Hashable, Sendable {
        /// You, through the keyboard.
        case keyboard
        /// The app: a field opened, a message sent, a paste, the caret moved.
        case app
    }

    public var field: String
    public var before: String
    public var after: String
    public var by: Author
    public var traits: InputTraits
    /// Seconds since 1970.
    public var at: Double

    public init(field: String, before: String, after: String, by: Author, traits: InputTraits, at: Double = 0) {
        self.field = field
        self.before = before
        self.after = after
        self.by = by
        self.traits = traits
        self.at = at
    }

    func shows(_ other: FieldUpdate) -> Bool {
        field == other.field && before == other.before && after == other.after
    }
}

/// What one source is sent, one update at a time, and the hint it last answered with. Your typing while an update is
/// on its way collapses into the newest text, but every change the app makes is sent in turn, so a source always sees
/// the text as it was before the app changed it (a sent message, a cleared field).
public struct SourceFeed: Sendable {
    private enum Link { case ready, sending, down }

    private var latest: FieldUpdate?
    private var waiting: [FieldUpdate] = []
    private var link = Link.ready
    private var hint: (field: String, text: String)?
    private var dismissed: String?

    public init() {}

    /// A field the keyboard hasn't shown before counts as the app's change: the app opened it. A change is also when a
    /// source that couldn't be reached gets tried again.
    public mutating func observe(_ update: FieldUpdate) {
        guard latest.map(update.shows) != true else { return }
        var update = update
        if update.field != latest?.field { update.by = .app }
        latest = update
        if link == .down { link = .ready }
        if update.by == .keyboard, waiting.last?.by == .keyboard {
            waiting[waiting.count - 1] = update
        } else {
            waiting.append(update)
        }
    }

    /// The update to send now, unless one is already on its way.
    public mutating func next() -> FieldUpdate? {
        guard link == .ready, !waiting.isEmpty else { return nil }
        link = .sending
        return waiting.removeFirst()
    }

    /// The source answered `update`: its hint stands until it answers again.
    public mutating func answered(_ update: FieldUpdate, hint text: String?) {
        link = .ready
        hint = text.map { (update.field, $0) }
        if text != dismissed { dismissed = nil }
    }

    /// The source couldn't be reached with `update`. It keeps its place, unless newer typing already stands in for it,
    /// and waits for the next change.
    public mutating func failed(_ update: FieldUpdate) {
        link = .down
        hint = nil
        if update.by == .app || waiting.first?.by != .keyboard { waiting.insert(update, at: 0) }
    }

    /// The hint for `field`, unless you dismissed it.
    public func hint(for field: String) -> String? {
        guard let hint, hint.field == field, hint.text != dismissed else { return nil }
        return hint.text
    }

    /// Hides the hint until the source answers with a different one.
    public mutating func dismissHint() {
        dismissed = hint?.text
    }
}
