#!/usr/bin/env python3
"""Watch mode — drive Khosrow from Claude Code's own session transcripts.

This is the **no-install** path: no `settings.json` edit, no hooks, and no
Claude Code restart. It tails the most recently active transcript under
``~/.claude/projects/*/*.jsonl``, maps the newest activity to a pet state, and
writes ``~/.claude-pet/state.json`` (plus a best-effort localhost POST) — exactly
the payload the app already understands.

Privacy: by default only the coarse state + tool bucket are emitted (the same
guarantee as the hook bridge). Pass ``--detail`` to also include a short,
human-readable "what" (a file name, a command, or a prompt snippet). That is
opt-in precisely because it surfaces real content.

Stdlib only, single file — so it can be bundled and launched by the app, or run
on its own:  ``python3 bridge/watch_claude.py``  (add ``--detail`` for the what).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import tempfile
import time
import urllib.request
from datetime import datetime, timezone

PROJECTS_DIR = os.path.expanduser("~/.claude/projects")


def state_file() -> str:
    override = os.environ.get("KHOSROW_PET_STATE_FILE")
    return os.path.expanduser(override) if override else os.path.expanduser("~/.claude-pet/state.json")


# --- tool -> coarse category -> state (mirrors khosrow_pet.core / StateMapper) ---
_CATEGORY = {
    "Read": "file-read", "NotebookRead": "file-read",
    "Edit": "file-edit", "Write": "file-edit", "MultiEdit": "file-edit",
    "NotebookEdit": "file-edit", "Update": "file-edit",
    "Grep": "search", "Glob": "search", "LS": "search", "Search": "search",
    "Bash": "command", "BashOutput": "command", "KillBash": "command", "KillShell": "command",
    "WebFetch": "network", "WebSearch": "network",
    "Task": "task", "Agent": "task",
}
_STATE_FOR_CATEGORY = {
    "file-read": "reading", "file-edit": "editing", "search": "searching",
    "command": "runningCommand", "network": "searching", "task": "attentive", "other": "attentive",
}


def category(tool: str | None) -> str:
    return _CATEGORY.get(tool or "", "other")


def state_for(cat: str | None) -> str:
    return _STATE_FOR_CATEGORY.get(cat or "other", "attentive")


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def newest_transcript() -> str | None:
    files = glob.glob(os.path.join(PROJECTS_DIR, "*", "*.jsonl"))
    return max(files, key=os.path.getmtime) if files else None


def _basename(path: str | None) -> str | None:
    return os.path.basename(path) if path else None


def detail_for(tool: str | None, tool_input) -> str | None:
    if not isinstance(tool_input, dict):
        return None
    if tool in ("Edit", "Write", "MultiEdit", "Read", "NotebookEdit", "NotebookRead", "Update"):
        return _basename(tool_input.get("file_path") or tool_input.get("notebook_path"))
    if tool in ("Bash", "BashOutput"):
        cmd = tool_input.get("command")
        return cmd.strip().splitlines()[0][:80] if isinstance(cmd, str) and cmd.strip() else None
    if tool in ("Grep", "Glob", "LS", "Search"):
        return tool_input.get("pattern") or _basename(tool_input.get("path"))
    if tool in ("WebFetch", "WebSearch"):
        return tool_input.get("url") or tool_input.get("query")
    if tool in ("Task", "Agent"):
        return tool_input.get("description")
    return None


def derive(entry: dict, want_detail: bool):
    """Map one transcript entry to (state, category, success, detail) or None to ignore."""
    if entry.get("type") not in ("assistant", "user"):
        return None
    message = entry.get("message") or {}
    role = message.get("role")
    content = message.get("content")

    if role == "assistant" and isinstance(content, list):
        for block in reversed(content):                       # newest tool_use = current activity
            if isinstance(block, dict) and block.get("type") == "tool_use":
                cat = category(block.get("name"))
                det = detail_for(block.get("name"), block.get("input")) if want_detail else None
                return (state_for(cat), cat, None, det)
        if any(isinstance(b, dict) and b.get("type") == "text" for b in content):
            return ("attentive", None, None, None)            # thinking / replying
        return None

    if role == "user":
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    if block.get("is_error") is True:
                        return ("failure", "other", False, "error" if want_detail else None)
                    return None                                # finished ok; keep working state
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    snippet = (block.get("text") or "").strip().replace("\n", " ")
                    return ("attentive", None, None, snippet[:80] or None if want_detail else None)
            return None
        if isinstance(content, str):                           # plain-string prompt
            snippet = content.strip().replace("\n", " ")
            return ("attentive", None, None, snippet[:80] or None if want_detail else None)
    return None


def build_payload(state, cat, success, detail):
    payload = {"state": state, "toolCategory": cat, "timestamp": iso_now(), "success": success}
    if detail:
        payload["detail"] = detail
    return payload


def write_state(payload, path=None):
    path = path or state_file()
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".state-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(payload, fh, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def post_http(payload, port=51763, timeout=0.3):
    try:
        data = json.dumps(payload, sort_keys=True).encode("utf-8")
        req = urllib.request.Request(f"http://127.0.0.1:{port}/state", data=data,
                                     headers={"Content-Type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=timeout).read()
    except Exception:
        pass


def emit(payload, http=True):
    write_state(payload)
    if http:
        post_http(payload)


def scan_tail(path, want_detail, max_lines=400):
    """Read the last chunk of a transcript and return the most recent derived tuple."""
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - 262144))          # last 256 KB is plenty
            chunk = fh.read().decode("utf-8", "replace")
    except OSError:
        return None
    result = None
    for line in chunk.splitlines()[-max_lines:]:
        try:
            got = derive(json.loads(line), want_detail)
        except Exception:
            got = None
        if got is not None:
            result = got
    return result


def run(args):
    http = not args.no_http
    idle_after, sleep_after = args.idle_after, args.sleep_after
    current, last_change, last_activity = None, 0.0, time.time()
    path, pos = None, 0

    def switch(p):
        nonlocal path, pos
        path = p
        try:
            pos = os.path.getsize(p)                 # start at the end (react to *new* activity)
        except OSError:
            pos = 0

    print(f"Khosrow watch mode — following Claude Code transcripts in {PROJECTS_DIR}"
          f"{' (with detail)' if args.detail else ''}. Ctrl-C to stop.", file=sys.stderr)

    while True:
        newest = newest_transcript()
        if newest and newest != path:
            switch(newest)
        derived, monotonic = None, time.time()
        if path:
            try:
                cur = os.path.getsize(path)
            except OSError:
                cur = pos
            if cur < pos:                            # file rotated/truncated
                pos = 0
            if cur > pos:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    fh.seek(pos)
                    new_lines = fh.read().splitlines()
                    pos = fh.tell()
                for line in new_lines:
                    try:
                        got = derive(json.loads(line), args.detail)
                    except Exception:
                        got = None
                    if got is not None:
                        derived = got
                if derived is not None:
                    last_activity = monotonic

        if derived is not None:
            new_state = derived
        elif monotonic - last_activity > sleep_after:
            new_state = ("sleeping", None, None, None)
        elif monotonic - last_activity > idle_after:
            new_state = ("idle", None, None, None)
        else:
            new_state = None

        if new_state is not None and new_state != current:
            current = new_state
            payload = build_payload(*new_state)
            if not args.print_only:
                emit(payload, http=http)
            print(json.dumps(payload))
            sys.stdout.flush()

        time.sleep(args.interval)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--detail", action="store_true",
                    help="also emit a short 'what' (file/command/prompt) — opt-in; surfaces content")
    ap.add_argument("--interval", type=float, default=0.6, help="poll seconds")
    ap.add_argument("--idle-after", type=float, default=25.0, help="seconds of quiet -> idle")
    ap.add_argument("--sleep-after", type=float, default=240.0, help="seconds of quiet -> sleeping")
    ap.add_argument("--no-http", action="store_true", help="don't POST to the app's localhost port")
    ap.add_argument("--print-only", action="store_true", help="print payloads; don't write the state file")
    ap.add_argument("--test", action="store_true",
                    help="derive the current state from the newest transcript once, print it, and exit")
    args = ap.parse_args()

    if args.test:
        path = newest_transcript()
        if not path:
            print("no transcripts found under", PROJECTS_DIR, file=sys.stderr); return 1
        derived = scan_tail(path, args.detail) or ("idle", None, None, None)
        print(json.dumps({"transcript": os.path.basename(path), **build_payload(*derived)}))
        return 0

    try:
        return run(args) or 0
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
