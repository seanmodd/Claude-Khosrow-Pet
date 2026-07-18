#if canImport(AppKit)
import AppKit
import KhosrowKit

/// Persists ``Preferences`` and remembered window positions in `UserDefaults`.
/// Position is stored per display so multi-monitor layouts restore correctly.
final class PreferencesStore {
    private let defaults: UserDefaults
    private let prefsKey = "khosrow.preferences"
    private let positionsKey = "khosrow.positions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Preferences

    func load() -> Preferences {
        guard let data = defaults.data(forKey: prefsKey),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return prefs.clamped()
    }

    func save(_ prefs: Preferences) {
        if let data = try? JSONEncoder().encode(prefs.clamped()) {
            defaults.set(data, forKey: prefsKey)
        }
    }

    // MARK: Positions (per screen)

    private func positions() -> [String: SavedPosition] {
        guard let data = defaults.data(forKey: positionsKey),
              let map = try? JSONDecoder().decode([String: SavedPosition].self, from: data) else {
            return [:]
        }
        return map
    }

    func savePosition(_ pos: SavedPosition) {
        var map = positions()
        map[pos.screenID] = pos
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: positionsKey)
        }
    }

    func position(forScreen screenID: String) -> SavedPosition? {
        positions()[screenID]
    }

    /// Stable identifier for a screen (CGDirectDisplayID as string).
    static func screenID(for screen: NSScreen) -> String {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return num.stringValue
        }
        return "main"
    }
}
#endif
