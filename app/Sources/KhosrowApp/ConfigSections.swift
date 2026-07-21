#if canImport(AppKit)
import AppKit
import KhosrowKit

/// Everything a Configuration section needs to read and change app state.
/// AppController builds one; section views keep no other app references.
struct ConfigContext {
    var profile: () -> ConfigurationProfile
    /// Mutate the profile; the closure persists it and applies live effects.
    var updateProfile: ((inout ConfigurationProfile) -> Void) -> Void
    var prefs: () -> Preferences
    var updatePrefs: ((inout Preferences) -> Void) -> Void
    var resetPetPosition: () -> Void
    var exportConfiguration: () -> Void
    var importConfiguration: () -> Void
    var resetAllConfiguration: () -> Void
    /// Show a mood on the pet right now (non-destructive preview).
    var previewMood: (String) -> Void
    /// Preview image for a visual act id (still / first frame / sprite frame).
    var actPreview: (String) -> NSImage?
    var appVersion: String
}

// MARK: - Small builders

private func sectionTitle(_ s: String) -> NSTextField {
    let t = NSTextField(labelWithString: s)
    t.font = .systemFont(ofSize: 22, weight: .semibold)
    return t
}

private func subtitle(_ s: String) -> NSTextField {
    let t = NSTextField(wrappingLabelWithString: s)
    t.textColor = .secondaryLabelColor
    t.font = .systemFont(ofSize: 12)
    return t
}

private func labeledRow(_ label: String, _ control: NSView) -> NSStackView {
    let l = NSTextField(labelWithString: label)
    l.alignment = .right
    l.translatesAutoresizingMaskIntoConstraints = false
    l.widthAnchor.constraint(equalToConstant: 190).isActive = true
    let row = NSStackView(views: [l, control])
    row.orientation = .horizontal
    row.spacing = 12
    row.alignment = .firstBaseline
    return row
}

private func scrollWrap(_ stack: NSStackView) -> NSView {
    stack.translatesAutoresizingMaskIntoConstraints = false
    let flipped = FlippedClipView()
    flipped.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor, constant: 24),
        stack.topAnchor.constraint(equalTo: flipped.topAnchor, constant: 20),
        stack.trailingAnchor.constraint(lessThanOrEqualTo: flipped.trailingAnchor, constant: -24),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: flipped.bottomAnchor, constant: -20),
        flipped.widthAnchor.constraint(greaterThanOrEqualTo: stack.widthAnchor, constant: 48),
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

/// NSView whose y grows downward, so scroll content starts at the top.
final class FlippedClipView: NSView {
    override var isFlipped: Bool { true }
}

/// A checkbox that runs a closure on toggle.
final class ActionCheckbox: NSButton {
    private var handler: ((Bool) -> Void)?
    convenience init(_ title: String, on: Bool, _ handler: @escaping (Bool) -> Void) {
        self.init(checkboxWithTitle: title, target: nil, action: nil)
        state = on ? .on : .off
        self.handler = handler
        target = self
        action = #selector(fire)
    }
    @objc private func fire() { handler?(state == .on) }
}

/// A slider row with live value label.
final class SliderRow: NSStackView {
    private let slider = NSSlider()
    private let value = NSTextField(labelWithString: "")
    private var format: (Double) -> String = { String(format: "%.2f", $0) }
    private var handler: ((Double) -> Void)?

    convenience init(min: Double, max: Double, current: Double,
                     format: @escaping (Double) -> String,
                     _ handler: @escaping (Double) -> Void) {
        self.init(views: [])
        orientation = .horizontal
        spacing = 8
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = current
        slider.target = self
        slider.action = #selector(changed)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 240).isActive = true
        self.format = format
        self.handler = handler
        value.stringValue = format(current)
        value.textColor = .secondaryLabelColor
        addArrangedSubview(slider)
        addArrangedSubview(value)
    }
    @objc private func changed() {
        value.stringValue = format(slider.doubleValue)
        handler?(slider.doubleValue)
    }
}

private func actionButton(_ title: String, _ handler: @escaping () -> Void) -> NSButton {
    final class Holder: NSObject {
        let h: () -> Void
        init(_ h: @escaping () -> Void) { self.h = h }
        @objc func fire() { h() }
    }
    let holder = Holder(handler)
    let b = NSButton(title: title, target: holder, action: #selector(Holder.fire))
    objc_setAssociatedObject(b, Unmanaged.passUnretained(b).toOpaque(), holder, .OBJC_ASSOCIATION_RETAIN)
    return b
}

// MARK: - General

enum ConfigSectionBuilder {

    static func general(_ ctx: ConfigContext) -> NSView {
        let p = ctx.prefs()
        let stack = NSStackView(views: [
            sectionTitle("General"),
            subtitle("Global behaviour, visibility, and configuration management."),
            ActionCheckbox("Show Khosrow", on: p.showPet) { on in
                ctx.updatePrefs { $0.showPet = on }
            },
            ActionCheckbox("Keep Khosrow above other windows", on: p.floatOnTop) { on in
                ctx.updatePrefs { $0.floatOnTop = on }
            },
            ActionCheckbox("Show on all Spaces / full-screen apps", on: p.showOnAllSpaces) { on in
                ctx.updatePrefs { $0.showOnAllSpaces = on }
            },
            ActionCheckbox("Click-through (clicks pass through the pet)", on: p.clickThrough) { on in
                ctx.updatePrefs { $0.clickThrough = on }
            },
            labeledRow("Pet window:", actionButton("Reset Position") { ctx.resetPetPosition() }),
            NSBox.separatorLine(),
            labeledRow("Configuration:", {
                let row = NSStackView(views: [
                    actionButton("Export…") { ctx.exportConfiguration() },
                    actionButton("Import…") { ctx.importConfiguration() },
                    actionButton("Restore Defaults…") { ctx.resetAllConfiguration() },
                ])
                row.orientation = .horizontal; row.spacing = 8
                return row
            }()),
            subtitle("Export writes a JSON snapshot of moods, visual-act assignments, and hook mappings. Restore Defaults re-applies the shipped configuration (your preferences like scale and position are kept)."),
            NSBox.separatorLine(),
            labeledRow("Configuration schema:", subtitle("v\(ConfigurationProfile.currentSchemaVersion)")),
            labeledRow("App version:", subtitle(ctx.appVersion)),
            labeledRow("Storage:", subtitle(ConfigurationStore.defaultDirectory().path)),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        return scrollWrap(stack)
    }

    // MARK: Appearance

    static func appearance(_ ctx: ConfigContext) -> NSView {
        let p = ctx.prefs()
        let stack = NSStackView(views: [
            sectionTitle("Appearance"),
            subtitle("The pet's Scale is independent of the interface Text size: changing one never changes the other."),
            labeledRow("Pet scale:", SliderRow(min: Preferences.scaleRange.lowerBound,
                                               max: Preferences.scaleRange.upperBound,
                                               current: p.scale,
                                               format: { "\(Int($0 * 100))%" }) { v in
                ctx.updatePrefs { $0.scale = v }
            }),
            labeledRow("Interface text size:", SliderRow(min: Preferences.uiFontScaleRange.lowerBound,
                                                         max: Preferences.uiFontScaleRange.upperBound,
                                                         current: p.uiFontScale,
                                                         format: { "\(Int($0 * 100))%" }) { v in
                ctx.updatePrefs { $0.uiFontScale = v }
            }),
            labeledRow("Opacity:", SliderRow(min: Preferences.opacityRange.lowerBound,
                                             max: Preferences.opacityRange.upperBound,
                                             current: p.opacity,
                                             format: { "\(Int($0 * 100))%" }) { v in
                ctx.updatePrefs { $0.opacity = v }
            }),
            labeledRow("Animation speed:", SliderRow(min: Preferences.speedRange.lowerBound,
                                                     max: Preferences.speedRange.upperBound,
                                                     current: p.speedMultiplier,
                                                     format: { String(format: "%.1fx", $0) }) { v in
                ctx.updatePrefs { $0.speedMultiplier = v }
            }),
            NSBox.separatorLine(),
            ActionCheckbox("Show mood pill beneath the pet", on: p.showMoodPill) { on in
                ctx.updatePrefs { $0.showMoodPill = on }
            },
            ActionCheckbox("Show response-progress ring while Claude works", on: p.showProgressRing) { on in
                ctx.updatePrefs { $0.showProgressRing = on }
            },
            ActionCheckbox("Show unread badge", on: p.showUnreadBadge) { on in
                ctx.updatePrefs { $0.showUnreadBadge = on }
            },
            ActionCheckbox("Show notification bubbles", on: p.showNotificationBubbles) { on in
                ctx.updatePrefs { $0.showNotificationBubbles = on }
            },
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        return scrollWrap(stack)
    }

    // MARK: Mood States

    static func moodStates(_ ctx: ConfigContext) -> NSView {
        let stack = NSStackView(views: [
            sectionTitle("Mood States"),
            subtitle("Every mood Khosrow understands. Assign any visual act to any mood — the art and the meaning are independent. Praying is a first-class mood with no automatic condition until you give it one."),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        let profile = ctx.profile()
        for mood in profile.moods {
            stack.addArrangedSubview(moodCard(mood, ctx))
        }
        return scrollWrap(stack)
    }

    private static func moodCard(_ mood: MoodDefinition, _ ctx: ConfigContext) -> NSView {
        let profile = ctx.profile()
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderColor = NSColor.separatorColor
        box.borderWidth = 1
        box.fillColor = NSColor.textBackgroundColor.withAlphaComponent(0.35)
        box.titlePosition = .noTitle

        let name = NSTextField(labelWithString: "\(mood.displayName)")
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        let idLabel = NSTextField(labelWithString: mood.id)
        idLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        idLabel.textColor = .tertiaryLabelColor
        let kind = NSTextField(labelWithString: mood.builtin ? "built-in" : "custom")
        kind.font = .systemFont(ofSize: 10)
        kind.textColor = .secondaryLabelColor

        let header = NSStackView(views: [name, idLabel, kind, NSView()])
        header.orientation = .horizontal
        header.spacing = 8

        let desc = subtitle(mood.moodDescription)

        // Visual-act picker (mix and match).
        let actPopup = NSPopUpButton()
        for act in profile.visualActs {
            actPopup.addItem(withTitle: act.displayName)
            actPopup.lastItem?.representedObject = act.id
        }
        if let idx = profile.visualActs.firstIndex(where: { $0.id == mood.visualActId }) {
            actPopup.selectItem(at: idx)
        }
        final class PopupHandler: NSObject {
            let moodId: String; let ctx: ConfigContext
            init(_ m: String, _ c: ConfigContext) { moodId = m; ctx = c }
            @objc func changed(_ sender: NSPopUpButton) {
                guard let actId = sender.selectedItem?.representedObject as? String else { return }
                ctx.updateProfile { _ = $0.setVisualAct(actId, forMood: moodId) }
            }
        }
        let handler = PopupHandler(mood.id, ctx)
        actPopup.target = handler
        actPopup.action = #selector(PopupHandler.changed(_:))
        objc_setAssociatedObject(actPopup, Unmanaged.passUnretained(actPopup).toOpaque(),
                                 handler, .OBJC_ASSOCIATION_RETAIN)

        let preview = NSImageView()
        preview.image = ctx.actPreview(mood.visualActId)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 44).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let previewBtn = actionButton("Preview on pet") { ctx.previewMood(mood.id) }

        // Conditions currently assigned.
        let conds = profile.conditionIds(forMood: mood.id)
        let condText: String
        if conds.isEmpty {
            condText = mood.id == "praying"
                ? "No automatic conditions are assigned to Praying yet. Use Hook & Event Mapping to drag one here, or create a custom rule."
                : "No automatic conditions."
        } else {
            let labels = conds.compactMap { profile.condition(id: $0)?.label }
            condText = "Triggers: " + labels.joined(separator: " · ")
        }
        let condLabel = subtitle(condText)

        let notif = ActionCheckbox("Notifications", on: mood.notifies) { on in
            ctx.updateProfile { p in
                if let i = p.moods.firstIndex(where: { $0.id == mood.id }) { p.moods[i].notifies = on }
            }
        }
        let enabled = ActionCheckbox("Enabled", on: mood.enabled) { on in
            ctx.updateProfile { p in
                if let i = p.moods.firstIndex(where: { $0.id == mood.id }) { p.moods[i].enabled = on }
            }
        }

        let controls = NSStackView(views: [preview, actPopup, previewBtn, enabled, notif, NSView()])
        controls.orientation = .horizontal
        controls.spacing = 10

        let inner = NSStackView(views: [header, desc, controls, condLabel])
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
            box.widthAnchor.constraint(greaterThanOrEqualToConstant: 620),
        ])
        return box
    }

    // MARK: Visual Acts

    static func visualActs(_ ctx: ConfigContext) -> NSView {
        let stack = NSStackView(views: [
            sectionTitle("Visual Acts"),
            subtitle("The artwork library. A visual act is what Khosrow shows; a mood is when he shows it. Built-in acts can be reassigned but never deleted, so defaults are always recoverable."),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        let profile = ctx.profile()
        for group in VisualActGroup.allCases {
            let acts = profile.visualActs.filter { $0.group == group }
            if acts.isEmpty { continue }
            let groupTitle = NSTextField(labelWithString: groupName(group))
            groupTitle.font = .systemFont(ofSize: 15, weight: .semibold)
            stack.addArrangedSubview(groupTitle)
            for act in acts {
                stack.addArrangedSubview(actCard(act, ctx))
            }
        }
        return scrollWrap(stack)
    }

    private static func groupName(_ g: VisualActGroup) -> String {
        switch g {
        case .gemini: return "Gemini illustrated acts"
        case .builtin: return "Hand-drawn sequences"
        case .legacy: return "Legacy sprite clips (recoverable)"
        case .custom: return "Custom acts"
        }
    }

    private static func actCard(_ act: VisualActDefinition, _ ctx: ConfigContext) -> NSView {
        let profile = ctx.profile()
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderColor = NSColor.separatorColor
        box.borderWidth = 1
        box.fillColor = NSColor.textBackgroundColor.withAlphaComponent(0.35)
        box.titlePosition = .noTitle

        let preview = NSImageView()
        preview.image = ctx.actPreview(act.id)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 56).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let name = NSTextField(labelWithString: act.displayName)
        name.font = .systemFont(ofSize: 14, weight: .medium)
        let idLabel = NSTextField(labelWithString: act.id)
        idLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        idLabel.textColor = .tertiaryLabelColor

        let usedBy = profile.moodIds(usingAct: act.id)
            .compactMap { profile.mood(id: $0)?.displayName }
        let usage = subtitle(usedBy.isEmpty ? "Not currently assigned to any mood."
                                            : "Used by: \(usedBy.joined(separator: ", "))")

        let text = NSStackView(views: [name, idLabel, usage])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3

        let row = NSStackView(views: [preview, text, NSView()])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        box.contentView = NSView()
        box.contentView?.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor, constant: -8),
            box.widthAnchor.constraint(greaterThanOrEqualToConstant: 620),
        ])
        return box
    }
}

extension NSBox {
    static func separatorLine() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }
}
#endif
