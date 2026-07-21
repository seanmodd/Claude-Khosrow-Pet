"""Privacy tests: prove redaction strips ALL sensitive fields.

If any of these fail, the bridge could leak prompts, code, commands, paths, or
secrets — so these are the most important tests in the project.
"""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from khosrow_pet import core  # noqa: E402

# A hostile payload stuffed with every kind of sensitive value.
SENSITIVE = {
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "session_id": "sess-12345-secret",
    "transcript_path": "/Users/me/.claude/transcript.jsonl",
    "cwd": "/Users/me/private-repo",
    "prompt": "my password is hunter2 and API key sk-live-abcdef",
    "tool_input": {
        "command": "curl -H 'Authorization: Bearer sk-secret' https://internal.example",
        "file_path": "/Users/me/.ssh/id_rsa",
        "new_string": "const SECRET = 'do-not-leak';",
    },
    "tool_response": {
        "success": True,
        "stdout": "these are file CONTENTS that must never leak",
        "stderr": "secret stack trace",
    },
}

# Substrings that must NEVER appear anywhere in the emitted payload.
FORBIDDEN = [
    "hunter2", "sk-live", "sk-secret", "id_rsa", "SECRET", "password",
    "curl", "Authorization", "Bearer", "transcript", "private-repo",
    "sess-12345", "file CONTENTS", "stack trace", "id_rsa", "new_string",
    "/Users/me",
]

ALLOWED_KEYS = {"state", "toolCategory", "timestamp", "success"}


class RedactionTests(unittest.TestCase):
    def _payload_for(self, hook_input, event_override=None):
        safe = core.redact(hook_input, event_override=event_override)
        state = core.map_state(safe["event"], safe["category"], safe["success"])
        return core.build_payload(state, safe["category"], safe["success"])

    def test_payload_has_only_allowed_keys(self):
        payload = self._payload_for(SENSITIVE)
        self.assertEqual(set(payload.keys()), ALLOWED_KEYS)

    def test_no_sensitive_substring_leaks(self):
        payload = self._payload_for(SENSITIVE)
        blob = json.dumps(payload)
        for needle in FORBIDDEN:
            self.assertNotIn(needle, blob, f"leaked sensitive substring: {needle}")

    def test_redact_returns_only_coarse_triple(self):
        safe = core.redact(SENSITIVE)
        self.assertEqual(set(safe.keys()), {"event", "category", "success", "tool"})
        self.assertEqual(safe["event"], "PreToolUse")
        self.assertEqual(safe["category"], "command")  # Bash -> command
        # Known-vocabulary tool names may pass through as `tool` (a closed
        # enum, needed for per-tool mood mapping) — but NEVER a free-form name:
        self.assertEqual(safe["tool"], "Bash")
        mcp = core.redact({"hook_event_name": "PreToolUse",
                           "tool_name": "mcp__secret_server__reveal_password"})
        self.assertEqual(mcp["tool"], "Other")
        self.assertNotIn("secret_server", json.dumps(mcp))

    def test_tool_category_is_coarse_not_raw_name(self):
        payload = self._payload_for(SENSITIVE)
        self.assertEqual(payload["toolCategory"], "command")
        self.assertIn(payload["toolCategory"], core.CATEGORIES)

    def test_success_extracted_without_reading_output(self):
        ok = self._payload_for({
            "hook_event_name": "PostToolUse", "tool_name": "Bash",
            "tool_response": {"success": True, "stdout": "SECRET"}})
        self.assertEqual(ok["success"], True)
        self.assertNotIn("SECRET", json.dumps(ok))

        err = self._payload_for({
            "hook_event_name": "PostToolUse", "tool_name": "Bash",
            "tool_response": {"is_error": True, "stderr": "SECRET"}})
        self.assertEqual(err["success"], False)
        self.assertEqual(err["state"], "failure")

    def test_empty_and_malformed_inputs(self):
        for bad in [{}, {"hook_event_name": "Stop"}, {"tool_name": "Read"}]:
            payload = self._payload_for(bad)
            self.assertEqual(set(payload.keys()), ALLOWED_KEYS)
            self.assertIn(payload["state"], core.STATES)

    def test_event_override_beats_stdin(self):
        safe = core.redact({"hook_event_name": "PreToolUse"}, event_override="Stop")
        self.assertEqual(safe["event"], "Stop")


if __name__ == "__main__":
    unittest.main()
