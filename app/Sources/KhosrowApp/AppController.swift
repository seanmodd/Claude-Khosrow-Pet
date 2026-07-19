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
    private var skins: [Skin] = []
    private var currentSkinID = "khosrow"
    private let bridge = BridgeClient()
    private let store = PreferencesStore()
    private var prefs = Preferences()
    private var lastBridge: PetBridgeState?
    private var watchProcess: Process?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var testConsole: TestConsoleWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app (no Dock icon) by default. Set KHOSROW_FORCE_REGULAR=1 to
        // run as a regular app (Dock icon + Cmd-Tab): needed by on-screen
        // automation tools that only enumerate regular apps. Default unchanged.
        let forceRegular = ProcessInfo.processInfo.environment["KHOSROW_FORCE_REGULAR"] == "1"
        NSApp.setActivationPolicy(forceRegular ? .regular : .accessory)

        prefs = store.load()
        skins = SkinLibrary.all()
        guard let initial = skins.first(where: { $0.id == prefs.currentSkin }) ?? skins.first else {
            presentFatal("Failed to load Khosrow assets."); return
        }
        manifest = initial.manifest
        sheet = initial.sheet
        currentSkinID = initial.id
        let problems = manifest.validate()
        if !problems.isEmpty { NSLog("Khosrow: manifest problems: \(problems)") }
        if !sheet.hasAlpha { NSLog("Khosrow: WARNING runtime PNG has no alpha channel") }

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

        if prefs.watchMode { startWatcher() }
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
        petView.onContextMenu = { [weak self] event in self?.showActionInfo(for: event) }
    }

    /// A bare click briefly makes the pet attentive (a bit of life).
    private func poke() {
        guard prefs.followBridge == false || controller.state == .idle else { return }
        controller.apply(state: .attentive)
    }

    // MARK: Right-click — "what is he doing, and why?"

    /// Show a small context menu explaining Khosrow's current mood and why he's
    /// in it (the triggering Claude Code activity, or a manual pin).
    private func showActionInfo(for event: NSEvent) {
        let info = actionExplanation()
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: info.title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: info.title,
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        menu.addItem(header)

        for line in info.lines {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let follow = NSMenuItem(title: "Follow Claude Code", action: #selector(toggleFollow), keyEquivalent: "")
        follow.target = self
        follow.state = prefs.followBridge ? .on : .off
        menu.addItem(follow)

        menu.popUp(positioning: nil,
                   at: petView.convert(event.locationInWindow, from: nil),
                   in: petView)
    }

    /// A human summary of the current mood and *why* Khosrow is in it.
    private func actionExplanation() -> (title: String, lines: [String]) {
        let verbs: [PetState: String] = [
            .idle: "resting", .attentive: "listening", .reading: "reading a file",
            .searching: "searching", .editing: "editing", .runningCommand: "running a command",
            .waitingForPermission: "waiting for permission", .success: "celebrating a win",
            .failure: "recovering from an error", .sleeping: "sleeping",
        ]
        let state = controller.state
        let title = "Khosrow is \(verbs[state] ?? state.rawValue)"

        if !prefs.followBridge {
            return (title, ["You pinned this mood from the menu —",
                            "he isn't following Claude Code right now."])
        }

        let why: [PetState: String] = [
            .idle: "Nothing is running right now (or a tool just finished cleanly).",
            .attentive: "You just sent a prompt, or a session / sub-task started.",
            .reading: "Claude Code is reading a file.",
            .searching: "Claude Code is searching or browsing the codebase.",
            .editing: "Claude Code is editing a file.",
            .runningCommand: "Claude Code is running a shell command.",
            .waitingForPermission: "Claude Code is waiting for you to approve something.",
            .success: "A task just finished successfully.",
            .failure: "A tool or task just failed.",
            .sleeping: "The Claude Code session ended — he's asleep.",
        ]
        var lines = [why[state] ?? "Following Claude Code."]
        if prefs.detailMode, let detail = lastBridge?.detail, !detail.isEmpty {
            lines.append("→ \(detail)")
        } else if let category = lastBridge?.toolCategory {
            lines.append("Activity: \(category).")
        }
        // Only nudge about a signal source when we've genuinely never received one.
        // (An idle payload still counts as a live signal — don't cry "no signal".)
        if lastBridge == nil {
            lines.append(prefs.watchMode
                ? "(Watch mode is on — waiting for Claude Code to do something…)"
                : "(No live signal yet — turn on Watch mode, or install the hooks.)")
        } else if prefs.watchMode {
            lines.append("(via Watch mode)")
        }
        return (title, lines)
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
        lastBridge = payload
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

        let watch = makeItem(prefs.watchMode ? "Watching Claude Code (live)" : "Watch Claude Code (live)",
                             #selector(toggleWatch), "")
        watch.state = prefs.watchMode ? .on : .off
        watch.toolTip = "Follow Claude Code by reading its session transcripts — no settings.json, no restart."
        menu.addItem(watch)

        let detail = makeItem("Show detail (what he's doing)", #selector(toggleDetail), "")
        detail.state = prefs.detailMode ? .on : .off
        detail.toolTip = "Surface the current file / command / prompt. Off by default — it shows real content."
        menu.addItem(detail)
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

        // Skin submenu
        let skinItem = NSMenuItem(title: "Skin", action: nil, keyEquivalent: "")
        let skinMenu = NSMenu()
        for skin in skins {
            let item = makeItem(skin.name, #selector(pickSkin(_:)), "")
            item.representedObject = skin.id
            item.state = (skin.id == currentSkinID) ? .on : .off
            skinMenu.addItem(item)
        }
        skinMenu.addItem(.separator())
        skinMenu.addItem(makeItem("Reveal Skins Folder…", #selector(revealSkinsFolder), ""))
        skinMenu.addItem(makeItem("Rescan Skins", #selector(rescanSkins), ""))
        skinItem.submenu = skinMenu
        menu.addItem(skinItem)
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

    // MARK: Watch mode (no hooks / no restart) + detail

    @objc private func toggleWatch() {
        prefs.watchMode.toggle()
        if prefs.watchMode { startWatcher() } else { stopWatcher() }
        store.save(prefs); rebuildMenu()
    }

    @objc private func toggleDetail() {
        prefs.detailMode.toggle()
        store.save(prefs)
        if watchProcess != nil { stopWatcher(); startWatcher() }   // relaunch with/without --detail
        rebuildMenu()
    }

    /// Launch the bundled transcript watcher so the pet follows Claude Code with
    /// no settings.json edit and no restart.
    private func startWatcher() {
        guard watchProcess == nil, let script = KhosrowResources.watchScriptURL() else { return }
        let candidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            NSLog("Khosrow: watch mode needs python3 (none found)"); prefs.watchMode = false; return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = [script.path] + (prefs.detailMode ? ["--detail"] : [])
        var env = ProcessInfo.processInfo.environment
        env["KHOSROW_PET_STATE_FILE"] = BridgeClient.defaultStateFileURL.path
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.watchProcess = nil }
        }
        do { try proc.run(); watchProcess = proc }
        catch { NSLog("Khosrow: watch mode failed to start: \(error)"); prefs.watchMode = false }
    }

    private func stopWatcher() {
        watchProcess?.terminationHandler = nil
        watchProcess?.terminate()
        watchProcess = nil
    }

    // MARK: Skins

    @objc private func pickSkin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        switchSkin(to: id)
    }

    /// Swap the live skin: rebuild the controller with the new manifest + sheet,
    /// resize to its cell, and re-apply the current mood.
    private func switchSkin(to id: String) {
        guard id != currentSkinID, let skin = skins.first(where: { $0.id == id }) else { return }
        let keep = controller.state
        controller.stop()
        manifest = skin.manifest
        sheet = skin.sheet
        currentSkinID = skin.id
        prefs.currentSkin = skin.id

        let size = windowSize()
        petView.frame = NSRect(origin: .zero, size: size)
        var frame = window.frame
        frame.size = size
        window.setFrame(frame, display: true)

        controller = PetController(manifest: manifest, sheet: sheet, view: petView)
        controller.speedMultiplier = prefs.speedMultiplier
        controller.setBaseOpacity(CGFloat(prefs.opacity))
        controller.setPaused(prefs.paused)
        controller.start()
        controller.apply(state: keep)

        store.save(prefs); rebuildMenu()
    }

    @objc private func rescanSkins() {
        skins = SkinLibrary.all()
        if !skins.contains(where: { $0.id == currentSkinID }) {
            switchSkin(to: skins.first?.id ?? "khosrow")
        }
        rebuildMenu()
    }

    @objc private func revealSkinsFolder() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude-pet/skins")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
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
        stopWatcher()
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
