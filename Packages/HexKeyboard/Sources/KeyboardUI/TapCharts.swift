import UIKit
import KeyboardCore

/// How densely taps land across the keyboard: each key's learned Gaussian, weighted by its taps, summed, drawn on one
/// blue ramp that darkens (light) or brightens (dark) with density, on a square-root scale so rare keys still show.
public enum TapHeat {
    static let pixelsPerPoint = 2.0

    public static func color(at value: Double, isDark: Bool) -> UIColor {
        let (r, g, b, a) = rgba(at: value, isDark: isDark)
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    static func rgba(at value: Double, isDark: Bool) -> (Double, Double, Double, Double) {
        let v = min(max(value, 0), 1)
        let low: (Double, Double, Double) = isDark ? (0, 88, 220) : (90, 170, 255)
        let high: (Double, Double, Double) = isDark ? (178, 224, 255) : (0, 48, 176)
        let mix = { (a: Double, b: Double) in (a + (b - a) * v) / 255 }
        return (mix(low.0, high.0), mix(low.1, high.1), mix(low.2, high.2), min(1, v * 1.6) * 0.94)
    }

    static func image(of aims: [Aim], size: CGSize, isDark: Bool) -> CGImage? {
        let width = Int(size.width * pixelsPerPoint), height = Int(size.height * pixelsPerPoint)
        guard width > 0, height > 0 else { return nil }
        var density = [Double](repeating: 0, count: width * height)
        for aim in aims where aim.taps > 0 {
            let (xx, xy, yy) = aim.spread
            let determinant = xx * yy - xy * xy
            guard determinant > 0 else { continue }
            let weight = Double(aim.taps) / (2 * .pi * determinant.squareRoot())
            let reachX = 4 * xx.squareRoot(), reachY = 4 * yy.squareRoot()
            let columns = max(0, Int((aim.center.x - reachX) * pixelsPerPoint))...min(width - 1, Int((aim.center.x + reachX) * pixelsPerPoint))
            let rows = max(0, Int((aim.center.y - reachY) * pixelsPerPoint))...min(height - 1, Int((aim.center.y + reachY) * pixelsPerPoint))
            guard !columns.isEmpty, !rows.isEmpty else { continue }
            for row in rows {
                let dy = (Double(row) + 0.5) / pixelsPerPoint - aim.center.y
                for column in columns {
                    let dx = (Double(column) + 0.5) / pixelsPerPoint - aim.center.x
                    let distance = (yy * dx * dx - 2 * xy * dx * dy + xx * dy * dy) / determinant
                    if distance < 16 { density[row * width + column] += weight * exp(-distance / 2) }
                }
            }
        }
        guard let peak = density.max(), peak > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in density.indices where density[index] > 0 {
            let (r, g, b, a) = rgba(at: (density[index] / peak).squareRoot(), isDark: isDark)
            pixels[index * 4] = UInt8(r * a * 255)
            pixels[index * 4 + 1] = UInt8(g * a * 255)
            pixels[index * 4 + 2] = UInt8(b * a * 255)
            pixels[index * 4 + 3] = UInt8(a * 255)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// One key and its neighbors, enlarged: the key's last taps (blue where the grid reads them as the key, orange where
/// it reads another), the ellipse holding half its taps, where each of its three memories centers, and its aim.
public final class TapCloseUpView: UIView {
    private var aim: Aim?
    private var keys: [(key: Key, frame: Rect)] = []

    public static let height: CGFloat = 220

    override public init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.setNeedsDisplay() }
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show(_ aim: Aim, keys: [(key: Key, frame: Rect)]) {
        self.aim = aim
        self.keys = keys
        setNeedsDisplay()
    }

    private var theme: KeyboardTheme { KeyboardTheme.current(for: traitCollection, appearance: nil) }

    /// The part of the keyboard to show: the key with a good share of its neighbors, and every mark of its taps.
    private func region(of aim: Aim) -> CGRect {
        let frame = CGRect(aim.frame)
        var region = frame.insetBy(dx: -min(frame.width, 44) * 0.7, dy: -frame.height * 0.35)
        for tap in aim.recent { region = region.union(CGRect(x: tap.x - 4, y: tap.y - 4, width: 8, height: 8)) }
        let keyboard = keys.reduce(CGRect.null) { $0.union(CGRect($1.frame)) }.insetBy(dx: -4, dy: -4)
        return keyboard.isNull ? region : region.intersection(keyboard)
    }

    override public func draw(_ rect: CGRect) {
        guard let aim, let context = UIGraphicsGetCurrentContext() else { return }
        let theme = theme
        let source = region(of: aim)
        let scale = min(bounds.width / source.width, bounds.height / source.height, 4)
        let origin = CGPoint(x: bounds.midX - source.midX * scale, y: bounds.midY - source.midY * scale)
        let map = { (x: Double, y: Double) in CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        let keyRect = { (frame: Rect) in
            CGRect(origin: map(frame.x, frame.y), size: CGSize(width: frame.width * scale, height: frame.height * scale))
        }

        context.saveGState()
        UIBezierPath(roundedRect: bounds, cornerRadius: 16).addClip()
        TapMapPalette.backdrop.setFill()
        context.fill(bounds)

        for (key, frame) in keys {
            let rect = keyRect(frame)
            guard rect.intersects(bounds) else { continue }
            let isTarget = key == aim.key
            (key.label == nil ? theme.key.ui.withAlphaComponent(0.55) : theme.key.ui).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: min(8.5 * scale, 18)).fill()
            let name = NSAttributedString(string: TapMapPalette.name(of: key), attributes: [
                .font: UIFont.systemFont(ofSize: isTarget ? 17 : 15, weight: isTarget ? .semibold : .regular),
                .foregroundColor: isTarget ? UIColor.label : UIColor.secondaryLabel,
            ])
            name.draw(at: CGPoint(x: rect.minX + 9, y: rect.minY + 6))
        }

        let target = keyRect(aim.frame)
        tintColor.setStroke()
        let outline = UIBezierPath(roundedRect: target, cornerRadius: min(8.5 * scale, 18))
        outline.lineWidth = 2
        outline.stroke()

        let center = map(aim.center.x, aim.center.y)
        let (major, minor, angle) = TapMarksView.axes(of: aim.spread)
        let half = (2 * log(2.0)).squareRoot() * scale
        let ring = UIBezierPath(ovalIn: CGRect(x: -major * half, y: -minor * half, width: 2 * major * half, height: 2 * minor * half))
        ring.apply(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        tintColor.withAlphaComponent(0.1).setFill()
        ring.fill()
        tintColor.withAlphaComponent(0.55).setStroke()
        ring.lineWidth = 1.25
        ring.stroke()

        let middle = map(aim.frame.midX, aim.frame.midY)
        UIColor.secondaryLabel.setStroke()
        let cross = UIBezierPath()
        cross.move(to: CGPoint(x: middle.x - 5, y: middle.y))
        cross.addLine(to: CGPoint(x: middle.x + 5, y: middle.y))
        cross.move(to: CGPoint(x: middle.x, y: middle.y - 5))
        cross.addLine(to: CGPoint(x: middle.x, y: middle.y + 5))
        cross.lineWidth = 1
        cross.stroke()

        for tap in aim.recent {
            let point = map(tap.x, tap.y)
            let dot = UIBezierPath(ovalIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            (tap.landed == aim.key ? tintColor : TapMapPalette.miss)?.withAlphaComponent(0.85).setFill()
            dot.fill()
            theme.key.ui.withAlphaComponent(0.9).setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }

        TapGlyph.aim.draw(at: center, color: tintColor, surface: theme.key.ui)
        let points = aim.memories.map { map($0.center.x, $0.center.y) }
        let trail = UIBezierPath()
        trail.move(to: points[0])
        points.dropFirst().forEach(trail.addLine)
        UIColor.label.withAlphaComponent(0.55).setStroke()
        trail.lineWidth = 1.25
        trail.lineCapStyle = .round
        trail.lineJoinStyle = .round
        trail.stroke()
        for (index, point) in points.enumerated() {
            TapGlyph.memory(index).draw(at: point, color: .label, surface: theme.key.ui)
        }
        context.restoreGState()
    }
}

/// The marks the close-up and its legend share, so each legend entry is drawn exactly as on the keyboard.
public enum TapGlyph {
    case memory(Int), aim, hit, miss

    public func draw(at point: CGPoint, color: UIColor, surface: UIColor) {
        let circle = { (radius: CGFloat) in UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)) }
        switch self {
        case .memory(0), .memory(1):
            let ring = circle(self == .memory(0) ? 6 : 4)
            color.setStroke()
            ring.lineWidth = 1.75
            ring.stroke()
        case .memory:
            color.setFill()
            circle(2.5).fill()
        case .aim:
            let dot = circle(4.5)
            surface.setStroke()
            dot.lineWidth = 3
            dot.stroke()
            color.setFill()
            dot.fill()
        case .hit, .miss:
            let dot = circle(3.5)
            color.withAlphaComponent(0.85).setFill()
            dot.fill()
        }
    }

    public func image(color: UIColor, surface: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14)).image { _ in
            draw(at: CGPoint(x: 7, y: 7), color: color, surface: surface)
        }
    }
}

extension TapGlyph: Equatable {}

/// Every key's aim as an arrow from its center, drawn `magnification` times longer than it is, so the pattern of
/// how each thumb pulls across the keyboard shows.
public final class TapPullView: UIView {
    public static let magnification = 4.0
    private var aims: [Aim] = []
    private var keys: [(key: Key, frame: Rect)] = []
    private var size = CGSize.zero

    override public init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        translatesAutoresizingMaskIntoConstraints = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.setNeedsDisplay() }
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show(_ aims: [Aim], keys: [(key: Key, frame: Rect)], size: CGSize) {
        self.aims = aims
        self.keys = keys
        self.size = size
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: size.width > 0 ? size.height * min(1, (bounds.width > 0 ? bounds.width : size.width) / size.width) : 0)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }

    override public func draw(_ rect: CGRect) {
        guard size.width > 0 else { return }
        let scale = bounds.width / size.width
        let theme = KeyboardTheme.current(for: traitCollection, appearance: nil)
        TapMapPalette.backdrop.setFill()
        UIBezierPath(roundedRect: bounds, cornerRadius: 16).fill()
        for (key, frame) in keys {
            let rect = CGRect(x: frame.x * scale, y: frame.y * scale, width: frame.width * scale, height: frame.height * scale)
            (key.label == nil ? theme.key.ui.withAlphaComponent(0.45) : theme.key.ui).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 6 * scale).fill()
        }
        for aim in aims where aim.taps >= 10 && aim.key.label != " " {
            let start = CGPoint(x: aim.frame.midX * scale, y: aim.frame.midY * scale)
            let end = CGPoint(x: start.x + aim.drift.x * Self.magnification * scale, y: start.y + aim.drift.y * Self.magnification * scale)
            UIColor.secondaryLabel.setFill()
            UIBezierPath(ovalIn: CGRect(x: start.x - 1.75, y: start.y - 1.75, width: 3.5, height: 3.5)).fill()
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length >= 3 else { continue }
            let arrow = UIBezierPath()
            arrow.move(to: start)
            arrow.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x), head = min(6, length * 0.45)
            for side in [CGFloat.pi * 0.8, -.pi * 0.8] {
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x + head * cos(angle + side), y: end.y + head * sin(angle + side)))
            }
            tintColor.setStroke()
            arrow.lineWidth = 2
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.stroke()
        }
    }
}
