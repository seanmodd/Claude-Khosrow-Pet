import Foundation

/// A minimal, deterministic sprite-clip player.
///
/// It is pure time-arithmetic — no timers, no drawing — so it is fully unit
/// testable. The app feeds it elapsed time each display tick; the manual test
/// console drives it frame-by-frame.
public struct AnimationPlayer: Equatable {

    public private(set) var frameCount: Int
    public private(set) var fps: Double
    public private(set) var loops: Bool

    /// Accumulated time within the current frame cadence.
    private var accumulator: TimeInterval = 0
    /// Current 0-based frame index.
    public private(set) var frameIndex: Int = 0
    /// Whether a non-looping clip has reached and is holding its last frame.
    public private(set) var finished: Bool = false
    public var paused: Bool = false

    public init(frameCount: Int, fps: Double, loops: Bool) {
        self.frameCount = max(1, frameCount)
        self.fps = max(0.01, fps)
        self.loops = loops
    }

    public init(clip: RuntimeManifest.Clip, fpsOverride: Double? = nil) {
        self.init(frameCount: clip.frameCount,
                  fps: fpsOverride ?? clip.fps,
                  loops: clip.loop)
    }

    public var secondsPerFrame: TimeInterval { 1.0 / fps }

    /// Reconfigure for a new clip and rewind to frame 0.
    public mutating func reset(frameCount: Int, fps: Double, loops: Bool) {
        self.frameCount = max(1, frameCount)
        self.fps = max(0.01, fps)
        self.loops = loops
        self.accumulator = 0
        self.frameIndex = 0
        self.finished = false
    }

    public mutating func reset(clip: RuntimeManifest.Clip, fpsOverride: Double? = nil) {
        reset(frameCount: clip.frameCount, fps: fpsOverride ?? clip.fps, loops: clip.loop)
    }

    /// Advance playback by `dt` seconds. Returns true if the frame index changed.
    @discardableResult
    public mutating func advance(by dt: TimeInterval) -> Bool {
        guard !paused, dt > 0, frameCount > 1 else { return false }
        if finished && !loops { return false }

        accumulator += dt
        let spf = secondsPerFrame
        var advanced = 0
        while accumulator >= spf {
            accumulator -= spf
            advanced += 1
        }
        guard advanced > 0 else { return false }

        let previous = frameIndex
        if loops {
            frameIndex = (frameIndex + advanced) % frameCount
        } else {
            let next = frameIndex + advanced
            if next >= frameCount - 1 {
                frameIndex = frameCount - 1
                finished = true
            } else {
                frameIndex = next
            }
        }
        return frameIndex != previous
    }

    // MARK: - Manual controls (used by the test console)

    public mutating func nextFrame() {
        accumulator = 0
        finished = false
        frameIndex = (frameIndex + 1) % frameCount
    }

    public mutating func previousFrame() {
        accumulator = 0
        finished = false
        frameIndex = (frameIndex - 1 + frameCount) % frameCount
    }

    public mutating func seek(to index: Int) {
        accumulator = 0
        frameIndex = min(max(0, index), frameCount - 1)
        finished = loops ? false : (frameIndex == frameCount - 1)
    }

    public mutating func rewind() {
        accumulator = 0
        frameIndex = 0
        finished = false
    }
}
