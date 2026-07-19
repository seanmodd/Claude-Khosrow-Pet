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

    /// A bare click gives a little wave — but ONLY when Khosrow is idle and in
    /// automatic mode. This never overrides a mood you deliberately pinned (so a
    /// click on a sleeping Khosrow won't wake him), and the next live update
    /// harmlessly supersedes the wave.
    private func poke() {
        guard prefs.followBridge, controller.state == .idle else { return }
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

        let auto = NSMenuItem(title: "Automatic (react to Claude Code)", action: #selector(toggleFollow), keyEquivalent: "")
        auto.target = self
        auto.state = prefs.followBridge ? .on : .off
        menu.addItem(auto)

        menu.popUp(positioning: nil,
                   at: petView.convert(event.locationInWindow, from: nil),
                   in: petView)
    }

    private static let moodVerbs: [PetState: String] = [
        .idle: "resting", .attentive: "listening", .reading: "reading a file",
        .searching: "searching", .editing: "editing", .runningCommand: "running a command",
        .waitingForPermission: "waiting for permission", .success: "celebrating a win",
        .failure: "recovering from an error", .sleeping: "sleeping",
    ]
    private func moodVerb(_ s: PetState) -> String { Self.moodVerbs[s] ?? s.rawValue }

    /// What Claude Code is doing right now per the last live signal (with the
    /// file/command appended when Detail mode is on). Nil until a signal arrives.
    private func liveActivityLine() -> String? {
        guard let payload = lastBridge, let s = payload.petState else { return nil }
        var text = moodVerb(s)
        if prefs.detailMode, let d = payload.detail, !d.isEmpty { text += " (\(d))" }
        return text
    }

    /// Where the live signal comes from, and which session — one short line.
    private func sourceLine() -> String {
        if lastBridge == nil {
            return prefs.watchMode
                ? "Watch mode is on — waiting for activity…"
                : "No live signal yet — turn on Watch mode, or install the hooks."
        }
        let via = prefs.watchMode ? "Watch mode" : "installed hooks"
        if let label = lastBridge?.sessionLabel, !label.isEmpty {
            return "Live via \(via) · session: \(label)"
        }
        return "Live via \(via)."
    }

    /// A human summary of the current mood and *why* Khosrow is in it.
    /// Consistent vocabulary: **Automatic** (reacting to Claude Code) vs
    /// **Hold** (a mood you pinned); **Watch mode** is the live-signal source.
    private func actionExplanation() -> (title: String, lines: [String]) {
        let state = controller.state

        // Hold mode: he holds a mood you picked and ignores Claude Code.
        if !prefs.followBridge {
            var lines = ["You pinned this mood — he is NOT reacting to Claude Code.",
                         "Pick  Mood ▸ Automatic  to make him react again."]
            if prefs.detailMode, let live = liveActivityLine() {
                lines.append("Meanwhile, Claude Code is \(live).")
            }
            return ("Khosrow — holding “\(moodVerb(state))”", lines)
        }

        // Automatic mode: he mirrors Claude Code.
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
        var lines = [why[state] ?? "Reacting to Claude Code."]
        // Detail line always reflects the Show-detail toggle, so toggling it
        // visibly changes what you see here.
        if prefs.detailMode {
            if let d = lastBridge?.detail, !d.isEmpty { lines.append("→ \(d)") }
            else { lines.append("→ (no file or command for this activity)") }
        } else {
            lines.append("Turn on  Show detail  to see the file / command.")
        }
        lines.append(sourceLine())
        return ("Khosrow is \(moodVerb(state))", lines)
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

        // Mood submenu: Automatic (react to Claude Code) vs. holding a mood you pick.
        let moodItem = NSMenuItem(title: "Mood", action: nil, keyEquivalent: "")
        let moodMenu = NSMenu()
        let auto = makeItem("Automatic (react to Claude Code)", #selector(toggleFollow), "")
        auto.state = prefs.followBridge ? .on : .off
        moodMenu.addItem(auto)
        let holdHeader = NSMenuItem(title: "— or hold one —", action: nil, keyEquivalent: "")
        holdHeader.isEnabled = false
        moodMenu.addItem(holdHeader)
        for state in PetState.allCases {
            let item = makeItem(state.rawValue, #selector(pickState(_:)), "")
            item.representedObject = state.rawValue
            item.state = (!prefs.followBridge && controller.state == state) ? .on : .off
            moodMenu.addItem(item)
        }
        moodItem.submenu = moodMenu
        menu.addItem(moodItem)
        menu.addItem(.separator())

        let watch = makeItem("Watch mode (live updates)", #selector(toggleWatch), "")
        watch.state = prefs.watchMode ? .on : .off
        watch.toolTip = "The live-signal source: reads Claude Code's session transcripts so Khosrow can react in Automatic mode — no settings.json, no restart."
        menu.addItem(watch)

        let detail = makeItem("Show detail (files & commands)", #selector(toggleDetail), "")
        detail.state = prefs.detailMode ? .on : .off
        detail.toolTip = "Adds the current file / command / prompt to the right-click info. Off by default — it surfaces real content."
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
        if prefs.watchMode {
            prefs.followBridge = true   // turning on the live source implies "react to it"
            startWatcher()
        } else {
            stopWatcher()
        }
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
