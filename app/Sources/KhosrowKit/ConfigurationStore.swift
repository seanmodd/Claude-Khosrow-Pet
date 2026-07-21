import Foundation

/// Loads and persists the ``ConfigurationProfile`` as JSON in Application
/// Support, with atomic writes, forward migration, reconciliation against the
/// current built-in defaults (so new built-in moods like Praying appear for
/// existing users), and safe recovery from a corrupt or partial file.
public final class ConfigurationStore {

    public let fileURL: URL

    /// - Parameter directory: where to store `configuration.json`. Defaults to
    ///   `~/Library/Application Support/Khosrow/`.
    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("configuration.json")
    }

    public static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Khosrow", isDirectory: true)
    }

    // MARK: Load

    /// Load the profile, always returning a valid, reconciled one. A missing or
    /// unreadable/corrupt file yields the built-in default (never throws).
    public func load() -> ConfigurationProfile {
        let defaults = ConfigurationProfile.builtInDefault()
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = Self.decodeAndMigrate(data) else {
            return defaults
        }
        return Self.reconcile(decoded, with: defaults)
    }

    /// Decode + migrate the raw bytes. Returns nil if the JSON can't be decoded
    /// (caller then falls back to defaults).
    public static func decodeAndMigrate(_ data: Data) -> ConfigurationProfile? {
        guard var profile = try? JSONDecoder().decode(ConfigurationProfile.self, from: data) else {
            return nil
        }
        // Future schema bumps hook in here. v1 is the first version.
        if profile.schemaVersion < ConfigurationProfile.currentSchemaVersion {
            profile.schemaVersion = ConfigurationProfile.currentSchemaVersion
        }
        return profile
    }

    /// Merge a decoded profile with the current built-in defaults: add any
    /// missing built-in visual acts / moods / conditions / assignments (so new
    /// built-ins such as Praying appear for existing users), keep every user
    /// override, and repair dangling references to a safe value.
    public static func reconcile(_ profile: ConfigurationProfile,
                                 with defaults: ConfigurationProfile) -> ConfigurationProfile {
        var out = profile
        out.schemaVersion = ConfigurationProfile.currentSchemaVersion

        // Visual acts: add any missing built-in acts.
        let haveActs = Set(out.visualActs.map { $0.id })
        for act in defaults.visualActs where !haveActs.contains(act.id) {
            out.visualActs.append(act)
        }

        // Moods: add any missing built-in moods (e.g. praying for an old profile).
        let haveMoods = Set(out.moods.map { $0.id })
        for mood in defaults.moods where !haveMoods.contains(mood.id) {
            out.moods.append(mood)
        }

        // Conditions: add any missing built-in conditions.
        let haveConds = Set(out.conditions.map { $0.id })
        for cond in defaults.conditions where !haveConds.contains(cond.id) {
            out.conditions.append(cond)
        }

        // Assignments: ensure every condition has one; add the default for any
        // condition that lacks a saved assignment.
        let assigned = Set(out.assignments.map { $0.conditionId })
        for a in defaults.assignments where !assigned.contains(a.conditionId) {
            out.assignments.append(a)
        }

        // Repair dangling references so the profile always validates.
        let actIds = Set(out.visualActs.map { $0.id })
        let defaultActFor = Dictionary(uniqueKeysWithValues: defaults.moods.map { ($0.id, $0.visualActId) })
        for i in out.moods.indices where !actIds.contains(out.moods[i].visualActId) {
            out.moods[i].visualActId = defaultActFor[out.moods[i].id]
                ?? out.visualActs.first?.id ?? out.moods[i].visualActId
        }
        let moodIds = Set(out.moods.map { $0.id })
        for i in out.assignments.indices {
            if let m = out.assignments[i].moodId, !moodIds.contains(m) {
                out.assignments[i].moodId = nil   // dangling -> Unassigned (safe)
            }
        }
        out.rules.removeAll { !moodIds.contains($0.moodId) }
        return out
    }

    // MARK: Save

    /// Validate (reconcile away any dangling refs) and atomically write.
    public func save(_ profile: ConfigurationProfile) throws {
        let safe = Self.reconcile(profile, with: ConfigurationProfile.builtInDefault())
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(safe)
        // Atomic write via a temp file + replace.
        let tmp = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".configuration-\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }

    // MARK: Reset / import / export

    /// Reset everything to the shipped defaults (and persist).
    @discardableResult
    public func resetAll() -> ConfigurationProfile {
        let d = ConfigurationProfile.builtInDefault()
        try? save(d)
        return d
    }

    public func export(_ profile: ConfigurationProfile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: url, options: .atomic)
    }

    /// Import a profile from a file, reconciled against the current defaults.
    public func importProfile(from url: URL) throws -> ConfigurationProfile {
        let data = try Data(contentsOf: url)
        guard let decoded = Self.decodeAndMigrate(data) else {
            throw ConfigurationError.invalidImport
        }
        return Self.reconcile(decoded, with: ConfigurationProfile.builtInDefault())
    }

    public enum ConfigurationError: Error, CustomStringConvertible {
        case invalidImport
        public var description: String {
            switch self {
            case .invalidImport: return "That file isn't a valid Khosrow configuration."
            }
        }
    }
}
