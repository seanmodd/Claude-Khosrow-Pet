# Troubleshooting

## Building & launching

**`swift: command not found` / old Swift**
Install the Xcode Command Line Tools: `xcode-select --install`, then check
`swift --version` (need 5.9+). Full Xcode also works.

**`swift build` fails on `import AppKit` / platform**
Build from the `app/` directory (`cd app && swift build`). The package targets
macOS 12+. On Linux the UI is compiled out by design — build the app only on
macOS.

**The app runs but I see no pet**
- It starts near the **lower-right of your main display**. Look there, or use the
  menu-bar 🦁 → **Reset Position**.
- If **click-through** is on, you can't grab it — toggle it off in the menu.
- If scale is tiny, bump it via 🦁 → **Scale**.

**No menu-bar 🦁**
The app is a menu-bar (`.accessory`) app with no Dock icon. If the icon isn't
visible, the menu bar may be full — quit some other menu-bar apps, or run from a
terminal to see logs: `swift run KhosrowApp`.

**The pet doesn't appear on a second monitor / full-screen app**
Ensure 🦁 → **Show on all Spaces** is checked. Drag it to the monitor you want;
its position is remembered per display.

## Assets

**"Spritesheet is NxM, expected 1536x2288" at launch**
The runtime PNG doesn't match the atlas. Regenerate it:
```bash
python3 scripts/convert_spritesheet.py
python3 scripts/verify_assets.py
```

**"runtime PNG has no alpha channel" warning**
The conversion lost transparency. Re-run `convert_spritesheet.py` (it forces
RGBA and verifies alpha) and `verify_assets.py`.

**I want to confirm the originals are untouched**
```bash
shasum -a 256 -c artifacts/ORIGINAL-CHECKSUMS.sha256
```

## Claude Code hooks

**The pet doesn't react to Claude Code**
1. Confirm hooks are installed: look for `KHOSROW_PET_HOOK` in
   `~/.claude/settings.json`.
2. **Restart Claude Code** so it reloads settings.
3. Confirm state is being written:
   ```bash
   cat ~/.claude-pet/state.json      # should update as you work
   ```
4. Drive it manually to isolate app vs. bridge:
   ```bash
   python3 bridge/simulate_states.py --state editing
   ```
   If the pet reacts to this but not to Claude Code, the hooks aren't firing
   (step 1–2). If it doesn't react to this either, it's the app (see below).

**Pet reacts to the file but I want lower latency**
The app also listens on `127.0.0.1:51763`. Hooks POST there automatically; if the
port is busy the file path still works. Nothing to configure.

**`install_hooks.sh` refuses to run**
It guards against non-macOS. On a Mac it should proceed; on Linux it exits by
design. (You should not run it in a cloud/CI environment.)

**Did the installer clobber my settings?**
No — it merges and always writes a timestamped backup:
`~/.claude/settings.json.khosrow-backup-*`. Restore by copying a backup back.

**Remove everything**
```bash
./bridge/uninstall_hooks.sh --purge     # removes hooks + ~/.claude-pet
```

## App behavior

**Animations look wrong / frames misaligned**
Open 🦁 → **Animation Test Console…**, pick each clip, and step frame-by-frame.
Cross-check against `artifacts/contact-sheet.png`. If a specific state maps to
the wrong clip, edit the `STATES` table in
`scripts/build_runtime_manifest.py`, re-run it, and rebuild.

**Edges show a white/black halo**
That indicates alpha isn't being composited. Verify the runtime PNG has alpha
(`python3 scripts/verify_assets.py`) and that you didn't replace it with a
flattened image.

**Position isn't remembered**
Positions are stored in `UserDefaults` per display id. If you run via a
throwaway bundle id it may reset; running via `swift run` uses a stable domain.

## CI

**macOS job fails to build but Linux is fine**
The AppKit UI only compiles on macOS (it's `#if canImport(AppKit)` elsewhere), so
some errors surface only in the macOS job. Read the job log, fix, push. See
[HANDOFF.md](HANDOFF.md) for the known example (a cross-module `public` fix).

**Bridge job asset check fails**
Run `python3 scripts/verify_assets.py` locally; it reports exactly which check
(checksum / dimensions / alpha / lossless) failed.
