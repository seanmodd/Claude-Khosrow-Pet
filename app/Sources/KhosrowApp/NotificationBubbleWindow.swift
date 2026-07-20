#if canImport(AppKit)
import AppKit

/// A ChatGPT-pet-style notification bubble shown above Khosrow: a title (what
/// just happened), a timestamp + body, and actions — dismiss, reply (type a
/// message back to the session), and open-in-Claude. Interactive (unlike the
/// hover popup), styled as a readable light card, and scaled by the Scale
/// setting.
final class NotificationBubbleWindow: NSWindow {

    var onDismiss: (() -> Void)?
    var onReply: ((String) -> Void)?
    var onOpenSession: (() -> Void)?
    var onSuggest: (() -> Void)?

    private let card = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let stampLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let dismissButton = NSButton()
    private let minimizeButton = NSButton()
    private let replyButton = NSButton()
    private let suggestButton = NSButton()
    private let openButton = NSButton()
    private let replyField = NSTextField()
    private let sendButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let column = NSStackView()
    private let actionRow = NSStackView()
    private let replyRow = NSStackView()

    private var uiScale: CGFloat = 1
    private var canReply = true
    private var minimized = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true      // drag the card to move it
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.98, alpha: 0.98).cgColor
        card.layer?.cornerRadius = 14
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedWhite: 0.0, alpha: 0.12).cgColor
        card.layer?.masksToBounds = true
        contentView = card

        titleLabel.textColor = .black
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stampLabel.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
        bodyLabel.textColor = NSColor(calibratedWhite: 0.17, alpha: 1)

        styleIcon(dismissButton, symbol: "xmark", fallback: "✕", action: #selector(dismissTapped))
        styleIcon(minimizeButton, symbol: "minus", fallback: "–", action: #selector(minimizeTapped))
        styleText(replyButton, title: "↩ Reply", action: #selector(replyTapped))
        styleText(suggestButton, title: "💡 Suggest", action: #selector(suggestTapped))
        styleText(openButton, title: "Open in Claude", action: #selector(openTapped))
        styleText(sendButton, title: "Send", action: #selector(sendTapped))

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false

        replyField.placeholderString = "Reply to Claude…"
        replyField.isBezeled = true
        replyField.bezelStyle = .roundedBezel
        replyField.focusRingType = .none
        replyField.target = self
        replyField.action = #selector(sendTapped)   // Enter sends

        let header = NSStackView(views: [titleLabel, minimizeButton, dismissButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.distribution = .fill
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        actionRow.orientation = .horizontal
        actionRow.spacing = 8
        actionRow.addArrangedSubview(replyButton)
        actionRow.addArrangedSubview(suggestButton)
        actionRow.addArrangedSubview(openButton)

        replyRow.orientation = .horizontal
        replyRow.spacing = 6
        replyRow.addArrangedSubview(spinner)
        replyRow.addArrangedSubview(replyField)
        replyRow.addArrangedSubview(sendButton)
        replyRow.isHidden = true

        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 5
        column.translatesAutoresizingMaskIntoConstraints = false
        [header, stampLabel, bodyLabel, actionRow, replyRow].forEach { column.addArrangedSubview($0) }
        header.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: 14),
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            card.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: 12),
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            replyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: Content

    func present(title: String, timestamp: String, body: String,
                 canReply: Bool, scale: CGFloat) {
        uiScale = max(0.6, min(scale, 3.0))
        self.canReply = canReply
        let s = uiScale
        titleLabel.font = .boldSystemFont(ofSize: 13 * s)
        stampLabel.font = .systemFont(ofSize: 10 * s)
        bodyLabel.font = .systemFont(ofSize: 11.5 * s)
        bodyLabel.preferredMaxLayoutWidth = 300 * s
        titleLabel.stringValue = title
        stampLabel.stringValue = timestamp
        bodyLabel.stringValue = body
        bodyLabel.isHidden = body.isEmpty
        replyButton.isHidden = !canReply
        card.layer?.cornerRadius = 14 * s
        restIcons(scale: s)

        replyRow.isHidden = true
        actionRow.isHidden = false
        stampLabel.isHidden = false
        minimized = false
        minimizeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: nil)
        replyField.isEnabled = true; sendButton.isEnabled = true
        replyField.placeholderString = "Reply to Claude…"
        resize()
    }

    private func resize() {
        column.layoutSubtreeIfNeeded()
        let fit = column.fittingSize
        setContentSize(NSSize(width: ceil(fit.width + 28), height: ceil(fit.height + 24)))
    }

    /// Programmatically enter reply mode (used by the "Reply to Claude…" menu).
    func beginReply() { showReplyField() }

    /// Reveal the inline reply field and focus it.
    private func showReplyField() {
        replyRow.isHidden = false
        actionRow.isHidden = true
        resize()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(replyField)
    }

    // MARK: Suggestion (best-reply generation)

    /// Show the reply field with a spinner while the app generates a suggestion.
    func beginSuggesting() {
        replyRow.isHidden = false
        actionRow.isHidden = true
        replyField.isEnabled = false
        replyField.placeholderString = "Finding the best reply…"
        sendButton.isEnabled = false
        spinner.startAnimation(nil)
        resize()
        orderFront(nil)
    }

    /// Fill the reply field with the generated suggestion (editable before Send).
    func setSuggestion(_ text: String) {
        spinner.stopAnimation(nil)
        replyField.isEnabled = true
        sendButton.isEnabled = true
        replyField.stringValue = text
        resize()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(replyField)
        replyField.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    func suggestionFailed() {
        spinner.stopAnimation(nil)
        replyField.isEnabled = true
        sendButton.isEnabled = true
        replyField.placeholderString = "Couldn't suggest — type your reply…"
        resize()
    }

    // MARK: Actions

    @objc private func dismissTapped() { onDismiss?() }
    @objc private func replyTapped() { showReplyField() }
    @objc private func suggestTapped() { onSuggest?() }
    @objc private func openTapped() { onOpenSession?() }
    @objc private func minimizeTapped() { setMinimized(!minimized) }

    /// Collapse to just the title bar (or expand back).
    private func setMinimized(_ on: Bool) {
        minimized = on
        stampLabel.isHidden = on
        bodyLabel.isHidden = on || bodyLabel.stringValue.isEmpty
        actionRow.isHidden = on
        if on { replyRow.isHidden = true; spinner.stopAnimation(nil) }
        else { replyRow.isHidden = true }
        minimizeButton.image = NSImage(systemSymbolName: on ? "plus" : "minus", accessibilityDescription: nil)
        resize()
    }
    @objc private func sendTapped() {
        let text = replyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyField.stringValue = ""
        onReply?(text)
    }

    // MARK: Styling helpers

    private func styleText(_ b: NSButton, title: String, action: Selector) {
        b.title = title
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.target = self
        b.action = action
    }

    private func styleIcon(_ b: NSButton, symbol: String, fallback: String, action: Selector) {
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            b.image = img; b.imagePosition = .imageOnly
        } else {
            b.title = fallback
        }
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.contentTintColor = NSColor(calibratedWhite: 0.4, alpha: 1)
        b.target = self
        b.action = action
    }

    private func restIcons(scale s: CGFloat) {
        replyButton.font = .systemFont(ofSize: 11 * s)
        openButton.font = .systemFont(ofSize: 11 * s)
        sendButton.font = .systemFont(ofSize: 11 * s)
        replyField.font = .systemFont(ofSize: 11.5 * s)
    }
}
#endif
