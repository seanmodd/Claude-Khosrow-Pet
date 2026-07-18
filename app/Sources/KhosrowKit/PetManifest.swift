import Foundation

/// Decoder for the ORIGINAL ChatGPT `pet.json` (spriteVersionNumber 2).
///
/// This is identity-only: it deliberately mirrors exactly the five fields the
/// upstream manifest carries and nothing more. It does **not** describe the
/// animation grid — that lives in ``RuntimeManifest``.
public struct PetManifest: Codable, Equatable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let spriteVersionNumber: Int
    public let spritesheetPath: String

    public init(id: String,
                displayName: String,
                description: String?,
                spriteVersionNumber: Int,
                spritesheetPath: String) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.spriteVersionNumber = spriteVersionNumber
        self.spritesheetPath = spritesheetPath
    }

    public static func decode(from data: Data) throws -> PetManifest {
        try JSONDecoder().decode(PetManifest.self, from: data)
    }

    public static func decode(fromFile url: URL) throws -> PetManifest {
        try decode(from: Data(contentsOf: url))
    }
}
