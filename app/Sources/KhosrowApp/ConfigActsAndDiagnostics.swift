#if canImport(AppKit)
import AppKit
import ImageIO
import KhosrowKit
import UniformTypeIdentifiers

/// Extra context for the acts/notifications/diagnostics sections.
struct ConfigDiagContext {
    var importCustomAct: () -> Void
    var deleteCustomAct: (String) -> Void
    var setActFPS: (String, Double) -> Void
    var renameAct: (String, String) -> Void
    var cliStatus: (@escaping (String) -> Void) -> Void
    var signInCLI: () -> Void
    var diagnosticsInfo: () -> [(String, String)]
    var simulateCondition: (String) -> Void
    var resetMappings: () -> Void
    var exportDiagnostics: () -> Void
}

private func header(_ title: String, _ blurb: String) -> [NSView] {
    let t = NSTextField(labelWithString: title)
    t.font = .systemFont(ofSize: 22, weight: .semibold)
    let b = NSTextField(wrappingLabelWithString: blurb)
    b.textColor = .secondaryLabelColor
    b.font = .systemFont(ofSize: 12)
    return [t, b]
}

private func wrapScroll(_ stack: NSStackView) -> NSView {
    stack.translatesAutoresizingMaskIntoConstraints = false
    let flipped = FlippedClipView()
    flipped.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor, constant: 24),
        stack.topAnchor.constraint(equalTo: flipped.topAnchor, constant: 20),
        stack.trailingAnchor.constraint(lessThanOrEqualTo: flipped.trailingAnchor, constant: -24),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: flipped.bottomAnchor, constant: -20),
    ])
    let scroll = NSScrollView()
    scroll.documentView = flipped
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    flipped.translatesAutoresizingMaskIntoConstraints = false
    flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    flipped.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
    return scroll
}

private final class Handler2: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}
private func button(_ title: String, _ run: @escaping () -> Void) -> NSButton {
    let h = Handler2(run)
    let b = NSButton(title: title, target: h, action: #selector(Handler2.fire))
    objc_setAssociatedObject(b, Unmanaged.passUnretained(b).toOpaque(), h, .OBJC_ASSOCIATION_RETAIN)
    return b
}

private func card(_ views: [NSView]) -> NSBox {
    let box = NSBox()
    box.boxType = .custom
    box.cornerRadius = 8
    box.borderColor = NSColor.separatorColor
    box.borderWidth = 1
    box.fillColor = NSColor.textBackgroundColor.withAlphaComponent(0.35)
    box.titlePosition = .noTitle
    let inner = NSStackView(views: views)
    inner.orientation = .vertical
    inner.alignment = .leading
    inner.spacing = 6
    inner.translatesAutoresizingMaskIntoConstraints = false
    box.contentView = NSView()
    box.contentView?.addSubview(inner)
    NSLayoutConstraint.activate([
        inner.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 12),
        inner.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -12),
        inner.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 10),
        inner.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor, constant: -10),
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: 640),
    ])
    return box
}

// MARK: - Custom Visual Acts

enum ConfigCustomActsBuilder {
    static func build(_ ctx: ConfigContext, _ dctx: ConfigDiagContext) -> NSView {
        let stack = NSStackView(views: header("Custom Visual Acts",
            "Import your own artwork — a PNG, an animated GIF, or several PNG frames in order — and assign it to any mood (including Praying) from Mood States or Custom Moods. Imports live in Application Support and never touch the built-in art."))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        let profile = ctx.profile()
        let customs = profile.visualActs.filter { $0.group == .custom }
        if customs.isEmpty {
            let empty = NSTextField(wrappingLabelWithString:
                "No custom acts yet. Import a PNG, GIF, or frame sequence to create one.")
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
        }
        for act in customs {
            let preview = NSImageView()
            preview.image = ctx.actPreview(act.id)
            preview.imageScaling = .scaleProportionallyUpOrDown
            preview.translatesAutoresizingMaskIntoConstraints = false
            preview.widthAnchor.constraint(equalToConstant: 56).isActive = true
            preview.heightAnchor.constraint(equalToConstant: 60).isActive = true

            let name = NSTextField(string: act.displayName)
            name.translatesAutoresizingMaskIntoConstraints = false
            name.widthAnchor.constraint(equalToConstant: 180).isActive = true
            final class Rename: NSObject, NSTextFieldDelegate {
                let id: String; let dctx: ConfigDiagContext
                init(_ id: String, _ d: ConfigDiagContext) { self.id = id; dctx = d }
                func controlTextDidEndEditing(_ n: Notification) {
                    if let f = n.object as? NSTextField { dctx.renameAct(id, f.stringValue) }
                }
            }
            let rn = Rename(act.id, dctx)
            name.delegate = rn
            objc_setAssociatedObject(name, Unmanaged.passUnretained(name).toOpaque(), rn, .OBJC_ASSOCIATION_RETAIN)

            let fps = NSTextField(string: String(format: "%.0f", act.fps))
            fps.translatesAutoresizingMaskIntoConstraints = false
            fps.widthAnchor.constraint(equalToConstant: 44).isActive = true
            final class FPS: NSObject, NSTextFieldDelegate {
                let id: String; let dctx: ConfigDiagContext
                init(_ id: String, _ d: ConfigDiagContext) { self.id = id; dctx = d }
                func controlTextDidEndEditing(_ n: Notification) {
                    if let f = n.object as? NSTextField, let v = Double(f.stringValue) {
                        dctx.setActFPS(id, max(0.5, min(30, v)))
                    }
                }
            }
            let fh = FPS(act.id, dctx)
            fps.delegate = fh
            objc_setAssociatedObject(fps, Unmanaged.passUnretained(fps).toOpaque(), fh, .OBJC_ASSOCIATION_RETAIN)
            let fpsLabel = NSTextField(labelWithString: "fps")
            fpsLabel.textColor = .secondaryLabelColor

            let usedBy = profile.moodIds(usingAct: act.id)
                .compactMap { profile.mood(id: $0)?.displayName }
            let usage = NSTextField(labelWithString: usedBy.isEmpty ? "Unused"
                                    : "Used by: \(usedBy.joined(separator: ", "))")
            usage.textColor = .secondaryLabelColor
            usage.font = .systemFont(ofSize: 11)

            let del = button("Delete…") {
                let alert = NSAlert()
                alert.messageText = "Delete custom act “\(act.displayName)”?"
                alert.informativeText = "Moods using it fall back to their default art. The imported files are removed."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Delete")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn { dctx.deleteCustomAct(act.id) }
            }

            let row = NSStackView(views: [preview, name, fps, fpsLabel, usage, del, NSView()])
            row.orientation = .horizontal
            row.spacing = 10
            stack.addArrangedSubview(card([row]))
        }

        stack.addArrangedSubview(button("＋ Import Artwork…") { dctx.importCustomAct() })

        // Generate Visual Act — provider-ready, honestly not configured.
        let genTitle = NSTextField(labelWithString: "Generate Visual Act")
        genTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let genBody = NSTextField(wrappingLabelWithString:
            "No image-generation provider is configured, so generation is disabled — nothing here fakes success. Manual import (above) is fully functional. When a provider is added, its credentials belong in the macOS Keychain, never in settings files; a provider failure will never touch existing acts or mappings.")
        genBody.textColor = .secondaryLabelColor
        genBody.font = .systemFont(ofSize: 12)
        let genButton = NSButton(title: "Generate…", target: nil, action: nil)
        genButton.isEnabled = false
        stack.addArrangedSubview(card([genTitle, genBody, genButton]))

        return wrapScroll(stack)
    }
}

// MARK: - Notifications & Interaction

enum ConfigNotificationsBuilder {
    static func build(_ ctx: ConfigContext, _ dctx: ConfigDiagContext) -> NSView {
        let p = ctx.prefs()
        let stack = NSStackView(views: header("Notifications & Interaction",
            "How Khosrow announces state changes, and the reply tools built into his notifications."))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        stack.addArrangedSubview(ActionCheckbox("Show notification bubbles", on: p.showNotificationBubbles) { on in
            ctx.updatePrefs { $0.showNotificationBubbles = on }
        })
        stack.addArrangedSubview(ActionCheckbox("Show unread badge", on: p.showUnreadBadge) { on in
            ctx.updatePrefs { $0.showUnreadBadge = on }
        })
        stack.addArrangedSubview(ActionCheckbox("Show response-progress ring", on: p.showProgressRing) { on in
            ctx.updatePrefs { $0.showProgressRing = on }
        })

        let debounceRow = NSStackView(views: [
            NSTextField(labelWithString: "“Waiting for you” debounce:"),
            SliderRow(min: Preferences.waitingDebounceRange.lowerBound,
                      max: Preferences.waitingDebounceRange.upperBound,
                      current: p.waitingDebounceSeconds,
                      format: { "\(Int($0))s" }) { v in
                ctx.updatePrefs { $0.waitingDebounceSeconds = v }
            },
        ])
        debounceRow.orientation = .horizontal
        debounceRow.spacing = 10
        stack.addArrangedSubview(debounceRow)
        let hint = NSTextField(wrappingLabelWithString:
            "Khosrow only announces “waiting for you” if Claude stays idle this long — brief mid-response pauses never trigger a false notification.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(hint)

        // Reply / Suggest / Open in Claude — and the two separate sign-ins.
        let replyTitle = NSTextField(labelWithString: "Reply, Suggest & Open in Claude")
        replyTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let replyBody = NSTextField(wrappingLabelWithString:
            "↩ Reply copies your message and opens the exact session in Claude Desktop (⌘V ↵ to send). 💡 Suggest drafts the best next reply using the standalone `claude` CLI. These use two SEPARATE sign-ins: Claude Desktop has its own account session, while Suggest needs the standalone CLI to be signed in.")
        replyBody.textColor = .secondaryLabelColor
        replyBody.font = .systemFont(ofSize: 12)

        let statusLabel = NSTextField(labelWithString: "CLI status: not checked")
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let check = button("Check CLI status") {
            statusLabel.stringValue = "CLI status: checking…"
            dctx.cliStatus { result in
                DispatchQueue.main.async { statusLabel.stringValue = "CLI status: \(result)" }
            }
        }
        let signIn = button("Sign in to Claude CLI…") { dctx.signInCLI() }
        let cliRow = NSStackView(views: [check, signIn, statusLabel, NSView()])
        cliRow.orientation = .horizontal
        cliRow.spacing = 10
        stack.addArrangedSubview(card([replyTitle, replyBody, cliRow]))

        return wrapScroll(stack)
    }
}

// MARK: - Advanced & Diagnostics

enum ConfigDiagnosticsBuilder {
    static func build(_ ctx: ConfigContext, _ dctx: ConfigDiagContext) -> NSView {
        let stack = NSStackView(views: header("Advanced & Diagnostics",
            "Live signal status, simulation, and recovery tools. Nothing here exposes prompts, file contents, or credentials."))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        var rows: [NSView] = []
        for (k, v) in dctx.diagnosticsInfo() {
            let key = NSTextField(labelWithString: k)
            key.font = .systemFont(ofSize: 12, weight: .semibold)
            key.translatesAutoresizingMaskIntoConstraints = false
            key.widthAnchor.constraint(equalToConstant: 200).isActive = true
            let val = NSTextField(wrappingLabelWithString: v)
            val.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            val.textColor = .secondaryLabelColor
            let row = NSStackView(views: [key, val])
            row.orientation = .horizontal
            row.spacing = 8
            rows.append(row)
        }
        stack.addArrangedSubview(card(rows))

        // Simulation: preview any mood (Praying included, no rule needed) and
        // fire any condition through the live mapping.
        let simTitle = NSTextField(labelWithString: "Simulate")
        simTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let profile = ctx.profile()

        let moodPopup = NSPopUpButton()
        for mood in profile.moods {
            moodPopup.addItem(withTitle: mood.displayName)
            moodPopup.lastItem?.representedObject = mood.id
        }
        let previewBtn = button("Preview mood") {
            if let id = moodPopup.selectedItem?.representedObject as? String {
                ctx.previewMood(id)
            }
        }
        let moodRow = NSStackView(views: [moodPopup, previewBtn])
        moodRow.orientation = .horizontal
        moodRow.spacing = 8

        let condPopup = NSPopUpButton()
        for cond in profile.conditions {
            condPopup.addItem(withTitle: "\(cond.phase) · \(cond.label)")
            condPopup.lastItem?.representedObject = cond.id
        }
        let fireBtn = button("Fire condition through mapping") {
            if let id = condPopup.selectedItem?.representedObject as? String {
                dctx.simulateCondition(id)
            }
        }
        let condRow = NSStackView(views: [condPopup, fireBtn])
        condRow.orientation = .horizontal
        condRow.spacing = 8
        stack.addArrangedSubview(card([simTitle, moodRow, condRow]))

        let resetBtn = button("Reset hook mappings to defaults…") {
            let alert = NSAlert()
            alert.messageText = "Reset all hook mappings?"
            alert.informativeText = "Every condition returns to its default mood. Rules, custom moods, and visual-act assignments are kept."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Reset Mappings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { dctx.resetMappings() }
        }
        let exportBtn = button("Export diagnostic report…") { dctx.exportDiagnostics() }
        let tools = NSStackView(views: [resetBtn, exportBtn])
        tools.orientation = .horizontal
        tools.spacing = 10
        stack.addArrangedSubview(tools)

        return wrapScroll(stack)
    }
}
#endif
