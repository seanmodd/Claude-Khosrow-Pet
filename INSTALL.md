# Installing Khosrow

Two independent pieces:

1. **The app** — the floating desktop pet (build & run with Swift).
2. **The hooks** *(optional)* — makes the pet react to Claude Code.

You can use the app on its own; the hooks just add live reactions.

---

## 0. Requirements

- macOS 12 (Monterey) or newer
- Xcode 14+ **or** the Xcode Command Line Tools (for the Swift toolchain)
  ```bash
  xcode-select --install     # if you don't have Xcode
  swift --version            # should print Swift 5.9+ (6.x is fine)
  ```
- Python 3.9+ (preinstalled on macOS) — only needed for the hooks
- No code signing or Apple Developer account required for a local dev build.

---

## 1. Build & run the app

```bash
git clone https://github.com/seanmodd/Claude-Khosrow-Pet.git
cd Claude-Khosrow-Pet/app
swift run KhosrowApp
```

A 🦁 appears in the menu bar and Khosrow appears near the lower-right of your
main display. Drag him anywhere. Open the menu-bar 🦁 for all controls.

### Build a reusable `.app` bundle (optional)

`swift run` is fine for daily use, but you can wrap the binary in a double-click
`.app`:

```bash
cd Claude-Khosrow-Pet/app
swift build -c release
APP="Khosrow.app/Contents/MacOS"
mkdir -p "$APP" "Khosrow.app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/KhosrowApp" "$APP/Khosrow"
# Bundle the KhosrowKit resource bundle next to the binary:
cp -R "$(swift build -c release --show-bin-path)/Khosrow_KhosrowKit.bundle" "$APP/"
# App icon (Khosrow's face) — shown in Finder / Dock / Cmd-Tab:
cp AppIcon.icns "Khosrow.app/Contents/Resources/AppIcon.icns"
cat > Khosrow.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Khosrow</string>
  <key>CFBundleIdentifier</key><string>local.khosrow.pet</string>
  <key>CFBundleExecutable</key><string>Khosrow</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict></plist>
PLIST
open Khosrow.app
```

> `LSUIElement=true` makes it a menu-bar-only app (no Dock icon), matching the
> `swift run` behavior. The exact bundle name for `Khosrow_KhosrowKit.bundle`
> may vary by toolchain — check the `--show-bin-path` directory for the
> `*_KhosrowKit.bundle`.

---

## 2. Install the Claude Code hooks (optional)

This makes the pet react to what Claude Code is doing. The installer **merges**
into your existing `~/.claude/settings.json` (it never overwrites) and writes a
timestamped backup first.

```bash
cd Claude-Khosrow-Pet/bridge

# Preview exactly what will change — writes NOTHING:
./install_hooks.sh --dry-run

# Install for real:
./install_hooks.sh
```

What it does:

1. Copies the bridge to `~/.claude-pet/bridge/`.
2. Backs up `~/.claude/settings.json` → `settings.json.khosrow-backup-<timestamp>`.
3. Adds ten hook entries (all tagged `KHOSROW_PET_HOOK`) that write the pet's
   state to `~/.claude-pet/state.json` — including the dedicated
   `PostToolUseFailure` (→ `failure`) and `PermissionRequest`
   (→ `waitingForPermission`) events.

Restart any running Claude Code sessions so the new hooks load. Now start a
Claude Code task and watch Khosrow read, search, edit, and run commands.

See **[docs/CLAUDE-HOOKS.md](docs/CLAUDE-HOOKS.md)** for the exact settings diff
and **[PRIVACY.md](PRIVACY.md)** for what is (and isn't) transmitted.

---

## 3. Try it without Claude Code

```bash
cd Claude-Khosrow-Pet/bridge
python3 simulate_states.py --cycle          # visit every state
python3 simulate_events.py --scenario session   # a scripted work session
```

Both write to the same `~/.claude-pet/state.json` the real hooks use, so the
running app reacts immediately.

---

## 4. Uninstall

```bash
cd Claude-Khosrow-Pet/bridge
./uninstall_hooks.sh            # removes ONLY the pet hooks (backup first)
./uninstall_hooks.sh --purge    # also delete ~/.claude-pet entirely
```

Then quit the app from the menu-bar 🦁 → **Quit Khosrow**. Nothing else is left
behind (preferences live in `defaults` under `khosrow.*`; remove with
`defaults delete local.khosrow.pet` if you made a bundle, or they're harmless).

---

## Reproducing the runtime assets (maintainers)

The committed runtime PNG + atlas are derived from the originals. To regenerate:

```bash
pip3 install Pillow numpy
python3 scripts/analyze_assets.py
python3 scripts/convert_spritesheet.py
python3 scripts/build_runtime_manifest.py
python3 scripts/make_contact_sheet.py
python3 scripts/verify_assets.py        # integrity gate
```
