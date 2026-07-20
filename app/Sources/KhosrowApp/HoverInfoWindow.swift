#if canImport(AppKit)
import AppKit

/// A small floating, blurred info card shown when you hover the pet. It explains
/// the current mood and *why* (the same content as the right-click menu), styled
/// as a rounded HUD popover and scaled by the menu-bar Scale setting. Purely
/// informational: it never accepts mouse events or steals focus.
final class HoverInfoWindow: NSWindow {
    private let effect = NSVisualEffectView()
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

        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        contentView = effect

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        padLeading = stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12)
        padTrailing = effect.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 12)
        padTop = stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 10)
        padBottom = effect.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 10)
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
        effect.layer?.cornerRadius = 12 * s

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let maxWidth = 320 * s

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .boldSystemFont(ofSize: 12.5 * s)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail
        titleField.preferredMaxLayoutWidth = maxWidth
        stack.addArrangedSubview(titleField)

        for line in lines where !line.isEmpty {
            let f = NSTextField(wrappingLabelWithString: line)
            f.font = .systemFont(ofSize: 11 * s)
            f.textColor = NSColor.white.withAlphaComponent(0.86)
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
