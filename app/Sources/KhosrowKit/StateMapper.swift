import Foundation

/// Claude Code lifecycle hook events the bridge understands.
///
/// Raw hook payloads are parsed by the Python hook layer, which forwards only a
/// coarse, non-sensitive summary. This enum is the canonical vocabulary shared
/// by the Swift mapper (tested here) and the Python hook (tested in `bridge/`).
public enum HookEvent: String, CaseIterable, Codable, Equatable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
}

/// Deterministic mapping from a (hook event, tool category, success) triple to a
/// ``PetState``. This is the single source of truth for the mapping
/// *specification*; the Python hook mirrors it and both are covered by tests.
public enum StateMapper {

    /// Map a normalized hook event to a pet state.
    ///
    /// - Parameters:
    ///   - event: the lifecycle event.
    ///   - category: coarse tool bucket (only meaningful for tool events).
    ///   - success: outcome flag (only meaningful for Post/Stop events).
    public static func map(event: HookEvent,
                           category: ToolCategory? = nil,
                           success: Bool? = nil) -> PetState {
        switch event {
        case .sessionStart:
            return .attentive
        case .sessionEnd:
            return .sleeping
        case .userPromptSubmit:
            // You just sent a prompt: Claude is now composing a response.
            return .writing
        case .preToolUse:
            return stateForTool(category)
        case .postToolUse:
            // A tool just finished; Claude is composing the next step. Showing
            // `writing` (not idle) keeps the pet active between tools instead of
            // flickering to rest mid-turn. `success == false -> failure` is a
            // defensive fallback for builds that route failures here.
            return (success == false) ? .failure : .writing
        case .postToolUseFailure:
            // Dedicated failure event — always failure.
            return .failure
        case .permissionRequest:
            // A permission dialog is up: the pet should look like it's waiting.
            return .waitingForPermission
        case .notification:
            // Fallback attention signal (permission prompt, idle prompt, agent
            // needs input). permissionRequest above is the precise signal.
            return .waitingForPermission
        case .stop:
            return (success == false) ? .failure : .success
        case .stopFailure:
            return .failure
        case .subagentStart:
            return .searching
        case .subagentStop:
            return .idle
        }
    }

    /// Which working state a tool category implies while it is running.
    public static func stateForTool(_ category: ToolCategory?) -> PetState {
        switch category {
        case .fileRead:  return .reading
        case .fileEdit:  return .editing
        case .search:    return .searching
        case .command:   return .runningCommand
        case .network:   return .searching
        case .task:      return .attentive
        case .other, .none: return .attentive
        }
    }

    /// Bucket a raw Claude Code tool name into a coarse category **without**
    /// retaining any of its arguments. Mirrors the Python hook's `categorize`.
    public static func category(forToolNamed name: String) -> ToolCategory {
        switch name {
        case "Read", "NotebookRead":
            return .fileRead
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "Update":
            return .fileEdit
        case "Grep", "Glob", "LS", "Search":
            return .search
        case "Bash", "BashOutput", "KillBash", "KillShell":
            return .command
        case "WebFetch", "WebSearch":
            return .network
        case "Task", "Agent":
            return .task
        default:
            // MCP tools (mcp__server__tool) and anything unknown -> other.
            return .other
        }
    }
}
