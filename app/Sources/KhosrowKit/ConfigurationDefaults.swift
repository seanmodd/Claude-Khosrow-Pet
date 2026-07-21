import Foundation

/// Built-in defaults for the configuration profile. These are the shipped
/// moods, the visual-act library (Gemini + hand-drawn + recoverable legacy
/// sprite clips), the recognized hook conditions, and the default
/// condition→mood assignments (which mirror ``StateMapper``).
public extension ConfigurationProfile {

    /// The visual-act library shipped with the app.
    static func builtInVisualActs() -> [VisualActDefinition] {
        var acts: [VisualActDefinition] = []
        // Gemini illustrated stills.
        let gemini: [(String, String)] = [
            ("attentive", "Gemini Attentive"), ("searching", "Gemini Searching"),
            ("waiting", "Gemini Waiting"), ("writing", "Gemini Writing"),
            ("running", "Gemini Running"), ("praying", "Gemini Praying"),
        ]
        for (name, display) in gemini {
            acts.append(VisualActDefinition(
                id: "gemini-\(name)", displayName: display,
                source: .geminiStill(name), group: .gemini, fps: 1, loops: true))
        }
        // Hand-drawn frame sequences.
        acts.append(VisualActDefinition(id: "frames-reading", displayName: "Reading (hand-drawn)",
                                        source: .frameSequence("reading"), group: .builtin, fps: 5))
        acts.append(VisualActDefinition(id: "frames-sleeping", displayName: "Sleeping in bed (hand-drawn)",
                                        source: .frameSequence("sleeping"), group: .builtin, fps: 4))
        acts.append(VisualActDefinition(id: "frames-success", displayName: "Triumph (hand-drawn)",
                                        source: .frameSequence("success"), group: .builtin, fps: 9))
        // Legacy sprite-sheet clips — the original art, kept recoverable.
        let legacy: [(String, String)] = [
            ("idle", "Sprite — Idle stance"), ("present", "Sprite — Arms open"),
            ("idle_guard", "Sprite — Guard stance"), ("walk_right", "Sprite — Scanning walk"),
            ("ready", "Sprite — Sword ready"), ("run_left", "Sprite — Running"),
            ("cheer", "Sprite — Cheer"), ("bow", "Sprite — Ceremonial bow"),
        ]
        for (clip, display) in legacy {
            acts.append(VisualActDefinition(
                id: "legacy-\(clip)", displayName: display,
                source: .spriteClip(clip), group: .legacy, fps: 8, loops: true))
        }
        return acts
    }

    /// The built-in moods (one per ``PetState``), with their default visual act.
    static func builtInMoods() -> [MoodDefinition] {
        func mood(_ state: PetState, _ name: String, _ desc: String, act: String,
                  notifies: Bool = true) -> MoodDefinition {
            MoodDefinition(id: state.rawValue, displayName: name, moodDescription: desc,
                           builtin: true, enabled: true, visualActId: act, notifies: notifies)
        }
        return [
            mood(.idle, "Idle", "Nothing is running — a calm resting stance.",
                 act: "legacy-idle", notifies: false),
            mood(.attentive, "Attentive", "Engaged and listening right after a session or sub-task starts.",
                 act: "gemini-attentive"),
            mood(.writing, "Writing", "Composing a response to your prompt.",
                 act: "gemini-writing"),
            mood(.reading, "Reading", "Reading a file.",
                 act: "frames-reading"),
            mood(.searching, "Searching", "Searching or browsing the codebase.",
                 act: "gemini-searching"),
            mood(.editing, "Editing", "Editing a file.",
                 act: "legacy-ready"),
            mood(.runningCommand, "Running", "Executing a shell command.",
                 act: "gemini-running"),
            mood(.waitingForPermission, "Waiting", "Waiting for you to approve something or reply.",
                 act: "gemini-waiting"),
            mood(.praying, "Praying", "A reflective, reverent mood. Has no automatic trigger by default — assign a condition or rule, or preview it manually.",
                 act: "gemini-praying", notifies: false),
            mood(.success, "Success", "A task just finished successfully.",
                 act: "frames-success"),
            mood(.failure, "Failure", "A tool or task just failed.",
                 act: "legacy-bow"),
            mood(.sleeping, "Sleeping", "The Claude Code session ended — he's asleep.",
                 act: "frames-sleeping", notifies: false),
        ]
    }

    /// The recognized hook/event conditions, per tool where the category function
    /// distinguishes them (so the editor can list Read and NotebookRead
    /// separately), plus lifecycle events.
    static func builtInConditions() -> [HookConditionDefinition] {
        func pre(_ tool: String, _ label: String, _ cat: String) -> HookConditionDefinition {
            HookConditionDefinition(id: "pre:\(tool)", phase: "PreToolUse",
                                    label: label, toolCategory: cat)
        }
        return [
            HookConditionDefinition(id: "sessionStart", phase: "SessionStart", label: "Session starts"),
            HookConditionDefinition(id: "userPromptSubmit", phase: "UserPromptSubmit", label: "You submit a prompt"),
            pre("Read", "Read a file", "file-read"),
            pre("NotebookRead", "Read a notebook", "file-read"),
            pre("Edit", "Edit a file", "file-edit"),
            pre("Write", "Write a file", "file-edit"),
            pre("MultiEdit", "Multi-edit a file", "file-edit"),
            pre("NotebookEdit", "Edit a notebook", "file-edit"),
            pre("Grep", "Grep the codebase", "search"),
            pre("Glob", "Glob for files", "search"),
            pre("LS", "List a directory", "search"),
            pre("Bash", "Run a shell command", "command"),
            pre("WebFetch", "Fetch a URL", "network"),
            pre("WebSearch", "Search the web", "network"),
            pre("Task", "Launch a sub-agent task", "task"),
            pre("Other", "Any other / MCP tool", "other"),
            HookConditionDefinition(id: "postToolUse", phase: "PostToolUse", label: "A tool finished (composing next step)"),
            HookConditionDefinition(id: "postToolUseFailure", phase: "PostToolUseFailure", label: "A tool failed"),
            HookConditionDefinition(id: "permissionRequest", phase: "PermissionRequest", label: "Permission requested"),
            HookConditionDefinition(id: "notification", phase: "Notification", label: "Notification / needs input"),
            HookConditionDefinition(id: "stopSuccess", phase: "Stop", label: "Turn finished successfully"),
            HookConditionDefinition(id: "stopFailure", phase: "StopFailure", label: "Turn ended in failure"),
            HookConditionDefinition(id: "subagentStart", phase: "SubagentStart", label: "Sub-agent started"),
            HookConditionDefinition(id: "subagentStop", phase: "SubagentStop", label: "Sub-agent stopped"),
            HookConditionDefinition(id: "sessionEnd", phase: "SessionEnd", label: "Session ended"),
        ]
    }

    /// Default condition→mood assignments — mirror ``StateMapper`` exactly, so
    /// out of the box the app behaves identically to today. Praying is in NONE
    /// of these (no invented trigger).
    static func builtInAssignments() -> [HookAssignment] {
        let map: [String: PetState] = [
            "sessionStart": .attentive,
            "userPromptSubmit": .writing,
            "pre:Read": .reading, "pre:NotebookRead": .reading,
            "pre:Edit": .editing, "pre:Write": .editing,
            "pre:MultiEdit": .editing, "pre:NotebookEdit": .editing,
            "pre:Grep": .searching, "pre:Glob": .searching, "pre:LS": .searching,
            "pre:Bash": .runningCommand,
            "pre:WebFetch": .searching, "pre:WebSearch": .searching,
            "pre:Task": .attentive, "pre:Other": .attentive,
            "postToolUse": .writing,
            "postToolUseFailure": .failure,
            "permissionRequest": .waitingForPermission,
            "notification": .waitingForPermission,
            "stopSuccess": .success,
            "stopFailure": .failure,
            "subagentStart": .searching,
            "subagentStop": .idle,
            "sessionEnd": .sleeping,
        ]
        return builtInConditions().map { cond in
            HookAssignment(conditionId: cond.id, moodId: map[cond.id]?.rawValue)
        }
    }

    /// The complete shipped default profile.
    static func builtInDefault() -> ConfigurationProfile {
        ConfigurationProfile(
            visualActs: builtInVisualActs(),
            moods: builtInMoods(),
            conditions: builtInConditions(),
            assignments: builtInAssignments(),
            rules: [])
    }
}
