"""Core bridge logic: event→state mapping, redaction, and emit.

This mapping is the Python mirror of `KhosrowKit/StateMapper.swift`. The two are
kept identical (both covered by tests) — see docs/CLAUDE-HOOKS.md for the table.

Only the Python standard library is used, so the installed hook has no
third-party dependencies and cannot fail to import on a user's Mac.
"""
from __future__ import annotations

import json
import os
import tempfile
from datetime import datetime, timezone

# The complete, closed set of states the pet understands.
STATES = [
    "idle", "attentive", "reading", "searching", "editing", "runningCommand",
    "waitingForPermission", "success", "failure", "sleeping",
]

# Coarse tool categories (a tool's *arguments* are never retained).
CATEGORIES = ["file-read", "file-edit", "search", "command", "network", "task", "other"]

DEFAULT_STATE = "idle"

# ---------------------------------------------------------------------------
# Tool name -> coarse category (mirrors StateMapper.category(forToolNamed:))
# ---------------------------------------------------------------------------
_TOOL_CATEGORY = {
    "Read": "file-read", "NotebookRead": "file-read",
    "Edit": "file-edit", "Write": "file-edit", "MultiEdit": "file-edit",
    "NotebookEdit": "file-edit", "Update": "file-edit",
    "Grep": "search", "Glob": "search", "LS": "search", "Search": "search",
    "Bash": "command", "BashOutput": "command", "KillBash": "command", "KillShell": "command",
    "WebFetch": "network", "WebSearch": "network",
    "Task": "task", "Agent": "task",
}


def categorize(tool_name: str | None) -> str:
    """Bucket a raw Claude Code tool name into a coarse category.

    Unknown tools and MCP tools (``mcp__server__tool``) become ``other`` — the
    raw name is used only to pick the bucket and is then discarded.
    """
    if not tool_name:
        return "other"
    return _TOOL_CATEGORY.get(tool_name, "other")


# ---------------------------------------------------------------------------
# Tool category -> working state (mirrors StateMapper.stateForTool)
# ---------------------------------------------------------------------------
_TOOL_STATE = {
    "file-read": "reading",
    "file-edit": "editing",
    "search": "searching",
    "command": "runningCommand",
    "network": "searching",
    "task": "attentive",
    "other": "attentive",
}


def state_for_tool(category: str | None) -> str:
    return _TOOL_STATE.get(category or "other", "attentive")


def map_state(event: str, category: str | None = None, success: bool | None = None) -> str:
    """Map a normalized (event, category, success) triple to a pet state.

    Identical to `StateMapper.map` in Swift.
    """
    if event == "SessionStart":
        return "attentive"
    if event == "SessionEnd":
        return "sleeping"
    if event == "UserPromptSubmit":
        return "attentive"
    if event == "PreToolUse":
        return state_for_tool(category)
    if event == "PostToolUse":
        return "failure" if success is False else "idle"
    if event == "PostToolUseFailure":
        return "failure"
    if event == "Notification":
        return "waitingForPermission"
    if event == "Stop":
        return "failure" if success is False else "success"
    if event == "StopFailure":
        return "failure"
    if event == "SubagentStart":
        return "searching"
    if event == "SubagentStop":
        return "idle"
    # Unknown event: stay neutral rather than guess.
    return DEFAULT_STATE


# ---------------------------------------------------------------------------
# Redaction: extract ONLY the safe, coarse fields from a raw hook payload.
# ---------------------------------------------------------------------------
def _extract_success(hook_input: dict) -> bool | None:
    """Best-effort success flag WITHOUT reading tool output content.

    We only inspect a small set of boolean-ish keys. We never read strings such
    as command output or file contents.
    """
    resp = hook_input.get("tool_response")
    if isinstance(resp, dict):
        if isinstance(resp.get("success"), bool):
            return resp["success"]
        if isinstance(resp.get("is_error"), bool):
            return not resp["is_error"]
        if "error" in resp and resp.get("error"):
            return False
    for key in ("success", "is_error"):
        if isinstance(hook_input.get(key), bool):
            return hook_input[key] if key == "success" else (not hook_input[key])
    return None


def redact(hook_input: dict, event_override: str | None = None) -> dict:
    """Reduce a raw Claude Code hook payload to the safe coarse triple.

    Returns ``{"event", "category", "success"}``. Everything else in the input
    (prompt, tool_input, file paths, command strings, transcript, cwd, session
    ids, tool output) is intentionally ignored and never returned.
    """
    event = event_override or hook_input.get("hook_event_name") or hook_input.get("event") or ""
    tool_name = hook_input.get("tool_name")
    category = categorize(tool_name) if tool_name else None
    success = _extract_success(hook_input)
    return {"event": str(event), "category": category, "success": success}


# ---------------------------------------------------------------------------
# Payload + emit
# ---------------------------------------------------------------------------
def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_payload(state: str, category: str | None, success: bool | None,
                  timestamp: str | None = None) -> dict:
    """Construct the ENTIRE allowed payload — nothing else is ever added."""
    payload: dict = {
        "state": state,
        "toolCategory": category,
        "timestamp": timestamp or iso_now(),
        "success": success,
    }
    return payload


def default_state_file() -> str:
    override = os.environ.get("KHOSROW_PET_STATE_FILE")
    if override:
        return os.path.expanduser(override)
    return os.path.expanduser("~/.claude-pet/state.json")


def write_state_file(payload: dict, path: str | None = None) -> str:
    """Atomically write the payload to the state file. Returns the path."""
    path = path or default_state_file()
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".state-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(payload, fh, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, path)  # atomic on POSIX
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return path


def post_http(payload: dict, port: int, timeout: float = 0.3) -> bool:
    """Best-effort POST to the app's localhost listener. Never raises."""
    import urllib.request
    try:
        data = json.dumps(payload, sort_keys=True).encode("utf-8")
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/state", data=data,
            headers={"Content-Type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=timeout).read()
        return True
    except Exception:
        return False


def emit(payload: dict, state_file: str | None = None,
         http_port: int | None = 51763) -> None:
    """Emit via file (always) and localhost HTTP (best-effort)."""
    write_state_file(payload, state_file)
    if http_port:
        post_http(payload, http_port)
