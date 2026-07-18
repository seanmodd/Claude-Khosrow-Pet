"""State-mapping tests for the Python bridge. Must match StateMappingTests.swift."""
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from khosrow_pet import core  # noqa: E402


class StateMapTests(unittest.TestCase):
    def test_lifecycle_events(self):
        self.assertEqual(core.map_state("SessionStart"), "attentive")
        self.assertEqual(core.map_state("SessionEnd"), "sleeping")
        self.assertEqual(core.map_state("UserPromptSubmit"), "attentive")
        self.assertEqual(core.map_state("PermissionRequest"), "waitingForPermission")
        self.assertEqual(core.map_state("Notification"), "waitingForPermission")
        self.assertEqual(core.map_state("SubagentStart"), "searching")
        self.assertEqual(core.map_state("SubagentStop"), "idle")
        self.assertEqual(core.map_state("StopFailure"), "failure")
        self.assertEqual(core.map_state("PostToolUseFailure"), "failure")

    def test_permission_request_maps_to_waiting(self):
        # Hardening: the dedicated permission event maps directly, ignoring
        # category/success. Notification remains a fallback for the same state.
        self.assertEqual(core.map_state("PermissionRequest"), "waitingForPermission")
        self.assertEqual(core.map_state("PermissionRequest", "command", None),
                         "waitingForPermission")
        self.assertEqual(core.map_state("Notification"), "waitingForPermission")

    def test_post_tool_use_failure_maps_to_failure(self):
        # Dedicated failure event is unconditional — no payload parsing.
        self.assertEqual(core.map_state("PostToolUseFailure"), "failure")
        self.assertEqual(core.map_state("PostToolUseFailure", "command", None), "failure")
        self.assertEqual(core.map_state("PostToolUseFailure", "command", True), "failure")

    def test_post_tool_use_success_is_never_failure(self):
        # PostToolUse is the success path; it must not read as failure.
        self.assertEqual(core.map_state("PostToolUse", "command", True), "idle")
        self.assertEqual(core.map_state("PostToolUse", "command", None), "idle")
        self.assertNotEqual(core.map_state("PostToolUse", "command", True), "failure")
        self.assertNotEqual(core.map_state("PostToolUse", "command", None), "failure")

    def test_stop_outcome(self):
        self.assertEqual(core.map_state("Stop", success=True), "success")
        self.assertEqual(core.map_state("Stop", success=None), "success")
        self.assertEqual(core.map_state("Stop", success=False), "failure")

    def test_pre_tool_use_per_category(self):
        self.assertEqual(core.map_state("PreToolUse", "file-read"), "reading")
        self.assertEqual(core.map_state("PreToolUse", "file-edit"), "editing")
        self.assertEqual(core.map_state("PreToolUse", "search"), "searching")
        self.assertEqual(core.map_state("PreToolUse", "command"), "runningCommand")
        self.assertEqual(core.map_state("PreToolUse", "network"), "searching")
        self.assertEqual(core.map_state("PreToolUse", "task"), "attentive")
        self.assertEqual(core.map_state("PreToolUse", "other"), "attentive")
        self.assertEqual(core.map_state("PreToolUse", None), "attentive")

    def test_post_tool_use_outcome(self):
        self.assertEqual(core.map_state("PostToolUse", "command", False), "failure")
        self.assertEqual(core.map_state("PostToolUse", "command", True), "idle")
        self.assertEqual(core.map_state("PostToolUse", "command", None), "idle")

    def test_categorize(self):
        self.assertEqual(core.categorize("Read"), "file-read")
        self.assertEqual(core.categorize("NotebookRead"), "file-read")
        self.assertEqual(core.categorize("Edit"), "file-edit")
        self.assertEqual(core.categorize("Write"), "file-edit")
        self.assertEqual(core.categorize("MultiEdit"), "file-edit")
        self.assertEqual(core.categorize("Grep"), "search")
        self.assertEqual(core.categorize("Glob"), "search")
        self.assertEqual(core.categorize("Bash"), "command")
        self.assertEqual(core.categorize("WebFetch"), "network")
        self.assertEqual(core.categorize("Task"), "task")
        self.assertEqual(core.categorize("mcp__github__get_me"), "other")
        self.assertEqual(core.categorize("SomethingNew"), "other")
        self.assertEqual(core.categorize(None), "other")

    def test_unknown_event_stays_neutral(self):
        self.assertEqual(core.map_state("TotallyUnknown"), core.DEFAULT_STATE)

    def test_all_states_are_valid(self):
        # Every event we support must map into the closed STATES set.
        events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse",
                  "PostToolUse", "PostToolUseFailure", "PermissionRequest",
                  "Notification", "Stop", "StopFailure", "SubagentStart",
                  "SubagentStop"]
        for e in events:
            for cat in core.CATEGORIES + [None]:
                for s in (True, False, None):
                    self.assertIn(core.map_state(e, cat, s), core.STATES)


if __name__ == "__main__":
    unittest.main()
