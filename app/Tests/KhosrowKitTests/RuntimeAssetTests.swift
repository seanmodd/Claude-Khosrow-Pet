import XCTest
@testable import KhosrowKit
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

/// Verifies the bundled runtime PNG exists and (on Apple platforms) has the
/// expected dimensions and a real alpha channel — i.e. the WebP→PNG conversion
/// preserved geometry and transparency.
final class RuntimeAssetTests: XCTestCase {

    func testRuntimePNGResourceExists() throws {
        let url = try KhosrowResources.spritesheetURL()
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 100_000, "runtime PNG looks too small")
    }

    #if canImport(ImageIO)
    func testRuntimePNGDimensionsMatchManifest() throws {
        let manifest = try KhosrowResources.loadRuntimeManifest()
        let url = try KhosrowResources.spritesheetURL()
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(image.width, manifest.sheet.width)
        XCTAssertEqual(image.height, manifest.sheet.height)
    }

    func testRuntimePNGHasAlphaChannel() throws {
        let url = try KhosrowResources.spritesheetURL()
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let alpha = image.alphaInfo
        let hasAlpha = !(alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast)
        XCTAssertTrue(hasAlpha, "runtime PNG lost its alpha channel")
    }
    #endif
}
