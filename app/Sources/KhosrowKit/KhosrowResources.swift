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

    /// Hand-drawn frame sequence for a given state, if one is bundled.
    ///
    /// Files are named `khosrow-<state>-1.png`, `khosrow-<state>-2.png`, … (a
    /// contiguous 1-based run of transparent 192×208 frames). Returns them in
    /// order; an empty array means "this state has no custom frames — use the
    /// sprite sheet." Bundled today for `sleeping`, `reading`, and `success`.
    public static func customFrameURLs(forState state: String) -> [URL] {
        var urls: [URL] = []
        var i = 1
        while let url = Bundle.module.url(forResource: "khosrow-\(state)-\(i)", withExtension: "png") {
            urls.append(url)
            i += 1
            if i > 64 { break }   // safety cap; sequences are short
        }
        return urls
    }

    /// The bundled Gemini illustrated "visual acts" — one transparent still per
    /// mood, imported by `scripts/import_gemini_acts.py`. Named `gemini-<name>.png`
    /// (e.g. `gemini-praying`). Returns nil when the named act is not bundled, so
    /// callers fall back to the sprite-sheet clip.
    public static let geminiActNames = [
        "attentive", "searching", "waiting", "writing", "running", "praying",
    ]

    public static func geminiActURL(named name: String) -> URL? {
        Bundle.module.url(forResource: "gemini-\(name)", withExtension: "png")
    }

    /// The bundled "watch mode" script — lets the app follow Claude Code's
    /// transcripts with no settings.json edit and no restart.
    public static func watchScriptURL() -> URL? {
        Bundle.module.url(forResource: "watch_claude", withExtension: "py")
    }
}
