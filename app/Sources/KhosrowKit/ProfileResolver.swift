import Foundation

/// Applies the user's configurable condition→mood mapping to live bridge
/// signals. Pure and fully testable.
///
/// The bridge sends a default-mapped state (mirroring ``StateMapper``), plus a
/// coarse tool category and — new — the tool's *name* (fixed vocabulary only,
/// never arguments). From those the resolver infers which configurable
/// condition fired and looks up the mood the user assigned to it.
public enum ProfileResolver {

    /// The condition a bridge signal corresponds to, or nil when it can't be
    /// determined (unknown state string, etc.).
    public static func conditionId(forState state: PetState,
                                   tool: String?,
                                   category: String?) -> String? {
        // Tool-driven working states: the exact tool name wins; else the
        // category's representative condition.
        if let tool, !tool.isEmpty {
            return "pre:\(tool)"
        }
        if category != nil {
            switch state {
            case .reading: return "pre:Read"
            case .editing: return "pre:Edit"
            case .searching: return "pre:Grep"
            case .runningCommand: return "pre:Bash"
            case .attentive: return "pre:Other"
            case .failure: return "postToolUseFailure"
            default: break
            }
        }
        // Lifecycle states -> their canonical condition.
        switch state {
        case .writing: return "userPromptSubmit"
        case .success: return "stopSuccess"
        case .failure: return "stopFailure"
        case .waitingForPermission: return "permissionRequest"
        case .sleeping: return "sessionEnd"
        case .attentive: return "sessionStart"
        case .idle, .praying, .reading, .editing, .searching, .runningCommand:
            return nil   // no canonical hook condition without a tool signal
        }
    }

    public enum Resolution: Equatable {
        /// Show this mood (may equal the input state).
        case mood(String)
        /// The user unassigned/disabled this condition: ignore the signal.
        case ignore
        /// No mapping information: keep the bridge's default state.
        case passthrough
    }

    /// Resolve a bridge signal through the profile.
    public static func resolve(state: PetState,
                               tool: String?,
                               category: String?,
                               profile: ConfigurationProfile) -> Resolution {
        guard let condId = conditionId(forState: state, tool: tool, category: category),
              profile.condition(id: condId) != nil else {
            return .passthrough
        }
        guard let assignment = profile.assignment(conditionId: condId),
              assignment.enabled else {
            return .passthrough
        }
        guard let moodId = assignment.moodId else {
            return .ignore                       // explicitly Unassigned
        }
        guard let mood = profile.mood(id: moodId), mood.enabled else {
            return .ignore                       // destination disabled/missing
        }
        return .mood(moodId)
    }
}
