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


def vocab_tool(tool: str | None) -> "str | None":
    """Tool name limited to the FIXED vocabulary (else "Other"), never free-form.
    Lets the app's configurable per-tool mood mapping distinguish tools without
    ever emitting an arbitrary (potentially sensitive) string."""
    if not tool:
        return None
    return tool if tool in _CATEGORY else "Other"


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def newest_transcript() -> str | None:
    files = glob.glob(os.path.join(PROJECTS_DIR, "*", "*.jsonl"))
    return max(files, key=os.path.getmtime) if files else None


def find_transcript(session_id: str) -> str | None:
    """The transcript file for a given session id (the filename is the id)."""
    hits = glob.glob(os.path.join(PROJECTS_DIR, "*", f"{session_id}.jsonl"))
    return hits[0] if hits else None


def _read_tail(path: str, nbytes: int = 262144) -> str:
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            fh.seek(max(0, fh.tell() - nbytes))
            return fh.read().decode("utf-8", "replace")
    except OSError:
        return ""


def session_meta(path: str, allow_prompt: bool = False) -> dict:
    """A compact descriptor of a session transcript: {id, label, cwd, mtime}.

    The label never contains prompt text unless ``allow_prompt`` (Detail mode) is
    set — that keeps the base payload's "no prompt text ever" guarantee. Without a
    saved title it falls back to the project name plus a short session id, which
    stays descriptive and distinguishable while revealing no content.
    """
    sid = os.path.splitext(os.path.basename(path))[0]
    cwd = custom = ai = last_prompt = None
    for line in _read_tail(path).splitlines():
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if not isinstance(obj, dict):
            continue
        kind = obj.get("type")
        if kind == "custom-title" and obj.get("customTitle"):
            custom = obj["customTitle"]
        elif kind == "ai-title" and obj.get("aiTitle"):
            ai = obj["aiTitle"]
        elif kind == "last-prompt" and obj.get("lastPrompt"):
            last_prompt = obj["lastPrompt"]
        if cwd is None and isinstance(obj.get("cwd"), str):
            cwd = obj["cwd"]
    project = os.path.basename(cwd) if cwd else None
    title = custom or ai
    if not title and allow_prompt and last_prompt:
        title = last_prompt.strip().replace("\n", " ")[:48]
    if title:
        label = title if (not project or project.lower() in title.lower()) else f"{title} · {project}"
    else:
        # No saved title (and prompt withheld): stay privacy-safe but still
        # distinguishable — the project name plus a short session id.
        short = sid[:8]
        label = f"{project} · {short}" if project else short
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        mtime = 0.0
    return {"id": sid, "label": label[:70], "cwd": cwd or "", "mtime": mtime}


def list_sessions(limit: int = 12, allow_prompt: bool = False) -> list:
    """Recent Claude Code sessions, most-recently-active first."""
    files = glob.glob(os.path.join(PROJECTS_DIR, "*", "*.jsonl"))
    files.sort(key=lambda p: os.path.getmtime(p) if os.path.exists(p) else 0, reverse=True)
    out = []
    for p in files[:limit]:
        try:
            out.append(session_meta(p, allow_prompt=allow_prompt))
        except Exception:
            pass
    return out


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
                return (state_for(cat), cat, None, det, vocab_tool(block.get("name")))
        if any(isinstance(b, dict) and b.get("type") == "text" for b in content):
            return ("writing", None, None, None, None)         # composing prose = writing
        return None

    if role == "user":
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    if block.get("is_error") is True:
                        return ("failure", "other", False, "error" if want_detail else None, None)
                    return None                                # finished ok; keep working state
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    snippet = (block.get("text") or "").strip().replace("\n", " ")
                    return ("writing", None, None, snippet[:80] or None if want_detail else None, None)
            return None
        if isinstance(content, str):                           # plain-string prompt
            snippet = content.strip().replace("\n", " ")
            return ("writing", None, None, snippet[:80] or None if want_detail else None, None)
    return None


def entry_kind(entry) -> "str | None":
    """Classify a transcript entry for turn-progress tracking.

    Returns 'user_prompt' | 'tool_use' | 'tool_result' | 'assistant_text' | None.
    Used to tell whether a turn is *in progress* even when no new lines are being
    written (Claude composing a response), so the pet doesn't falsely go to sleep.
    """
    if not isinstance(entry, dict) or entry.get("type") not in ("assistant", "user"):
        return None
    message = entry.get("message") or {}
    role = message.get("role")
    content = message.get("content")
    if role == "assistant":
        if isinstance(content, list):
            if any(isinstance(b, dict) and b.get("type") == "tool_use" for b in content):
                return "tool_use"
            if any(isinstance(b, dict) and b.get("type") == "text" for b in content):
                return "assistant_text"
        return "assistant_text"
    if role == "user":
        if isinstance(content, list):
            if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
                return "tool_result"
            if any(isinstance(b, dict) and b.get("type") == "text" for b in content):
                return "user_prompt"
            return None
        if isinstance(content, str):
            return "user_prompt"
    return None


def last_entry_kind(path: str) -> "str | None":
    """The kind of the most recent classifiable entry (to init state on switch)."""
    kind = None
    for line in _read_tail(path).splitlines():
        try:
            k = entry_kind(json.loads(line))
        except Exception:
            k = None
        if k is not None:
            kind = k
    return kind


def build_payload(state, cat, success, detail, tool=None, session=None, session_label=None):
    payload = {"state": state, "toolCategory": cat, "timestamp": iso_now(), "success": success}
    if tool:
        payload["tool"] = tool
    if detail:
        payload["detail"] = detail
    if session:
        payload["session"] = session
    if session_label:
        payload["sessionLabel"] = session_label
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
    target_id = None if (not args.session or args.session == "auto") else args.session
    current, current_session, last_activity = None, None, time.time()
    path, pos, session_id, session_label, tail_kind = None, 0, None, None, None

    def switch(p):
        nonlocal path, pos, session_id, session_label, last_activity, tail_kind
        path = p
        try:
            pos = os.path.getsize(p)                 # start at the end (react to *new* activity)
        except OSError:
            pos = 0
        meta = session_meta(p, allow_prompt=args.detail)
        session_id, session_label = meta["id"], meta["label"]
        # Seed the turn-progress tracker from the existing tail, so at startup we
        # already know whether a response is in progress.
        tail_kind = last_entry_kind(p)
        # Restart the idle/sleep window for the newly-watched session, so a
        # session that just became active isn't immediately tagged with a stale
        # idle/sleeping state carried over from the previous one.
        last_activity = time.time()

    print(f"Khosrow watch mode — {('session ' + target_id) if target_id else 'newest active session'}"
          f"{' (with detail)' if args.detail else ''}. Ctrl-C to stop.", file=sys.stderr)

    while True:
        if target_id:                                # follow one assigned session
            tp = find_transcript(target_id)
            if tp and tp != path:
                switch(tp)
        else:                                        # auto: follow whatever's active now
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
                        obj = json.loads(line)
                    except Exception:
                        continue
                    k = entry_kind(obj)
                    if k is not None:
                        tail_kind = k
                    got = derive(obj, args.detail)
                    if got is not None:
                        derived = got
                if derived is not None:
                    last_activity = monotonic

        # Decide the state. A turn can be *in progress* with no new lines being
        # written (Claude composing a response) — detected via tail_kind — so we
        # show `writing` and hold off idle/sleep instead of falsely resting.
        if derived is not None:
            new_state = derived
        elif tail_kind == "user_prompt":             # your prompt, no reply yet
            new_state = ("writing", None, None, None, None)
            last_activity = monotonic                # turn in progress; stay awake
        elif tail_kind == "tool_use":                # a tool is still running
            last_activity = monotonic                # stay awake; hold current state
            new_state = None
        elif monotonic - last_activity > sleep_after:
            new_state = ("sleeping", None, None, None, None)
        elif tail_kind == "tool_result":             # tool done; composing next step
            new_state = ("writing", None, None, None, None)
        elif monotonic - last_activity > idle_after:
            new_state = ("idle", None, None, None, None)
        else:
            new_state = None

        if new_state is not None and (new_state != current or session_id != current_session):
            current, current_session = new_state, session_id
            payload = build_payload(*new_state, session=session_id, session_label=session_label)
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
                    help="derive the current state from the target/newest transcript once, print it, and exit")
    ap.add_argument("--session", default=None,
                    help="follow a specific Claude Code session id (default: auto = newest active)")
    ap.add_argument("--list-sessions", action="store_true",
                    help="print recent Claude Code sessions as JSON and exit")
    args = ap.parse_args()

    if args.list_sessions:
        print(json.dumps(list_sessions()))
        return 0

    if args.test:
        path = (find_transcript(args.session)
                if args.session and args.session != "auto" else newest_transcript())
        if not path:
            print("no transcripts found under", PROJECTS_DIR, file=sys.stderr); return 1
        derived = scan_tail(path, args.detail) or ("idle", None, None, None, None)
        meta = session_meta(path, allow_prompt=args.detail)
        print(json.dumps({"transcript": os.path.basename(path),
                          **build_payload(*derived, session=meta["id"], session_label=meta["label"])}))
        return 0

    try:
        return run(args) or 0
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
