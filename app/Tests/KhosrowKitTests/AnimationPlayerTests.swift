import XCTest
@testable import KhosrowKit

/// Playback state-machine tests (Phase 4).
final class AnimationPlayerTests: XCTestCase {

    func testStartsAtFrameZero() {
        let p = AnimationPlayer(frameCount: 8, fps: 10, loops: true)
        XCTAssertEqual(p.frameIndex, 0)
        XCTAssertFalse(p.finished)
    }

    func testAdvancesOneFramePerInterval() {
        var p = AnimationPlayer(frameCount: 8, fps: 10, loops: true) // 0.1s/frame
        XCTAssertTrue(p.advance(by: 0.1))
        XCTAssertEqual(p.frameIndex, 1)
        XCTAssertTrue(p.advance(by: 0.1))
        XCTAssertEqual(p.frameIndex, 2)
    }

    func testSubFrameTimeDoesNotAdvance() {
        var p = AnimationPlayer(frameCount: 8, fps: 10, loops: true)
        XCTAssertFalse(p.advance(by: 0.05))
        XCTAssertEqual(p.frameIndex, 0)
        // Accumulated time carries over.
        XCTAssertTrue(p.advance(by: 0.05))
        XCTAssertEqual(p.frameIndex, 1)
    }

    func testLoopingWrapsAround() {
        var p = AnimationPlayer(frameCount: 4, fps: 10, loops: true)
        p.advance(by: 0.4) // 4 frames -> wraps to 0
        XCTAssertEqual(p.frameIndex, 0)
        XCTAssertFalse(p.finished)
    }

    func testNonLoopingHoldsLastFrame() {
        var p = AnimationPlayer(frameCount: 4, fps: 10, loops: false)
        p.advance(by: 1.0) // way past the end
        XCTAssertEqual(p.frameIndex, 3)
        XCTAssertTrue(p.finished)
        // Further advancing does nothing.
        XCTAssertFalse(p.advance(by: 1.0))
        XCTAssertEqual(p.frameIndex, 3)
    }

    func testPauseStopsAdvance() {
        var p = AnimationPlayer(frameCount: 8, fps: 10, loops: true)
        p.paused = true
        XCTAssertFalse(p.advance(by: 1.0))
        XCTAssertEqual(p.frameIndex, 0)
    }

    func testManualNextPrevWrap() {
        var p = AnimationPlayer(frameCount: 3, fps: 10, loops: true)
        p.nextFrame(); XCTAssertEqual(p.frameIndex, 1)
        p.nextFrame(); p.nextFrame() // 2 -> 0
        XCTAssertEqual(p.frameIndex, 0)
        p.previousFrame() // wraps to 2
        XCTAssertEqual(p.frameIndex, 2)
    }

    func testSeekClamps() {
        var p = AnimationPlayer(frameCount: 5, fps: 10, loops: false)
        p.seek(to: 99)
        XCTAssertEqual(p.frameIndex, 4)
        p.seek(to: -3)
        XCTAssertEqual(p.frameIndex, 0)
    }

    func testResetRewinds() {
        var p = AnimationPlayer(frameCount: 8, fps: 10, loops: true)
        p.advance(by: 0.3)
        p.reset(frameCount: 4, fps: 5, loops: false)
        XCTAssertEqual(p.frameIndex, 0)
        XCTAssertEqual(p.frameCount, 4)
        XCTAssertEqual(p.fps, 5)
        XCTAssertFalse(p.loops)
    }

    func testSingleFrameClipNeverAdvances() {
        var p = AnimationPlayer(frameCount: 1, fps: 10, loops: true)
        XCTAssertFalse(p.advance(by: 10))
        XCTAssertEqual(p.frameIndex, 0)
    }

    func testInitFromClip() throws {
        let m = try KhosrowResources.loadRuntimeManifest()
        let idle = try XCTUnwrap(m.clips["idle"])
        let p = AnimationPlayer(clip: idle)
        XCTAssertEqual(p.frameCount, idle.frameCount)
        XCTAssertEqual(p.fps, idle.fps)
        XCTAssertEqual(p.loops, idle.loop)
    }
}
