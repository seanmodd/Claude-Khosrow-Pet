#if canImport(AppKit)
import AppKit
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

    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    /// When true (manual/test mode) the display timer does not auto-advance.
    var manualMode: Bool = false
    /// When true (the sleeping mood) frames are rotated flat onto the ground.
    private var lyingDown = false
    private var rotatedCache: [Int: CGImage] = [:]

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
        renderCurrentFrame()
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
        if player.advance(by: dt * max(0.01, speedMultiplier)) {
            renderCurrentFrame()
        }
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
        lyingDown = (state == .sleeping)
        renderCurrentFrame()
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
        let base = sheet.frame(row: clip.row, index: player.frameIndex)
        guard lyingDown, let base else { view.show(base); return }
        let key = clip.row * manifest.sheet.cols + player.frameIndex
        if let cached = rotatedCache[key] { view.show(cached); return }
        let rotated = SpriteSheet.lyingFrame(base)
        if let rotated { rotatedCache[key] = rotated }
        view.show(rotated ?? base)
    }
}
#endif
