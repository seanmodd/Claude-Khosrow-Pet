#if canImport(AppKit)
import AppKit
import ImageIO
import KhosrowKit
import UniformTypeIdentifiers

/// Application delegate: builds the pet window, the menu-bar controls, wires the
/// bridge, and persists preferences/position.
final class AppController: NSObject, NSApplicationDelegate {
    private var manifest: RuntimeManifest!
    private var sheet: SpriteSheet!
    private var window: PetWindow!
    private var petView: PetView!
    private var container: NSView!          // holds the sprite + the mood pill
    private let pill = MoodPillView(frame: .zero)   // always-visible mood label beneath him
    private var hoverInfo: HoverInfoWindow? // the "why" popup shown on hover
    private var isHovering = false
    private var hoverHideWork: DispatchWorkItem?
    private var notificationBubble: NotificationBubbleWindow?
    private var lastNotification: (title: String, body: String)?
    private var pendingIdleNotify: DispatchWorkItem?
    private var previousState: PetState?
    private let badge = BadgeView(frame: .zero)   // unread count on the pet
    private var unread = 0
    private let progressRing = ProgressRingView(frame: .zero)  // response-progress timer
    private var turnStart: TimeInterval?
    private var avgTurnDuration: TimeInterval = 20
    private var ringTimer: Timer?
    private var controller: PetController!

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private var skins: [Skin] = []
    private var currentSkinID = "khosrow"
    private let bridge = BridgeClient()
    private let store = PreferencesStore()
    private var prefs = Preferences()
    private var lastBridge: PetBridgeState?
    private var watchProcess: Process?
    private var sessionCache: [(id: String, label: String)] = []

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var testConsole: TestConsoleWindowController?
    private var configWindow: ConfigurationWindowController?
    let configStore = ConfigurationStore()
    private(set) var configProfile = ConfigurationProfile.builtInDefault()

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

        let sprite = spriteSize()
        petView = PetView(frame: NSRect(x: 0, y: pillBandHeight(), width: sprite.width, height: sprite.height))
        container = NSView(frame: NSRect(origin: .zero, size: containerSize()))
        container.addSubview(petView)
        container.addSubview(pill)
        configureBadge()
        progressRing.isHidden = true
        container.addSubview(progressRing)
        window = PetWindow(contentSize: containerSize(),
                           floatOnTop: prefs.floatOnTop,
                           showOnAllSpaces: prefs.showOnAllSpaces)
        window.contentView = container
        window.setClickThrough(prefs.clickThrough)

        controller = PetController(manifest: manifest, sheet: sheet, view: petView)
        controller.speedMultiplier = prefs.speedMultiplier
        controller.setBaseOpacity(CGFloat(prefs.opacity))
        controller.onStateChanged = { [weak self] _ in self?.updateMood() }
        controller.setPaused(prefs.paused)
        controller.start()

        layoutContainer()      // positions the sprite + pill, sets the initial mood label
        wireDragging()
        restorePosition()
        window.orderFront(nil)

        buildMenu()

        // Bridge: file polling always; localhost HTTP best-effort.
        bridge.onState = { [weak self] payload in self?.handleBridge(payload) }
        bridge.startFilePolling()
        bridge.startHTTPListener()

        if prefs.watchMode { startWatcher() }
        refreshSessionsAsync()   // populate the session picker in the background

        configProfile = configStore.load()
        applyProfileArt()
    }

    /// Re-activating the app (e.g. launching it again from Finder/Spotlight —
    /// the closest supported "app icon" interaction for a Dock-less menu-bar
    /// accessory) opens or focuses the Configuration window.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        openConfiguration()
        return true
    }

    /// Open (or focus) the Configuration window.
    @objc func openConfiguration() {
        if configWindow == nil {
            let c = ConfigurationWindowController()
            c.sectionProvider = { [weak self] section in
                guard let self else { return nil }
                let ctx = self.makeConfigContext()
                switch section {
                case .general: return ConfigSectionBuilder.general(ctx)
                case .appearance: return ConfigSectionBuilder.appearance(ctx)
                case .moodStates: return ConfigSectionBuilder.moodStates(ctx)
                case .visualActs: return ConfigSectionBuilder.visualActs(ctx)
                case .hookMapping: return ConfigHookMappingBuilder.build(ctx)
                case .rules: return ConfigRulesBuilder.build(ctx)
                case .customMoods: return ConfigCustomMoodsBuilder.build(ctx)
                case .customActs: return ConfigCustomActsBuilder.build(ctx, self.makeDiagContext())
                case .notifications: return ConfigNotificationsBuilder.build(ctx, self.makeDiagContext())
                case .diagnostics: return ConfigDiagnosticsBuilder.build(ctx, self.makeDiagContext())
                }
            }
            configWindow = c
        }
        configWindow?.show()
    }

    /// Everything the Configuration sections read/write, bundled up.
    private func makeConfigContext() -> ConfigContext {
        ConfigContext(
            profile: { [weak self] in self?.configProfile ?? .builtInDefault() },
            updateProfile: { [weak self] mutate in
                self?.mutateProfile(mutate)
            },
            prefs: { [weak self] in self?.prefs ?? Preferences() },
            updatePrefs: { [weak self] mutate in
                guard let self else { return }
                mutate(&self.prefs)
                self.prefs = self.prefs.clamped()
                self.applyPrefsSideEffects()
                self.store.save(self.prefs)
                self.rebuildMenu()
            },
            resetPetPosition: { [weak self] in self?.resetPosition() },
            exportConfiguration: { [weak self] in self?.exportConfiguration() },
            importConfiguration: { [weak self] in self?.importConfiguration() },
            resetAllConfiguration: { [weak self] in self?.confirmResetConfiguration() },
            previewMood: { [weak self] id in
                guard let self, let state = PetState(rawValue: id) else { return }
                // Non-destructive: shows now; the next live signal supersedes it.
                self.controller.apply(state: state)
            },
            actPreview: { [weak self] id in self?.previewImage(forAct: id) },
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
    }

    /// Apply every preference that has a live visual effect (used by the
    /// Configuration window so changes show immediately).
    private func applyPrefsSideEffects() {
        controller.speedMultiplier = prefs.speedMultiplier
        controller.setBaseOpacity(CGFloat(prefs.opacity))
        controller.setPaused(prefs.paused)
        window.setClickThrough(prefs.clickThrough)
        window.applyLevel(floatOnTop: prefs.floatOnTop)
        window.applySpaces(showOnAllSpaces: prefs.showOnAllSpaces)
        applyScale()                 // covers scale changes (keeps center, re-lays out)
        applyUIFontScale()           // covers text-size changes
        pill.isHidden = !prefs.showMoodPill
        if !prefs.showProgressRing { progressRing.isHidden = true }
        if !prefs.showUnreadBadge { badge.isHidden = true } else if unread > 0 { badge.isHidden = false }
        if prefs.showPet { window.orderFront(nil) } else { window.orderOut(nil) }
    }

    /// Re-render the currently visible Configuration section (model changed).
    private func refreshConfigSection() {
        guard let c = configWindow, c.window?.isVisible == true else { return }
        c.select(section: c.currentSection)
    }

    /// A preview image for a visual act (used by Mood States / Visual Acts).
    private func previewImage(forAct id: String) -> NSImage? {
        guard let act = configProfile.visualAct(id: id) else { return nil }
        switch act.source {
        case .geminiStill(let name):
            guard let url = KhosrowResources.geminiActURL(named: name) else { return nil }
            return NSImage(contentsOf: url)
        case .frameSequence(let name):
            guard let url = KhosrowResources.customFrameURLs(forState: name).first else { return nil }
            return NSImage(contentsOf: url)
        case .spriteClip(let clipId):
            guard let clip = manifest.clips[clipId],
                  let cg = sheet.frame(row: clip.row, index: 0) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        case .customFrames:
            guard let art = frames(forAct: id), let first = art.frames.first else { return nil }
            return NSImage(cgImage: first, size: .zero)
        }
    }

    // MARK: Configuration import / export / reset

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "khosrow-configuration.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try configStore.export(configProfile, to: url) }
        catch { presentConfigError("Export failed: \(error)") }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            configProfile = try configStore.importProfile(from: url)
            try configStore.save(configProfile)
            applyProfileArt()
            updateMood()
            refreshConfigSection()
        } catch { presentConfigError("That file isn't a valid Khosrow configuration.") }
    }

    private func confirmResetConfiguration() {
        let alert = NSAlert()
        alert.messageText = "Restore default configuration?"
        alert.informativeText = "Moods, visual-act assignments, hook mappings, and rules return to the shipped defaults. Preferences like scale and position are kept. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore Defaults")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        configProfile = configStore.resetAll()
        applyProfileArt()
        updateMood()
        refreshConfigSection()
    }

    private func presentConfigError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Khosrow"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: Profile-driven art (mix-and-match on the live pet)

    /// Directory holding imported custom acts: <App Support>/Khosrow/acts/<slug>/
    private var customActsDir: URL {
        ConfigurationStore.defaultDirectory().appendingPathComponent("acts", isDirectory: true)
    }

    /// Frames + fps for a visual act, for the live pet.
    private func frames(forAct id: String) -> (frames: [CGImage], fps: Double, loops: Bool)? {
        guard let act = configProfile.visualAct(id: id) else { return nil }
        func cg(_ url: URL) -> CGImage? {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        switch act.source {
        case .geminiStill(let name):
            guard let url = KhosrowResources.geminiActURL(named: name),
                  let img = cg(url) else { return nil }
            return ([img], 1, true)
        case .frameSequence(let name):
            let imgs = KhosrowResources.customFrameURLs(forState: name).compactMap(cg)
            guard !imgs.isEmpty else { return nil }
            return (imgs, act.fps, act.loops)
        case .spriteClip(let clipId):
            guard let clip = manifest.clips[clipId] else { return nil }
            let imgs = (0..<clip.frameCount).compactMap { sheet.frame(row: clip.row, index: $0) }
            guard !imgs.isEmpty else { return nil }
            return (imgs, clip.fps, clip.loop)
        case .customFrames(let slug):
            let dir = customActsDir.appendingPathComponent(slug, isDirectory: true)
            let urls = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let imgs = urls.compactMap(cg)
            guard !imgs.isEmpty else { return nil }
            return (imgs, act.fps, act.loops)
        }
    }

    /// Sync the pet's per-mood art with the profile: any mood whose assigned
    /// act differs from the shipped default gets a live override; defaults get
    /// the built-in bundled art back. Missing custom assets fail safely (the
    /// built-in art shows instead).
    private func applyProfileArt() {
        let defaults = ConfigurationProfile.builtInDefault()
        for state in PetState.allCases {
            guard let mood = configProfile.mood(id: state.rawValue),
                  let defaultAct = defaults.mood(id: state.rawValue)?.visualActId else {
                controller.clearArtOverride(for: state)
                continue
            }
            if mood.visualActId == defaultAct {
                controller.clearArtOverride(for: state)
            } else if let art = frames(forAct: mood.visualActId) {
                controller.setArtOverride(for: state, frames: art.frames,
                                          fps: art.fps, loops: art.loops)
            } else {
                controller.clearArtOverride(for: state)   // missing asset: fall back
            }
        }
    }

    // MARK: Custom acts, CLI status, diagnostics

    private func makeDiagContext() -> ConfigDiagContext {
        ConfigDiagContext(
            importCustomAct: { [weak self] in self?.importCustomAct() },
            deleteCustomAct: { [weak self] id in self?.deleteCustomAct(id) },
            setActFPS: { [weak self] id, fps in
                self?.mutateProfile { p in
                    if let i = p.visualActs.firstIndex(where: { $0.id == id }) { p.visualActs[i].fps = fps }
                }
            },
            renameAct: { [weak self] id, name in
                guard !name.isEmpty else { return }
                self?.mutateProfile { p in
                    if let i = p.visualActs.firstIndex(where: { $0.id == id && !$0.builtin }) {
                        p.visualActs[i].displayName = name
                    }
                }
            },
            cliStatus: { [weak self] done in self?.checkCLIStatus(done) ?? done("unknown") },
            signInCLI: { [weak self] in self?.signInClaudeCLI() },
            diagnosticsInfo: { [weak self] in self?.diagnosticsInfo() ?? [] },
            simulateCondition: { [weak self] id in self?.simulateCondition(id) },
            resetMappings: { [weak self] in
                self?.mutateProfile { p in p.assignments = ConfigurationProfile.builtInAssignments() }
            },
            exportDiagnostics: { [weak self] in self?.exportDiagnostics() })
    }

    /// Shared "mutate + persist + refresh" used by the diag context.
    private func mutateProfile(_ mutate: (inout ConfigurationProfile) -> Void) {
        mutate(&configProfile)
        try? configStore.save(configProfile)
        configProfile = configStore.load()
        applyProfileArt()
        updateMood()
        refreshConfigSection()
    }

    /// Import a PNG / GIF / ordered PNG sequence as a new custom visual act.
    private func importCustomAct() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .gif]
        panel.allowsMultipleSelection = true
        panel.message = "Choose one PNG or GIF, or several PNG frames in order."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let slug = "act-\(UUID().uuidString.prefix(8).lowercased())"
        let dir = customActsDir.appendingPathComponent(slug, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var frameIndex = 1
            for url in panel.urls {
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { continue }
                let count = CGImageSourceGetCount(src)     // GIF frames or 1 for PNG
                for i in 0..<count {
                    guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
                    let dest = dir.appendingPathComponent(String(format: "frame-%03d.png", frameIndex))
                    guard let sink = CGImageDestinationCreateWithURL(dest as CFURL,
                                                                     UTType.png.identifier as CFString, 1, nil) else { continue }
                    CGImageDestinationAddImage(sink, img, nil)
                    CGImageDestinationFinalize(sink)
                    frameIndex += 1
                }
            }
            guard frameIndex > 1 else {
                presentConfigError("No frames could be read from that selection."); return
            }
            let name = panel.urls[0].deletingPathExtension().lastPathComponent
            mutateProfile { p in
                p.visualActs.append(VisualActDefinition(
                    id: "custom-\(slug)", displayName: name,
                    source: .customFrames(slug), group: .custom,
                    fps: frameIndex > 2 ? 6 : 1, loops: true, builtin: false))
            }
        } catch {
            presentConfigError("Import failed: \(error.localizedDescription)")
        }
    }

    /// Delete a custom act: moods using it revert to their default art and the
    /// imported files are removed. Built-in acts are structurally protected.
    private func deleteCustomAct(_ id: String) {
        guard let act = configProfile.visualAct(id: id), !act.builtin else { return }
        if case .customFrames(let slug) = act.source {
            try? FileManager.default.removeItem(
                at: customActsDir.appendingPathComponent(slug, isDirectory: true))
        }
        mutateProfile { p in
            p.visualActs.removeAll { $0.id == id && !$0.builtin }
            // reconcile() repairs any mood still pointing at it.
        }
    }

    /// Async standalone-CLI auth check. Only a coarse classification is ever
    /// shown — never raw command output.
    private func checkCLIStatus(_ done: @escaping (String) -> Void) {
        let claude = claudeExecutable()
        guard FileManager.default.isExecutableFile(atPath: claude) else {
            done("not installed"); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let out = AppController.runClaudePrint(claude: claude, prompt: "ping", cwd: NSHomeDirectory())
            let text = (out ?? "").lowercased()
            if text.isEmpty || text.contains("not logged in") || text.contains("/login")
                || text.contains("401") || text.contains("authentication") {
                done("⚠️ signed out — use “Sign in to Claude CLI…”")
            } else {
                done("✅ signed in — Suggest is ready")
            }
        }
    }

    /// Non-sensitive status pairs for the Diagnostics section.
    private func diagnosticsInfo() -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Current mood", controller.state.rawValue))
        rows.append(("Assigned visual act",
                     configProfile.mood(id: controller.state.rawValue)?.visualActId ?? "-"))
        rows.append(("Mode", prefs.followBridge ? "Automatic" : "Hold"))
        rows.append(("Watch mode", prefs.watchMode ? (watchProcess != nil ? "running" : "starting…") : "off"))
        if let b = lastBridge {
            rows.append(("Last signal", "\(b.state)\(b.tool.map { " · \($0)" } ?? "") @ \(b.timestamp)"))
            rows.append(("Session", b.session.map { String($0.prefix(8)) } ?? "-"))
        } else {
            rows.append(("Last signal", "none yet"))
        }
        let problems = configProfile.validate()
        rows.append(("Profile integrity", problems.isEmpty ? "OK" : problems.joined(separator: "; ")))
        rows.append(("Rules", "\(configProfile.rules.count)"))
        rows.append(("Custom moods", "\(configProfile.moods.filter { !$0.builtin }.count)"))
        rows.append(("Storage", configStore.fileURL.path))
        return rows
    }

    /// Fire a condition through the live mapping, exactly like a real signal.
    private func simulateCondition(_ conditionId: String) {
        guard let cond = configProfile.condition(id: conditionId) else { return }
        let state: PetState
        var tool: String?
        if conditionId.hasPrefix("pre:") {
            let name = String(conditionId.dropFirst(4))
            tool = name
            state = StateMapper.stateForTool(cond.toolCategory.flatMap { ToolCategory(rawValue: $0) })
        } else {
            switch conditionId {
            case "userPromptSubmit", "postToolUse": state = .writing
            case "stopSuccess": state = .success
            case "stopFailure", "postToolUseFailure": state = .failure
            case "permissionRequest", "notification": state = .waitingForPermission
            case "sessionEnd": state = .sleeping
            case "subagentStart": state = .searching
            case "subagentStop": state = .idle
            default: state = .attentive
            }
        }
        switch ProfileResolver.resolve(state: state, tool: tool,
                                       category: cond.toolCategory, profile: configProfile) {
        case .mood(let id): controller.apply(state: PetState(rawValue: id) ?? state)
        case .ignore: break
        case .passthrough: controller.apply(state: state)
        }
    }

    /// Write a non-sensitive diagnostic snapshot to a user-chosen file.
    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "khosrow-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var dict: [String: Any] = [:]
        for (k, v) in diagnosticsInfo() { dict[k] = v }
        dict["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        dict["schemaVersion"] = ConfigurationProfile.currentSchemaVersion
        dict["timestamp"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    // MARK: Sizing

    /// The sprite (pet) size at the current scale.
    private func spriteSize() -> NSSize {
        let s = CGFloat(prefs.scale)
        return NSSize(width: CGFloat(manifest.sheet.cellWidth) * s,
                      height: CGFloat(manifest.sheet.cellHeight) * s)
    }

    /// Height of the band reserved beneath the sprite for the mood pill.
    /// Sized by the text scale, so bigger text gets more room.
    private func pillBandHeight() -> CGFloat { max(20, 26 * CGFloat(prefs.uiFontScale)) }

    /// The whole window (sprite + pill band).
    private func containerSize() -> NSSize {
        let s = spriteSize()
        return NSSize(width: s.width, height: s.height + pillBandHeight())
    }

    /// Position the sprite (top) and the mood pill (centered in the bottom band).
    private func layoutContainer() {
        let sprite = spriteSize()
        container.frame = NSRect(origin: .zero, size: containerSize())
        petView.frame = NSRect(x: 0, y: pillBandHeight(), width: sprite.width, height: sprite.height)
        layoutBadge()
        layoutProgressRing()
        updateMood()
    }

    private func layoutProgressRing() {
        let d = max(22, 27 * CGFloat(prefs.uiFontScale))
        let sprite = spriteSize()
        // top-left of the sprite (opposite the unread badge)
        progressRing.frame = NSRect(x: 1, y: pillBandHeight() + sprite.height - d, width: d, height: d)
        progressRing.uiScale = CGFloat(prefs.uiFontScale)
    }

    // MARK: Response-progress ring (estimate of how far along Claude's reply is)

    private func handleTurnProgress(to state: PetState) {
        let active: Set<PetState> = [.writing, .reading, .searching, .editing, .runningCommand, .attentive]
        if active.contains(state) {
            if turnStart == nil { startTurn() }
        } else if turnStart != nil {
            endTurn()
        }
    }

    private func startTurn() {
        turnStart = ProcessInfo.processInfo.systemUptime
        progressRing.isHidden = !prefs.showProgressRing
        layoutProgressRing()
        ringTimer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tickRing() }
        RunLoop.main.add(t, forMode: .common)
        ringTimer = t
        tickRing()
    }

    private func tickRing() {
        guard let start = turnStart else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let tau = max(4, avgTurnDuration)
        // Asymptotic estimate: ~63% at the average length, never 100% until done.
        progressRing.progress = CGFloat(1 - exp(-elapsed / tau))
        progressRing.seconds = Int(elapsed)
    }

    private func endTurn() {
        guard let start = turnStart else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        if elapsed > 2 { avgTurnDuration = avgTurnDuration * 0.7 + elapsed * 0.3 }   // rolling average
        ringTimer?.invalidate(); ringTimer = nil
        turnStart = nil
        progressRing.progress = 1                         // snap full, then fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if self?.turnStart == nil { self?.progressRing.isHidden = true }
        }
    }

    private func applyScale() {
        resizeKeepingCenter(to: containerSize())   // "recenter": keep the unit centered
        layoutContainer()
    }

    /// Re-lay everything after a text-size change (independent of the pet scale).
    private func applyUIFontScale() {
        resizeKeepingCenter(to: containerSize())    // the pill band depends on the text size
        layoutContainer()                           // repositions pill/badge/ring + updateMood
        if isHovering { refreshHoverInfo() }
        if let n = lastNotification, notificationBubble?.isVisible == true {
            notify(title: n.title, body: n.body)    // re-render the bubble at the new size
        }
    }

    /// Resize the window while keeping its center point fixed — but clamped so it
    /// never slides off the visible screen (e.g. when text size grows it a lot).
    private func resizeKeepingCenter(to newSize: NSSize) {
        let old = window.frame
        var origin = NSPoint(x: old.midX - newSize.width / 2,
                             y: old.midY - newSize.height / 2)
        if let vf = (window.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), max(vf.minX, vf.maxX - newSize.width))
            origin.y = min(max(origin.y, vf.minY), max(vf.minY, vf.maxY - newSize.height))
        }
        window.setFrame(NSRect(origin: origin, size: newSize), display: true)
    }

    // MARK: Mood pill + hover "why" popup

    private static let pillLabels: [PetState: String] = [
        .idle: "🧍 idle", .attentive: "🙌 attentive", .writing: "📝 writing",
        .reading: "📖 reading", .searching: "🔎 searching", .editing: "✍️ editing",
        .runningCommand: "🏃 running", .waitingForPermission: "✋ waiting",
        .praying: "🙏 praying",
        .success: "🎉 success", .failure: "🙇 failure", .sleeping: "😴 sleeping",
    ]
    private func pillText(_ s: PetState) -> String {
        // A custom pill label from Configuration wins; else the built-in emoji.
        if let custom = configProfile.mood(id: s.rawValue)?.pillText, !custom.isEmpty {
            return custom
        }
        return Self.pillLabels[s] ?? s.rawValue
    }

    /// Refresh the pill's label + position for the current mood, and the popup if open.
    private func updateMood() {
        let state = controller.state
        pill.isHidden = !prefs.showMoodPill
        pill.set(text: pillText(state), scale: CGFloat(prefs.uiFontScale))
        let sz = pill.pillSize
        let band = pillBandHeight()
        pill.frame = NSRect(x: (spriteSize().width - sz.width) / 2,
                            y: (band - sz.height) / 2, width: sz.width, height: sz.height)
        if isHovering || hoverInfo?.pinned == true { refreshHoverInfo() }
        if state != previousState {
            maybeNotify(from: previousState, to: state)   // notify when he stops working
            handleTurnProgress(to: state)                 // update the response-progress ring
            previousState = state
        }
    }

    private func setHover(_ inside: Bool) {
        if inside {
            hoverHideWork?.cancel(); hoverHideWork = nil
            showHoverInfo()
        } else {
            scheduleHoverHide()
        }
    }

    private func showHoverInfo() {
        // Don't stack on a visible notification — unless the popup is pinned open.
        if notificationBubble?.isVisible == true, hoverInfo?.pinned != true { return }
        if hoverInfo == nil {
            let h = HoverInfoWindow()
            h.onDismiss = { [weak self] in self?.dismissHoverInfo() }
            h.onPopupHover = { [weak self] inside in
                if inside { self?.hoverHideWork?.cancel(); self?.hoverHideWork = nil }
                else { self?.scheduleHoverHide() }
            }
            h.onPinToggle = { [weak self] pinned in
                if !pinned { self?.scheduleHoverHide() }   // unpinned → hide on next move-away
            }
            hoverInfo = h
        }
        isHovering = true
        refreshHoverInfo()
        hoverInfo?.order(.above, relativeTo: window.windowNumber)
    }

    /// Hide after a short grace period, so moving the cursor onto the popup
    /// (to pin, drag, or dismiss it) doesn't make it vanish. Pinned = never.
    private func scheduleHoverHide() {
        guard hoverInfo?.pinned != true else { return }
        hoverHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideHoverInfo() }
        hoverHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func hideHoverInfo() {
        guard hoverInfo?.pinned != true else { return }    // a pinned popup stays put
        isHovering = false
        hoverInfo?.orderOut(nil)
    }

    /// The ✕ on the popup: always hide and clear the pin.
    private func dismissHoverInfo() {
        hoverInfo?.setPinned(false)
        isHovering = false
        hoverInfo?.orderOut(nil)
    }

    private func refreshHoverInfo() {
        let info = actionExplanation()
        hoverInfo?.update(title: info.title, lines: info.lines, scale: CGFloat(prefs.uiFontScale))
        if hoverInfo?.pinned != true { positionHoverInfo() }   // leave a pinned/dragged popup put
    }

    private func positionHoverInfo() {
        guard let hoverInfo else { return }
        positionAbovePet(hoverInfo)
    }

    /// Sit a companion window just above the pet, centered, kept on-screen.
    private func positionAbovePet(_ win: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let pet = window.frame, size = win.frame.size, vf = screen.visibleFrame
        var y = pet.maxY + 8 * CGFloat(prefs.uiFontScale)
        if y + size.height > vf.maxY { y = pet.minY - size.height - 8 }   // flip below if needed
        var x = pet.midX - size.width / 2
        x = min(max(x, vf.minX + 4), vf.maxX - size.width - 4)
        y = min(max(y, vf.minY + 4), vf.maxY - size.height - 4)
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Notifications + reply (respond to the session from the pet)

    /// Show a notification bubble above the pet.
    private func notify(title: String, body: String, startReply: Bool = false) {
        hideHoverInfo()                                // never overlap the hover popup
        if notificationBubble == nil {
            let b = NotificationBubbleWindow()
            b.onDismiss = { [weak self] in self?.dismissNotification() }
            b.onReply = { [weak self] text in self?.deliverReply(text) }   // deliverReply shows the confirmation
            b.onOpenSession = { [weak self] in self?.openInClaudeDesktop() }
            b.onSuggest = { [weak self] in self?.generateSuggestion() }
            notificationBubble = b
        }
        lastNotification = (title, body)
        notificationBubble?.present(title: title,
                                    timestamp: Self.timeFormatter.string(from: Date()),
                                    body: body, canReply: currentSessionInfo() != nil,
                                    scale: CGFloat(prefs.uiFontScale))
        positionAbovePet(notificationBubble!)
        notificationBubble?.orderFront(nil)
        setUnread(0)                                   // seeing it clears the badge
        if startReply { notificationBubble?.beginReply() }
    }

    private func dismissNotification() { notificationBubble?.orderOut(nil) }

    /// Fire a "Claude finished / needs you" notification when he stops working —
    /// and never leave a stale one up once he resumes.
    private func maybeNotify(from old: PetState?, to new: PetState) {
        guard prefs.followBridge else { return }        // only for live, automatic transitions
        guard prefs.showNotificationBubbles else { return }
        // Per-mood notification toggle from Configuration ▸ Mood States.
        if configProfile.mood(id: new.rawValue)?.notifies == false { return }
        let active: Set<PetState> = [.writing, .reading, .searching, .editing, .runningCommand, .attentive]
        // Resumed working → cancel any pending "waiting" and drop a stale bubble.
        if active.contains(new) {
            pendingIdleNotify?.cancel(); pendingIdleNotify = nil
            dismissNotification()
            return
        }
        guard let old, active.contains(old) else { return }   // only when he STOPS working
        let ctx = detailContext()
        switch new {
        case .waitingForPermission:
            notify(title: "Khosrow needs you", body: "Claude Code is waiting for your approval."); bumpUnread()
        case .success:
            notify(title: "Task complete 🎉", body: ctx.isEmpty ? "Claude Code finished successfully." : ctx); bumpUnread()
        case .failure:
            notify(title: "Something failed", body: ctx.isEmpty ? "A tool or task just failed." : ctx); bumpUnread()
        case .idle:
            // Debounce: only announce "waiting" if he STAYS idle ~10s, so a brief
            // think-pause mid-response never triggers a false "waiting for you".
            pendingIdleNotify?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.controller.state == .idle else { return }
                self.notify(title: "Khosrow is waiting for you",
                            body: ctx.isEmpty ? "Claude Code paused — reply to keep going." : ctx)
                self.bumpUnread()
            }
            pendingIdleNotify = work
            DispatchQueue.main.asyncAfter(deadline: .now() + prefs.waitingDebounceSeconds,
                                          execute: work)
        default: break
        }
    }

    /// A short "what just happened" line for the notification body.
    private func detailContext() -> String {
        guard let s = previousState else { return "" }
        var t = "Just \(moodVerb(s))"
        if let d = lastBridge?.detail, !d.isEmpty { t += " — \(d)" }
        return t + "."
    }

    @objc private func openReply() {
        let ctx = detailContext()
        notify(title: "Reply to Claude",
               body: ctx.isEmpty ? "Type a message to send to your session." : ctx,
               startReply: true)
    }

    // MARK: Badge

    private func configureBadge() {
        badge.isHidden = true
        container.addSubview(badge)
    }

    private func layoutBadge() {
        let d = max(16, 18 * CGFloat(prefs.uiFontScale))
        let sprite = spriteSize()
        badge.frame = NSRect(x: sprite.width - d, y: pillBandHeight() + sprite.height - d, width: d, height: d)
        badge.uiScale = CGFloat(prefs.uiFontScale)
    }

    private func bumpUnread() { setUnread(unread + 1) }
    private func setUnread(_ n: Int) {
        unread = max(0, n)
        badge.count = unread
        badge.isHidden = unread == 0 || !prefs.showUnreadBadge
        if unread > 0 { layoutBadge() }
    }

    // MARK: Reply delivery

    /// The session id + cwd to reply into (assigned session, else the live one).
    private func currentSessionInfo() -> (id: String, cwd: String)? {
        let id: String?
        if prefs.watchMode, prefs.watchSession != "auto", !prefs.watchSession.isEmpty {
            id = prefs.watchSession
        } else {
            id = lastBridge?.session
        }
        guard let sid = id, !sid.isEmpty else { return nil }
        return (sid, sessionCwd(for: sid) ?? FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// The transcript file for a session id (filename is the id).
    private func transcriptURL(for id: String) -> URL? {
        let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { return nil }
        for dir in dirs {
            let f = dir.appendingPathComponent("\(id).jsonl")
            if FileManager.default.fileExists(atPath: f.path) { return f }
        }
        return nil
    }

    /// Read the `cwd` field from the head of a session transcript.
    private func sessionCwd(for id: String) -> String? {
        guard let f = transcriptURL(for: id), let handle = try? FileHandle(forReadingFrom: f) else { return nil }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 16384)
        for line in String(decoding: head, as: UTF8.self).split(separator: "\n") {
            if let d = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let cwd = obj["cwd"] as? String, !cwd.isEmpty { return cwd }
        }
        return nil
    }

    /// The last assistant *text* message in a session (what Claude just said),
    /// capped to a reasonable length — the context for a suggested reply.
    private func lastAssistantMessage(for id: String) -> String? {
        guard let f = transcriptURL(for: id), let handle = try? FileHandle(forReadingFrom: f) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 131_072 ? end - 131_072 : 0)
        let data = handle.readDataToEndOfFile()
        var last: String?
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            let texts = content.compactMap { blk -> String? in
                (blk["type"] as? String) == "text" ? (blk["text"] as? String) : nil
            }
            let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { last = joined }
        }
        guard let last else { return nil }
        return last.count > 4000 ? String(last.suffix(4000)) : last
    }

    private func claudeExecutable() -> String {
        ["\(NSHomeDirectory())/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
    }

    // MARK: Suggested reply (asks Claude for the best next message)

    /// Generate the single best suggested reply to Claude's last message and
    /// prefill the reply field with it. Runs `claude -p` (tools disabled) off-main.
    private func generateSuggestion() {
        notificationBubble?.beginSuggesting()
        guard let info = currentSessionInfo() else { notificationBubble?.suggestionFailed(); return }
        let context = lastAssistantMessage(for: info.id) ?? ""
        let meta = """
        You are helping a software developer decide how to reply to their AI pair-programmer (Claude Code) mid-session. Here is Claude's most recent message to the developer:

        \"\"\"
        \(context.isEmpty ? "(Claude is waiting for the developer's next instruction.)" : context)
        \"\"\"

        Write the single best next message the developer should send to keep the work moving productively — approving, redirecting, answering a question, or giving the next instruction as appropriate. Be specific, natural, and concise (1–3 sentences). Output ONLY the message text the developer would send: no preamble, no quotes, no explanation.
        """
        let claude = claudeExecutable()
        let cwd = info.cwd
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let out = AppController.runClaudePrint(claude: claude, prompt: meta, cwd: cwd)
            let text = (out ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if let reason = AppController.claudeErrorReason(text) {
                    self?.notificationBubble?.suggestionFailed(reason)   // don't dump raw errors into the field
                } else {
                    self?.notificationBubble?.setSuggestion(text)
                }
            }
        }
    }

    /// If `claude -p` output is actually an error (not a suggestion), return a
    /// short, actionable reason to show; otherwise nil.
    private static func claudeErrorReason(_ out: String) -> String? {
        if out.isEmpty { return "No suggestion came back — type your reply…" }
        let s = out.lowercased()
        if s.contains("api error") || s.contains("authentication") || s.contains("401")
            || s.contains("not logged in") || s.contains("/login") || s.hasPrefix("failed to") {
            return "Claude CLI is signed out — use the menu ▸ “Sign in to Claude CLI…”, then retry."
        }
        return nil
    }

    /// Open a Terminal that signs the standalone `claude` CLI in (one-time), so
    /// 💡 Suggest can generate replies. Desktop's sign-in is separate from this.
    @objc private func signInClaudeCLI() {
        let claude = claudeExecutable()
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        #!/bin/bash
        unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
        clear
        echo "Signing the Claude CLI in — this enables Khosrow's 💡 Suggest."
        echo "Follow the prompts (a browser window will open), then you can close this."
        echo
        exec \(q(claude)) auth login
        """
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("khosrow-signin-\(UUID().uuidString).command")
        do {
            try script.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            NSWorkspace.shared.open(tmp)
        } catch { NSLog("Khosrow: sign-in failed: \(error)") }
    }

    /// Run `claude -p` with tools disabled, prompt on stdin, with a watchdog.
    private static func runClaudePrint(claude: String, prompt: String, cwd: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claude)
        proc.arguments = ["-p", "--tools", ""]          // no tools -> pure text generation
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        // Run like a normal terminal: drop the Claude Code session + auth-context
        // env vars so `claude` uses your normal signed-in CLI credentials (and
        // never trips the nested-session guard or an endpoint/token mismatch).
        var env = ProcessInfo.processInfo.environment
        for key in env.keys where key.hasPrefix("CLAUDE_CODE") || key.hasPrefix("ANTHROPIC_")
            || key == "CLAUDECODE" || key == "CLAUDE_AGENT_SDK_VERSION"
            || key == "CLAUDE_PID" || key == "CLAUDE_EFFORT" || key == "AI_AGENT" {
            env.removeValue(forKey: key)
        }
        proc.environment = env
        let outPipe = Pipe(), inPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = inPipe
        do { try proc.run() } catch { return nil }
        inPipe.fileHandleForWriting.write(Data(prompt.utf8))
        try? inPipe.fileHandleForWriting.close()
        let watchdog = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: watchdog)
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        watchdog.cancel()
        return String(data: data, encoding: .utf8)
    }

    /// Deliver the user's reply by opening the exact session in Claude Desktop
    /// and copying the message so it's one paste from being sent.
    ///
    /// There is no supported way to silently inject a turn into a live Desktop
    /// session (no local endpoint; running `claude --resume` in a Terminal races
    /// the single-writer live session and crashes). Opening the session by id via
    /// the ungated `claude://resume?session=<uuid>` deep link, plus the clipboard,
    /// reliably lands the reply in the session you're working in — and you confirm
    /// with ⌘V ↵ so it can never fire into the wrong conversation.
    private func deliverReply(_ text: String) {
        guard let info = currentSessionInfo() else {
            notify(title: "No session to reply to", body: "Turn on Watch mode or assign a session first.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        openSessionInDesktop(info.id)
        let preview = text.count > 70 ? String(text.prefix(70)) + "…" : text
        notify(title: "Opened your session in Claude Desktop",
               body: "Your reply is on the clipboard — press ⌘V then ↵ to send it:\n“\(preview)”")
    }

    /// Navigate Claude Desktop to a specific Claude Code session by its id.
    private func openSessionInDesktop(_ id: String) {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        let url = URL(string: "claude://resume?session=\(enc)") ?? URL(string: "claude://claude.ai/code")!
        NSWorkspace.shared.open(url)
    }

    /// The "Open in Claude" button — jump to this session in Claude Desktop.
    private func openInClaudeDesktop() {
        if let info = currentSessionInfo() { openSessionInDesktop(info.id) }
        else if let url = URL(string: "claude://claude.ai/code") { NSWorkspace.shared.open(url) }
    }

    // MARK: Dragging

    private func wireDragging() {
        petView.onDragged = { [weak self] delta in
            guard let self, let window = self.window else { return }
            let origin = window.frame.origin
            window.setFrameOrigin(NSPoint(x: origin.x + delta.width,
                                          y: origin.y + delta.height))
            if self.isHovering { self.positionHoverInfo() }   // popup follows during a drag
        }
        petView.onDragEnded = { [weak self] in self?.savePosition() }
        petView.onClick = { [weak self] in self?.poke() }
        petView.onContextMenu = { [weak self] event in self?.showActionInfo(for: event) }
        petView.onHover = { [weak self] inside in self?.setHover(inside) }
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
        // Never block the main thread here: warm the session list off-main only
        // if it's still empty (launch + Rescan keep it fresh otherwise).
        if sessionCache.isEmpty { refreshSessionsAsync() }
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

        // Assign / show which Claude Code session Khosrow reacts to — right here
        // in the right-click menu (not only the status-bar menu).
        let sessionItem = NSMenuItem(title: "Watch session", action: nil, keyEquivalent: "")
        sessionItem.submenu = buildSessionSubmenu()
        sessionItem.toolTip = "Assign which Claude Code session Khosrow reacts to (Automatic = the newest active one)."
        menu.addItem(sessionItem)

        let replyItem = NSMenuItem(title: "💬 Reply to Claude…", action: #selector(openReply), keyEquivalent: "")
        replyItem.target = self
        menu.addItem(replyItem)

        menu.popUp(positioning: nil,
                   at: petView.convert(event.locationInWindow, from: nil),
                   in: petView)
    }

    private static let moodVerbs: [PetState: String] = [
        .idle: "resting", .attentive: "listening", .writing: "writing a response",
        .reading: "reading a file", .searching: "searching", .editing: "editing",
        .runningCommand: "running a command", .waitingForPermission: "waiting for permission",
        .praying: "praying", .success: "celebrating a win",
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

    /// The session Khosrow is tuned to: the live label if present, else the
    /// assigned one, else "newest active session".
    private func sessionDisplay() -> String {
        // A specifically-assigned session takes priority — but only while Watch
        // mode is actually driving it. That way a stale signal (or a hook, which
        // ignores the assignment) is never mislabelled with the assigned session,
        // and a session you just picked shows immediately instead of the old one.
        if prefs.watchMode, prefs.watchSession != "auto", !prefs.watchSession.isEmpty {
            return prefs.watchSessionLabel.isEmpty ? String(prefs.watchSession.prefix(8)) : prefs.watchSessionLabel
        }
        if let label = lastBridge?.sessionLabel, !label.isEmpty { return label }
        return "newest active session"
    }

    /// Where the live signal comes from, and which session — one short line.
    private func sourceLine() -> String {
        if !prefs.watchMode, lastBridge == nil {
            return "No live signal yet — turn on Watch mode, or install the hooks."
        }
        let via = prefs.watchMode ? "Watch mode" : "installed hooks"
        let waiting = (lastBridge == nil) ? " (waiting…)" : ""
        return "Session: \(sessionDisplay())\(waiting) · via \(via)"
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
            // Keep Show detail meaningful even while holding a mood, and even with
            // no live signal: toggling it always adds or removes a line.
            if prefs.detailMode {
                if let live = liveActivityLine() { lines.append("Meanwhile, Claude Code is \(live).") }
                else { lines.append("Meanwhile: no live activity from Claude Code.") }
            } else {
                lines.append("Turn on  Show detail  to see live Claude Code activity.")
            }
            return ("Khosrow — holding “\(moodVerb(state))”", lines)
        }

        // Automatic mode: he mirrors Claude Code.
        let why: [PetState: String] = [
            .idle: "Nothing is running right now (or a tool just finished cleanly).",
            .attentive: "A Claude Code session or sub-task just started.",
            .writing: "Claude Code is composing a response to your prompt.",
            .reading: "Claude Code is reading a file.",
            .searching: "Claude Code is searching or browsing the codebase.",
            .editing: "Claude Code is editing a file.",
            .runningCommand: "Claude Code is running a shell command.",
            .waitingForPermission: "Claude Code is waiting for you to approve something.",
            .praying: "Reflecting — a manual/optional mood with no automatic Claude Code trigger.",
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
        // Route through the user's configurable condition->mood mapping.
        switch ProfileResolver.resolve(state: state, tool: payload.tool,
                                       category: payload.toolCategory,
                                       profile: configProfile) {
        case .mood(let id):
            controller.apply(state: PetState(rawValue: id) ?? state)
        case .ignore:
            break                       // condition unassigned/disabled: no change
        case .passthrough:
            controller.apply(state: state)
        }
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

        let sessionItem = NSMenuItem(title: "Watch session", action: nil, keyEquivalent: "")
        sessionItem.submenu = buildSessionSubmenu()
        sessionItem.toolTip = "Which Claude Code session Khosrow reacts to (or Automatic = the newest active one)."
        menu.addItem(sessionItem)

        let replyItem = makeItem("💬 Reply to Claude…", #selector(openReply), "r")
        replyItem.toolTip = "Type a message; opens your session in Claude Desktop with it copied (⌘V ↵ to send)."
        menu.addItem(replyItem)

        let signInItem = makeItem("Sign in to Claude CLI…", #selector(signInClaudeCLI), "")
        signInItem.toolTip = "One-time: sign the standalone claude CLI in so 💡 Suggest can generate replies."
        menu.addItem(signInItem)
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

        // Text size submenu — the mood pill, popups, notification, badge & timer
        // ring, sized independently of the pet Scale above.
        let textItem = NSMenuItem(title: "Text size", action: nil, keyEquivalent: "")
        let textMenu = NSMenu()
        for pct in [75, 100, 125, 150, 200, 250, 300] {
            let item = makeItem("\(pct)%", #selector(pickUIFontScale(_:)), "")
            item.representedObject = Double(pct) / 100.0
            item.state = abs(prefs.uiFontScale - Double(pct) / 100.0) < 0.001 ? .on : .off
            textMenu.addItem(item)
        }
        textItem.submenu = textMenu
        textItem.toolTip = "Size of the mood pill, popups, notifications, badge & timer — independent of Scale."
        menu.addItem(textItem)

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

        let configItem = makeItem("Configure Khosrow…", #selector(openConfiguration), ",")
        configItem.toolTip = "All settings in one place: appearance, moods, visual acts, hook mapping, and diagnostics."
        menu.addItem(configItem)
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
            lastBridge = nil            // the watcher's last signal is no longer live
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
        var arguments = [script.path]
        if prefs.detailMode { arguments.append("--detail") }
        arguments += ["--session", prefs.watchSession.isEmpty ? "auto" : prefs.watchSession]
        proc.arguments = arguments
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

    // MARK: Watch-session picker

    /// Build the "Watch session" submenu: Automatic + recent sessions + Rescan.
    private func buildSessionSubmenu() -> NSMenu {
        let m = NSMenu()
        let auto = makeItem("Automatic (newest active)", #selector(pickSession(_:)), "")
        auto.representedObject = "auto"
        auto.state = (prefs.watchSession.isEmpty || prefs.watchSession == "auto") ? .on : .off
        m.addItem(auto)
        if !sessionCache.isEmpty { m.addItem(.separator()) }
        for s in sessionCache {
            let item = makeItem(s.label, #selector(pickSession(_:)), "")
            item.representedObject = s.id
            item.state = (prefs.watchSession == s.id) ? .on : .off
            m.addItem(item)
        }
        m.addItem(.separator())
        m.addItem(makeItem("Rescan sessions", #selector(rescanSessions), ""))
        return m
    }

    @objc private func pickSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        prefs.watchSession = id
        prefs.watchSessionLabel = (id == "auto") ? "" : sender.title
        // Pinning a specific session: drop the previous session's signal so the
        // info reads "(waiting…)" for the new target until it emits, rather than
        // attributing the old session's activity to the one you just picked.
        if id != "auto" { lastBridge = nil }
        if watchProcess != nil { stopWatcher(); startWatcher() }   // re-target the watcher
        store.save(prefs); rebuildMenu()
    }

    @objc private func rescanSessions() { refreshSessionsAsync() }

    private func refreshSessionsAsync() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let list = self.runListSessions()
            DispatchQueue.main.async {
                guard !list.isEmpty else { return }
                self.sessionCache = list
                self.rebuildMenu()
            }
        }
    }

    /// Ask the bundled watcher to enumerate recent Claude Code sessions.
    private func runListSessions() -> [(id: String, label: String)] {
        guard let script = KhosrowResources.watchScriptURL() else { return [] }
        let candidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return [] }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = [script.path, "--list-sessions"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let id = dict["id"] as? String else { return nil }
            return (id, (dict["label"] as? String) ?? id)
        }
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

        resizeKeepingCenter(to: containerSize())

        controller = PetController(manifest: manifest, sheet: sheet, view: petView)
        controller.speedMultiplier = prefs.speedMultiplier
        controller.setBaseOpacity(CGFloat(prefs.opacity))
        controller.onStateChanged = { [weak self] _ in self?.updateMood() }
        controller.setPaused(prefs.paused)
        controller.start()
        controller.apply(state: keep)
        layoutContainer()

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

    @objc private func pickUIFontScale(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        prefs.uiFontScale = Preferences.uiFontScaleRange.clamp(v)
        applyUIFontScale()
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
