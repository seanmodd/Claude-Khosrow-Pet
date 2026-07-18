import XCTest
@testable import KhosrowKit

/// Settings-merging tests (Phase 4). Proves the installer preserves existing
/// settings and hooks, is idempotent, and uninstalls cleanly.
final class SettingsMergeTests: XCTestCase {

    private let bindings = [
        ClaudeSettings.HookBinding(event: "PreToolUse", matcher: "*",
                                   command: "python3 hook.py pre # KHOSROW_PET_HOOK"),
        ClaudeSettings.HookBinding(event: "Stop", matcher: "*",
                                   command: "python3 hook.py stop # KHOSROW_PET_HOOK"),
    ]

    func testDeepMergePreservesUnrelatedKeys() throws {
        let base = try JSONValue.parse(#"{"model":"opus","permissions":{"allow":["Bash"]}}"#)
        let overlay = try JSONValue.parse(#"{"theme":"dark"}"#)
        let merged = JSONValue.deepMerge(base, overlay)
        XCTAssertEqual(merged["model"]?.stringValue, "opus")
        XCTAssertEqual(merged["theme"]?.stringValue, "dark")
        XCTAssertNotNil(merged["permissions"]?["allow"])
    }

    func testInstallPreservesExistingTopLevelKeys() {
        let base = try! JSONValue.parse(#"{"model":"opus","hooks":{}}"#)
        let out = ClaudeSettings.installHooks(into: base, bindings: bindings)
        XCTAssertEqual(out["model"]?.stringValue, "opus")
        XCTAssertEqual(ClaudeSettings.petHookCount(in: out), 2)
    }

    func testInstallPreservesExistingUserHooksForSameEvent() throws {
        let base = try JSONValue.parse("""
        {
          "hooks": {
            "PreToolUse": [
              { "matcher": "Bash",
                "hooks": [ { "type": "command", "command": "echo user-hook" } ] }
            ]
          }
        }
        """)
        let out = ClaudeSettings.installHooks(into: base, bindings: bindings)
        let pre = out["hooks"]?["PreToolUse"]?.arrayValue ?? []
        // One user group + one pet group.
        XCTAssertEqual(pre.count, 2)
        // The user hook survives.
        let commands = pre.flatMap { $0["hooks"]?.arrayValue ?? [] }
            .compactMap { $0["command"]?.stringValue }
        XCTAssertTrue(commands.contains("echo user-hook"))
        XCTAssertTrue(commands.contains { $0.contains(ClaudeSettings.marker) })
    }

    func testInstallIsIdempotent() {
        let base = JSONValue.object([:])
        let once = ClaudeSettings.installHooks(into: base, bindings: bindings)
        let twice = ClaudeSettings.installHooks(into: once, bindings: bindings)
        XCTAssertEqual(ClaudeSettings.petHookCount(in: once), 2)
        XCTAssertEqual(ClaudeSettings.petHookCount(in: twice), 2)
        XCTAssertEqual(once, twice)
    }

    /// Hardening: the two new tool-scoped events install with matcher "*",
    /// reinstall without duplicating, and uninstall cleanly.
    func testInstallsNewToolScopedEventsIdempotently() {
        let newBindings = [
            ClaudeSettings.HookBinding(event: "PostToolUseFailure", matcher: "*",
                                       command: "python3 hook.py ptuf # KHOSROW_PET_HOOK"),
            ClaudeSettings.HookBinding(event: "PermissionRequest", matcher: "*",
                                       command: "python3 hook.py perm # KHOSROW_PET_HOOK"),
        ]
        let once = ClaudeSettings.installHooks(into: .object([:]), bindings: newBindings)
        for event in ["PostToolUseFailure", "PermissionRequest"] {
            let groups = once["hooks"]?[event]?.arrayValue ?? []
            XCTAssertEqual(groups.count, 1, "\(event) should have exactly one pet group")
            XCTAssertEqual(groups.first?["matcher"]?.stringValue, "*")
        }
        let twice = ClaudeSettings.installHooks(into: once, bindings: newBindings)
        XCTAssertEqual(ClaudeSettings.petHookCount(in: twice), 2)
        XCTAssertEqual(once, twice)  // no duplicates on reinstall

        let removed = ClaudeSettings.removeHooks(from: twice)
        XCTAssertEqual(ClaudeSettings.petHookCount(in: removed), 0)
        XCTAssertNil(removed["hooks"])  // nothing else used hooks
    }

    func testRemoveOnlyRemovesPetHooks() throws {
        let base = try JSONValue.parse("""
        {
          "model": "opus",
          "hooks": {
            "PreToolUse": [
              { "matcher": "Bash",
                "hooks": [ { "type": "command", "command": "echo user-hook" } ] }
            ]
          }
        }
        """)
        let installed = ClaudeSettings.installHooks(into: base, bindings: bindings)
        XCTAssertEqual(ClaudeSettings.petHookCount(in: installed), 2)

        let removed = ClaudeSettings.removeHooks(from: installed)
        XCTAssertEqual(ClaudeSettings.petHookCount(in: removed), 0)
        // Unrelated key preserved.
        XCTAssertEqual(removed["model"]?.stringValue, "opus")
        // User hook preserved.
        let pre = removed["hooks"]?["PreToolUse"]?.arrayValue ?? []
        let commands = pre.flatMap { $0["hooks"]?.arrayValue ?? [] }
            .compactMap { $0["command"]?.stringValue }
        XCTAssertEqual(commands, ["echo user-hook"])
    }

    func testRemoveCleansUpEmptyHooksObject() {
        let base = JSONValue.object([:])
        let installed = ClaudeSettings.installHooks(into: base, bindings: bindings)
        let removed = ClaudeSettings.removeHooks(from: installed)
        // With no other hooks, the "hooks" key should be gone entirely.
        XCTAssertNil(removed["hooks"])
    }

    func testRoundTripSerialization() throws {
        let base = try JSONValue.parse(#"{"model":"opus"}"#)
        let installed = ClaudeSettings.installHooks(into: base, bindings: bindings)
        let data = try installed.serializedPretty()
        let reparsed = try JSONValue.parse(data)
        XCTAssertEqual(installed, reparsed)
    }
}
