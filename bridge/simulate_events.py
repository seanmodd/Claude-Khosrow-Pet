#!/usr/bin/env python3
"""Hook-event simulator.

Feeds synthetic — but realistically shaped — Claude Code hook payloads through
the SAME redaction + mapping + emit path the real hook uses, so you can watch
the pet react without running Claude Code. Also doubles as an end-to-end check
that redaction drops everything sensitive.

Examples:
    python3 simulate_events.py --scenario session      # a scripted work session
    python3 simulate_events.py --event PreToolUse --tool Bash
    python3 simulate_events.py --list
    python3 simulate_events.py --scenario session --print-only   # no file writes
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from khosrow_pet import core  # noqa: E402

# A scripted "work session": each step is a raw-ish hook payload. The payloads
# deliberately include sensitive fields (prompt, command, file contents) to
# prove they are stripped by redaction and never reach the emitted state.
SCENARIO_SESSION = [
    {"hook_event_name": "SessionStart"},
    {"hook_event_name": "UserPromptSubmit",
     "prompt": "SECRET: refactor the auth module and my password is hunter2"},
    {"hook_event_name": "PreToolUse", "tool_name": "Grep",
     "tool_input": {"pattern": "API_KEY", "path": "/Users/me/secret"}},
    {"hook_event_name": "PreToolUse", "tool_name": "Read",
     "tool_input": {"file_path": "/Users/me/.ssh/id_rsa"}},
    {"hook_event_name": "PreToolUse", "tool_name": "Edit",
     "tool_input": {"file_path": "auth.swift", "new_string": "let token = ..."}},
    {"hook_event_name": "PreToolUse", "tool_name": "Bash",
     "tool_input": {"command": "curl -H 'Authorization: Bearer sk-secret' api"}},
    {"hook_event_name": "PostToolUse", "tool_name": "Bash",
     "tool_response": {"success": True, "stdout": "build passed; SECRET tokens here"}},
    {"hook_event_name": "PermissionRequest", "tool_name": "Bash",
     "tool_input": {"command": "rm -rf /tmp/secret-cache"}},
    {"hook_event_name": "Notification", "message": "Claude needs permission to run rm -rf"},
    {"hook_event_name": "PostToolUseFailure", "tool_name": "Bash",
     "tool_response": {"is_error": True, "stderr": "compilation failed at secret.swift:42"}},
    {"hook_event_name": "Stop"},
    {"hook_event_name": "SessionEnd"},
]

# Standalone event samples for --list / single --event runs.
SAMPLE_EVENTS = [
    ("SessionStart", None, None),
    ("UserPromptSubmit", None, None),
    ("PreToolUse", "Read", None),
    ("PreToolUse", "Grep", None),
    ("PreToolUse", "Edit", None),
    ("PreToolUse", "Bash", None),
    ("PreToolUse", "WebFetch", None),
    ("PreToolUse", "Task", None),
    ("PostToolUse", "Bash", True),
    ("PostToolUseFailure", "Bash", None),
    ("PermissionRequest", "Bash", None),
    ("Notification", None, None),
    ("Stop", None, True),
    ("SubagentStop", None, None),
    ("SessionEnd", None, None),
]


def process(hook_input: dict, print_only: bool, http: bool) -> dict:
    safe = core.redact(hook_input)
    state = core.map_state(safe["event"], safe["category"], safe["success"])
    payload = core.build_payload(state, safe["category"], safe["success"])
    if not print_only:
        core.emit(payload, http_port=51763 if http else None)
    return payload


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scenario", choices=["session"], help="run a scripted scenario")
    ap.add_argument("--event", help="single event name")
    ap.add_argument("--tool", help="tool name for a single PreToolUse/PostToolUse")
    ap.add_argument("--success", choices=["true", "false"], help="success flag")
    ap.add_argument("--delay", type=float, default=1.2, help="seconds between steps")
    ap.add_argument("--print-only", action="store_true", help="don't write state file")
    ap.add_argument("--no-http", action="store_true", help="don't POST to localhost")
    ap.add_argument("--list", action="store_true", help="print the mapping table and exit")
    args = ap.parse_args()

    if args.list:
        print(f"{'event':16} {'tool':10} {'success':8} -> state")
        for event, tool, success in SAMPLE_EVENTS:
            cat = core.categorize(tool) if tool else None
            state = core.map_state(event, cat, success)
            print(f"{event:16} {str(tool or ''):10} {str(success):8} -> {state}")
        return 0

    http = not args.no_http
    if args.scenario == "session":
        for step in SCENARIO_SESSION:
            payload = process(step, args.print_only, http)
            print(json.dumps(payload))
            time.sleep(args.delay)
        return 0

    if args.event:
        hook_input: dict = {"hook_event_name": args.event}
        if args.tool:
            hook_input["tool_name"] = args.tool
        if args.success:
            hook_input["tool_response"] = {"success": args.success == "true"}
        payload = process(hook_input, args.print_only, http)
        print(json.dumps(payload))
        return 0

    ap.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
