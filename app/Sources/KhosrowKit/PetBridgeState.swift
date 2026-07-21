import Foundation

/// The **entire** payload the bridge is permitted to carry between Claude Code
/// and the pet. Deliberately tiny and non-sensitive: a state, a coarse tool
/// bucket, a timestamp, and an outcome flag. No prompt text, source code, file
/// contents, command strings, credentials, or secrets — ever.
public struct PetBridgeState: Codable, Equatable {
    public let state: String
    public let toolCategory: String?
    /// The tool's NAME from the fixed Claude Code vocabulary ("Read", "Bash",
    /// …, or "Other" for MCP/unknown tools). Never carries arguments. Lets the
    /// configurable per-tool mood mapping distinguish e.g. Read from
    /// NotebookRead, which the coarse category cannot.
    public let tool: String?
    public let timestamp: String   // ISO-8601
    public let success: Bool?
    /// Optional, opt-in "what": a file name, command, or prompt snippet. Only
    /// present when the user turned on Detail mode; nil keeps the payload minimal.
    public let detail: String?
    /// Which Claude Code session produced this signal (session id / uuid).
    public let session: String?
    /// A short human label for that session (title or project), for the UI.
    public let sessionLabel: String?

    public init(state: String, toolCategory: String? = nil, tool: String? = nil,
                timestamp: String, success: Bool? = nil, detail: String? = nil,
                session: String? = nil, sessionLabel: String? = nil) {
        self.state = state
        self.toolCategory = toolCategory
        self.tool = tool
        self.timestamp = timestamp
        self.success = success
        self.detail = detail
        self.session = session
        self.sessionLabel = sessionLabel
    }

    public init(state: PetState, toolCategory: ToolCategory? = nil, tool: String? = nil,
                timestamp: String, success: Bool? = nil, detail: String? = nil,
                session: String? = nil, sessionLabel: String? = nil) {
        self.init(state: state.rawValue,
                  toolCategory: toolCategory?.rawValue,
                  tool: tool,
                  timestamp: timestamp,
                  success: success, detail: detail,
                  session: session, sessionLabel: sessionLabel)
    }

    /// Resolve the payload's state string into a known ``PetState`` (lenient).
    public var petState: PetState? { PetState(loose: state) }

    public static func decode(from data: Data) throws -> PetBridgeState {
        try JSONDecoder().decode(PetBridgeState.self, from: data)
    }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(self)
    }
}
