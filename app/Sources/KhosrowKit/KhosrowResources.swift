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

    /// URL of the Faravahar menu-bar glyph (a template PNG), if bundled.
    /// Optional: the app falls back to a text glyph when it is absent.
    public static func menuBarIconURL() -> URL? {
        Bundle.module.url(forResource: "faravahar-menubar", withExtension: "png")
    }

    /// The frames of the "sleeping in a bed" scene, shown for the sleeping mood.
    public static func bedFrameURLs() -> [URL] {
        (1...4).compactMap { Bundle.module.url(forResource: "khosrow-bed-\($0)", withExtension: "png") }
    }

    /// The bundled "watch mode" script — lets the app follow Claude Code's
    /// transcripts with no settings.json edit and no restart.
    public static func watchScriptURL() -> URL? {
        Bundle.module.url(forResource: "watch_claude", withExtension: "py")
    }
}
