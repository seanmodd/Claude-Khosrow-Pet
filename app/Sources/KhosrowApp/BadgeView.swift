#if canImport(AppKit)
import AppKit

/// A small red unread-count badge drawn on the pet. Custom-drawn so the number
/// is perfectly centered in the circle (an NSTextField can't vertically center
/// reliably). Never intercepts mouse events.
final class BadgeView: NSView {
    var count = 0 { didSet { needsDisplay = true } }
    var uiScale: CGFloat = 1 { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard count > 0 else { return }
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor(calibratedWhite: 1, alpha: 0.9).setStroke()
        let ring = NSBezierPath(ovalIn: r); ring.lineWidth = max(1, 1.2 * uiScale); ring.stroke()

        let text = count > 99 ? "99+" : "\(count)"
        let font = NSFont.systemFont(ofSize: max(9, bounds.height * 0.6), weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let sz = (text as NSString).size(withAttributes: attrs)
        // Center both axes; nudge up ~1px for optical baseline centering.
        let pt = NSPoint(x: (bounds.width - sz.width) / 2,
                         y: (bounds.height - sz.height) / 2)
        (text as NSString).draw(at: pt, withAttributes: attrs)
    }
}
#endif
