import Foundation

/// Access to the runtime assets bundled with `KhosrowKit`.
///
/// The original `pet.json` / `spritesheet.webp` are *not* bundled — only the
/// derived, separate runtime assets produced by the `scripts/` tools:
///   * `khosrow.runtime.json`     — the animation atlas (grid, clips, states)
///   * `khosrow-spritesheet.png`  — pixel-exact PNG copy of the sheet
public enum KhosrowResources {

    public enum ResourceError: Error, CustomStringConvertible {
        case missing(String)
        public var description: String {
            switch self {
            case .missing(let name): return "Bundled resource not found: \(name)"
            }
        }
    }

    /// URL of the runtime spritesheet PNG inside the KhosrowKit bundle.
    public static func spritesheetURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "khosrow-spritesheet", withExtension: "png") else {
            throw ResourceError.missing("khosrow-spritesheet.png")
        }
        return url
    }

    /// URL of the runtime manifest JSON inside the KhosrowKit bundle.
    public static func runtimeManifestURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "khosrow.runtime", withExtension: "json") else {
            throw ResourceError.missing("khosrow.runtime.json")
        }
        return url
    }

    /// Decode the bundled runtime manifest.
    public static func loadRuntimeManifest() throws -> RuntimeManifest {
        let data = try Data(contentsOf: runtimeManifestURL())
        return try RuntimeManifest.decode(from: data)
    }
}
