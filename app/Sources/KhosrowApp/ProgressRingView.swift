#if canImport(AppKit)
import AppKit

/// A small circular timer ring shown near the pet while Claude works on a
/// response. The filled arc is an *estimate* of how far along the response is
/// (elapsed time vs. a rolling-average turn length, asymptotic so it never quite
/// completes until the turn actually finishes); the center shows elapsed time.
/// Never intercepts mouse events.
final class ProgressRingView: NSView {
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }   // 0…1 estimate
    var seconds: Int = 0 { didSet { needsDisplay = true } }
    var uiScale: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let lw = max(2.5, 3.5 * uiScale)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - lw / 2 - 1.5

        // Dark backing disc so the ring reads over any part of the sprite.
        NSColor(calibratedWhite: 0.10, alpha: 0.62).setFill()
        NSBezierPath(ovalIn: bounds).fill()

        // Track.
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lw
        NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
        track.stroke()

        // Progress arc, clockwise from 12 o'clock.
        let p = min(max(progress, 0), 1)
        if p > 0.001 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                          endAngle: 90 - 360 * p, clockwise: true)
            arc.lineWidth = lw
            arc.lineCapStyle = .round
            NSColor.systemBlue.setStroke()
            arc.stroke()
        }

        // Center: elapsed time.
        let label = seconds >= 60 ? "\(seconds / 60)m" : "\(seconds)s"
        let font = NSFont.systemFont(ofSize: max(8, radius * 0.66), weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let sz = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2),
                                 withAttributes: attrs)
    }
}
#endif
