# Claude Code Hooks — what's installed and how it maps

This documents every Claude Code settings change the installer makes, the exact
event→state mapping, and the payload. For the privacy guarantees behind it, see
[../PRIVACY.md](../PRIVACY.md).

## 1. Events registered

The installer adds hooks for the **officially available** Claude Code lifecycle
events. Each entry runs `khosrow_pet_hook.py --event <Event>`, which reduces the
event to the minimal payload and writes it to `~/.claude-pet/state.json`.

| Hook event | Official? | Resulting pet state |
|------------|-----------|---------------------|
| `SessionStart` | ✅ | `attentive` |
| `SessionEnd` | ✅ | `sleeping` |
| `UserPromptSubmit` | ✅ | `writing` (composing a reply) |
| `PreToolUse` (matcher `*`) | ✅ | depends on tool category (below) |
| `PostToolUse` (matcher `*`) | ✅ | `writing` (composing the next step; success only) |
| `PostToolUseFailure` (matcher `*`) | ✅ | `failure` |
| `PermissionRequest` (matcher `*`) | ✅ | `waitingForPermission` |
| `Notification` | ✅ | `waitingForPermission` (fallback) |
| `Stop` | ✅ | `success` (or `failure`) |
| `SubagentStop` | ✅ | `idle` |

`PostToolUseFailure` and `PermissionRequest` are **real, registered hooks** (both
are official Claude Code events): tool failures and permission prompts are
signalled by their own dedicated events rather than inferred. `PostToolUse` is
registered for **successful** completions only, but keeps a defensive
`failure`-on-error fallback so a failure is never dropped. `PermissionRequest` is
the precise permission signal; `Notification` remains a fallback for permission
prompts, idle prompts, and agent-needs-input.

The mapper also still understands `StopFailure` and `SubagentStart`, which are
**not** separate hooks — they exist only so the simulators can exercise every
state.

## 2. Tool category mapping

`PreToolUse` picks a working state from the tool's coarse category. The raw tool
name is used only to choose the bucket and is then discarded.

| Tool name(s) | Category | State while running |
|--------------|----------|---------------------|
| `Read`, `NotebookRead` | `file-read` | `reading` |
| `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Update` | `file-edit` | `editing` |
| `Grep`, `Glob`, `LS`, `Search` | `search` | `searching` |
| `Bash`, `BashOutput`, `KillBash`, `KillShell` | `command` | `runningCommand` |
| `WebFetch`, `WebSearch` | `network` | `searching` |
| `Task`, `Agent` | `task` | `attentive` |
| anything else, incl. `mcp__*` | `other` | `attentive` |

## 3. Full state table

The canonical mapping (implemented identically in Swift `StateMapper` and Python
`core.map_state`, both tested):

| Event | category | success | → state |
|-------|----------|---------|---------|
| SessionStart | – | – | attentive |
| SessionEnd | – | – | sleeping |
| UserPromptSubmit | – | – | writing |
| PreToolUse | file-read | – | reading |
| PreToolUse | file-edit | – | editing |
| PreToolUse | search | – | searching |
| PreToolUse | command | – | runningCommand |
| PreToolUse | network | – | searching |
| PreToolUse | task/other/none | – | attentive |
| PostToolUse | any | true / none | writing |
| PostToolUse | any | false | failure *(defensive fallback)* |
| PostToolUseFailure | any | – | failure |
| PermissionRequest | – | – | waitingForPermission |
| Notification | – | – | waitingForPermission *(fallback)* |
| Stop | – | true / none | success |
| Stop | – | false | failure |
| SubagentStop | – | – | idle |

Each pet state then resolves to an animation clip via
[ANIMATION-MAPPING.md](ANIMATION-MAPPING.md).

## 4. Exact settings modification

Into `~/.claude/settings.json`, the installer merges the block below (assuming
the bridge was installed at `~/.claude-pet/bridge`). **Existing keys and existing
hooks are preserved**; only these tagged entries are added. Every command ends
with the `# KHOSROW_PET_HOOK` marker so it can be found, refreshed, or removed
without disturbing anything else.

```jsonc
{
  "hooks": {
    "SessionStart":     [ { "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event SessionStart  # KHOSROW_PET_HOOK" } ] } ],
    "SessionEnd":       [ { "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event SessionEnd  # KHOSROW_PET_HOOK" } ] } ],
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event UserPromptSubmit  # KHOSROW_PET_HOOK" } ] } ],
    "PreToolUse":       [ { "matcher": "*", "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event PreToolUse  # KHOSROW_PET_HOOK" } ] } ],
    "PostToolUse":      [ { "matcher": "*", "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event PostToolUse  # KHOSROW_PET_HOOK" } ] } ],
    "PostToolUseFailure": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event PostToolUseFailure  # KHOSROW_PET_HOOK" } ] } ],
    "PermissionRequest":  [ { "matcher": "*", "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event PermissionRequest  # KHOSROW_PET_HOOK" } ] } ],
    "Notification":     [ { "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event Notification  # KHOSROW_PET_HOOK" } ] } ],
    "Stop":             [ { "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event Stop  # KHOSROW_PET_HOOK" } ] } ],
    "SubagentStop":     [ { "hooks": [ { "type": "command", "command": "python3 \"$HOME/.claude-pet/bridge/khosrow_pet_hook.py\" --event SubagentStop  # KHOSROW_PET_HOOK" } ] } ]
  }
}
```

> The actual file uses absolute paths (e.g. `/Users/you/.claude-pet/bridge/…`).
> `$HOME` is shown here for readability. The tool-scoped events — `PreToolUse`,
> `PostToolUse`, `PostToolUseFailure`, `PermissionRequest` — use `matcher: "*"`
> (all tools); the non-tool events omit `matcher`, matching Claude Code's schema.

### Preview it before installing

```bash
./bridge/install_hooks.sh --dry-run     # prints the merged file, writes nothing
```

## 5. Backup & safety behavior

- Before writing, the installer copies your existing `settings.json` to
  `settings.json.khosrow-backup-YYYYMMDD-HHMMSS`.
- The write is atomic (temp file + `os.replace`).
- Re-running install is **idempotent** — it refreshes the tagged entries rather
  than duplicating them.
- `uninstall_hooks.sh` removes exactly the tagged entries, deletes now-empty
  event arrays and an empty `hooks` object, and leaves everything else intact.

## 6. The payload

```json
{ "state": "editing", "toolCategory": "file-edit",
  "timestamp": "2026-07-18T02:21:01Z", "success": true }
```

Written atomically to `~/.claude-pet/state.json` and, if the app's loopback
listener is up, POSTed to `http://127.0.0.1:51763/state`. See
[../PRIVACY.md](../PRIVACY.md) for the full guarantee.

## 7. Hook robustness

`khosrow_pet_hook.py` is written to **never** interfere with Claude Code:

- Reads stdin defensively; empty/invalid input is fine.
- Catches every exception and exits `0` (a failing hook never blocks a tool).
- Does no blocking I/O of consequence: the file write is local and atomic; the
  optional HTTP POST has a 0.3 s timeout and ignored failures.
