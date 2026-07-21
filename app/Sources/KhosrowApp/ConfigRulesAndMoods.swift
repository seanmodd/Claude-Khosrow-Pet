#if canImport(AppKit)
import AppKit
import KhosrowKit

/// Shared plumbing for the Rules and Custom Moods sections.
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

private func card() -> NSBox {
    let box = NSBox()
    box.boxType = .custom
    box.cornerRadius = 8
    box.borderColor = NSColor.separatorColor
    box.borderWidth = 1
    box.fillColor = NSColor.textBackgroundColor.withAlphaComponent(0.35)
    box.titlePosition = .noTitle
    return box
}

private func fill(_ box: NSBox, with inner: NSStackView) {
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
}

/// Generic retained-target button/popup helpers.
private final class Handler: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}
private func button(_ title: String, _ run: @escaping () -> Void) -> NSButton {
    let h = Handler(run)
    let b = NSButton(title: title, target: h, action: #selector(Handler.fire))
    objc_setAssociatedObject(b, Unmanaged.passUnretained(b).toOpaque(), h, .OBJC_ASSOCIATION_RETAIN)
    return b
}
private final class PopupPicker: NSObject {
    let changed: (String) -> Void
    init(_ changed: @escaping (String) -> Void) { self.changed = changed }
    @objc func fire(_ sender: NSPopUpButton) {
        if let id = sender.selectedItem?.representedObject as? String { changed(id) }
    }
}
private func popup(items: [(id: String, title: String)], selected: String?,
                   _ changed: @escaping (String) -> Void) -> NSPopUpButton {
    let p = NSPopUpButton()
    for it in items {
        p.addItem(withTitle: it.title)
        p.lastItem?.representedObject = it.id
    }
    if let sel = selected, let idx = items.firstIndex(where: { $0.id == sel }) {
        p.selectItem(at: idx)
    }
    let h = PopupPicker(changed)
    p.target = h
    p.action = #selector(PopupPicker.fire(_:))
    objc_setAssociatedObject(p, Unmanaged.passUnretained(p).toOpaque(), h, .OBJC_ASSOCIATION_RETAIN)
    return p
}
private final class TextChange: NSObject, NSTextFieldDelegate {
    let changed: (String) -> Void
    init(_ c: @escaping (String) -> Void) { changed = c }
    func controlTextDidEndEditing(_ n: Notification) {
        if let f = n.object as? NSTextField { changed(f.stringValue) }
    }
}
private func editableField(_ value: String, width: CGFloat = 180,
                           _ changed: @escaping (String) -> Void) -> NSTextField {
    let f = NSTextField(string: value)
    f.translatesAutoresizingMaskIntoConstraints = false
    f.widthAnchor.constraint(equalToConstant: width).isActive = true
    let d = TextChange(changed)
    f.delegate = d
    objc_setAssociatedObject(f, Unmanaged.passUnretained(f).toOpaque(), d, .OBJC_ASSOCIATION_RETAIN)
    return f
}

// MARK: - Rules & Conditions

enum ConfigRulesBuilder {
    static func build(_ ctx: ConfigContext) -> NSView {
        let stack = NSStackView(views: header("Rules & Conditions",
            "Rules are explicit overrides evaluated BEFORE the drag-and-drop mapping. Resolution order: enabled rule with the highest priority (ties broken deterministically) → the condition's mapped mood → default behaviour. Disabled rules never fire. Praying is a valid destination like any other mood."))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        let profile = ctx.profile()

        if profile.rules.isEmpty {
            let empty = NSTextField(wrappingLabelWithString:
                "No rules yet. A rule pins one condition to one mood — for example: “when a session starts → Praying”.")
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
        }

        for rule in profile.rules.sorted(by: { ($0.priority, $1.id) > ($1.priority, $0.id) }) {
            stack.addArrangedSubview(ruleCard(rule, ctx))
        }

        stack.addArrangedSubview(button("＋ Add Rule") {
            ctx.updateProfile { p in
                let cond = p.conditions.first?.id ?? "sessionStart"
                _ = p.addRule(name: "New rule", conditionId: cond,
                              moodId: "praying", priority: 100)
            }
        })
        return wrapScroll(stack)
    }

    private static func ruleCard(_ rule: MoodRule, _ ctx: ConfigContext) -> NSView {
        let profile = ctx.profile()
        let box = card()

        let name = editableField(rule.name, width: 160) { new in
            ctx.updateProfile { p in
                if let i = p.rules.firstIndex(where: { $0.id == rule.id }) { p.rules[i].name = new }
            }
        }
        let conds = profile.conditions.map { (id: $0.id, title: "\($0.phase) · \($0.label)") }
        let condPopup = popup(items: conds, selected: rule.conditionId) { id in
            ctx.updateProfile { p in
                if let i = p.rules.firstIndex(where: { $0.id == rule.id }) { p.rules[i].conditionId = id }
            }
        }
        let moods = profile.moods.map { (id: $0.id, title: $0.displayName) }
        let moodPopup = popup(items: moods, selected: rule.moodId) { id in
            ctx.updateProfile { p in
                if let i = p.rules.firstIndex(where: { $0.id == rule.id }) { p.rules[i].moodId = id }
            }
        }
        let priority = editableField("\(rule.priority)", width: 56) { new in
            ctx.updateProfile { p in
                if let i = p.rules.firstIndex(where: { $0.id == rule.id }) {
                    p.rules[i].priority = Int(new) ?? p.rules[i].priority
                }
            }
        }
        let enabled = ActionCheckbox("Enabled", on: rule.enabled) { on in
            ctx.updateProfile { p in
                if let i = p.rules.firstIndex(where: { $0.id == rule.id }) { p.rules[i].enabled = on }
            }
        }
        let simulate = button("Simulate") { ctx.previewMood(rule.moodId) }
        let delete = button("Delete") {
            ctx.updateProfile { p in p.rules.removeAll { $0.id == rule.id } }
        }

        let arrow = NSTextField(labelWithString: "→")
        let prio = NSTextField(labelWithString: "priority")
        prio.textColor = .secondaryLabelColor
        prio.font = .systemFont(ofSize: 10)

        let row = NSStackView(views: [name, condPopup, arrow, moodPopup, prio, priority,
                                      enabled, simulate, delete, NSView()])
        row.orientation = .horizontal
        row.spacing = 8
        let inner = NSStackView(views: [row])
        inner.orientation = .vertical
        inner.alignment = .leading
        fill(box, with: inner)
        return box
    }
}

// MARK: - Custom Moods

enum ConfigCustomMoodsBuilder {
    static func build(_ ctx: ConfigContext) -> NSView {
        let stack = NSStackView(views: header("Custom Moods",
            "Create your own semantic moods and wire them up with rules or the hook mapping. Built-in moods (including Praying) can be disabled or re-skinned but never deleted; custom moods delete safely — their conditions return to Unassigned."))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        let profile = ctx.profile()
        let customs = profile.moods.filter { !$0.builtin }
        if customs.isEmpty {
            let empty = NSTextField(wrappingLabelWithString:
                "No custom moods yet. Create one, give it a visual act, then assign conditions to it in Hook & Event Mapping.")
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
        }
        for mood in customs {
            stack.addArrangedSubview(moodCard(mood, ctx))
        }

        stack.addArrangedSubview(button("＋ New Custom Mood") {
            ctx.updateProfile { p in
                _ = p.addCustomMood(name: "My mood",
                                    description: "Describe when Khosrow should feel this.",
                                    visualActId: "gemini-praying")
            }
        })
        return wrapScroll(stack)
    }

    private static func moodCard(_ mood: MoodDefinition, _ ctx: ConfigContext) -> NSView {
        let profile = ctx.profile()
        let box = card()

        let name = editableField(mood.displayName, width: 160) { new in
            ctx.updateProfile { p in
                if let i = p.moods.firstIndex(where: { $0.id == mood.id }), !new.isEmpty {
                    p.moods[i].displayName = new
                }
            }
        }
        let idLabel = NSTextField(labelWithString: mood.id)
        idLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        idLabel.textColor = .tertiaryLabelColor

        let desc = editableField(mood.moodDescription, width: 380) { new in
            ctx.updateProfile { p in
                if let i = p.moods.firstIndex(where: { $0.id == mood.id }) {
                    p.moods[i].moodDescription = new
                }
            }
        }

        let preview = NSImageView()
        preview.image = ctx.actPreview(mood.visualActId)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: 44).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let acts = profile.visualActs.map { (id: $0.id, title: $0.displayName) }
        let actPopup = popup(items: acts, selected: mood.visualActId) { id in
            ctx.updateProfile { p in _ = p.setVisualAct(id, forMood: mood.id) }
        }
        let enabled = ActionCheckbox("Enabled", on: mood.enabled) { on in
            ctx.updateProfile { p in
                if let i = p.moods.firstIndex(where: { $0.id == mood.id }) { p.moods[i].enabled = on }
            }
        }
        let notifies = ActionCheckbox("Notifications", on: mood.notifies) { on in
            ctx.updateProfile { p in
                if let i = p.moods.firstIndex(where: { $0.id == mood.id }) { p.moods[i].notifies = on }
            }
        }
        let duplicate = button("Duplicate") {
            ctx.updateProfile { p in _ = p.duplicateMood(id: mood.id) }
        }
        let delete = button("Delete…") {
            let alert = NSAlert()
            alert.messageText = "Delete “\(mood.displayName)”?"
            alert.informativeText = "Conditions assigned to it return to Unassigned and its rules are removed. This cannot be undone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                ctx.updateProfile { p in _ = p.deleteCustomMood(id: mood.id) }
            }
        }

        let conds = profile.conditionIds(forMood: mood.id)
            .compactMap { profile.condition(id: $0)?.label }
        let condLabel = NSTextField(wrappingLabelWithString:
            conds.isEmpty ? "No conditions assigned yet — use Hook & Event Mapping or a rule."
                          : "Triggers: \(conds.joined(separator: " · "))")
        condLabel.textColor = .secondaryLabelColor
        condLabel.font = .systemFont(ofSize: 11)

        let top = NSStackView(views: [name, idLabel, NSView()])
        top.orientation = .horizontal; top.spacing = 8
        let mid = NSStackView(views: [preview, actPopup, enabled, notifies, duplicate, delete, NSView()])
        mid.orientation = .horizontal; mid.spacing = 8
        let inner = NSStackView(views: [top, desc, mid, condLabel])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 6
        fill(box, with: inner)
        return box
    }
}
#endif
