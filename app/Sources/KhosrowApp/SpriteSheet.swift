#if canImport(AppKit)
import AppKit
import CoreGraphics
import CoreImage
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

    /// Turn an upright frame into a "lying flat on the ground" frame for the
    /// sleeping mood: rotate 90°, trim to the figure, and drop it bottom-centred
    /// on a full-size transparent cell so it rests on the ground and still scales
    /// with the window. (The sheet has no dedicated lying-down art.)
    static func lyingFrame(_ cell: CGImage) -> CGImage? {
        let cw = cell.width, ch = cell.height
        let rotatedCI = CIImage(cgImage: cell)
            .transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
        guard let rotated = ciContext.createCGImage(rotatedCI, from: rotatedCI.extent) else { return nil }
        let figure = trimmedToContent(rotated) ?? rotated
        guard let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return figure }
        ctx.interpolationQuality = .high
        let maxW = CGFloat(cw) * 0.98, maxH = CGFloat(ch) * 0.72
        let scale = min(maxW / CGFloat(figure.width), maxH / CGFloat(figure.height), 1)
        let dw = CGFloat(figure.width) * scale, dh = CGFloat(figure.height) * scale
        // CGContext's origin is bottom-left, so a small y sits him on the ground.
        ctx.draw(figure, in: CGRect(x: (CGFloat(cw) - dw) / 2, y: CGFloat(ch) * 0.05, width: dw, height: dh))
        return ctx.makeImage()
    }

    /// Crop an image to the bounding box of its non-transparent pixels.
    private static func trimmedToContent(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height, bpr = w * 4
        var px = [UInt8](repeating: 0, count: h * bpr)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[y * bpr + x * 4 + 3] > 12 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    private static let ciContext = CIContext(options: nil)
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
