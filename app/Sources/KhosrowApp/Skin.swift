#if canImport(AppKit)
import AppKit
import CoreImage
import ImageIO
import KhosrowKit

/// A pet "skin": a runtime manifest (grid + clips + state map) paired with a
/// sprite sheet. The app can switch between skins live from the menu.
struct Skin {
    let id: String
    let name: String
    let manifest: RuntimeManifest
    let sheet: SpriteSheet
}

/// Discovers the skins available to the app: the built-in Khosrow, a bundled
/// recolor demo, and any user skins dropped into `~/.claude-pet/skins/`.
enum SkinLibrary {
    private static let ciContext = CIContext(options: nil)

    /// The bundled Khosrow.
    static func builtIn() -> Skin? {
        guard let manifest = try? KhosrowResources.loadRuntimeManifest(),
              let sheet = try? SpriteSheet(manifest: manifest) else { return nil }
        return Skin(id: "khosrow", name: "Khosrow", manifest: manifest, sheet: sheet)
    }

    /// A recolored variant of a base skin (a zero-asset demo that also shows how
    /// a skin can be a simple filter over the art).
    static func recolored(_ base: Skin, id: String, name: String,
                          sepia: Double) -> Skin? {
        let input = CIImage(cgImage: base.sheet.full)
        guard let filter = CIFilter(name: "CISepiaTone") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(sepia, forKey: kCIInputIntensityKey)
        let extent = CGRect(x: 0, y: 0, width: base.sheet.full.width, height: base.sheet.full.height)
        guard let output = filter.outputImage,
              let cg = ciContext.createCGImage(output, from: extent) else { return nil }
        return Skin(id: id, name: name, manifest: base.manifest,
                    sheet: SpriteSheet(image: cg, geometry: base.sheet.geometry))
    }

    /// User skins under `~/.claude-pet/skins/<name>/` — each a `runtime.json`
    /// (or `khosrow.runtime.json`) plus a spritesheet PNG.
    static func userSkins() -> [Skin] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-pet/skins")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }

        var skins: [Skin] = []
        for dir in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let manifestURL = ["khosrow.runtime.json", "runtime.json"]
                .map { dir.appendingPathComponent($0) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            guard let mURL = manifestURL,
                  let manifest = try? RuntimeManifest.decode(fromFile: mURL) else { continue }
            let pngs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension.lowercased() == "png" } ?? []
            let sheetURL = pngs.first { $0.lastPathComponent.lowercased().contains("spritesheet") } ?? pngs.first
            guard let pURL = sheetURL,
                  let sheet = try? SpriteSheet(pngURL: pURL, geometry: FrameGeometry(sheet: manifest.sheet))
            else { continue }
            skins.append(Skin(id: "user:\(dir.lastPathComponent)", name: dir.lastPathComponent,
                              manifest: manifest, sheet: sheet))
        }
        return skins
    }

    /// Every skin the menu should offer, in order.
    static func all() -> [Skin] {
        var skins: [Skin] = []
        if let base = builtIn() {
            skins.append(base)
            if let sepia = recolored(base, id: "khosrow-sepia", name: "Khosrow — Sepia", sepia: 0.95) {
                skins.append(sepia)
            }
        }
        skins.append(contentsOf: userSkins())
        return skins
    }
}
#endif
