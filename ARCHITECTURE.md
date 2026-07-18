# Architecture

Khosrow is split into three cooperating pieces, each independently testable:

```
   Claude Code                    Bridge (Python)                 App (Swift)
 ┌──────────────┐   hook JSON   ┌──────────────────┐   minimal   ┌───────────────┐
 │  lifecycle   │──────────────▶│ redact → map →   │──────JSON──▶│  BridgeClient │
 │  hook events │   (stdin)     │ emit (file/HTTP) │  {state,…}  │      ↓        │
 └──────────────┘               └──────────────────┘             │ PetController │
                                        │                        │      ↓        │
                            ~/.claude-pet/state.json             │  PetView (⍺)  │
                                                                 └───────────────┘
```

The **only** thing that crosses the bridge boundary is
`{state, toolCategory, timestamp, success}` — see [PRIVACY.md](PRIVACY.md).

---

## 1. Assets & derivation (deterministic, offline)

The originals carry no animation metadata, so a small Python pipeline derives
everything and writes **separate** runtime files (originals stay byte-identical):

| Script | Input | Output |
|--------|-------|--------|
| `analyze_assets.py` | `spritesheet.webp` | `artifacts/atlas-analysis.json` (grid, per-cell facts) |
| `make_contact_sheet.py` | `spritesheet.webp` | `artifacts/contact-sheet.png` (labeled) |
| `convert_spritesheet.py` | `spritesheet.webp` | `…/Resources/khosrow-spritesheet.png` (pixel-exact PNG) |
| `build_runtime_manifest.py` | analysis + `pet.json` | `…/Resources/khosrow.runtime.json` (atlas) |
| `verify_assets.py` | all | integrity gate (checksums, dims, alpha, lossless) |

The grid (8×11, 192×208) is recovered from transparent gutters + exact
divisibility; clip identities are inferred from the contact sheet; the
Claude-state map is a tunable table. See [docs/ASSET-INVENTORY.md](docs/ASSET-INVENTORY.md)
and [docs/ANIMATION-MAPPING.md](docs/ANIMATION-MAPPING.md).

---

## 2. `KhosrowKit` — pure, portable core (no AppKit)

Foundation-only so it compiles and unit-tests on Linux *and* macOS. This is
where the logic — and the tests — live.

| File | Responsibility |
|------|----------------|
| `PetManifest.swift` | Decode the original `pet.json` (identity). |
| `RuntimeManifest.swift` | Decode the derived atlas; resolve state→clip, fps, validation. |
| `FrameGeometry.swift` | Pure pixel-rect math: `rect(clipRow:frameIndex:)`. |
| `AnimationPlayer.swift` | Time-based playback state machine (loop/once, manual step). |
| `PetState.swift` | The closed set of 10 states + lenient parsing; `ToolCategory`. |
| `StateMapper.swift` | `(event, category, success) → PetState` (mirror of the Python map). |
| `Preferences.swift` | Prefs model (+ clamping) and `SavedPosition`. |
| `JSONValue.swift` | Minimal JSON value type + deep merge. |
| `ClaudeSettings.swift` | Idempotent hook install/remove on a settings tree. |
| `PetBridgeState.swift` | The minimal, non-sensitive bridge payload. |
| `KhosrowResources.swift` | `Bundle.module` access to the runtime PNG + atlas. |

**Why a separate runtime manifest?** `pet.json` is identity-only. Rather than
mutate the original or hard-code a grid, the app reads an additive
`khosrow.runtime.json` that embeds the `pet.json` fields verbatim and adds the
derived animation layer. One editable table (`build_runtime_manifest.py`) is the
single source of truth for clips, fps, and the state map.

---

## 3. `KhosrowApp` — AppKit UI (macOS only)

Every file is wrapped in `#if canImport(AppKit)` so the package still builds on
Linux (the UI compiles to a no-op there; the real compile happens in macOS CI).

| File | Responsibility |
|------|----------------|
| `main.swift` | `NSApplication` bootstrap. |
| `AppController.swift` | App delegate; menu-bar (`NSStatusItem`) controls; wires bridge, prefs, window, dragging. |
| `PetWindow.swift` | Borderless, transparent, non-opaque, shadowless, floating, multi-Space, click-through `NSWindow`. |
| `PetView.swift` | Layer-backed view: sets `layer.contents` to a cropped `CGImage`; precise window dragging; dim/opacity. |
| `SpriteSheet.swift` | Loads the PNG via ImageIO; crops & caches per-frame `CGImage`s; verifies dimensions + alpha. |
| `PetController.swift` | 60 Hz display timer → `AnimationPlayer.advance(dt)`; applies states (clip/fps/dim); manual controls. |
| `PreferencesStore.swift` | `UserDefaults` persistence; per-display position memory (`NSScreenNumber`). |
| `BridgeClient.swift` | Reads state: polls `state.json` (always) + optional loopback HTTP listener. |
| `TestConsoleWindowController.swift` | Manual test mode: play/pause, step, speed, scale, state/direction select, checkerboard alpha check. |

### Rendering & anchoring

Every frame is a full 192×208 cell drawn at a fixed **bottom-center** anchor.
Because the character's feet sit at y ≈ 202 in every cell, no per-frame offset
table is needed. `CGImage.cropping(to:)` uses top-left pixel space, matching
`FrameGeometry.PixelRect` exactly. Retina is handled by AppKit: the PNG is
treated as the backing store and scaled by the window's points→pixels factor and
the user's scale preference; `CALayer` does the filtering.

### Timing

`PetController` runs a 60 Hz `Timer` and advances the player by the **measured**
`CACurrentMediaTime()` delta (× speed multiplier), so animation speed stays
correct under timer jitter. Each clip carries its own fps; states may override
it (e.g. `sleeping` at 4 fps, dimmed).

---

## 4. The bridge (Python, stdlib only)

| File | Responsibility |
|------|----------------|
| `khosrow_pet/core.py` | `map_state`, `categorize`, `redact` (coarse triple only), atomic file + HTTP emit. |
| `khosrow_pet/settings_merge.py` | Deep merge + idempotent hook install/remove; timestamped backup; atomic write. |
| `khosrow_pet_hook.py` | Hook entry: parse stdin defensively, redact, map, emit; **always exit 0**. |
| `simulate_events.py` / `simulate_states.py` | Feed synthetic events / cycle states. |
| `install_hooks.sh` / `uninstall_hooks.sh` | Safe, macOS-guarded, merge-not-overwrite. |

**Transport.** Preferred low-latency path is a loopback HTTP POST to the app's
`127.0.0.1:51763` listener; the always-available fallback is an atomically
written `~/.claude-pet/state.json` the app polls. Both converge on the same
`PetBridgeState` and the same handler. Short-lived hook processes make the file
path the robust default; HTTP is best-effort.

**Robustness.** The hook must never break Claude Code, so it swallows every error
and exits 0, reads stdin defensively, and blocks on nothing (HTTP has a 0.3 s
timeout, failures ignored).

---

## 5. Testing & CI

- `KhosrowKitTests` (41 tests): manifest decoding, frame coordinates, state
  mapping, settings merge, animation player, runtime-asset dims/alpha (ImageIO).
- `bridge/tests` (23 tests): state map, settings merge, and an adversarial
  **redaction** test proving no sensitive substring can leak.
- `.github/workflows/ci.yml`: a **macOS** job (build + Swift tests + checksum +
  sips alpha/dim check) and an **ubuntu** job (Python tests + Pillow asset
  integrity + deterministic re-derivation). See [HANDOFF.md](HANDOFF.md).

---

## Key design decisions

1. **Never touch the originals.** All runtime needs are derived into separate
   files; CI enforces the original checksums.
2. **WebP → PNG at build-derivation time**, not runtime — reliable on macOS 12+
   and pixel-identical, so alpha and geometry are guaranteed.
3. **Pure core, thin UI.** All logic that *can* be tested without a screen lives
   in `KhosrowKit`, so the untestable surface (actual window compositing) is
   minimal and clearly delimited.
4. **Minimal, one-way bridge payload.** The pet learns *what kind* of thing is
   happening, never *what* is being read/edited/run.
