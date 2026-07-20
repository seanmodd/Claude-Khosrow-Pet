#if canImport(AppKit)
import AppKit

/// A small floating info card shown when you hover the pet. It explains the
/// current mood and *why* (the same content as the right-click menu), styled as
/// a rounded card and scaled by the menu-bar Scale setting. A solid light
/// background with dark text keeps it legible over any window behind it. Purely
/// informational: it never accepts mouse events or steals focus.
final class HoverInfoWindow: NSWindow {
    private let card = NSView()
    private let stack = NSStackView()
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
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 0.98).cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedWhite: 0.0, alpha: 0.12).cgColor
        card.layer?.masksToBounds = true
        contentView = card

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        padLeading = stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12)
        padTrailing = card.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 12)
        padTop = stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10)
        padBottom = card.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 10)
        NSLayoutConstraint.activate([padLeading, padTrailing, padTop, padBottom])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Rebuild the card content and resize to fit.
    func update(title: String, lines: [String], scale: CGFloat) {
        let s = max(0.6, min(scale, 3.0))
        let pad = 12 * s
        padLeading.constant = pad; padTrailing.constant = pad
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
        setContentSize(NSSize(width: ceil(fit.width + pad * 2),
                              height: ceil(fit.height + pad * 1.7)))
    }
}
#endif
