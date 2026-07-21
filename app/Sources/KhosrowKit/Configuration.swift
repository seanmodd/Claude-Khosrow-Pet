import Foundation

// MARK: - Visual acts

/// Where a visual act's pixels come from. Kept separate from the mood so any act
/// can be assigned to any mood (mix-and-match).
public enum VisualActSource: Codable, Equatable {
    /// A bundled Gemini illustrated still: `gemini-<name>.png`.
    case geminiStill(String)
    /// A bundled hand-drawn frame sequence: `khosrow-<name>-N.png`.
    case frameSequence(String)
    /// A row/clip in the built-in sprite sheet.
    case spriteClip(String)
    /// A user-imported sequence stored under Application Support (directory name).
    case customFrames(String)
}

/// Which library group a visual act belongs to (for filtering/organising the UI).
public enum VisualActGroup: String, Codable, CaseIterable, Equatable {
    case gemini      // the imported Gemini illustrated acts
    case builtin     // hand-drawn frame sequences shipped with the app
    case legacy      // original sprite-sheet clips (recoverable, never deleted)
    case custom      // user-imported acts
}

/// A reusable piece of artwork/animation. A *visual act* is what Khosrow shows;
/// a *mood* is the semantic condition. They are deliberately distinct concepts.
public struct VisualActDefinition: Codable, Equatable, Identifiable {
    public let id: String            // stable identifier, never derived from displayName
    public var displayName: String
    public var source: VisualActSource
    public var group: VisualActGroup
    public var fps: Double
    public var loops: Bool
    public let builtin: Bool         // built-in acts can be hidden/overridden but never destroyed

    public init(id: String, displayName: String, source: VisualActSource,
                group: VisualActGroup, fps: Double = 1, loops: Bool = true,
                builtin: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.group = group
        self.fps = fps
        self.loops = loops
        self.builtin = builtin
    }
}

// MARK: - Moods

/// A semantic mood state. Built-in moods keep a stable `id` equal to the
/// corresponding ``PetState`` rawValue; custom moods use `custom-<uuid>`.
public struct MoodDefinition: Codable, Equatable, Identifiable {
    public let id: String
    public var displayName: String
    public var moodDescription: String
    public let builtin: Bool
    public var enabled: Bool
    /// Which visual act this mood shows (a `VisualActDefinition.id`).
    public var visualActId: String
    /// Whether reaching this mood may raise a notification (built-in behaviour
    /// is preserved by the app; this is the user-facing toggle).
    public var notifies: Bool
    /// Optional override for the pill label; nil = use the built-in emoji label.
    public var pillText: String?

    public init(id: String, displayName: String, moodDescription: String,
                builtin: Bool, enabled: Bool = true, visualActId: String,
                notifies: Bool = true, pillText: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.moodDescription = moodDescription
        self.builtin = builtin
        self.enabled = enabled
        self.visualActId = visualActId
        self.notifies = notifies
        self.pillText = pillText
    }
}

// MARK: - Hook / event conditions and their mood assignments

/// A recognized Claude Code condition that can drive a mood — one per hook
/// phase / tool / lifecycle event. These are the draggable items in the Hook &
/// Event Mapping editor.
public struct HookConditionDefinition: Codable, Equatable, Identifiable {
    public let id: String            // e.g. "pre:Read", "userPromptSubmit", "stop:success"
    public var phase: String         // "PreToolUse", "PostToolUse", "UserPromptSubmit", …
    public var label: String         // human-readable, e.g. "Read a file"
    public var toolCategory: String? // coarse category the bridge actually transmits (privacy)
    public let builtin: Bool

    public init(id: String, phase: String, label: String,
                toolCategory: String? = nil, builtin: Bool = true) {
        self.id = id
        self.phase = phase
        self.label = label
        self.toolCategory = toolCategory
        self.builtin = builtin
    }
}

/// Which mood a condition currently drives. `moodId == nil` means Unassigned.
public struct HookAssignment: Codable, Equatable {
    public var conditionId: String
    public var moodId: String?
    public var priority: Int
    public var enabled: Bool

    public init(conditionId: String, moodId: String?, priority: Int = 0, enabled: Bool = true) {
        self.conditionId = conditionId
        self.moodId = moodId
        self.priority = priority
        self.enabled = enabled
    }
}

// MARK: - User rules (advanced)

/// A user-authored rule: when the matched condition fires, drive `moodId`.
/// Structured (not a scripting language) and understandable at a glance.
public struct MoodRule: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var enabled: Bool
    public var conditionId: String   // references a HookConditionDefinition.id
    public var moodId: String        // destination mood
    public var priority: Int
    public var delayMs: Int
    public var debounceMs: Int
    public var minDurationMs: Int

    public init(id: String, name: String, enabled: Bool = true,
                conditionId: String, moodId: String, priority: Int = 100,
                delayMs: Int = 0, debounceMs: Int = 0, minDurationMs: Int = 0) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.conditionId = conditionId
        self.moodId = moodId
        self.priority = priority
        self.delayMs = delayMs
        self.debounceMs = debounceMs
        self.minDurationMs = minDurationMs
    }
}

// MARK: - The profile

/// The whole configurable profile: moods, the visual-act library, hook
/// conditions + their current assignments, and user rules. Versioned so it can
/// migrate forward safely.
public struct ConfigurationProfile: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var visualActs: [VisualActDefinition]
    public var moods: [MoodDefinition]
    public var conditions: [HookConditionDefinition]
    public var assignments: [HookAssignment]
    public var rules: [MoodRule]

    public init(schemaVersion: Int = ConfigurationProfile.currentSchemaVersion,
                visualActs: [VisualActDefinition],
                moods: [MoodDefinition],
                conditions: [HookConditionDefinition],
                assignments: [HookAssignment],
                rules: [MoodRule] = []) {
        self.schemaVersion = schemaVersion
        self.visualActs = visualActs
        self.moods = moods
        self.conditions = conditions
        self.assignments = assignments
        self.rules = rules
    }

    // MARK: Lookups

    public func mood(id: String) -> MoodDefinition? { moods.first { $0.id == id } }
    public func visualAct(id: String) -> VisualActDefinition? { visualActs.first { $0.id == id } }
    public func condition(id: String) -> HookConditionDefinition? { conditions.first { $0.id == id } }
    public func assignment(conditionId: String) -> HookAssignment? {
        assignments.first { $0.conditionId == conditionId }
    }

    /// The mood a condition currently drives (nil = Unassigned or disabled).
    public func moodId(forCondition conditionId: String) -> String? {
        guard let a = assignment(conditionId: conditionId), a.enabled else { return nil }
        return a.moodId
    }

    /// Condition ids currently assigned to a given mood.
    public func conditionIds(forMood moodId: String) -> [String] {
        assignments.filter { $0.moodId == moodId && $0.enabled }.map { $0.conditionId }
    }

    /// Which moods currently use a given visual act.
    public func moodIds(usingAct actId: String) -> [String] {
        moods.filter { $0.visualActId == actId }.map { $0.id }
    }

    // MARK: Mutation helpers (validated)

    /// Reassign a condition to a mood (or nil for Unassigned). Rejects unknown
    /// ids so the profile never references something that doesn't exist.
    @discardableResult
    public mutating func assign(conditionId: String, toMood moodId: String?) -> Bool {
        guard condition(id: conditionId) != nil else { return false }
        if let m = moodId, mood(id: m) == nil { return false }
        if let idx = assignments.firstIndex(where: { $0.conditionId == conditionId }) {
            assignments[idx].moodId = moodId
        } else {
            assignments.append(HookAssignment(conditionId: conditionId, moodId: moodId))
        }
        return true
    }

    /// Point a mood at a different visual act. Rejects unknown ids.
    @discardableResult
    public mutating func setVisualAct(_ actId: String, forMood moodId: String) -> Bool {
        guard visualAct(id: actId) != nil,
              let idx = moods.firstIndex(where: { $0.id == moodId }) else { return false }
        moods[idx].visualActId = actId
        return true
    }

    /// Create a new custom mood with a unique stable id. Returns its id.
    @discardableResult
    public mutating func addCustomMood(name: String, description: String,
                                       visualActId: String? = nil) -> String {
        let id = "custom-\(UUID().uuidString.prefix(8).lowercased())"
        let act = visualActId ?? visualActs.first?.id ?? ""
        moods.append(MoodDefinition(id: id, displayName: name,
                                    moodDescription: description,
                                    builtin: false, enabled: true,
                                    visualActId: act, notifies: false))
        return id
    }

    /// Duplicate a mood (built-in or custom) into a NEW custom mood.
    @discardableResult
    public mutating func duplicateMood(id: String) -> String? {
        guard let src = mood(id: id) else { return nil }
        return addCustomMood(name: src.displayName + " copy",
                             description: src.moodDescription,
                             visualActId: src.visualActId)
    }

    /// Delete a CUSTOM mood safely: its assignments become Unassigned and its
    /// rules are removed. Built-in moods (praying, writing, …) are refused.
    @discardableResult
    public mutating func deleteCustomMood(id: String) -> Bool {
        guard let m = mood(id: id), !m.builtin else { return false }
        moods.removeAll { $0.id == id }
        for i in assignments.indices where assignments[i].moodId == id {
            assignments[i].moodId = nil
        }
        rules.removeAll { $0.moodId == id }
        return true
    }

    /// Add a user rule. Returns its id.
    @discardableResult
    public mutating func addRule(name: String, conditionId: String, moodId: String,
                                 priority: Int = 100) -> String? {
        guard condition(id: conditionId) != nil, mood(id: moodId) != nil else { return nil }
        let id = "rule-\(UUID().uuidString.prefix(8).lowercased())"
        rules.append(MoodRule(id: id, name: name, conditionId: conditionId,
                              moodId: moodId, priority: priority))
        return id
    }

    /// Validate referential integrity. Returns a list of problems (empty = ok).
    public func validate() -> [String] {
        var problems: [String] = []
        var seenMood = Set<String>()
        for m in moods {
            if !seenMood.insert(m.id).inserted { problems.append("duplicate mood id '\(m.id)'") }
            if visualAct(id: m.visualActId) == nil {
                problems.append("mood '\(m.id)' -> unknown visual act '\(m.visualActId)'")
            }
        }
        var seenAct = Set<String>()
        for a in visualActs where !seenAct.insert(a.id).inserted {
            problems.append("duplicate visual-act id '\(a.id)'")
        }
        for a in assignments {
            if condition(id: a.conditionId) == nil {
                problems.append("assignment -> unknown condition '\(a.conditionId)'")
            }
            if let m = a.moodId, mood(id: m) == nil {
                problems.append("assignment '\(a.conditionId)' -> unknown mood '\(m)'")
            }
        }
        for r in rules where mood(id: r.moodId) == nil {
            problems.append("rule '\(r.id)' -> unknown mood '\(r.moodId)'")
        }
        return problems
    }
}
