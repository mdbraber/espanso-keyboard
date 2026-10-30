import UIKit
import KeyboardCore

extension KeyboardView {
    final class TrackedTouch {
        enum Mode { case typing, alternates, trackpad, slide, menu }

        var key: Key
        weak var keyView: KeyView?
        var mode = Mode.typing
        var flicked = false
        let start: CGPoint
        var point: CGPoint
        var lastCursorX: CGFloat
        var hold: Timer?
        var menuFrame: CGRect?

        init(keyView: KeyView, start: CGPoint) {
            self.key = keyView.key
            self.keyView = keyView
            self.start = start
            self.point = start
            self.lastCursorX = start.x
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let start = CACurrentMediaTime()
        defer { TouchTrace.shared.record("began", touches, event, since: start) }
        for touch in touches.inOrder {
            rollOver()
            let point = touch.location(in: self)
            guard let view = keyView(at: point) else { continue }
            let tracked = TrackedTouch(keyView: view, start: point)
            self.tracked[ObjectIdentifier(touch)] = tracked
            if view.key == menu.key, !menu.items.isEmpty { tracked.menuFrame = view.frame }
            press(view, tracked: tracked)
            onEvent(.down(view.key, tapCount: touch.tapCount))
            if case .layer = view.key.action { tracked.mode = .slide }
            scheduleHold(for: tracked)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let start = CACurrentMediaTime()
        defer { TouchTrace.shared.record("moved", touches, event, since: start) }
        for touch in touches {
            guard let tracked = tracked[ObjectIdentifier(touch)] else { continue }
            let point = touch.location(in: self)
            tracked.point = point
            switch tracked.mode {
            case .alternates, .menu:
                alternates.track(point)
            case .trackpad:
                let step: CGFloat = 9
                let offset = Int((point.x - tracked.lastCursorX) / step)
                if offset != 0 {
                    tracked.lastCursorX += CGFloat(offset) * step
                    onEvent(.cursor(offset: offset))
                }
            case .typing, .slide:
                if let flick = flickTarget(tracked, point) {
                    tracked.hold?.invalidate()
                    tracked.flicked = flick
                    tracked.keyView?.isFlicked = flick
                    continue
                }
                if let frame = tracked.menuFrame, !frame.contains(point) {
                    tracked.menuFrame = nil
                    tracked.hold?.invalidate()
                }
                guard let view = keyView(at: point), view.key != tracked.key,
                      tracked.mode == .slide || (view.key.isInput && tracked.key.isInput) else { continue }
                tracked.keyView?.isPressed = false
                tracked.key = view.key
                tracked.keyView = view
                press(view, tracked: tracked)
                guard tracked.menuFrame == nil else { continue }
                tracked.hold?.invalidate()
                scheduleHold(for: tracked)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let start = CACurrentMediaTime()
        defer { TouchTrace.shared.record("ended", touches, event, since: start) }
        for touch in touches.inOrder {
            guard let tracked = tracked.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            tracked.point = touch.location(in: self)
            finish(tracked, commit: true)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let start = CACurrentMediaTime()
        defer { TouchTrace.shared.record("cancelled", touches, event, since: start) }
        for touch in touches {
            guard let tracked = tracked.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            finish(tracked, commit: false)
        }
    }

    private func rollOver() {
        for (id, other) in tracked where other.mode == .typing && other.key.isInput {
            tracked.removeValue(forKey: id)
            finish(other, commit: true)
        }
    }

    private func finish(_ tracked: TrackedTouch, commit: Bool) {
        tracked.hold?.invalidate()
        callout.hide()
        let key = tracked.key
        tracked.keyView?.isPressed = false
        tracked.keyView?.isFlicked = false
        defer { onEvent(.up(key)) }

        switch tracked.mode {
        case .alternates:
            if commit, key.alternates.indices.contains(alternates.selection) {
                onEvent(.type(key, tap(tracked, displayed(key.alternates[alternates.selection]))))
            }
            alternates.hide()
        case .menu:
            if commit, menu.items.indices.contains(alternates.selection) {
                switch menu.items[alternates.selection] {
                case .hand(let hand): onEvent(.pick(hand))
                case .language(let language): onEvent(.language(language))
                }
            }
            alternates.hide()
        case .trackpad:
            setLabelsVisible(true)
        case .slide:
            if commit, key.isInput, let text = text(for: key, flicked: tracked.flicked) {
                onEvent(.slide(text))
            }
        case .typing:
            guard commit else { return }
            if let text = text(for: key, flicked: tracked.flicked) {
                onEvent(.type(key, tap(tracked, text)))
            } else if key.action == .space {
                onEvent(.type(key, tap(tracked, " ")))
            } else {
                onEvent(.trigger(key))
            }
        }
    }

    private func tap(_ tracked: TrackedTouch, _ text: String) -> Tap {
        Tap(x: tracked.point.x, y: tracked.point.y, key: text)
    }

    private func press(_ view: KeyView, tracked: TrackedTouch) {
        view.isPressed = !(showsCallouts && view.key.text(shifted: false) != nil)
        show(tracked)
    }

    private func show(_ tracked: TrackedTouch) {
        guard showsCallouts, tracked.mode != .alternates, let view = tracked.keyView,
              let text = text(for: view.key, flicked: tracked.flicked) else { return callout.hide() }
        callout.show(displayed(text), over: view.frame, in: drawableBounds, metrics: metrics, theme: theme)
    }

    private func text(for key: Key, flicked: Bool) -> String? {
        key.text(shifted: faceContext.shift.isUppercase, flicked: flicked)
    }

    private func displayed(_ text: String) -> String {
        faceContext.shift.isUppercase ? text.uppercased() : text
    }

    private func flickTarget(_ tracked: TrackedTouch, _ point: CGPoint) -> Bool? {
        guard faceContext.device == .pad || faceContext.device == .compactPad,
              tracked.mode == .typing, tracked.key.secondary != nil else { return nil }
        let dy = point.y - tracked.start.y
        return abs(point.x - tracked.start.x) < metrics.keyHeight * 0.6 ? dy > metrics.keyHeight * 0.35 : nil
    }

    private func scheduleHold(for tracked: TrackedTouch) {
        let key = tracked.key
        if tracked.mode == .slide, tracked.menuFrame != nil { return scheduleMenu(for: tracked) }
        guard tracked.mode == .typing else { return }
        let isSpace = key.action == .space
        guard isSpace || key.alternates.count > 1 else { return }
        tracked.hold = Timer.scheduledTimer(withTimeInterval: isSpace ? 0.4 : 0.45, repeats: false) { [weak self, weak tracked] _ in
            MainActor.assumeIsolated {
                guard let self, let tracked, tracked.mode == .typing, let view = tracked.keyView else { return }
                if isSpace {
                    tracked.mode = .trackpad
                    view.isPressed = false
                    self.setLabelsVisible(false)
                } else {
                    tracked.mode = .alternates
                    view.isPressed = KeyboardStyle.current.dimsKeyUnderAccents
                    self.callout.hide()
                    let shown = view.key.alternates.map(self.displayed)
                    let base = self.displayed(self.text(for: view.key, flicked: false) ?? "")
                    self.alternates.show(shown, selected: shown.firstIndex(of: base) ?? 0, over: view.frame, in: self.drawableBounds, metrics: self.metrics, theme: self.theme)
                }
            }
        }
    }

    private func scheduleMenu(for tracked: TrackedTouch) {
        tracked.hold = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self, weak tracked] _ in
            MainActor.assumeIsolated {
                guard let self, let tracked, tracked.mode == .slide, let frame = tracked.menuFrame else { return }
                tracked.mode = .menu
                self.callout.hide()
                let items = self.menu.items
                let selected = items.firstIndex(of: .hand(self.menu.current)) ?? items.firstIndex(of: .language(self.menu.language)) ?? 0
                let shown = items.map { item -> AlternatesView.MenuChoice in
                    switch item {
                    case .hand(let hand): .symbol(hand.symbol)
                    case .language(let language): .text(language.code)
                    }
                }
                self.alternates.show(menu: shown, selected: selected, over: frame, in: self.drawableBounds, metrics: self.metrics, theme: self.theme)
            }
        }
    }

    private func setLabelsVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.keyViews.forEach { $0.showsLabel = visible }
        }
    }
}

private extension OneHanded {
    var symbol: String {
        switch self {
        case .left: "keyboard.onehanded.left"
        case .off: "keyboard"
        case .right: "keyboard.onehanded.right"
        }
    }
}

private extension Set<UITouch> {
    var inOrder: [UITouch] { sorted { $0.timestamp < $1.timestamp } }
}
