# Khosrow — a native macOS desktop companion

Khosrow is a small **native macOS** desktop pet: a regal Sasanian-inspired
warrior king who idles, walks, works, and reacts to what **Claude Code** is
doing — reading, searching, editing, running commands, waiting for permission,
succeeding, failing, and sleeping.

He is built from the two ChatGPT custom-pet assets in this repository
(`pet.json` + `spritesheet.webp`), rendered by a floating, transparent AppKit
window. **No Electron. No web view. No Claude Desktop modification.**

> The original `pet.json` and `spritesheet.webp` are preserved byte-for-byte and
> never modified. Everything the app needs is derived into *separate* runtime
> files. This is enforced by CI (`shasum -c` on locked checksums).

|  |  |
|---|---|
| **UI** | Swift + AppKit, borderless transparent floating window |
| **Core** | `KhosrowKit` — pure, cross-platform, 41 unit tests |
| **Bridge** | stdlib-only Python hooks → minimal, non-sensitive state |
| **Assets** | 1536×2288 RGBA sheet, 8×11 grid, 11 clips / 74 frames |
| **Targets** | macOS 12+ (no code signing required for dev builds) |

## What it does

- Floats above your other windows, transparent and borderless, draggable
  anywhere, with an optional **click-through** mode so it never gets in the way.
- Lives in the **menu bar** (🦁) with controls for pause/sleep, scale,
  click-through, float, multi-Space, manual state, and a test console.
- Reflects **Claude Code activity** in real time via a privacy-preserving hook
  bridge — mapping events to ten animated states.
- Remembers its position **per display** and supports Retina and multiple
  monitors.

## Repository layout

```
pet.json                     ← ORIGINAL identity manifest (untouched)
spritesheet.webp             ← ORIGINAL sprite sheet (untouched)
app/                         ← Swift Package (KhosrowKit library + KhosrowApp)
  Sources/KhosrowKit/        ← pure logic + runtime assets (PNG + atlas JSON)
  Sources/KhosrowApp/        ← AppKit UI
  Tests/KhosrowKitTests/     ← 41 tests
bridge/                      ← Claude Code hook bridge (Python, stdlib only)
  khosrow_pet/               ← core mapping + settings merge
  *.sh, simulate_*.py        ← safe installer/uninstaller + simulators
  tests/                     ← 23 bridge tests (incl. privacy/redaction)
scripts/                     ← deterministic asset tooling (Python + Pillow)
docs/                        ← inventory, schema, animation map, hooks, verify
artifacts/                   ← contact sheet, analysis, checksums
.github/workflows/ci.yml     ← macOS build/test + asset integrity
```

## Quick start (on a Mac)

```bash
# 1. Build & run the pet
cd app
swift run KhosrowApp        # 🦁 appears in the menu bar

# 2. (optional) Install the Claude Code hooks
cd ../bridge
./install_hooks.sh          # merges hooks into ~/.claude/settings.json (backed up)

# 3. See every animation without Claude Code
python3 simulate_states.py --cycle
```

Full, step-by-step instructions are in **[INSTALL.md](INSTALL.md)** and
**[HANDOFF.md](HANDOFF.md)**.

## Documentation

| Doc | What's in it |
|-----|--------------|
| [INSTALL.md](INSTALL.md) | Build, run, install hooks, uninstall |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Modules, data flow, design decisions |
| [PRIVACY.md](PRIVACY.md) | Exactly what the bridge does and does not send |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and fixes |
| [HANDOFF.md](HANDOFF.md) | Everything done + exact Mac steps + limitations |
| [docs/ASSET-INVENTORY.md](docs/ASSET-INVENTORY.md) | Measured facts about the assets |
| [docs/PET-JSON-SCHEMA.md](docs/PET-JSON-SCHEMA.md) | Full `pet.json` schema |
| [docs/ANIMATION-MAPPING.md](docs/ANIMATION-MAPPING.md) | Clips + Claude-state map |
| [docs/CLAUDE-HOOKS.md](docs/CLAUDE-HOOKS.md) | Hook events, payload, settings changes |
| [docs/LOCAL-MAC-VERIFICATION.md](docs/LOCAL-MAC-VERIFICATION.md) | How to visually verify on your Mac |

## Status & honesty note

This project was implemented and tested in a **Linux cloud environment**, which
**cannot run or visually inspect an AppKit app**. Therefore:

- ✅ `KhosrowKit` (manifest decode, frame math, playback, state map, settings
  merge) is **built and unit-tested** (41 tests).
- ✅ The Python bridge is **built and unit-tested** (23 tests, incl. redaction).
- ✅ Assets are inspected, converted losslessly, and integrity-checked.
- ✅ The macOS app **compiles and its tests run in CI on a macOS runner**.
- ⏳ The floating-window **look and behavior have NOT been visually verified** —
  that requires a Mac. See [docs/LOCAL-MAC-VERIFICATION.md](docs/LOCAL-MAC-VERIFICATION.md).

## License / attribution

The character art (`spritesheet.webp`) and `pet.json` are the user's own ChatGPT
custom-pet assets. The application code, bridge, and tooling in this repository
are provided for the user's own use with these assets.
