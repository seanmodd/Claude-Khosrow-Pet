import XCTest
@testable import KhosrowKit

/// Manifest-decoding tests (Phase 4). Verifies both the original `pet.json`
/// identity model and the derived runtime atlas decode and self-validate.
final class ManifestDecodingTests: XCTestCase {

    func testPetManifestDecodesOriginalShape() throws {
        let json = """
        {
          "id": "khosrow",
          "displayName": "Khosrow",
          "description": "A regal human Iranian warrior king.",
          "spriteVersionNumber": 2,
          "spritesheetPath": "spritesheet.webp"
        }
        """
        let pet = try PetManifest.decode(from: Data(json.utf8))
        XCTAssertEqual(pet.id, "khosrow")
        XCTAssertEqual(pet.displayName, "Khosrow")
        XCTAssertEqual(pet.spriteVersionNumber, 2)
        XCTAssertEqual(pet.spritesheetPath, "spritesheet.webp")
    }

    func testPetManifestToleratesMissingDescription() throws {
        let json = """
        {"id":"x","displayName":"X","spriteVersionNumber":2,"spritesheetPath":"s.webp"}
        """
        let pet = try PetManifest.decode(from: Data(json.utf8))
        XCTAssertNil(pet.description)
    }

    func testBundledRuntimeManifestDecodes() throws {
        let manifest = try KhosrowResources.loadRuntimeManifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.pet.id, "khosrow")
        XCTAssertEqual(manifest.pet.spriteVersionNumber, 2)
    }

    func testRuntimeManifestGridMatchesDerivedFacts() throws {
        let m = try KhosrowResources.loadRuntimeManifest()
        XCTAssertEqual(m.sheet.width, 1536)
        XCTAssertEqual(m.sheet.height, 2288)
        XCTAssertEqual(m.sheet.cols, 8)
        XCTAssertEqual(m.sheet.rows, 11)
        XCTAssertEqual(m.sheet.cellWidth, 192)
        XCTAssertEqual(m.sheet.cellHeight, 208)
        // Grid math is internally consistent.
        XCTAssertEqual(m.sheet.cols * m.sheet.cellWidth, m.sheet.width)
        XCTAssertEqual(m.sheet.rows * m.sheet.cellHeight, m.sheet.height)
    }

    func testRuntimeManifestHasElevenClipsAnd74Frames() throws {
        let m = try KhosrowResources.loadRuntimeManifest()
        XCTAssertEqual(m.clips.count, 11)
        let totalFrames = m.clips.values.reduce(0) { $0 + $1.frameCount }
        XCTAssertEqual(totalFrames, 74)
    }

    func testRuntimeManifestHasAllTenStates() throws {
        let m = try KhosrowResources.loadRuntimeManifest()
        for state in PetState.allCases {
            XCTAssertNotNil(m.states[state.rawValue],
                            "missing state binding for \(state.rawValue)")
        }
    }

    func testRuntimeManifestSelfValidates() throws {
        let m = try KhosrowResources.loadRuntimeManifest()
        XCTAssertEqual(m.validate(), [], "manifest reported problems: \(m.validate())")
    }

    func testEveryClipFrameCountFitsGrid() throws {
        let m = try KhosrowResources.loadRuntimeManifest()
        for (name, clip) in m.clips {
            XCTAssertGreaterThanOrEqual(clip.frameCount, 1, "\(name)")
            XCTAssertLessThanOrEqual(clip.frameCount, m.sheet.cols, "\(name)")
            XCTAssertGreaterThanOrEqual(clip.row, 0, "\(name)")
            XCTAssertLessThan(clip.row, m.sheet.rows, "\(name)")
        }
    }
}
