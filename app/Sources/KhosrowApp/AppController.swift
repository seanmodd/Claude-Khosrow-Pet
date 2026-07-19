#if canImport(AppKit)
import AppKit
import KhosrowKit

/// Application delegate: builds the pet window, the menu-bar controls, wires the
/// bridge, and persists preferences/position.
final class AppController: NSObject, NSApplicationDelegate {
    private var manifest: RuntimeManifest!
    private var sheet: SpriteSheet!
    private var window: PetWindow!
    private var petView: PetView!
    private var controller: PetController!
    private let bridge = BridgeClient()
    private let store = PreferencesStore()
    private var prefs = Preferences()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var testConsole: TestConsoleWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app (no Dock icon) by default. Set KHOSROW_FORCE_REGULAR=1 to
        // run as a regular app (Dock icon + Cmd-Tab): needed by on-screen
        // automation tools that only enumerate regular apps. Default unchanged.
        let forceRegular = ProcessInfo.processInfo.environment["KHOSROW_FORCE_REGULAR"] == "1"
        NSApp.setActivationPolicy(forceRegular ? .regular : .accessory)

        do {
            manifest = try KhosrowResources.loadRuntimeManifest()
            let problems = manifest.validate()
            if !problems.isEmpty {
                NSLog("Khosrow: manifest problems: \(problems)")
            }
            sheet = try SpriteSheet(manifest: manifest)
            if !sheet.hasAlpha {
                NSLog("Khosrow: WARNING runtime PNG has no alpha channel")
            }
        } catch {
            presentFatal("Failed to load Khosrow assets: \(error)")
            return
        }

        prefs = store.load()

        let size = windowSize()
        petView = PetView(frame: NSRect(origin: .zero, size: size))
        window = PetWindow(contentSize: size,
                           floatOnTop: prefs.floatOnTop,
                           showOnAllSpaces: prefs.showOnAllSpaces)
        window.contentView = petView
        window.setClickThrough(prefs.clickThrough)

        controller = PetController(manifest: manifest, sheet: sheet, view: petView)
        controller.speedMultiplier = prefs.speedMultiplier
        controller.setBaseOpacity(CGFloat(prefs.opacity))
        controller.setPaused(prefs.paused)
        controller.start()

        wireDragging()
        restorePosition()
        window.orderFront(nil)

        buildMenu()

        // Bridge: file polling always; localhost HTTP best-effort.
        bridge.onState = { [weak self] payload in self?.handleBridge(payload) }
        bridge.startFilePolling()
        bridge.startHTTPListener()
    }

    // MARK: Sizing

    private func windowSize() -> NSSize {
        let s = CGFloat(prefs.scale)
        return NSSize(width: CGFloat(manifest.sheet.cellWidth) * s,
                      height: CGFloat(manifest.sheet.cellHeight) * s)
    }

    private func applyScale() {
        let newSize = windowSize()
        var frame = window.frame
        // Keep the pet's feet anchored: grow/shrink from the bottom-left.
        frame.size = newSize
        window.setFrame(frame, display: true)
        petView.frame = NSRect(origin: .zero, size: newSize)
    }

    // MARK: Dragging

    private func wireDragging() {
        petView.onDragged = { [weak self] delta in
            guard let self, let window = self.window else { return }
            let origin = window.frame.origin
            window.setFrameOrigin(NSPoint(x: origin.x + delta.width,
                                          y: origin.y + delta.height))
        }
        petView.onDragEnded = { [weak self] in self?.savePosition() }
        petView.onClick = { [weak self] in self?.poke() }
    }

    /// A bare click briefly makes the pet attentive (a bit of life).
    private func poke() {
        guard prefs.followBridge == false || controller.state == .idle else { return }
        controller.apply(state: .attentive)
    }

    // MARK: Position memory (per screen)

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(window.frame.origin) } ?? window.screen ?? NSScreen.main
    }

    private func savePosition() {
        guard let screen = currentScreen() else { return }
        let id = PreferencesStore.screenID(for: screen)
        store.savePosition(SavedPosition(screenID: id,
                                         x: Double(window.frame.origin.x),
                                         y: Double(window.frame.origin.y)))
    }

    private func restorePosition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let screen, let saved = store.position(forScreen: PreferencesStore.screenID(for: screen)) {
            let pt = NSPoint(x: saved.x, y: saved.y)
            if screen.frame.insetBy(dx: -200, dy: -200).contains(pt) {
                window.setFrameOrigin(pt)
                return
            }
        }
        // Default: lower-right of the main screen with a margin.
        if let vf = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: vf.maxX - window.frame.width - 40,
                                          y: vf.minY + 40))
        }
    }

    // MARK: Bridge

    private func handleBridge(_ payload: PetBridgeState) {
        guard prefs.followBridge else { return }
        guard let state = payload.petState else { return }
        controller.apply(state: state)
        updateMenuChecks()
    }

    // MARK: Menu

    private func buildMenu() {
        if let button = statusItem.button {
            if let icon = Self.menuBarIcon() {
                button.image = icon
                button.imagePosition = .imageOnly
            } else {
                button.title = "🦁" // fallback if the glyph asset is missing
            }
            button.toolTip = manifest.pet.displayName
        }
        rebuildMenu()
    }

    /// The Faravahar menu-bar glyph as a template image (auto-tints for light /
    /// dark menu bars), sized to the standard status-bar height.
    private static func menuBarIcon() -> NSImage? {
        guard let url = KhosrowResources.menuBarIconURL(),
              let image = NSImage(contentsOf: url) else { return nil }
        let height: CGFloat = 18
        let width = image.size.height > 0 ? image.size.width / image.size.height * height : height
        image.size = NSSize(width: width, height: height)
        image.isTemplate = true
        return image
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: manifest.pet.displayName, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(makeItem(controller.isPaused ? "Resume" : "Pause", #selector(togglePause), "p"))
        menu.addItem(makeItem(controller.state == .sleeping ? "Wake" : "Sleep", #selector(toggleSleep), "s"))

        // State submenu
        let stateItem = NSMenuItem(title: "State", action: nil, keyEquivalent: "")
        let stateMenu = NSMenu()
        let follow = makeItem("Follow Claude Code", #selector(toggleFollow), "")
        follow.state = prefs.followBridge ? .on : .off
        stateMenu.addItem(follow)
        stateMenu.addItem(.separator())
        for state in PetState.allCases {
            let item = makeItem(state.rawValue, #selector(pickState(_:)), "")
            item.representedObject = state.rawValue
            item.state = (!prefs.followBridge && controller.state == state) ? .on : .off
            stateMenu.addItem(item)
        }
        stateItem.submenu = stateMenu
        menu.addItem(stateItem)
        menu.addItem(.separator())

        let clickThrough = makeItem("Click-through", #selector(toggleClickThrough), "")
        clickThrough.state = prefs.clickThrough ? .on : .off
        menu.addItem(clickThrough)

        let float = makeItem("Float on top", #selector(toggleFloat), "")
        float.state = prefs.floatOnTop ? .on : .off
        menu.addItem(float)

        let spaces = makeItem("Show on all Spaces", #selector(toggleSpaces), "")
        spaces.state = prefs.showOnAllSpaces ? .on : .off
        menu.addItem(spaces)

        // Scale submenu
        let scaleItem = NSMenuItem(title: "Scale", action: nil, keyEquivalent: "")
        let scaleMenu = NSMenu()
        for pct in [25, 50, 75, 100, 150, 200, 300, 400] {
            let item = makeItem("\(pct)%", #selector(pickScale(_:)), "")
            item.representedObject = Double(pct) / 100.0
            item.state = abs(prefs.scale - Double(pct) / 100.0) < 0.001 ? .on : .off
            scaleMenu.addItem(item)
        }
        scaleItem.submenu = scaleMenu
        menu.addItem(scaleItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("Animation Test Console…", #selector(openTestConsole), "t"))
        menu.addItem(makeItem("Reset Position", #selector(resetPosition), ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Khosrow", #selector(quit), "q"))

        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateMenuChecks() { rebuildMenu() }

    // MARK: Menu actions

    @objc private func togglePause() {
        controller.togglePaused()
        prefs.paused = controller.isPaused
        store.save(prefs); rebuildMenu()
    }

    @objc private func toggleSleep() {
        if controller.state == .sleeping {
            prefs.followBridge = true
            controller.apply(state: .idle)
        } else {
            prefs.followBridge = false
            controller.apply(state: .sleeping)
        }
        store.save(prefs); rebuildMenu()
    }

    @objc private func toggleFollow() {
        prefs.followBridge.toggle()
        store.save(prefs); rebuildMenu()
    }

    @objc private func pickState(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let state = PetState(rawValue: raw) else { return }
        prefs.followBridge = false
        controller.apply(state: state)
        store.save(prefs); rebuildMenu()
    }

    @objc private func toggleClickThrough() {
        prefs.clickThrough.toggle()
        window.setClickThrough(prefs.clickThrough)
        store.save(prefs); rebuildMenu()
    }

    @objc private func toggleFloat() {
        prefs.floatOnTop.toggle()
        window.applyLevel(floatOnTop: prefs.floatOnTop)
        store.save(prefs); rebuildMenu()
    }

    @objc private func toggleSpaces() {
        prefs.showOnAllSpaces.toggle()
        window.applySpaces(showOnAllSpaces: prefs.showOnAllSpaces)
        store.save(prefs); rebuildMenu()
    }

    @objc private func pickScale(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? Double else { return }
        prefs.scale = Preferences.scaleRange.clamp(scale)
        applyScale()
        store.save(prefs); rebuildMenu()
    }

    @objc private func openTestConsole() {
        if testConsole == nil {
            testConsole = TestConsoleWindowController(manifest: manifest, sheet: sheet)
        }
        NSApp.activate(ignoringOtherApps: true)
        testConsole?.showWindow(nil)
    }

    @objc private func resetPosition() {
        restorePosition()
        savePosition()
    }

    @objc private func quit() {
        store.save(prefs)
        savePosition()
        NSApp.terminate(nil)
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Khosrow"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
#endif
