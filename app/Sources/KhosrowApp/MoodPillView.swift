#if canImport(AppKit)
import AppKit

/// A small rounded "pill" shown directly beneath the pet, always visible, with
/// the current mood (e.g. "📝 writing"). It never intercepts mouse events, so
/// dragging / clicking / hovering all still target the pet above it. Everything
/// scales with the menu-bar Scale setting.
final class MoodPillView: NSView {
    private var text: String = ""
    private var uiScale: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// Update the label and the UI scale, resizing to fit.
    func set(text: String, scale: CGFloat) {
        self.text = text
        self.uiScale = max(0.4, scale)
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    private func font() -> NSFont {
        NSFont.systemFont(ofSize: max(9, 11 * uiScale), weight: .semibold)
    }

    private var attrs: [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 1.5 * uiScale
        shadow.shadowOffset = NSSize(width: 0, height: -0.5 * uiScale)
        return [.font: font(), .foregroundColor: NSColor.white, .shadow: shadow]
    }

    /// The size this pill wants (text + padding), used to lay it out.
    var pillSize: NSSize {
        let s = (text as NSString).size(withAttributes: [.font: font()])
        let padH = 11 * uiScale, padV = 4.5 * uiScale
        return NSSize(width: ceil(s.width + padH * 2), height: ceil(s.height + padV * 2))
    }

    override var intrinsicContentSize: NSSize { pillSize }

    // Pass every mouse event through to the pet above.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = r.height / 2
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSColor(calibratedWhite: 0.09, alpha: 0.74).setFill()
        path.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.14).setStroke()
        path.lineWidth = 1
        path.stroke()

        let str = text as NSString
        let sz = str.size(withAttributes: attrs)
        let pt = NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2)
        str.draw(at: pt, withAttributes: attrs)
    }
}
#endif
