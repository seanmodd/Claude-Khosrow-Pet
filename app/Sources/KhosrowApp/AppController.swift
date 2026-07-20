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
    private var container: NSView!          // holds the sprite + the mood pill
    private let pill = MoodPillView(frame: .zero)   // always-visible mood label beneath him
    private var hoverInfo: HoverInfoWindow? // the "why" popup shown on hover
    private var isHovering = false
    private var hoverHideWork: DispatchWorkItem?
    private var notificationBubble: NotificationBubbleWindow?
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
    }

    // MARK: Sizing

    /// The sprite (pet) size at the current scale.
    private func spriteSize() -> NSSize {
        let s = CGFloat(prefs.scale)
        return NSSize(width: CGFloat(manifest.sheet.cellWidth) * s,
                      height: CGFloat(manifest.sheet.cellHeight) * s)
    }

    /// Height of the band reserved beneath the sprite for the mood pill.
    private func pillBandHeight() -> CGFloat { max(20, 26 * CGFloat(prefs.scale)) }

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
        let d = max(22, 27 * CGFloat(prefs.scale))
        let sprite = spriteSize()
        // top-left of the sprite (opposite the unread badge)
        progressRing.frame = NSRect(x: 1, y: pillBandHeight() + sprite.height - d, width: d, height: d)
        progressRing.uiScale = CGFloat(prefs.scale)
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
        progressRing.isHidden = false
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

    /// Resize the window while keeping its center point fixed on screen.
    private func resizeKeepingCenter(to newSize: NSSize) {
        let old = window.frame
        let origin = NSPoint(x: old.midX - newSize.width / 2,
                             y: old.midY - newSize.height / 2)
        window.setFrame(NSRect(origin: origin, size: newSize), display: true)
    }

    // MARK: Mood pill + hover "why" popup

    private static let pillLabels: [PetState: String] = [
        .idle: "🧍 idle", .attentive: "🙌 attentive", .writing: "📝 writing",
        .reading: "📖 reading", .searching: "🔎 searching", .editing: "✍️ editing",
        .runningCommand: "🏃 running", .waitingForPermission: "✋ waiting",
        .success: "🎉 success", .failure: "🙇 failure", .sleeping: "😴 sleeping",
    ]
    private func pillText(_ s: PetState) -> String { Self.pillLabels[s] ?? s.rawValue }

    /// Refresh the pill's label + position for the current mood, and the popup if open.
    private func updateMood() {
        let state = controller.state
        pill.set(text: pillText(state), scale: CGFloat(prefs.scale))
        let sz = pill.pillSize
        let band = pillBandHeight()
        pill.frame = NSRect(x: (spriteSize().width - sz.width) / 2,
                            y: (band - sz.height) / 2, width: sz.width, height: sz.height)
        if isHovering { refreshHoverInfo() }
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
        // Never stack on top of a visible notification bubble.
        if notificationBubble?.isVisible == true { return }
        if hoverInfo == nil {
            let h = HoverInfoWindow()
            h.onDismiss = { [weak self] in self?.hideHoverInfo() }
            h.onPopupHover = { [weak self] inside in
                if inside { self?.hoverHideWork?.cancel(); self?.hoverHideWork = nil }
                else { self?.scheduleHoverHide() }
            }
            hoverInfo = h
        }
        isHovering = true
        refreshHoverInfo()
        hoverInfo?.order(.above, relativeTo: window.windowNumber)
    }

    /// Hide after a short grace period, so moving the cursor onto the popup
    /// (to drag or dismiss it) doesn't make it vanish.
    private func scheduleHoverHide() {
        hoverHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideHoverInfo() }
        hoverHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func hideHoverInfo() {
        isHovering = false
        hoverInfo?.orderOut(nil)
    }

    private func refreshHoverInfo() {
        let info = actionExplanation()
        hoverInfo?.update(title: info.title, lines: info.lines, scale: CGFloat(prefs.scale))
        positionHoverInfo()
    }

    private func positionHoverInfo() {
        guard let hoverInfo else { return }
        positionAbovePet(hoverInfo)
    }

    /// Sit a companion window just above the pet, centered, kept on-screen.
    private func positionAbovePet(_ win: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let pet = window.frame, size = win.frame.size, vf = screen.visibleFrame
        var y = pet.maxY + 8 * CGFloat(prefs.scale)
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
            b.onReply = { [weak self] text in self?.deliverReply(text); self?.dismissNotification() }
            b.onOpenSession = { [weak self] in self?.openInClaudeDesktop() }
            b.onSuggest = { [weak self] in self?.generateSuggestion() }
            notificationBubble = b
        }
        notificationBubble?.present(title: title,
                                    timestamp: Self.timeFormatter.string(from: Date()),
                                    body: body, canReply: currentSessionInfo() != nil,
                                    scale: CGFloat(prefs.scale))
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
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
        let d = max(16, 18 * CGFloat(prefs.scale))
        let sprite = spriteSize()
        badge.frame = NSRect(x: sprite.width - d, y: pillBandHeight() + sprite.height - d, width: d, height: d)
        badge.uiScale = CGFloat(prefs.scale)
    }

    private func bumpUnread() { setUnread(unread + 1) }
    private func setUnread(_ n: Int) {
        unread = max(0, n)
        badge.count = unread
        badge.isHidden = unread == 0
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
                if text.isEmpty { self?.notificationBubble?.suggestionFailed() }
                else { self?.notificationBubble?.setSuggestion(text) }
            }
        }
    }

    /// Run `claude -p` with tools disabled, prompt on stdin, with a watchdog.
    private static func runClaudePrint(claude: String, prompt: String, cwd: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claude)
        proc.arguments = ["-p", "--tools", ""]          // no tools -> pure text generation
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        // Never let the suggestion call trip the "nested Claude Code session" guard.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
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

    /// Deliver the user's reply to the session by resuming it in a Terminal
    /// (there is no supported way to inject into a live Desktop session).
    private func deliverReply(_ text: String) {
        guard let info = currentSessionInfo() else {
            notify(title: "No session to reply to", body: "Turn on Watch mode or assign a session first.")
            return
        }
        let claudePath = ["\(NSHomeDirectory())/.local/bin/claude",
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        #!/bin/bash
        unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT
        cd \(q(info.cwd)) 2>/dev/null || cd "$HOME"
        clear
        echo "→ Khosrow is delivering your reply to Claude Code…"
        echo
        exec \(q(claudePath)) --resume \(q(info.id)) \(q(text))
        """
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("khosrow-reply-\(UUID().uuidString).command")
        do {
            try script.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            NSWorkspace.shared.open(tmp)
        } catch {
            NSLog("Khosrow: reply failed: \(error)")
        }
    }

    /// Focus Claude Desktop (best-effort; the scheme can't target a Code session).
    private func openInClaudeDesktop() {
        if let url = URL(string: "claude://claude.ai/code") { NSWorkspace.shared.open(url) }
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
        .success: "celebrating a win", .failure: "recovering from an error", .sleeping: "sleeping",
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

        let sessionItem = NSMenuItem(title: "Watch session", action: nil, keyEquivalent: "")
        sessionItem.submenu = buildSessionSubmenu()
        sessionItem.toolTip = "Which Claude Code session Khosrow reacts to (or Automatic = the newest active one)."
        menu.addItem(sessionItem)

        let replyItem = makeItem("💬 Reply to Claude…", #selector(openReply), "r")
        replyItem.toolTip = "Type a message and send it to your session (opens it via claude --resume in Terminal)."
        menu.addItem(replyItem)
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
