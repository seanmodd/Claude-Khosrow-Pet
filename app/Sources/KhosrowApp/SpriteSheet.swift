#if canImport(AppKit)
import AppKit
import CoreGraphics
import ImageIO
import KhosrowKit

/// Loads the runtime PNG and vends per-frame `CGImage` crops.
///
/// Frames are cropped lazily and cached per (row, frame). `CGImage.cropping`
/// works in the image's native top-left pixel space, which matches
/// ``FrameGeometry``'s `PixelRect` exactly.
final class SpriteSheet {
    let full: CGImage
    let geometry: FrameGeometry
    private var cache: [Int: CGImage] = [:]

    init(pngURL: URL, geometry: FrameGeometry) throws {
        guard let src = CGImageSourceCreateWithURL(pngURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw SpriteSheetError.decodeFailed(pngURL)
        }
        // Sanity: the PNG must match the grid we expect.
        guard image.width == geometry.sheetWidth, image.height == geometry.sheetHeight else {
            throw SpriteSheetError.dimensionMismatch(
                got: (image.width, image.height),
                expected: (geometry.sheetWidth, geometry.sheetHeight))
        }
        self.full = image
        self.geometry = geometry
    }

    convenience init(manifest: RuntimeManifest) throws {
        try self.init(pngURL: try KhosrowResources.spritesheetURL(),
                      geometry: FrameGeometry(sheet: manifest.sheet))
    }

    /// Whether the source image carries an alpha channel (used at startup to
    /// confirm transparency survived conversion).
    var hasAlpha: Bool {
        switch full.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    func frame(row: Int, index: Int) -> CGImage? {
        let key = row * geometry.cols + index
        if let cached = cache[key] { return cached }
        let r = geometry.rect(clipRow: row, frameIndex: index)
        let rect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        guard let cropped = full.cropping(to: rect) else { return nil }
        cache[key] = cropped
        return cropped
    }
}

enum SpriteSheetError: Error, CustomStringConvertible {
    case decodeFailed(URL)
    case dimensionMismatch(got: (Int, Int), expected: (Int, Int))

    var description: String {
        switch self {
        case .decodeFailed(let url):
            return "Failed to decode spritesheet PNG at \(url.path)"
        case .dimensionMismatch(let got, let expected):
            return "Spritesheet is \(got.0)x\(got.1), expected \(expected.0)x\(expected.1)"
        }
    }
}
#endif
