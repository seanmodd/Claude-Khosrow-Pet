import XCTest
@testable import KhosrowKit

/// Tests for the versioned configuration model: built-in defaults, stable ids,
/// mood/act separation, hook assignments, validation, persistence, migration,
/// import/export, and reset.
final class ConfigurationTests: XCTestCase {

    // MARK: Defaults

    func testBuiltInDefaultValidates() {
        let p = ConfigurationProfile.builtInDefault()
        XCTAssertEqual(p.schemaVersion, ConfigurationProfile.currentSchemaVersion)
        XCTAssertEqual(p.validate(), [])
    }

    func testEveryPetStateHasABuiltInMood() {
        let p = ConfigurationProfile.builtInDefault()
        for state in PetState.allCases {
            XCTAssertNotNil(p.mood(id: state.rawValue), "missing mood for \(state.rawValue)")
        }
    }

    func testStableBuiltInIdentifiers() {
        let p = ConfigurationProfile.builtInDefault()
        for id in ["attentive", "searching", "waitingForPermission", "writing",
                   "runningCommand", "praying"] {
            XCTAssertNotNil(p.mood(id: id), "missing stable id \(id)")
            XCTAssertEqual(p.mood(id: id)?.builtin, true)
        }
    }

    func testDefaultGeminiAssignments() {
        let p = ConfigurationProfile.builtInDefault()
        XCTAssertEqual(p.mood(id: "attentive")?.visualActId, "gemini-attentive")
        XCTAssertEqual(p.mood(id: "searching")?.visualActId, "gemini-searching")
        XCTAssertEqual(p.mood(id: "waitingForPermission")?.visualActId, "gemini-waiting")
        XCTAssertEqual(p.mood(id: "writing")?.visualActId, "gemini-writing")
        XCTAssertEqual(p.mood(id: "runningCommand")?.visualActId, "gemini-running")
        XCTAssertEqual(p.mood(id: "praying")?.visualActId, "gemini-praying")
    }

    func testWritingNoLongerUsesReadingArt() {
        let p = ConfigurationProfile.builtInDefault()
        XCTAssertNotEqual(p.mood(id: "writing")?.visualActId,
                          p.mood(id: "reading")?.visualActId)
    }

    func testPrayingHasNoDefaultAutomaticCondition() {
        let p = ConfigurationProfile.builtInDefault()
        XCTAssertTrue(p.conditionIds(forMood: "praying").isEmpty,
                      "praying must ship with no automatic trigger")
        // …but praying is a valid destination (enabled, built-in, present).
        XCTAssertEqual(p.mood(id: "praying")?.enabled, true)
    }

    func testDefaultAssignmentsMirrorStateMapper() {
        let p = ConfigurationProfile.builtInDefault()
        // Every condition with a category maps to the same state the mapper picks.
        for cond in p.conditions where cond.phase == "PreToolUse" {
            guard let cat = cond.toolCategory,
                  let category = ToolCategory(rawValue: cat) else { continue }
            let expected = StateMapper.stateForTool(category).rawValue
            XCTAssertEqual(p.moodId(forCondition: cond.id), expected, cond.id)
        }
        XCTAssertEqual(p.moodId(forCondition: "userPromptSubmit"), "writing")
        XCTAssertEqual(p.moodId(forCondition: "stopSuccess"), "success")
        XCTAssertEqual(p.moodId(forCondition: "sessionEnd"), "sleeping")
        XCTAssertEqual(p.moodId(forCondition: "permissionRequest"), "waitingForPermission")
    }

    // MARK: Reassignment (the hook-mapping editor's model operations)

    func testReassignConditionBetweenMoods() {
        var p = ConfigurationProfile.builtInDefault()
        XCTAssertEqual(p.moodId(forCondition: "pre:Read"), "reading")
        XCTAssertTrue(p.assign(conditionId: "pre:Read", toMood: "attentive"))
        XCTAssertEqual(p.moodId(forCondition: "pre:Read"), "attentive")
        XCTAssertTrue(p.assign(conditionId: "pre:NotebookRead", toMood: "attentive"))
        XCTAssertEqual(p.moodId(forCondition: "pre:NotebookRead"), "attentive")
        XCTAssertEqual(p.validate(), [])
    }

    func testAssignConditionToPraying() {
        var p = ConfigurationProfile.builtInDefault()
        XCTAssertTrue(p.assign(conditionId: "sessionStart", toMood: "praying"))
        XCTAssertEqual(p.moodId(forCondition: "sessionStart"), "praying")
        XCTAssertEqual(p.conditionIds(forMood: "praying"), ["sessionStart"])
    }

    func testUnassignCondition() {
        var p = ConfigurationProfile.builtInDefault()
        XCTAssertTrue(p.assign(conditionId: "pre:Bash", toMood: nil))
        XCTAssertNil(p.moodId(forCondition: "pre:Bash"))
    }

    func testAssignRejectsUnknownIds() {
        var p = ConfigurationProfile.builtInDefault()
        XCTAssertFalse(p.assign(conditionId: "nope", toMood: "praying"))
        XCTAssertFalse(p.assign(conditionId: "pre:Read", toMood: "nope"))
        XCTAssertEqual(p.moodId(forCondition: "pre:Read"), "reading", "failed assign must not mutate")
    }

    func testMixAndMatchVisualActs() {
        var p = ConfigurationProfile.builtInDefault()
        // Assign the praying act to another mood, and another act to praying.
        XCTAssertTrue(p.setVisualAct("gemini-praying", forMood: "idle"))
        XCTAssertEqual(p.mood(id: "idle")?.visualActId, "gemini-praying")
        XCTAssertTrue(p.setVisualAct("frames-reading", forMood: "praying"))
        XCTAssertEqual(p.mood(id: "praying")?.visualActId, "frames-reading")
        XCTAssertFalse(p.setVisualAct("nope", forMood: "praying"))
        XCTAssertEqual(p.moodIds(usingAct: "gemini-praying"), ["idle"])
    }

    func testValidateCatchesDanglingReferences() {
        var p = ConfigurationProfile.builtInDefault()
        p.moods[0].visualActId = "missing-act"
        XCTAssertFalse(p.validate().isEmpty)
    }

    // MARK: Persistence

    private func tempStore() -> ConfigurationStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("khosrow-config-tests-\(UUID().uuidString)", isDirectory: true)
        return ConfigurationStore(directory: dir)
    }

    func testSaveLoadRoundTrip() throws {
        let store = tempStore()
        var p = ConfigurationProfile.builtInDefault()
        p.assign(conditionId: "pre:Read", toMood: "attentive")
        p.setVisualAct("gemini-praying", forMood: "idle")
        try store.save(p)
        let loaded = store.load()
        XCTAssertEqual(loaded.moodId(forCondition: "pre:Read"), "attentive")
        XCTAssertEqual(loaded.mood(id: "idle")?.visualActId, "gemini-praying")
        XCTAssertEqual(loaded.validate(), [])
    }

    func testMissingFileYieldsDefaults() {
        let store = tempStore()
        let p = store.load()
        XCTAssertEqual(p.moods.count, ConfigurationProfile.builtInDefault().moods.count)
        XCTAssertEqual(p.validate(), [])
    }

    func testCorruptFileFallsBackToDefaults() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not json at all {{{".utf8).write(to: store.fileURL)
        let p = store.load()
        XCTAssertEqual(p.validate(), [])
        XCTAssertNotNil(p.mood(id: "praying"))
    }

    /// An old profile saved before Praying existed gains it on load (migration).
    func testOldProfileGainsPrayingOnLoad() throws {
        let store = tempStore()
        var old = ConfigurationProfile.builtInDefault()
        old.moods.removeAll { $0.id == "praying" }
        old.visualActs.removeAll { $0.id == "gemini-praying" }
        // Write the stripped profile bytes directly (bypassing save's reconcile).
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: store.fileURL)

        let migrated = store.load()
        XCTAssertNotNil(migrated.mood(id: "praying"), "praying must be added by reconcile")
        XCTAssertEqual(migrated.mood(id: "praying")?.visualActId, "gemini-praying")
        XCTAssertEqual(migrated.validate(), [])
    }

    /// User overrides survive migration.
    func testMigrationKeepsUserOverrides() throws {
        let store = tempStore()
        var p = ConfigurationProfile.builtInDefault()
        p.assign(conditionId: "pre:Grep", toMood: "praying")
        try store.save(p)
        let again = store.load()
        XCTAssertEqual(again.moodId(forCondition: "pre:Grep"), "praying")
    }

    func testResetRestoresDefaults() throws {
        let store = tempStore()
        var p = ConfigurationProfile.builtInDefault()
        p.assign(conditionId: "pre:Read", toMood: "praying")
        try store.save(p)
        let reset = store.resetAll()
        XCTAssertEqual(reset.moodId(forCondition: "pre:Read"), "reading")
        XCTAssertEqual(store.load().moodId(forCondition: "pre:Read"), "reading")
        XCTAssertEqual(reset.mood(id: "praying")?.visualActId, "gemini-praying")
    }

    func testExportImportRoundTrip() throws {
        let store = tempStore()
        var p = ConfigurationProfile.builtInDefault()
        p.assign(conditionId: "pre:Bash", toMood: "praying")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("khosrow-export-\(UUID().uuidString).json")
        try store.export(p, to: url)
        let imported = try store.importProfile(from: url)
        XCTAssertEqual(imported.moodId(forCondition: "pre:Bash"), "praying")
        XCTAssertEqual(imported.validate(), [])
    }

    func testImportRejectsGarbage() throws {
        let store = tempStore()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("khosrow-garbage-\(UUID().uuidString).json")
        try Data("[1,2,3]".utf8).write(to: url)
        XCTAssertThrowsError(try store.importProfile(from: url))
    }

    /// Dangling assignment moods become Unassigned instead of corrupting.
    func testReconcileRepairsDanglingAssignment() {
        var p = ConfigurationProfile.builtInDefault()
        p.assignments[0].moodId = "deleted-custom-mood"
        let fixed = ConfigurationStore.reconcile(p, with: .builtInDefault())
        XCTAssertNil(fixed.assignments[0].moodId)
        XCTAssertEqual(fixed.validate(), [])
    }
}
