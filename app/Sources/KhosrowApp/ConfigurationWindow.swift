#if canImport(AppKit)
import AppKit
import KhosrowKit

/// The sections shown in the Configuration window's sidebar.
enum ConfigSection: String, CaseIterable {
    case general = "General"
    case appearance = "Appearance"
    case moodStates = "Mood States"
    case visualActs = "Visual Acts"
    case hookMapping = "Hook & Event Mapping"
    case rules = "Rules & Conditions"
    case customMoods = "Custom Moods"
    case customActs = "Custom Visual Acts"
    case notifications = "Notifications & Interaction"
    case diagnostics = "Advanced & Diagnostics"

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .moodStates: return "face.smiling"
        case .visualActs: return "photo.on.rectangle"
        case .hookMapping: return "arrow.triangle.branch"
        case .rules: return "list.bullet.rectangle"
        case .customMoods: return "plus.bubble"
        case .customActs: return "photo.badge.plus"
        case .notifications: return "bell"
        case .diagnostics: return "stethoscope"
        }
    }
}

/// A section content view. M5 ships the navigation shell; each section's real
/// editor arrives in its own milestone and replaces the placeholder.
protocol ConfigSectionViewProvider {
    func makeView() -> NSView
}

/// Khosrow's Configuration window: native, resizable, sidebar-navigated.
/// Opening it repeatedly focuses the existing window; closing it never quits
/// the app (Khosrow is a menu-bar accessory).
final class ConfigurationWindowController: NSWindowController, NSWindowDelegate {

    private let sidebar = NSTableView()
    private let sidebarScroll = NSScrollView()
    private let contentContainer = NSView()
    private var currentSectionView: NSView?
    private(set) var currentSection: ConfigSection = .general

    /// Supplies the content view for a section. The app controller injects
    /// real editors as milestones land; nil -> a standard placeholder.
    var sectionProvider: ((ConfigSection) -> NSView?)?

    private let sections = ConfigSection.allCases

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Khosrow Configuration"
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false          // reopen -> same window
        window.center()
        self.init(window: window)
        window.delegate = self
        buildLayout()
        select(section: .general)
    }

    // MARK: Layout

    private func buildLayout() {
        guard let content = window?.contentView else { return }
        window?.contentMinSize = NSSize(width: 760, height: 480)

        sidebar.headerView = nil
        sidebar.rowHeight = 32
        sidebar.style = .sourceList
        sidebar.allowsEmptySelection = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        sidebar.addTableColumn(col)
        sidebar.delegate = self
        sidebar.dataSource = self

        sidebarScroll.documentView = sidebar
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.drawsBackground = false

        // Frame-based layout with autoresizing masks — deliberately NOT Auto
        // Layout at the window level: a constraint chain from the section
        // content was able to drive the whole window frame to its title bar.
        // Autoresizing cannot resize a window, only follow it.
        let bounds = content.bounds
        sidebarScroll.frame = NSRect(x: 0, y: 0, width: 220, height: bounds.height)
        sidebarScroll.autoresizingMask = [.height]
        contentContainer.frame = NSRect(x: 221, y: 0, width: bounds.width - 221,
                                        height: bounds.height)
        contentContainer.autoresizingMask = [.width, .height]

        content.addSubview(sidebarScroll)
        content.addSubview(contentContainer)
    }

    // MARK: Section switching

    func select(section: ConfigSection) {
        currentSection = section
        if let row = sections.firstIndex(of: section),
           sidebar.selectedRow != row {
            sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        let view = sectionProvider?(section) ?? Self.placeholder(for: section)
        currentSectionView?.removeFromSuperview()
        currentSectionView = view
        view.frame = contentContainer.bounds          // frame-based; see buildLayout
        view.autoresizingMask = [.width, .height]
        contentContainer.addSubview(view)
        restoreFrameIfCollapsed()
    }

    /// Section content is constraint-heavy; if Auto Layout ever drives the
    /// window frame toward zero (observed on-screen as a title-bar-only
    /// window), snap it back. Runs after every render, sync and async.
    private func restoreFrameIfCollapsed() {
        func restore() {
            guard let w = window, w.frame.height < 300 else { return }
            w.setContentSize(NSSize(width: max(920, w.frame.width), height: 640))
            if w.frame.origin.y + w.frame.height > (w.screen?.visibleFrame.maxY ?? 10_000) {
                w.center()
            }
        }
        restore()
        DispatchQueue.main.async(execute: restore)
    }

    /// Standard "coming here" placeholder used until a section's editor ships.
    static func placeholder(for section: ConfigSection) -> NSView {
        let container = NSView()
        let title = NSTextField(labelWithString: section.rawValue)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString:
            "This section is under construction — its controls arrive in an upcoming update.")
        body.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
        ])
        return container
    }

    // MARK: Show / focus

    /// Open the window (or focus it if already open). Never creates duplicates.
    func show() {
        if let w = window, w.frame.height < 200 {   // recover a collapsed frame
            w.setContentSize(NSSize(width: 920, height: 640))
            w.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // Closing hides the window; the app (menu-bar accessory) keeps running.
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

extension ConfigurationWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let section = sections[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: section.symbolName,
                             accessibilityDescription: section.rawValue)
        let label = NSTextField(labelWithString: section.rawValue)
        label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            icon.widthAnchor.constraint(equalToConstant: 18),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebar.selectedRow
        guard row >= 0, row < sections.count else { return }
        if sections[row] != currentSection {
            select(section: sections[row])
        }
    }
}
#endif
