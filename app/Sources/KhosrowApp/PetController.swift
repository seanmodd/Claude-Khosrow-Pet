#if canImport(AppKit)
import AppKit
import ImageIO
import QuartzCore
import KhosrowKit

/// Owns playback: advances the ``AnimationPlayer`` on a display timer and pushes
/// the current frame into the ``PetView``. Also exposes manual controls for the
/// test console.
final class PetController {
    let manifest: RuntimeManifest
    let sheet: SpriteSheet
    let view: PetView

    private(set) var state: PetState
    private(set) var clip: RuntimeManifest.Clip
    private var player: AnimationPlayer

    /// Extra multiplier on top of each clip's fps (from preferences / console).
    var speedMultiplier: Double = 1.0
    /// Base opacity from preferences (dimming for sleeping multiplies this).
    var baseOpacity: CGFloat = 1.0
    /// Called after the state changes, so the app can refresh the mood pill/popup.
    var onStateChanged: ((PetState) -> Void)?

    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    /// When true (manual/test mode) the display timer does not auto-advance.
    var manualMode: Bool = false

    /// A hand-drawn frame sequence that replaces the sprite sheet for a mood,
    /// played on its own clock — independent of the mapped clip's fps and frame
    /// count, so the number of frames never has to divide the clip's.
    private struct CustomAnim {
        let frames: [CGImage]
        let fps: Double
        let loops: Bool
    }
    /// Per-state art that replaces the sprite sheet: hand-drawn frame sequences
    /// (sleeping / reading / success) and Gemini illustrated stills (attentive /
    /// searching / waiting / writing / running / praying).
    private let customAnims: [PetState: CustomAnim]
    /// Playback cursor + accumulator for the active custom sequence.
    private var customFrame = 0
    private var customAccum: CFTimeInterval = 0

    init(manifest: RuntimeManifest, sheet: SpriteSheet, view: PetView) {
        self.manifest = manifest
        self.sheet = sheet
        self.view = view
        let initial = PetState(loose: manifest.defaultState) ?? .idle
        self.state = initial
        let clip = manifest.clip(forState: initial.rawValue) ?? Array(manifest.clips.values)[0]
        self.clip = clip
        self.player = AnimationPlayer(clip: clip,
                                      fpsOverride: manifest.states[initial.rawValue]?.fpsOverride)
        self.customAnims = PetController.loadCustomAnims()
        renderCurrentFrame()
    }

    /// Which bundled Gemini illustrated still each mood shows by default. The
    /// still (a transparent cut-out of one pose) replaces the sprite-sheet clip;
    /// PetView aspect-fits it, so the differing proportions never distort.
    static let geminiActForState: [PetState: String] = [
        .attentive: "attentive",
        .searching: "searching",
        .waitingForPermission: "waiting",
        .writing: "writing",
        .runningCommand: "running",
        .praying: "praying",
    ]

    /// Load the bundled per-state frame sequences and their playback cadence.
    private static func loadCustomAnims() -> [PetState: CustomAnim] {
        func loadFrames(_ name: String) -> [CGImage] {
            KhosrowResources.customFrameURLs(forState: name).compactMap { url -> CGImage? in
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(src, 0, nil)
            }
        }
        func loadStill(gemini name: String) -> CGImage? {
            guard let url = KhosrowResources.geminiActURL(named: name),
                  let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        var out: [PetState: CustomAnim] = [:]

        // Hand-drawn frame sequences (unchanged): sleeping / reading / success.
        let sleeping = loadFrames("sleeping")
        if !sleeping.isEmpty { out[.sleeping] = CustomAnim(frames: sleeping, fps: 4, loops: true) }
        let reading = loadFrames("reading")
        if !reading.isEmpty { out[.reading] = CustomAnim(frames: reading, fps: 5, loops: true) }
        let success = loadFrames("success")
        if !success.isEmpty { out[.success] = CustomAnim(frames: success, fps: 9, loops: true) }

        // Gemini illustrated stills — one static frame per mood. `writing` now has
        // its own dedicated art and no longer reuses the reading book frames.
        for (state, name) in geminiActForState {
            if let still = loadStill(gemini: name) {
                out[state] = CustomAnim(frames: [still], fps: 1, loops: true)
            }
        }
        return out
    }

    // MARK: Lifecycle

    func start() {
        stop()
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = max(0, now - lastTick)
        lastTick = now
        guard !manualMode, !player.paused else { return }
        let step = dt * max(0.01, speedMultiplier)
        if let anim = customAnims[state] {
            advanceCustom(anim, by: step)
        } else if player.advance(by: step) {
            renderCurrentFrame()
        }
    }

    /// Advance the active custom sequence on its own fps clock (loops or holds
    /// the last frame per the sequence's `loops` flag).
    private func advanceCustom(_ anim: CustomAnim, by dt: CFTimeInterval) {
        guard anim.fps > 0, !anim.frames.isEmpty else { return }
        customAccum += dt
        let frameDur = 1.0 / anim.fps
        var changed = false
        while customAccum >= frameDur {
            customAccum -= frameDur
            let next = customFrame + 1
            if anim.loops { customFrame = next % anim.frames.count }
            else if next < anim.frames.count { customFrame = next }
            changed = true
        }
        if changed { renderCurrentFrame() }
    }

    // MARK: State application

    /// Apply a Claude Code pet state, switching clips (and fps/dim) as mapped.
    func apply(state: PetState) {
        self.state = state
        let binding = manifest.states[state.rawValue]
        let resolved = manifest.clip(forState: state.rawValue)
            ?? Array(manifest.clips.values)[0]
        clip = resolved
        player.reset(clip: resolved, fpsOverride: binding?.fpsOverride)
        applyDim(binding?.dim ?? false)
        customFrame = 0        // restart any custom sequence for the new mood
        customAccum = 0
        renderCurrentFrame()
        onStateChanged?(state)
    }

    private func applyDim(_ dim: Bool) {
        view.setDim(dim ? baseOpacity * 0.55 : baseOpacity)
    }

    func setBaseOpacity(_ opacity: CGFloat) {
        baseOpacity = opacity
        applyDim(manifest.states[state.rawValue]?.dim ?? false)
    }

    // MARK: Pause / resume

    var isPaused: Bool { player.paused }

    func setPaused(_ paused: Bool) {
        player.paused = paused
    }

    func togglePaused() { player.paused.toggle() }

    // MARK: Manual controls (test console)

    /// Directly select a clip by id (bypasses the state map), for testing.
    func selectClip(id: String, fpsOverride: Double? = nil) {
        guard let c = manifest.clips[id] else { return }
        clip = c
        player.reset(clip: c, fpsOverride: fpsOverride)
        renderCurrentFrame()
    }

    func stepNext() { player.nextFrame(); renderCurrentFrame() }
    func stepPrevious() { player.previousFrame(); renderCurrentFrame() }
    func rewind() { player.rewind(); renderCurrentFrame() }

    var currentFrameIndex: Int { player.frameIndex }
    var currentRow: Int { clip.row }
    var currentColumn: Int { player.frameIndex }
    var currentFrameCount: Int { clip.frameCount }
    var sequentialIndex: Int { clip.row * manifest.sheet.cols + player.frameIndex }

    private func renderCurrentFrame() {
        // Custom-frame moods draw their own art — except while the test console
        // has taken over manual clip preview, where the sheet should show.
        if !manualMode, let anim = customAnims[state], !anim.frames.isEmpty {
            view.show(anim.frames[min(customFrame, anim.frames.count - 1)])
            return
        }
        view.show(sheet.frame(row: clip.row, index: player.frameIndex))
    }
}
#endif
