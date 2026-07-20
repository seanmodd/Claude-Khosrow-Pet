import XCTest
@testable import KhosrowKit
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

/// The six imported Gemini illustrated "visual acts" must be bundled, loadable,
/// and transparent (they are cut out of an opaque background). Missing acts must
/// resolve to nil so callers can fall back to the sprite sheet.
final class GeminiAssetTests: XCTestCase {

    func testAllSixGeminiActsAreBundled() throws {
        XCTAssertEqual(KhosrowResources.geminiActNames.count, 6)
        for name in KhosrowResources.geminiActNames {
            XCTAssertNotNil(KhosrowResources.geminiActURL(named: name),
                            "missing bundled Gemini act: gemini-\(name).png")
        }
    }

    func testWritingHasItsOwnActDistinctFromReading() {
        // Regression: writing used to reuse the reading frames. It must now be a
        // first-class, separately-named act.
        XCTAssertTrue(KhosrowResources.geminiActNames.contains("writing"))
        XCTAssertNotNil(KhosrowResources.geminiActURL(named: "writing"))
    }

    func testPrayingActExists() {
        XCTAssertTrue(KhosrowResources.geminiActNames.contains("praying"))
        XCTAssertNotNil(KhosrowResources.geminiActURL(named: "praying"))
    }

    func testUnknownActFailsSafely() {
        XCTAssertNil(KhosrowResources.geminiActURL(named: "does-not-exist"))
        XCTAssertNil(KhosrowResources.geminiActURL(named: ""))
    }

    #if canImport(ImageIO)
    func testEachActDecodesWithAlpha() throws {
        for name in KhosrowResources.geminiActNames {
            let url = try XCTUnwrap(KhosrowResources.geminiActURL(named: name))
            let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
            XCTAssertGreaterThan(image.width, 0, "\(name)")
            XCTAssertGreaterThan(image.height, 0, "\(name)")
            let a = image.alphaInfo
            let hasAlpha = !(a == .none || a == .noneSkipFirst || a == .noneSkipLast)
            XCTAssertTrue(hasAlpha, "gemini-\(name).png lost its alpha channel")
        }
    }
    #endif
}
