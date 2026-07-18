import Foundation

/// The normalized pet states the app understands. These are the only values the
/// bridge is allowed to emit — a deliberately small, non-sensitive vocabulary.
public enum PetState: String, CaseIterable, Codable, Equatable {
    case idle
    case attentive
    case reading
    case searching
    case editing
    case runningCommand
    case waitingForPermission
    case success
    case failure
    case sleeping

    /// Lenient parser: accepts the exact rawValue or a few friendly aliases.
    public init?(loose value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = PetState(rawValue: key) { self = s; return }
        switch key.lowercased() {
        case "run", "running", "command", "bash", "exec": self = .runningCommand
        case "read", "view", "cat": self = .reading
        case "search", "grep", "find", "glob": self = .searching
        case "edit", "write", "patch": self = .editing
        case "permission", "waiting", "approval", "confirm": self = .waitingForPermission
        case "ok", "done", "passed", "green": self = .success
        case "error", "failed", "fail", "red": self = .failure
        case "sleep", "asleep", "idlelong": self = .sleeping
        case "listening", "attention", "prompt": self = .attentive
        default: return nil
        }
    }
}

/// Coarse tool category the bridge may report alongside a state. This never
/// contains a tool's *arguments* — only which bucket the tool falls in.
public enum ToolCategory: String, CaseIterable, Codable, Equatable {
    case fileRead = "file-read"
    case fileEdit = "file-edit"
    case search = "search"
    case command = "command"
    case network = "network"
    case task = "task"
    case other = "other"
}
