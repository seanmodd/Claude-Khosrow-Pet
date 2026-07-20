#if canImport(AppKit)
import AppKit
import QuartzCore

/// Layer-backed view that displays one sprite frame with correct alpha and
/// performs precise window dragging (only the opaque pet is grabbable).
final class PetView: NSView {

    /// Called with the drag delta so the controller can move + remember position.
    var onDragged: ((_ delta: NSSize) -> Void)?
    var onDragEnded: (() -> Void)?
    /// Called on a bare click (no drag) — used to poke the pet.
    var onClick: (() -> Void)?
    /// Called on a right-click or control-click — shows "what is he doing, and why?".
    var onContextMenu: ((NSEvent) -> Void)?
    /// Called when the cursor enters (true) / leaves (false) the pet — drives the
    /// hover info popup.
    var onHover: ((_ inside: Bool) -> Void)?

    private var dragOrigin: NSPoint?
    private var didDrag = false
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.isOpaque = false
        // Painterly art, not pixel art: smooth scaling looks best.
        layer?.magnificationFilter = .trilinear
        layer?.minificationFilter = .trilinear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override var isFlipped: Bool { true }

    func show(_ image: CGImage?) {
        layer?.contents = image
    }

    // MARK: - Hover tracking (drives the info popup)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    /// Base opacity (0…1) for dimming (e.g. sleeping).
    func setDim(_ opacity: CGFloat) {
        layer?.opacity = Float(opacity)
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onContextMenu?(event); return }
        dragOrigin = event.locationInWindow
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let now = event.locationInWindow
        let delta = NSSize(width: now.x - origin.x, height: now.y - origin.y)
        if abs(delta.width) + abs(delta.height) > 1 { didDrag = true }
        onDragged?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            onDragEnded?()
        } else {
            onClick?()
        }
        dragOrigin = nil
        didDrag = false
    }
}
#endif
