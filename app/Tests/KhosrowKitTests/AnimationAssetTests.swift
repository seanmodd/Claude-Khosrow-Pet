import XCTest
@testable import KhosrowKit
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

/// Regression tests for the repaired mood animations: every animated mood must
/// be a real multi-frame sequence with consistent geometry and deterministic
/// ordering — never a single static frame.
final class AnimationAssetTests: XCTestCase {

    /// mood (PetState rawValue used in file names) -> expected frame count.
    static let expected: [String: Int] = [
        "writing": 6,
        "attentive": 6,
        "searching": 6,
        "waitingForPermission": 6,
        "praying": 6,
        "runningCommand": 7,
        "reading": 6,
        "sleeping": 6,
        "success": 5,
    ]

    func testEveryAnimatedMoodHasAllFrames() {
        for (mood, count) in Self.expected {
            let urls = KhosrowResources.customFrameURLs(forState: mood)
            XCTAssertEqual(urls.count, count, "\(mood): expected \(count) frames")
            XCTAssertGreaterThan(urls.count, 1, "\(mood) must not be static")
        }
    }

    func testFrameOrderingIsDeterministic() {
        for mood in Self.expected.keys {
            let urls = KhosrowResources.customFrameURLs(forState: mood)
            let names = urls.map { $0.lastPathComponent }
            let expected = (1...urls.count).map { "khosrow-\(mood)-\($0).png" }
            XCTAssertEqual(names, expected, "\(mood) frames out of order")
        }
    }

    func testRepairedMoodsDoNotShareFrameFiles() throws {
        // Writing must not reuse Reading's assets (or any other mood's).
        let writing = try Data(contentsOf: KhosrowResources.customFrameURLs(forState: "writing")[0])
        let reading = try Data(contentsOf: KhosrowResources.customFrameURLs(forState: "reading")[0])
        XCTAssertNotEqual(writing, reading, "writing reuses reading artwork")
        let waiting = try Data(contentsOf: KhosrowResources.customFrameURLs(forState: "waitingForPermission")[0])
        let praying = try Data(contentsOf: KhosrowResources.customFrameURLs(forState: "praying")[0])
        XCTAssertNotEqual(waiting, praying)
    }

    #if canImport(ImageIO)
    private func size(of url: URL) throws -> (Int, Int) {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        return (img.width, img.height)
    }

    /// All frames within a mood share one canvas; the repaired moods all use
    /// the pet cell (192x208), so nothing can jump scale or clip mid-loop.
    func testFrameDimensionsConsistentWithinEachMood() throws {
        for mood in Self.expected.keys {
            let urls = KhosrowResources.customFrameURLs(forState: mood)
            let first = try size(of: urls[0])
            for url in urls.dropFirst() {
                let s = try size(of: url)
                XCTAssertEqual(s.0, first.0, "\(mood) frame width varies")
                XCTAssertEqual(s.1, first.1, "\(mood) frame height varies")
            }
        }
    }

    func testRepairedMoodsUsePetCanvas() throws {
        for mood in ["writing", "attentive", "searching",
                     "waitingForPermission", "praying", "runningCommand"] {
            let urls = KhosrowResources.customFrameURLs(forState: mood)
            let s = try size(of: urls[0])
            XCTAssertEqual(s.0, 192, mood)
            XCTAssertEqual(s.1, 208, mood)
        }
    }

    /// Frames must actually differ from one another (genuine animation).
    func testFramesWithinAMoodAreDistinct() throws {
        for mood in ["writing", "attentive", "searching",
                     "waitingForPermission", "praying", "runningCommand"] {
            let urls = KhosrowResources.customFrameURLs(forState: mood)
            let datas = try urls.map { try Data(contentsOf: $0) }
            XCTAssertEqual(Set(datas).count, datas.count,
                           "\(mood) contains duplicate frames")
        }
    }
    #endif

    /// Behaviour guards: mappings and the waiting debounce are untouched by
    /// the art repairs.
    func testMappingsAndDebounceUnchanged() {
        XCTAssertEqual(StateMapper.map(event: .permissionRequest), .waitingForPermission)
        XCTAssertEqual(StateMapper.map(event: .userPromptSubmit), .writing)
        XCTAssertEqual(Preferences().waitingDebounceSeconds, 10)
        let p = ConfigurationProfile.builtInDefault()
        XCTAssertEqual(p.moodId(forCondition: "pre:Grep"), "searching")
        XCTAssertTrue(p.conditionIds(forMood: "praying").isEmpty)
    }
}
