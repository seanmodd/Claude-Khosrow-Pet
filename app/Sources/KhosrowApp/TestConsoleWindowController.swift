#if canImport(AppKit)
import AppKit
import KhosrowKit

/// A view that paints a checkerboard so sprite transparency is visible — the
/// "transparency verification" affordance of the test console.
final class CheckerboardView: NSView {
    var enabled = true { didSet { needsDisplay = true } }
    private let square: CGFloat = 12

    override var isFlipped: Bool { true }

    override func draw(_ dirty: NSRect) {
        guard enabled else {
            NSColor.clear.setFill(); dirty.fill(); return
        }
        NSColor(white: 0.82, alpha: 1).setFill(); bounds.fill()
        NSColor(white: 0.66, alpha: 1).setFill()
        var y: CGFloat = 0, row = 0
        while y < bounds.height {
            var x: CGFloat = (row % 2 == 0) ? 0 : square
            while x < bounds.width {
                NSRect(x: x, y: y, width: square, height: square).fill()
                x += square * 2
            }
            y += square; row += 1
        }
    }
}

/// Manual animation-testing mode. Drives a private ``PetController`` in manual
/// mode so it never disturbs the live desktop pet.
final class TestConsoleWindowController: NSWindowController {
    private let manifest: RuntimeManifest
    private let sheet: SpriteSheet
    private let controller: PetController

    private let checker = CheckerboardView()
    private let preview = PetView(frame: .zero)
    private let statePopup = NSPopUpButton()
    private let clipPopup = NSPopUpButton()
    private let facingPopup = NSPopUpButton()
    private let infoLabel = NSTextField(labelWithString: "")
    private let playButton = NSButton()
    private let speedSlider = NSSlider(value: 1, minValue: 0.1, maxValue: 4, target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "1.00×")
    private let scaleSlider = NSSlider(value: 1, minValue: 0.25, maxValue: 4, target: nil, action: nil)
    private let scaleLabel = NSTextField(labelWithString: "1.00×")
    private let checkerToggle = NSButton(checkboxWithTitle: "Checkerboard (verify alpha)", target: nil, action: nil)

    private var refresh: Timer?

    init(manifest: RuntimeManifest, sheet: SpriteSheet) {
        self.manifest = manifest
        self.sheet = sheet
        self.controller = PetController(manifest: manifest, sheet: sheet, view: preview)
        controller.manualMode = true
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Khosrow — Animation Test Console"
        super.init(window: window)
        buildUI()
        controller.start()
        controller.selectClip(id: "idle")
        startInfoRefresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        // Preview area (checkerboard + pet on top)
        checker.frame = NSRect(x: 20, y: 20, width: 340, height: 300)
        checker.autoresizingMask = [.width, .minYMargin]
        preview.frame = checker.bounds
        preview.autoresizingMask = [.width, .height]
        checker.addSubview(preview)
        content.addSubview(checker)

        var y: CGFloat = 470

        func addRow(_ label: String, _ control: NSView, height: CGFloat = 26) {
            let l = NSTextField(labelWithString: label)
            l.frame = NSRect(x: 20, y: y, width: 96, height: 20)
            l.alignment = .right
            l.textColor = .secondaryLabelColor
            content.addSubview(l)
            control.frame = NSRect(x: 124, y: y - 3, width: 236, height: height)
            content.addSubview(control)
            y -= 34
        }

        // State selection
        statePopup.addItems(withTitles: PetState.allCases.map { $0.rawValue })
        statePopup.target = self; statePopup.action = #selector(stateChanged)
        addRow("State:", statePopup)

        // Direction (facing) filter
        facingPopup.addItems(withTitles: ["all", "front", "left", "right"])
        facingPopup.target = self; facingPopup.action = #selector(facingChanged)
        addRow("Direction:", facingPopup)

        // Clip selection
        reloadClipPopup(facing: "all")
        clipPopup.target = self; clipPopup.action = #selector(clipChanged)
        addRow("Clip:", clipPopup)

        // Transport buttons
        let transport = NSStackView()
        transport.orientation = .horizontal
        transport.spacing = 8
        playButton.title = "Pause"; playButton.bezelStyle = .rounded
        playButton.target = self; playButton.action = #selector(togglePlay)
        let prev = NSButton(title: "◀ Prev", target: self, action: #selector(prevFrame))
        let next = NSButton(title: "Next ▶", target: self, action: #selector(nextFrame))
        let rewind = NSButton(title: "⏮ Rewind", target: self, action: #selector(rewind))
        prev.bezelStyle = .rounded; next.bezelStyle = .rounded; rewind.bezelStyle = .rounded
        [playButton, prev, next, rewind].forEach { transport.addArrangedSubview($0) }
        addRow("Transport:", transport, height: 28)

        // Speed
        speedSlider.target = self; speedSlider.action = #selector(speedChanged)
        let speedStack = NSStackView(views: [speedSlider, speedLabel])
        speedStack.orientation = .horizontal
        speedLabel.frame.size.width = 48
        addRow("Speed:", speedStack)

        // Scale
        scaleSlider.target = self; scaleSlider.action = #selector(scaleChanged)
        let scaleStack = NSStackView(views: [scaleSlider, scaleLabel])
        scaleStack.orientation = .horizontal
        addRow("Scale:", scaleStack)

        // Checkerboard toggle
        checkerToggle.state = .on
        checkerToggle.target = self; checkerToggle.action = #selector(toggleChecker)
        addRow("Alpha:", checkerToggle)

        // Info label
        infoLabel.frame = NSRect(x: 20, y: y - 6, width: 340, height: 20)
        infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = .secondaryLabelColor
        content.addSubview(infoLabel)
    }

    private func reloadClipPopup(facing: String) {
        clipPopup.removeAllItems()
        let ids = manifest.clips.values
            .filter { facing == "all" || $0.facing == facing }
            .sorted { $0.row < $1.row }
            .map { $0.id }
        clipPopup.addItems(withTitles: ids)
    }

    // MARK: Actions

    @objc private func stateChanged() {
        guard let title = statePopup.titleOfSelectedItem,
              let state = PetState(rawValue: title) else { return }
        controller.apply(state: state)
        if let clipID = manifest.states[state.rawValue]?.clip {
            clipPopup.selectItem(withTitle: clipID)
        }
    }

    @objc private func facingChanged() {
        reloadClipPopup(facing: facingPopup.titleOfSelectedItem ?? "all")
        clipChanged()
    }

    @objc private func clipChanged() {
        if let id = clipPopup.titleOfSelectedItem { controller.selectClip(id: id) }
    }

    @objc private func togglePlay() {
        controller.manualMode.toggle()
        playButton.title = controller.manualMode ? "Play" : "Pause"
    }

    @objc private func nextFrame() { controller.manualMode = true; playButton.title = "Play"; controller.stepNext() }
    @objc private func prevFrame() { controller.manualMode = true; playButton.title = "Play"; controller.stepPrevious() }
    @objc private func rewind() { controller.rewind() }

    @objc private func speedChanged() {
        controller.speedMultiplier = speedSlider.doubleValue
        speedLabel.stringValue = String(format: "%.2f×", speedSlider.doubleValue)
    }

    @objc private func scaleChanged() {
        let s = scaleSlider.doubleValue
        scaleLabel.stringValue = String(format: "%.2f×", s)
        // Resize the preview via layer transform for a quick visual check.
        preview.layer?.sublayerTransform = CATransform3DIdentity
        let base = CGFloat(1.0)
        preview.layer?.transform = CATransform3DMakeScale(base * CGFloat(s), base * CGFloat(s), 1)
    }

    @objc private func toggleChecker() {
        checker.enabled = (checkerToggle.state == .on)
    }

    private func startInfoRefresh() {
        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.infoLabel.stringValue = String(
                format: "clip=%@  row=%d  col=%d  frame=%d/%d  seq=#%d",
                self.controller.clip.id, self.controller.currentRow,
                self.controller.currentColumn, self.controller.currentFrameIndex + 1,
                self.controller.currentFrameCount, self.controller.sequentialIndex)
        }
        RunLoop.main.add(t, forMode: .common)
        refresh = t
    }
}
#endif
