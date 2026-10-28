import JavaScriptKit
import KeyboardCore

@JS final class Keyboard {
    private var engine = TypingEngine()
    private let document: WebDocument
    private var layout = KeyboardLayout(rows: [])
    private var grid = KeyGrid()
    private var offsets: [Int] = []
    private var width = 402.0
    private var height = 874.0
    private var dark = false
    private let style = KeyboardStyle.ios26

    @JS init(lexicon: JSUint8Array, document: JSObject) {
        self.document = WebDocument(document)
        let bytes = [UInt8](unsafeUninitializedCapacity: lexicon.length) { buffer, count in
            lexicon.copyMemory(to: buffer)
            count = lexicon.length
        }
        engine.corrector = Lexicon(bytes: bytes).map { Corrector(source: $0) }
        engine.documentChanged(self.document)
        render()
    }

    @JS func resize(width: Double, height: Double, dark: Bool) {
        self.width = width
        self.height = height
        self.dark = dark
        render()
    }

    @JS func configure(autoCapitalization: Bool, autoCorrection: Bool, capsLock: Bool, predictiveText: Bool, smartPunctuation: Bool, periodShortcut: Bool) {
        engine.settings.autoCapitalization = autoCapitalization
        engine.settings.autoCorrection = autoCorrection
        engine.settings.capsLock = capsLock
        engine.settings.predictiveText = predictiveText
        engine.settings.smartPunctuation = smartPunctuation
        engine.settings.periodShortcut = periodShortcut
        engine.documentChanged(document)
    }

    @JS func frame() -> Frame {
        render()
        let metrics = metrics
        let faces = engine.faces(on: .phone)
        let theme = dark ? KeyboardTheme.dark(style) : KeyboardTheme.light(style)
        let uppercase = engine.shift.isUppercase
        let caps = grid.rows.joined().map { key, frame in
            let face = KeyFace(key, trailing: frame.midX > width / 2, context: faces)
            let typed = key.text(shifted: uppercase)
            return Cap(
                x: frame.x, y: frame.y, width: frame.width, height: frame.height,
                face: face.content.kind, label: face.content.value,
                secondary: face.secondary, secondaryDimmed: face.secondaryIsDimmed,
                align: face.alignment.name, prominent: face.isProminent,
                action: key.action.name, isInput: key.isInput,
                typed: typed, shown: typed.map { uppercase ? $0.uppercased() : $0 },
                alternates: key.alternates.map { uppercase ? $0.uppercased() : $0 }
            )
        }
        return Frame(
            layout: grid.signature,
            width: width,
            height: metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow),
            showsSuggestions: engine.showsSuggestions,
            caps: caps,
            chips: engine.suggestions.map { Chip(text: $0.title, correction: $0.kind == .correction) },
            look: Look(metrics: metrics, theme: theme, style: style)
        )
    }

    @JS func resolve(x: Double, y: Double) -> Int {
        guard let index = engine.key(atX: x, y: y, in: grid) else { return -1 }
        return offsets[index.row] + index.key
    }

    @JS func down(index: Int, tapCount: Int) {
        guard let key = key(at: index) else { return }
        engine.handle(.down(key, tapCount: tapCount), in: document)
    }

    @JS func up(index: Int) {
        guard let key = key(at: index) else { return }
        engine.handle(.up(key), in: document)
    }

    @JS func type(index: Int, text: String, x: Double, y: Double) {
        guard let key = key(at: index) else { return }
        engine.handle(.type(key, Tap(x: x, y: y, key: text)), in: document)
    }

    @JS func slideTyped(text: String) {
        engine.handle(.slide(text), in: document)
    }

    @JS func trigger(index: Int) {
        guard let key = key(at: index) else { return }
        engine.handle(.trigger(key), in: document)
    }

    @JS func repeatDelete(words: Bool) {
        if words { engine.deleteWord(in: document) } else { engine.perform(.delete, in: document) }
    }

    @JS func select(suggestion index: Int) {
        guard engine.suggestions.indices.contains(index) else { return }
        engine.accept(engine.suggestions[index], in: document)
    }

    @JS func misspellings(text: String) -> [Int] {
        guard let corrector = engine.corrector else { return [] }
        var offsets: [Int] = []
        var index = text.startIndex
        var offset = 0
        for range in corrector.misspellings(in: text) {
            offset += text.utf16.distance(from: index, to: range.lowerBound)
            let length = text.utf16.distance(from: range.lowerBound, to: range.upperBound)
            offsets += [offset, offset + length]
            offset += length
            index = range.upperBound
        }
        return offsets
    }

    @JS func cursor(offset: Int) {
        engine.handle(.cursor(offset: offset), in: document)
    }

    @JS func documentChanged() {
        engine.documentChanged(document)
    }

    @JS func endSession() {
        engine.endSession()
    }

    private var metrics: KeyboardMetrics {
        .for(.phone, width: width, height: height, style: style)
    }

    private func render() {
        let context = engine.layout(on: .phone, isLandscape: width > height)
        layout = Layouts.layout(for: context)
        grid = KeyGrid(layout, width: width, metrics: metrics.grid, signature: context.signature)
        offsets = grid.rows.reduce(into: [0]) { $0.append($0.last! + $1.count) }
        engine.use(grid)
    }

    private func key(at index: Int) -> Key? {
        guard let row = offsets.lastIndex(where: { $0 <= index }), row < grid.rows.count, index - offsets[row] < grid.rows[row].count else { return nil }
        return grid.rows[row][index - offsets[row]].key
    }
}

final class WebDocument: TextDocument {
    private let object: JSObject

    init(_ object: JSObject) {
        self.object = object
    }

    var textBeforeInput: String? { object.before!().string }
    var textAfterInput: String? { object.after!().string }
    func insert(_ text: String) { _ = object.insert!(text) }
    func deleteBackward(_ count: Int) { _ = object.deleteBackward!(count) }
    func moveCursor(by offset: Int) { _ = object.moveCursor!(offset) }
}
