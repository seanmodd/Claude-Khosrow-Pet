#if canImport(AppKit)
import AppKit
import KhosrowKit

/// Drag-and-drop pasteboard type carrying a hook-condition id.
private let conditionPasteboardType = NSPasteboard.PasteboardType("com.khosrow.hook-condition")

/// The Hook & Event Mapping editor: every recognizable Claude Code condition
/// appears as a draggable chip inside the mood that currently owns it (or in
/// Unassigned). Drag a chip onto another mood — or use its ▾ menu (the
/// accessible, non-drag alternative) — and the change persists immediately.
enum ConfigHookMappingBuilder {

    static func build(_ ctx: ConfigContext) -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        let title = NSTextField(labelWithString: "Hook & Event Mapping")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)
        let sub = NSTextField(wrappingLabelWithString:
            "Each chip is a Claude Code condition. Drag it onto a mood — or use the chip's ▾ menu — to change which mood it triggers. Changes apply immediately and persist. Praying accepts conditions like any other mood.")
        sub.textColor = .secondaryLabelColor
        sub.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(sub)

        let profile = ctx.profile()

        // Unassigned bucket first, then a group per mood (profile order).
        let unassigned = profile.conditions
            .filter { profile.assignment(conditionId: $0.id)?.moodId == nil }
            .map { $0.id }
        stack.addArrangedSubview(groupBox(title: "Unassigned",
                                          subtitle: "Conditions here trigger nothing.",
                                          moodId: nil, conditionIds: unassigned, ctx: ctx))

        for mood in profile.moods {
            let conds = profile.conditionIds(forMood: mood.id)
            let subtitle: String
            if conds.isEmpty && mood.id == "praying" {
                subtitle = "No automatic conditions are assigned to Praying yet. Drag a hook or event here, or create a custom rule."
            } else if conds.isEmpty {
                subtitle = "No conditions assigned."
            } else {
                subtitle = ""
            }
            stack.addArrangedSubview(groupBox(title: mood.displayName,
                                              subtitle: subtitle,
                                              moodId: mood.id,
                                              conditionIds: conds, ctx: ctx))
        }

        return wrapScroll(stack)
    }

    private static func wrapScroll(_ stack: NSStackView) -> NSView {
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

    private static func groupBox(title: String, subtitle: String, moodId: String?,
                                 conditionIds: [String], ctx: ConfigContext) -> NSView {
        let box = MoodDropBox(moodId: moodId) { conditionId, destination in
            ctx.updateProfile { _ = $0.assign(conditionId: conditionId, toMood: destination) }
        }
        box.boxType = .custom
        box.cornerRadius = 10
        box.borderWidth = 1.5
        box.borderColor = NSColor.separatorColor
        box.fillColor = NSColor.textBackgroundColor.withAlphaComponent(0.35)
        box.titlePosition = .noTitle

        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 14, weight: .semibold)

        let inner = NSStackView(views: [name])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 6

        if !subtitle.isEmpty {
            let sub = NSTextField(wrappingLabelWithString: subtitle)
            sub.textColor = .secondaryLabelColor
            sub.font = .systemFont(ofSize: 11)
            inner.addArrangedSubview(sub)
        }

        let profile = ctx.profile()
        // Chips, chunked into rows so long groups wrap.
        var row = NSStackView(views: [])
        row.orientation = .horizontal
        row.spacing = 6
        var count = 0
        for id in conditionIds {
            guard let cond = profile.condition(id: id) else { continue }
            row.addArrangedSubview(chip(cond, ctx))
            count += 1
            if count % 3 == 0 {
                inner.addArrangedSubview(row)
                row = NSStackView(views: [])
                row.orientation = .horizontal
                row.spacing = 6
            }
        }
        if !row.arrangedSubviews.isEmpty { inner.addArrangedSubview(row) }

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

    private static func chip(_ cond: HookConditionDefinition, _ ctx: ConfigContext) -> NSView {
        ConditionChipView(condition: cond, moods: ctx.profile().moods) { destination in
            ctx.updateProfile { _ = $0.assign(conditionId: cond.id, toMood: destination) }
        }
    }
}

/// A mood group that accepts condition-chip drops.
final class MoodDropBox: NSBox {
    private let moodId: String?
    private let onDrop: (String, String?) -> Void

    init(moodId: String?, onDrop: @escaping (String, String?) -> Void) {
        self.moodId = moodId
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([conditionPasteboardType])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        borderColor = .controlAccentColor
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        borderColor = .separatorColor
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        borderColor = .separatorColor
        guard let id = sender.draggingPasteboard.string(forType: conditionPasteboardType) else {
            return false
        }
        onDrop(id, moodId)
        return true
    }
}

/// A draggable chip showing one hook condition, with a ▾ move-to menu as the
/// keyboard/pointer-accessible alternative to dragging.
final class ConditionChipView: NSView, NSDraggingSource {
    private let condition: HookConditionDefinition
    private let onMove: (String?) -> Void
    private let moods: [MoodDefinition]

    init(condition: HookConditionDefinition, moods: [MoodDefinition],
         onMove: @escaping (String?) -> Void) {
        self.condition = condition
        self.moods = moods
        self.onMove = onMove
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.4).cgColor
        toolTip = "\(condition.phase) — raw id: \(condition.id)"
            + (condition.toolCategory.map { " · category: \($0)" } ?? "")

        let phase = NSTextField(labelWithString: condition.phase)
        phase.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        phase.textColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: condition.label)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingTail

        let text = NSStackView(views: [phase, label])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let menuButton = NSPopUpButton()
        menuButton.bezelStyle = .inline
        menuButton.isBordered = false
        menuButton.addItem(withTitle: "▾")
        let move = NSMenuItem(title: "Move to…", action: nil, keyEquivalent: "")
        move.isEnabled = false
        menuButton.menu?.addItem(move)
        let un = NSMenuItem(title: "Unassigned", action: #selector(moveTo(_:)), keyEquivalent: "")
        un.target = self
        un.representedObject = "" as NSString
        menuButton.menu?.addItem(un)
        for mood in moods {
            let item = NSMenuItem(title: mood.displayName, action: #selector(moveTo(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mood.id as NSString
            menuButton.menu?.addItem(item)
        }
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.widthAnchor.constraint(equalToConstant: 26).isActive = true

        let stack = NSStackView(views: [text, menuButton])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func moveTo(_ sender: NSMenuItem) {
        let id = sender.representedObject as? String
        onMove((id?.isEmpty ?? true) ? nil : id)
    }

    // MARK: Dragging

    override func mouseDragged(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(condition.id, forType: conditionPasteboardType)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let img = snapshotImage()
        dragItem.setDraggingFrame(bounds, contents: img)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func snapshotImage() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
}
#endif
