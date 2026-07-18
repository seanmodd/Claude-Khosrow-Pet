"""Settings-merge tests for the Python installer. Mirrors SettingsMergeTests.swift."""
import copy
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from khosrow_pet import settings_merge as sm  # noqa: E402

BRIDGE = "/Users/me/.claude-pet/bridge"


class SettingsMergeTests(unittest.TestCase):
    def test_deep_merge_preserves_unrelated_keys(self):
        base = {"model": "opus", "permissions": {"allow": ["Bash"]}}
        overlay = {"theme": "dark", "permissions": {"deny": ["WebFetch"]}}
        merged = sm.deep_merge(base, overlay)
        self.assertEqual(merged["model"], "opus")
        self.assertEqual(merged["theme"], "dark")
        self.assertEqual(merged["permissions"]["allow"], ["Bash"])
        self.assertEqual(merged["permissions"]["deny"], ["WebFetch"])

    def test_install_preserves_top_level_keys(self):
        base = {"model": "opus"}
        out = sm.install_hooks(base, BRIDGE)
        self.assertEqual(out["model"], "opus")
        self.assertEqual(sm.pet_hook_count(out), len(sm.INSTALL_EVENTS))

    def test_install_registers_all_events(self):
        out = sm.install_hooks({}, BRIDGE)
        for event, _ in sm.INSTALL_EVENTS:
            self.assertIn(event, out["hooks"])

    def test_pre_tool_use_has_matcher_but_stop_does_not(self):
        out = sm.install_hooks({}, BRIDGE)
        pre_group = out["hooks"]["PreToolUse"][-1]
        self.assertEqual(pre_group.get("matcher"), "*")
        stop_group = out["hooks"]["Stop"][-1]
        self.assertNotIn("matcher", stop_group)

    def test_install_preserves_existing_user_hooks(self):
        base = {"hooks": {"PreToolUse": [
            {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo user"}]}
        ]}}
        out = sm.install_hooks(base, BRIDGE)
        pre = out["hooks"]["PreToolUse"]
        self.assertEqual(len(pre), 2)  # user group + pet group
        commands = [h["command"] for g in pre for h in g["hooks"]]
        self.assertIn("echo user", commands)
        self.assertTrue(any(sm.MARKER in c for c in commands))

    def test_install_is_idempotent(self):
        once = sm.install_hooks({}, BRIDGE)
        twice = sm.install_hooks(copy.deepcopy(once), BRIDGE)
        self.assertEqual(sm.pet_hook_count(once), len(sm.INSTALL_EVENTS))
        self.assertEqual(sm.pet_hook_count(twice), len(sm.INSTALL_EVENTS))
        self.assertEqual(once, twice)

    def test_remove_only_removes_pet_hooks(self):
        base = {"model": "opus", "hooks": {"PreToolUse": [
            {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo user"}]}
        ]}}
        installed = sm.install_hooks(base, BRIDGE)
        self.assertEqual(sm.pet_hook_count(installed), len(sm.INSTALL_EVENTS))
        removed = sm.remove_hooks(installed)
        self.assertEqual(sm.pet_hook_count(removed), 0)
        self.assertEqual(removed["model"], "opus")
        pre = removed["hooks"]["PreToolUse"]
        commands = [h["command"] for g in pre for h in g["hooks"]]
        self.assertEqual(commands, ["echo user"])

    def test_remove_cleans_empty_hooks(self):
        installed = sm.install_hooks({}, BRIDGE)
        removed = sm.remove_hooks(installed)
        self.assertNotIn("hooks", removed)

    def test_hook_command_contains_marker_and_event(self):
        cmd = sm.hook_command(BRIDGE, "PreToolUse")
        self.assertIn(sm.MARKER, cmd)
        self.assertIn("--event PreToolUse", cmd)
        self.assertIn("khosrow_pet_hook.py", cmd)


if __name__ == "__main__":
    unittest.main()
