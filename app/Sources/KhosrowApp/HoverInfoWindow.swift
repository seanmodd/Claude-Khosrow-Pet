#if canImport(AppKit)
import AppKit

/// A view that reports when the cursor enters/leaves it (so the popup can stay
/// open while you move onto it).
private final class TrackingView: NSView {
    var onInside: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a); area = a
    }
    override func mouseEntered(with e: NSEvent) { onInside?(true) }
    override func mouseExited(with e: NSEvent) { onInside?(false) }
}

/// A small floating info card shown when you hover the pet — the current mood
/// and *why* (same content as the right-click menu). Solid light card + dark
/// text for legibility, scaled by the Scale setting. You can drag it to move it
/// and click ✕ to dismiss it; it stays open while the cursor is over it.
final class HoverInfoWindow: NSWindow {
    var onDismiss: (() -> Void)?
    var onPopupHover: ((Bool) -> Void)?
    var onPinToggle: ((Bool) -> Void)?

    private let card = TrackingView()
    private let stack = NSStackView()
    private let closeButton = NSButton()
    private let pinButton = NSButton()
    private(set) var pinned = false
    private var padLeading: NSLayoutConstraint!
    private var padTrailing: NSLayoutConstraint!
    private var padTop: NSLayoutConstraint!
    private var padBottom: NSLayoutConstraint!

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 90),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true            // drag to move
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 0.98).cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedWhite: 0.0, alpha: 0.12).cgColor
        card.layer?.masksToBounds = true
        card.onInside = { [weak self] inside in self?.onPopupHover?(inside) }
        contentView = card

        if let x = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
            closeButton.image = x; closeButton.imagePosition = .imageOnly
        } else { closeButton.title = "✕" }
        closeButton.isBordered = false
        closeButton.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(closeButton)

        pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin")
        pinButton.imagePosition = .imageOnly
        pinButton.isBordered = false
        pinButton.contentTintColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        pinButton.target = self
        pinButton.action = #selector(pinTapped)
        pinButton.toolTip = "Pin — keep this open when you click away"
        pinButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(pinButton)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        padLeading = stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12)
        padTrailing = card.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 26)
        padTop = stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10)
        padBottom = card.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 10)
        NSLayoutConstraint.activate([
            padLeading, padTrailing, padTop, padBottom,
            closeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            card.trailingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 6),
            pinButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: pinButton.trailingAnchor, constant: 2),
        ])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func closeTapped() { onDismiss?() }

    @objc private func pinTapped() {
        pinned.toggle()
        updatePinIcon()
        onPinToggle?(pinned)
    }

    /// Set the pinned state programmatically (e.g. reset when re-shown).
    func setPinned(_ on: Bool) {
        pinned = on
        updatePinIcon()
    }

    private func updatePinIcon() {
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin",
                                  accessibilityDescription: pinned ? "Unpin" : "Pin")
        pinButton.contentTintColor = pinned ? .controlAccentColor
                                            : NSColor(calibratedWhite: 0.45, alpha: 1)
    }

    /// Rebuild the card content and resize to fit.
    func update(title: String, lines: [String], scale: CGFloat) {
        let s = max(0.6, min(scale, 3.0))
        let pad = 12 * s
        padLeading.constant = pad; padTrailing.constant = pad + 30 * s   // room for pin + ✕
        padTop.constant = pad * 0.85; padBottom.constant = pad * 0.85
        stack.spacing = 3 * s
        card.layer?.cornerRadius = 12 * s

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let maxWidth = 320 * s

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .boldSystemFont(ofSize: 12.5 * s)
        titleField.textColor = .black
        titleField.lineBreakMode = .byTruncatingTail
        titleField.preferredMaxLayoutWidth = maxWidth
        stack.addArrangedSubview(titleField)

        for line in lines where !line.isEmpty {
            let f = NSTextField(wrappingLabelWithString: line)
            f.font = .systemFont(ofSize: 11 * s)
            f.textColor = NSColor(calibratedWhite: 0.17, alpha: 1.0)
            f.preferredMaxLayoutWidth = maxWidth
            f.isSelectable = false
            stack.addArrangedSubview(f)
        }

        stack.layoutSubtreeIfNeeded()
        let fit = stack.fittingSize
        setContentSize(NSSize(width: ceil(fit.width + pad * 2 + 30 * s),
                              height: ceil(fit.height + pad * 1.7)))
    }
}
#endif
