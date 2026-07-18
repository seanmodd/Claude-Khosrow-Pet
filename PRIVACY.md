# Privacy

Khosrow is designed so the pet learns **what kind** of thing Claude Code is
doing, never **what** you are doing. This document states exactly what crosses
the bridge and how that is enforced.

## The entire payload

Every message from the hook bridge to the app is exactly this shape and nothing
more:

```json
{
  "state": "editing",
  "toolCategory": "file-edit",
  "timestamp": "2026-07-18T02:21:01Z",
  "success": true
}
```

- `state` — one of ten fixed labels: `idle`, `attentive`, `reading`,
  `searching`, `editing`, `runningCommand`, `waitingForPermission`, `success`,
  `failure`, `sleeping`.
- `toolCategory` — one of seven coarse buckets: `file-read`, `file-edit`,
  `search`, `command`, `network`, `task`, `other` (or `null`).
- `timestamp` — ISO-8601 time the event was processed.
- `success` — `true`, `false`, or `null`.

That is the whole vocabulary. There are no free-text fields.

## What is NEVER included

The bridge never reads into the payload — and the payload has no field that
could carry — any of:

- ❌ Prompt text or conversation content
- ❌ Source code or file contents
- ❌ File paths or file names
- ❌ Raw command strings or command output
- ❌ Tool arguments of any kind
- ❌ The raw tool name (it is bucketed into a category, then discarded)
- ❌ Session IDs, transcript paths, working directory
- ❌ Credentials, tokens, or secrets
- ❌ Environment variables

## How it is enforced

1. **Allow-list construction, not redaction-by-removal.** The payload is built
   field-by-field from a closed set (`core.build_payload`). There is no code
   path that copies arbitrary hook input into the output.

2. **Redaction extracts only a coarse triple.** `core.redact` returns just
   `{event, category, success}`. The tool name is used only to *choose* a
   category and is then dropped. Success is read only from small boolean-ish
   keys (`success`, `is_error`) — never from output strings.

3. **Tested adversarially.** `bridge/tests/test_redaction.py` feeds a payload
   stuffed with passwords, API keys, SSH key paths, commands, and file contents,
   then asserts (a) the output has *only* the four allowed keys and (b) not one
   of a long list of sensitive substrings appears anywhere in it. This test runs
   in CI on every push.

## Where the data goes

- **On your machine only.** The state is written to
  `~/.claude-pet/state.json` and/or POSTed to `http://127.0.0.1:51763`
  (loopback). Nothing is sent off your Mac. The HTTP listener binds to the
  loopback interface only (`requiredInterfaceType = .loopback`).
- **No network egress.** Neither the app nor the bridge contacts any remote
  server. There is no telemetry, analytics, or "phone home."
- **Ephemeral.** `state.json` holds only the most recent state; each write
  atomically replaces the previous one.

## What the installer changes

The installer only adds hook entries (tagged `KHOSROW_PET_HOOK`) to
`~/.claude/settings.json`, after making a timestamped backup, and copies the
bridge to `~/.claude-pet/`. It never overwrites your settings and never touches
anything else. The exact diff is in [docs/CLAUDE-HOOKS.md](docs/CLAUDE-HOOKS.md).
Remove everything with `bridge/uninstall_hooks.sh`.

## Auditing it yourself

```bash
# Watch exactly what the bridge would emit for a full scripted session,
# including a deliberately sensitive payload — nothing sensitive appears:
python3 bridge/simulate_events.py --scenario session --print-only

# Run the privacy test:
python3 -m unittest bridge.tests.test_redaction -v

# Inspect the only file the pet reads:
cat ~/.claude-pet/state.json
```
