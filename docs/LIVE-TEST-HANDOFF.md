# Khosrow — Live Claude Code Integration: Test Handoff

**Purpose:** everything needed to run the live hook test in a *fresh* Claude Code
session and verify Khosrow reacts to real events. Self-contained so it survives a
session/app restart.

- **Branch:** `claude/khosrow-macos-app-lu36vm`
- **Install commit (attribution fixed):** `cecdac2` (was `c77bcbf`)
- **Prepared:** 2026-07-17 (install session)

> **Hardening update (2026-07-18):** the integration now registers **10** hooks.
> Two dedicated events were added — `PostToolUseFailure → failure` and
> `PermissionRequest → waitingForPermission` — so failures and permission prompts
> are signalled by their own events instead of being inferred. `PostToolUse` now
> covers successful completions only (with a defensive failure fallback). The
> event→state map below and [CLAUDE-HOOKS.md](CLAUDE-HOOKS.md) reflect this. The
> §1 install facts (SHA/backup/count of 8) record the *original* install session.

---

## 1. Status — done & verified before this handoff

| Step | Result |
|------|--------|
| Commit attribution | `Sean Modd <seansmodd@gmail.com>` on HEAD `cecdac2`; force-with-lease push; **local HEAD == remote** |
| Hooks installed | 8 entries merged into `~/.claude/settings.json`, all tagged `KHOSROW_PET_HOOK` |
| Settings safety | only the `hooks` key added; **0** unrelated keys changed/removed |
| Backup | `~/.claude/settings.json.khosrow-backup-20260717-231748` (SHA-256 == pre-install original) |
| Idempotent | re-merge is a no-op (no stacking) |
| state.json | minimal payload only: `{state, toolCategory, timestamp, success}` |
| App | running from `/Applications/Khosrow.app`; reacts via 0.4 s poll of the state file + `127.0.0.1:51763` HTTP |
| Bridge tests | 23/23 pass (redaction, mapping, merge) |
| Early live signal | in the install session, `Bash` calls drove `runningCommand` and a `Read` drove `reading` in `state.json` — `PreToolUse` bridge already firing |

**Installed settings.json SHA-256:** `e1e4d1eacd9cef5d8fca4c7660752db3bc91ca6b072de97b9a21e809c7a11d15`

---

## 2. Event → Khosrow state map (source of truth: `khosrow_pet/core.py` == `StateMapper.swift`)

| Real Claude Code event | Condition | Khosrow state |
|---|---|---|
| `SessionStart` | — | `attentive` |
| `UserPromptSubmit` | — | `attentive` |
| `PreToolUse` | Read / NotebookRead | `reading` |
| `PreToolUse` | Grep / Glob / LS / Search | `searching` |
| `PreToolUse` | WebFetch / WebSearch | `searching` |
| `PreToolUse` | Edit / Write / MultiEdit / NotebookEdit | `editing` |
| `PreToolUse` | Bash / BashOutput / Kill* | `runningCommand` |
| `PreToolUse` | Task / Agent / MCP / other | `attentive` |
| `PostToolUse` | success only | `idle` |
| `PostToolUseFailure` | tool call failed | `failure` |
| `PermissionRequest` | permission dialog shown | `waitingForPermission` |
| `Notification` | idle prompt / agent needs input (fallback) | `waitingForPermission` |
| `Stop` | success | `success` |
| `Stop` | failure | `failure` |
| `SubagentStop` | — | `idle` |
| `SessionEnd` | — | `sleeping` |

`success` and `failure` are one-shot clips that **hold their last frame** until the
next event (no timed decay). `idle` is the neutral resting pose seen between tools.
Note: `SessionStart` perks the pet to **`attentive`**; `idle`/ready is the resting
pose it settles to between activity (this is the one wording nuance vs. the plan's
"SessionStart → idle/ready").

**Real per-turn sequence you'll observe:** `attentive` (prompt) →
`searching`/`reading`/`editing`/`runningCommand` (per tool, each followed by a brief
`idle` after `PostToolUse`) → `success` (at `Stop`). Very short states may be skipped
by the 0.4 s poll, but the ordering holds.

---

## 3. Safe to restart NOW

Install is complete and committed. Nothing is lost by restarting.

### If you use the `claude` CLI in a terminal
1. End the current session: type `/exit` (or press Ctrl-C twice). → fires
   `SessionEnd` (Khosrow → `sleeping`).
2. Open a new terminal and `cd /Users/seanmodd/Developer/Claude-Khosrow-Pet`.
3. Run `claude`. → fires `SessionStart` (Khosrow → `attentive`). The new session
   loads the freshly-installed hooks.

### If you run Claude Code inside the Claude Desktop app
1. Fully quit: **Claude ▸ Quit** (⌘Q), or right-click the Dock icon ▸ **Quit**.
   Make sure it's quit, not just minimized.
2. (Optional, to be certain) in a terminal: `pgrep -lf Claude` — expect no result.
3. Reopen the app, open this repo, and start a **new** Code session.

> The essential requirement is a **new session** (hooks load at session start). A
> full app quit/reopen is just the thorough version.

> Keep the *install* session idle during your test — all sessions share the one
> `~/.claude-pet/state.json`, so don't run tools in two sessions at once.

### (Optional) watch state transitions live, without perturbing them
In a **plain terminal** (a normal shell does *not* fire Claude Code hooks):
```bash
while true; do printf '%s  ' "$(date +%T)"; cat ~/.claude-pet/state.json; echo; sleep 0.4; done
```

### (Optional) give Khosrow a Dock icon while testing
The app defaults to a menu-bar accessory (pet window still visible). To also show a
Dock icon / Cmd-Tab entry:
```bash
pkill -f Khosrow.app; KHOSROW_FORCE_REGULAR=1 open -a /Applications/Khosrow.app
```

---

## 4. Test prompt — paste into the NEW session

**A. Happy path** (drives UserPromptSubmit → search → read → edit → command → success):

```
Do these steps in order, one tool at a time:
1. Use Grep to search this repo for the word "Khosrow" in README.md.
2. Read README.md.
3. Create the file /tmp/khosrow_livetest.txt with the text "hello".
4. Append a second line "live-test ok" to /tmp/khosrow_livetest.txt.
5. Run the shell command:  git status
Then give me a one-line summary. Keep each step a separate tool call.
```

Expected pet sequence: `attentive` → `searching` → `reading` → `editing` →
`runningCommand` → (`idle` between steps) → `success` at the end.

**B. Failure** (drives `failure`):
```
Run the shell command:  cat /tmp/definitely-does-not-exist-khosrow-xyz
```
The command exits non-zero → `PostToolUse` failure → Khosrow → `failure`.

**C. waitingForPermission** (drives `Notification`):
Run the new session in its **default** permission mode (not `--dangerously-skip`
/ not full auto-accept). The first `Bash`/file-write in prompt **A** will surface a
permission prompt; Claude Code emits a `Notification` hook → Khosrow →
`waitingForPermission`. Approve it to continue.

**D. SessionStart / SessionEnd**: happen automatically when you start (`attentive`)
and exit (`sleeping`) the session — see §3.

---

## 5. Verification checklist (Step 6)

Observe on the pet and/or in the state-file watcher:

- [ ] `SessionStart` → `attentive` (settles toward `idle` when quiet)
- [ ] `UserPromptSubmit` → `attentive`
- [ ] Grep/Read → `searching` / `reading`
- [ ] Write/Edit → `editing`
- [ ] Bash → `runningCommand`
- [ ] permission prompt → `waitingForPermission`
- [ ] response completes → `success` (then next prompt → `attentive`)
- [ ] failing command → `failure`
- [ ] `SessionEnd` → `sleeping`

---

## 6. Privacy re-check (run after the live test)

```bash
cat ~/.claude-pet/state.json
python3 - <<'PY'
import json,os
d=json.load(open(os.path.expanduser("~/.claude-pet/state.json")))
allowed={"state","toolCategory","timestamp","success"}
print("keys:", sorted(d))
print("only minimal keys:", set(d)<=allowed)
print("toolCategory in allowed set:", d.get("toolCategory") in
      {None,"file-read","file-edit","search","command","network","task","other"})
PY
```
Must contain **no** prompt text, source, filenames, file contents, raw commands,
API keys, tokens, credentials, or secrets — only the coarse triple.

---

## 7. Rollback (if ever needed)

```bash
# Remove only the tagged hooks (keeps all other settings):
bash /Users/seanmodd/Developer/Claude-Khosrow-Pet/bridge/uninstall_hooks.sh
# Or restore the exact pre-install file:
cp ~/.claude/settings.json.khosrow-backup-20260717-231748 ~/.claude/settings.json
```

---

## 8. Remaining gates before merging PR #1 (keep it a DRAFT)

Do **not** merge PR #1 until all hold:
- [ ] All real hooks verified live (§5)
- [ ] Khosrow reacts correctly
- [ ] Privacy checks pass (§6)
- [ ] CI green
- [ ] Explicit approval to merge

`/Applications/Khosrow.app` and `~/.claude-pet/` stay in place — intended install.
