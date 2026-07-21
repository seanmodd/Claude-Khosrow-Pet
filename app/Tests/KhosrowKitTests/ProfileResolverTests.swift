import XCTest
@testable import KhosrowKit

/// The live remapping layer: bridge signal -> user's condition->mood mapping.
final class ProfileResolverTests: XCTestCase {

    func testDefaultProfileIsBehaviorPreserving() {
        let p = ConfigurationProfile.builtInDefault()
        // With the shipped defaults, every signal resolves to its input state.
        let cases: [(PetState, String?, String?)] = [
            (.reading, "Read", "file-read"),
            (.reading, "NotebookRead", "file-read"),
            (.editing, "Edit", "file-edit"),
            (.searching, "Grep", "search"),
            (.runningCommand, "Bash", "command"),
            (.attentive, "Task", "task"),
            (.writing, nil, nil),
            (.success, nil, nil),
            (.waitingForPermission, nil, nil),
            (.sleeping, nil, nil),
        ]
        for (state, tool, cat) in cases {
            XCTAssertEqual(ProfileResolver.resolve(state: state, tool: tool,
                                                   category: cat, profile: p),
                           .mood(state.rawValue), "\(state) \(tool ?? "-")")
        }
    }

    func testMovedReadConditionsResolveToAttentive() {
        var p = ConfigurationProfile.builtInDefault()
        p.assign(conditionId: "pre:Read", toMood: "attentive")
        p.assign(conditionId: "pre:NotebookRead", toMood: "attentive")
        XCTAssertEqual(ProfileResolver.resolve(state: .reading, tool: "Read",
                                               category: "file-read", profile: p),
                       .mood("attentive"))
        XCTAssertEqual(ProfileResolver.resolve(state: .reading, tool: "NotebookRead",
                                               category: "file-read", profile: p),
                       .mood("attentive"))
        // Unrelated tools in the same phase are untouched.
        XCTAssertEqual(ProfileResolver.resolve(state: .searching, tool: "Grep",
                                               category: "search", profile: p),
                       .mood("searching"))
    }

    func testConditionMovedToPrayingInvokesPraying() {
        var p = ConfigurationProfile.builtInDefault()
        p.assign(conditionId: "pre:Bash", toMood: "praying")
        XCTAssertEqual(ProfileResolver.resolve(state: .runningCommand, tool: "Bash",
                                               category: "command", profile: p),
                       .mood("praying"))
    }

    func testUnassignedConditionIsIgnored() {
        var p = ConfigurationProfile.builtInDefault()
        p.assign(conditionId: "pre:Grep", toMood: nil)
        XCTAssertEqual(ProfileResolver.resolve(state: .searching, tool: "Grep",
                                               category: "search", profile: p),
                       .ignore)
    }

    func testDisabledDestinationMoodIsIgnored() {
        var p = ConfigurationProfile.builtInDefault()
        if let i = p.moods.firstIndex(where: { $0.id == "reading" }) {
            p.moods[i].enabled = false
        }
        XCTAssertEqual(ProfileResolver.resolve(state: .reading, tool: "Read",
                                               category: "file-read", profile: p),
                       .ignore)
    }

    func testUnknownToolFallsBackToOtherCondition() {
        var p = ConfigurationProfile.builtInDefault()
        p.assign(conditionId: "pre:Other", toMood: "praying")
        XCTAssertEqual(ProfileResolver.resolve(state: .attentive, tool: "Other",
                                               category: "other", profile: p),
                       .mood("praying"))
    }

    func testNoToolNoCategoryLifecycleMapping() {
        var p = ConfigurationProfile.builtInDefault()
        p.assign(conditionId: "userPromptSubmit", toMood: "praying")
        XCTAssertEqual(ProfileResolver.resolve(state: .writing, tool: nil,
                                               category: nil, profile: p),
                       .mood("praying"))
    }

    func testIdleAndPrayingSignalsPassThrough() {
        let p = ConfigurationProfile.builtInDefault()
        XCTAssertEqual(ProfileResolver.resolve(state: .idle, tool: nil,
                                               category: nil, profile: p),
                       .passthrough)
        XCTAssertEqual(ProfileResolver.resolve(state: .praying, tool: nil,
                                               category: nil, profile: p),
                       .passthrough)
    }

    // MARK: Rules

    func testEnabledRuleBeatsAssignment() {
        var p = ConfigurationProfile.builtInDefault()
        _ = p.addRule(name: "read is prayer", conditionId: "pre:Read",
                      moodId: "praying", priority: 100)
        XCTAssertEqual(ProfileResolver.resolve(state: .reading, tool: "Read",
                                               category: "file-read", profile: p),
                       .mood("praying"))
    }

    func testDisabledRuleDoesNotFire() {
        var p = ConfigurationProfile.builtInDefault()
        let id = p.addRule(name: "r", conditionId: "pre:Read", moodId: "praying")!
        if let i = p.rules.firstIndex(where: { $0.id == id }) { p.rules[i].enabled = false }
        XCTAssertEqual(ProfileResolver.resolve(state: .reading, tool: "Read",
                                               category: "file-read", profile: p),
                       .mood("reading"))
    }

    func testHigherPriorityRuleWinsDeterministically() {
        var p = ConfigurationProfile.builtInDefault()
        _ = p.addRule(name: "low", conditionId: "pre:Bash", moodId: "praying", priority: 10)
        _ = p.addRule(name: "high", conditionId: "pre:Bash", moodId: "success", priority: 200)
        XCTAssertEqual(ProfileResolver.resolve(state: .runningCommand, tool: "Bash",
                                               category: "command", profile: p),
                       .mood("success"))
    }

    // MARK: Custom moods

    func testCustomMoodLifecycle() {
        var p = ConfigurationProfile.builtInDefault()
        let id = p.addCustomMood(name: "Zen", description: "calm", visualActId: "gemini-praying")
        XCTAssertNotNil(p.mood(id: id))
        XCTAssertFalse(p.mood(id: id)!.builtin)
        XCTAssertEqual(p.validate(), [])

        // Assign a condition + a rule to it, then delete: everything unwinds.
        XCTAssertTrue(p.assign(conditionId: "pre:Grep", toMood: id))
        _ = p.addRule(name: "zen rule", conditionId: "pre:Bash", moodId: id)
        XCTAssertTrue(p.deleteCustomMood(id: id))
        XCTAssertNil(p.mood(id: id))
        XCTAssertNil(p.moodId(forCondition: "pre:Grep"))          // back to Unassigned
        XCTAssertTrue(p.rules.filter { $0.moodId == id }.isEmpty) // rules removed
        XCTAssertEqual(p.validate(), [])
    }

    func testBuiltInMoodsCannotBeDeleted() {
        var p = ConfigurationProfile.builtInDefault()
        for id in ["praying", "writing", "attentive"] {
            XCTAssertFalse(p.deleteCustomMood(id: id))
            XCTAssertNotNil(p.mood(id: id))
        }
    }

    func testDuplicateMoodMakesCustomCopy() {
        var p = ConfigurationProfile.builtInDefault()
        let id = p.duplicateMood(id: "praying")
        XCTAssertNotNil(id)
        XCTAssertEqual(p.mood(id: id!)?.visualActId, "gemini-praying")
        XCTAssertFalse(p.mood(id: id!)!.builtin)
    }

    func testCustomMoodSurvivesSaveLoad() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("khosrow-custom-\(UUID().uuidString)", isDirectory: true)
        let store = ConfigurationStore(directory: dir)
        var p = ConfigurationProfile.builtInDefault()
        let id = p.addCustomMood(name: "Zen", description: "calm", visualActId: "gemini-praying")
        p.assign(conditionId: "pre:LS", toMood: id)
        try store.save(p)
        let loaded = store.load()
        XCTAssertEqual(loaded.mood(id: id)?.displayName, "Zen")
        XCTAssertEqual(loaded.moodId(forCondition: "pre:LS"), id)
    }

    func testPayloadDecodesToolField() throws {
        let json = #"{"state":"reading","toolCategory":"file-read","tool":"Read","timestamp":"2026-01-01T00:00:00Z","success":null}"#
        let p = try PetBridgeState.decode(from: Data(json.utf8))
        XCTAssertEqual(p.tool, "Read")
        // Old payloads without the field still decode.
        let old = #"{"state":"reading","toolCategory":"file-read","timestamp":"2026-01-01T00:00:00Z","success":null}"#
        XCTAssertNil(try PetBridgeState.decode(from: Data(old.utf8)).tool)
    }
}
