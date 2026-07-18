import Foundation

/// The **entire** payload the bridge is permitted to carry between Claude Code
/// and the pet. Deliberately tiny and non-sensitive: a state, a coarse tool
/// bucket, a timestamp, and an outcome flag. No prompt text, source code, file
/// contents, command strings, credentials, or secrets — ever.
public struct PetBridgeState: Codable, Equatable {
    public let state: String
    public let toolCategory: String?
    public let timestamp: String   // ISO-8601
    public let success: Bool?

    public init(state: String, toolCategory: String? = nil,
                timestamp: String, success: Bool? = nil) {
        self.state = state
        self.toolCategory = toolCategory
        self.timestamp = timestamp
        self.success = success
    }

    public init(state: PetState, toolCategory: ToolCategory? = nil,
                timestamp: String, success: Bool? = nil) {
        self.init(state: state.rawValue,
                  toolCategory: toolCategory?.rawValue,
                  timestamp: timestamp,
                  success: success)
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
