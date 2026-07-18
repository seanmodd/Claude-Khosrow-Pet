#if canImport(AppKit)
import AppKit

/// Borderless, transparent, floating window that hosts the pet.
///
/// It has no title bar or chrome, a clear background, no shadow, and can float
/// above ordinary windows across every Space. Dragging is handled by ``PetView``
/// so it works even though the window is borderless.
final class PetWindow: NSWindow {

    init(contentSize: NSSize, floatOnTop: Bool, showOnAllSpaces: Bool) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false // PetView performs precise dragging
        // Borderless windows can't become key by default; allow it so the test
        // console and menu interactions behave, but we avoid stealing focus.
        applyLevel(floatOnTop: floatOnTop)
        applySpaces(showOnAllSpaces: showOnAllSpaces)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func applyLevel(floatOnTop: Bool) {
        level = floatOnTop ? .floating : .normal
    }

    func applySpaces(showOnAllSpaces: Bool) {
        collectionBehavior = showOnAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.fullScreenAuxiliary]
    }

    func setClickThrough(_ on: Bool) {
        ignoresMouseEvents = on
    }
}
#endif
