import XCTest
@testable import KhosrowKit

/// State-mapping tests (Phase 4). Locks the canonical (event, category, success)
/// -> PetState table that the Python hook mirrors. See docs/CLAUDE-HOOKS.md.
final class StateMappingTests: XCTestCase {

    func testLifecycleEventsMapToExpectedStates() {
        XCTAssertEqual(StateMapper.map(event: .sessionStart), .attentive)
        XCTAssertEqual(StateMapper.map(event: .sessionEnd), .sleeping)
        XCTAssertEqual(StateMapper.map(event: .userPromptSubmit), .attentive)
        XCTAssertEqual(StateMapper.map(event: .permissionRequest), .waitingForPermission)
        XCTAssertEqual(StateMapper.map(event: .notification), .waitingForPermission)
        XCTAssertEqual(StateMapper.map(event: .subagentStart), .searching)
        XCTAssertEqual(StateMapper.map(event: .subagentStop), .idle)
        XCTAssertEqual(StateMapper.map(event: .stopFailure), .failure)
        XCTAssertEqual(StateMapper.map(event: .postToolUseFailure), .failure)
    }

    /// Hardening (PermissionRequest + PostToolUseFailure): the two dedicated
    /// events map directly, Notification stays a fallback, and PostToolUse
    /// success never reads as failure.
    func testPermissionRequestAndFailureHardening() {
        XCTAssertEqual(StateMapper.map(event: .permissionRequest), .waitingForPermission)
        XCTAssertEqual(StateMapper.map(event: .notification), .waitingForPermission)
        // Dedicated failure event is unconditional (ignores the success flag).
        XCTAssertEqual(StateMapper.map(event: .postToolUseFailure), .failure)
        XCTAssertEqual(StateMapper.map(event: .postToolUseFailure, success: true), .failure)
        // PostToolUse success path must not read as failure.
        XCTAssertEqual(StateMapper.map(event: .postToolUse, success: true), .idle)
        XCTAssertEqual(StateMapper.map(event: .postToolUse, success: nil), .idle)
        XCTAssertNotEqual(StateMapper.map(event: .postToolUse, success: true), .failure)
    }

    func testStopSuccessAndFailure() {
        XCTAssertEqual(StateMapper.map(event: .stop, success: true), .success)
        XCTAssertEqual(StateMapper.map(event: .stop, success: nil), .success)
        XCTAssertEqual(StateMapper.map(event: .stop, success: false), .failure)
    }

    func testPreToolUsePerCategory() {
        XCTAssertEqual(StateMapper.map(event: .preToolUse, category: .fileRead), .reading)
        XCTAssertEqual(StateMapper.map(event: .preToolUse, category: .fileEdit), .editing)
        XCTAssertEqual(StateMapper.map(event: .preToolUse, category: .search), .searching)
        XCTAssertEqual(StateMapper.map(event: .preToolUse, category: .command), .runningCommand)
        XCTAssertEqual(StateMapper.map(event: .preToolUse, category: .network), .searching)
        XCTAssertEqual(StateMapper.map(event: .preToolUse, category: .task), .attentive)
        XCTAssertEqual(StateMapper.map(event: .preToolUse, category: .other), .attentive)
        XCTAssertEqual(StateMapper.map(event: .preToolUse, category: nil), .attentive)
    }

    func testPostToolUseOutcome() {
        XCTAssertEqual(StateMapper.map(event: .postToolUse, success: false), .failure)
        XCTAssertEqual(StateMapper.map(event: .postToolUse, success: true), .idle)
        XCTAssertEqual(StateMapper.map(event: .postToolUse, success: nil), .idle)
    }

    func testToolNameCategorization() {
        XCTAssertEqual(StateMapper.category(forToolNamed: "Read"), .fileRead)
        XCTAssertEqual(StateMapper.category(forToolNamed: "NotebookRead"), .fileRead)
        XCTAssertEqual(StateMapper.category(forToolNamed: "Edit"), .fileEdit)
        XCTAssertEqual(StateMapper.category(forToolNamed: "Write"), .fileEdit)
        XCTAssertEqual(StateMapper.category(forToolNamed: "MultiEdit"), .fileEdit)
        XCTAssertEqual(StateMapper.category(forToolNamed: "Grep"), .search)
        XCTAssertEqual(StateMapper.category(forToolNamed: "Glob"), .search)
        XCTAssertEqual(StateMapper.category(forToolNamed: "Bash"), .command)
        XCTAssertEqual(StateMapper.category(forToolNamed: "WebFetch"), .network)
        XCTAssertEqual(StateMapper.category(forToolNamed: "Task"), .task)
        XCTAssertEqual(StateMapper.category(forToolNamed: "mcp__github__get_me"), .other)
        XCTAssertEqual(StateMapper.category(forToolNamed: "SomethingNew"), .other)
    }

    func testLooseStateParsing() {
        XCTAssertEqual(PetState(loose: "editing"), .editing)
        XCTAssertEqual(PetState(loose: "  runningCommand "), .runningCommand)
        XCTAssertEqual(PetState(loose: "grep"), .searching)
        XCTAssertEqual(PetState(loose: "error"), .failure)
        XCTAssertEqual(PetState(loose: "sleep"), .sleeping)
        XCTAssertNil(PetState(loose: "banana"))
    }

    func testEveryStateResolvesToAClipInManifest() throws {
        let m = try KhosrowResources.loadRuntimeManifest()
        for state in PetState.allCases {
            XCTAssertNotNil(m.clip(forState: state.rawValue),
                            "state \(state.rawValue) resolved to no clip")
        }
    }

    func testFpsOverrideRespected() throws {
        let m = try KhosrowResources.loadRuntimeManifest()
        // sleeping is defined with an fps override of 4 in the generator.
        XCTAssertEqual(m.fps(forState: "sleeping"), 4, accuracy: 0.001)
    }
}
