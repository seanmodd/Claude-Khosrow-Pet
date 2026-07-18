"""Idempotent merge of the pet's hooks into Claude Code settings.json.

Python mirror of `KhosrowKit/ClaudeSettings.swift`, but schema-accurate for the
real Claude Code file (matcher is omitted for non-tool events). Never overwrites
the file wholesale — existing keys and hooks are preserved; our own hooks carry
a marker so re-running refreshes rather than duplicates them.

CLI:
    python3 -m khosrow_pet.settings_merge install --settings PATH --bridge-dir DIR [--dry-run]
    python3 -m khosrow_pet.settings_merge remove  --settings PATH [--dry-run]
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import sys
from datetime import datetime

# Every pet hook command contains this marker so we can find/refresh/remove ours.
MARKER = "KHOSROW_PET_HOOK"

# Events the installer registers, with the matcher to use ("" = no matcher key).
# Only officially-available Claude Code hook events are registered here.
INSTALL_EVENTS = [
    ("SessionStart", ""),
    ("SessionEnd", ""),
    ("UserPromptSubmit", ""),
    ("PreToolUse", "*"),
    ("PostToolUse", "*"),
    ("Notification", ""),
    ("Stop", ""),
    ("SubagentStop", ""),
]


def deep_merge(base: dict, overlay: dict) -> dict:
    """Recursive object merge; non-dict values from overlay win."""
    if not isinstance(base, dict) or not isinstance(overlay, dict):
        return copy.deepcopy(overlay)
    out = copy.deepcopy(base)
    for k, v in overlay.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def _is_pet_entry(entry: dict) -> bool:
    return isinstance(entry, dict) and MARKER in str(entry.get("command", ""))


def _is_pet_group(group: dict) -> bool:
    hooks = group.get("hooks", []) if isinstance(group, dict) else []
    return any(_is_pet_entry(h) for h in hooks)


def _pet_group(matcher: str, command: str) -> dict:
    group: dict = {"hooks": [{"type": "command", "command": command}]}
    if matcher:
        # Preserve Claude Code order (matcher first) for readability.
        group = {"matcher": matcher, "hooks": group["hooks"]}
    return group


def hook_command(bridge_dir: str, event: str, python: str = "python3") -> str:
    script = os.path.join(bridge_dir, "khosrow_pet_hook.py")
    return f'{python} "{script}" --event {event}  # {MARKER}'


def install_hooks(settings: dict, bridge_dir: str, python: str = "python3") -> dict:
    """Return a new settings dict with pet hooks merged in (idempotent)."""
    out = copy.deepcopy(settings) if isinstance(settings, dict) else {}
    hooks = out.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
    for event, matcher in INSTALL_EVENTS:
        groups = [g for g in hooks.get(event, []) if not _is_pet_group(g)]
        groups.append(_pet_group(matcher, hook_command(bridge_dir, event, python)))
        hooks[event] = groups
    out["hooks"] = hooks
    return out


def remove_hooks(settings: dict) -> dict:
    """Return a new settings dict with all pet hooks removed and tidied up."""
    out = copy.deepcopy(settings) if isinstance(settings, dict) else {}
    hooks = out.get("hooks")
    if not isinstance(hooks, dict):
        return out
    for event in list(hooks.keys()):
        groups = [g for g in hooks.get(event, []) if not _is_pet_group(g)]
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]
    if hooks:
        out["hooks"] = hooks
    else:
        out.pop("hooks", None)
    return out


def pet_hook_count(settings: dict) -> int:
    hooks = settings.get("hooks", {}) if isinstance(settings, dict) else {}
    count = 0
    for groups in hooks.values():
        for group in groups if isinstance(groups, list) else []:
            for entry in group.get("hooks", []) if isinstance(group, dict) else []:
                if _is_pet_entry(entry):
                    count += 1
    return count


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------
def load_settings(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    with open(path) as fh:
        text = fh.read().strip()
    if not text:
        return {}
    return json.loads(text)


def backup_settings(path: str) -> str | None:
    """Timestamped backup next to the settings file. Returns backup path."""
    if not os.path.exists(path):
        return None
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = f"{path}.khosrow-backup-{stamp}"
    shutil.copy2(path, backup)
    return backup


def atomic_write_json(path: str, data: dict) -> None:
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    tmp = f"{path}.tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def _main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_install = sub.add_parser("install")
    p_install.add_argument("--settings", required=True)
    p_install.add_argument("--bridge-dir", required=True)
    p_install.add_argument("--python", default="python3")
    p_install.add_argument("--dry-run", action="store_true")

    p_remove = sub.add_parser("remove")
    p_remove.add_argument("--settings", required=True)
    p_remove.add_argument("--dry-run", action="store_true")

    args = ap.parse_args(argv)
    current = load_settings(args.settings)

    if args.cmd == "install":
        updated = install_hooks(current, os.path.abspath(args.bridge_dir), args.python)
    else:
        updated = remove_hooks(current)

    if args.dry_run:
        print(json.dumps(updated, indent=2))
        print(f"# pet hook entries after {args.cmd}: {pet_hook_count(updated)}",
              file=sys.stderr)
        return 0

    backup = backup_settings(args.settings)
    atomic_write_json(args.settings, updated)
    if backup:
        print(f"Backed up existing settings to: {backup}")
    print(f"Wrote {args.settings} (pet hook entries: {pet_hook_count(updated)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
