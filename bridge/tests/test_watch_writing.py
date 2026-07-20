"""Tests for watch-mode turn-progress + the `writing` state.

These lock the behaviour behind bullet 1: Claude composing a response reads as
`writing`, and a turn *in progress* (no new transcript lines yet) is detected via
`entry_kind` so the pet never falsely goes to sleep mid-response.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
import watch_claude as wc  # noqa: E402


def _assistant_text(text="Sure, here's the plan."):
    return {"type": "assistant", "message": {"role": "assistant",
            "content": [{"type": "text", "text": text}]}}


def _assistant_tool(name="Read", inp=None):
    return {"type": "assistant", "message": {"role": "assistant",
            "content": [{"type": "tool_use", "name": name, "input": inp or {}}]}}


def _user_prompt(text="please refactor this"):
    return {"type": "user", "message": {"role": "user",
            "content": [{"type": "text", "text": text}]}}


def _user_prompt_str(text="hello"):
    return {"type": "user", "message": {"role": "user", "content": text}}


def _tool_result(is_error=False):
    return {"type": "user", "message": {"role": "user",
            "content": [{"type": "tool_result", "is_error": is_error}]}}


class EntryKindTests(unittest.TestCase):
    def test_classification(self):
        self.assertEqual(wc.entry_kind(_user_prompt()), "user_prompt")
        self.assertEqual(wc.entry_kind(_user_prompt_str()), "user_prompt")
        self.assertEqual(wc.entry_kind(_assistant_tool()), "tool_use")
        self.assertEqual(wc.entry_kind(_assistant_text()), "assistant_text")
        self.assertEqual(wc.entry_kind(_tool_result()), "tool_result")
        self.assertEqual(wc.entry_kind(_tool_result(is_error=True)), "tool_result")

    def test_non_message_entries_are_none(self):
        self.assertIsNone(wc.entry_kind({"type": "summary"}))
        self.assertIsNone(wc.entry_kind({"type": "custom-title", "customTitle": "x"}))
        self.assertIsNone(wc.entry_kind("not a dict"))


class DeriveWritingTests(unittest.TestCase):
    def test_user_prompt_is_writing(self):
        state, cat, success, detail = wc.derive(_user_prompt(), want_detail=False)
        self.assertEqual(state, "writing")

    def test_plain_string_prompt_is_writing(self):
        state, *_ = wc.derive(_user_prompt_str(), want_detail=False)
        self.assertEqual(state, "writing")

    def test_assistant_prose_is_writing(self):
        state, *_ = wc.derive(_assistant_text(), want_detail=False)
        self.assertEqual(state, "writing")

    def test_tool_use_still_maps_to_working_state(self):
        self.assertEqual(wc.derive(_assistant_tool("Read"), False)[0], "reading")
        self.assertEqual(wc.derive(_assistant_tool("Edit"), False)[0], "editing")
        self.assertEqual(wc.derive(_assistant_tool("Bash"), False)[0], "runningCommand")
        self.assertEqual(wc.derive(_assistant_tool("Grep"), False)[0], "searching")

    def test_tool_result_error_is_failure(self):
        self.assertEqual(wc.derive(_tool_result(is_error=True), False)[0], "failure")

    def test_tool_result_ok_keeps_working_state(self):
        self.assertIsNone(wc.derive(_tool_result(is_error=False), False))

    def test_writing_is_a_valid_state(self):
        # `writing` must be in the shared vocabulary the app understands.
        from khosrow_pet import core
        self.assertIn("writing", core.STATES)


if __name__ == "__main__":
    unittest.main()
