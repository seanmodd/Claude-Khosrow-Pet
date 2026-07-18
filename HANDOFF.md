# Handoff — Khosrow macOS desktop companion

Everything below reflects what was actually built, tested, and pushed. It is
deliberately explicit about what *is* verified and what still needs a Mac.

---

## 1. What was completed

| Phase | Deliverable | Status |
|-------|-------------|--------|
| 1 | Asset inspection + docs + labeled contact sheet + deterministic tooling | ✅ Done |
| 2 | Native macOS app (Swift/AppKit, no Electron) + manual test console | ✅ Done, compiles & tests pass in macOS CI |
| 3 | Privacy-preserving Claude Code hook bridge + simulators + safe installer | ✅ Done, unit-tested |
| 4 | GitHub Actions CI (macOS + Ubuntu) + asset-integrity gate | ✅ Done, **green** |
| 5 | Full documentation set + this handoff | ✅ Done |

**Constraints honored:** originals never modified (checksums enforced in CI);
runtime assets stored separately; separate native app (Claude Desktop untouched);
no Electron; no visual-verification claims; no real `~/.claude` modified from the
cloud; installer/uninstaller created but **not executed** here; the bridge
transmits only `{state, toolCategory, timestamp, success}`.

### Highlights

- **Assets:** `spritesheet.webp` is a single 1536×2288 RGBA image; the grid
  (**8×11, 192×208 cells, 11 clips, 74 frames**) was derived from the pixels
  because `pet.json` carries no animation metadata. A pixel-exact PNG runtime
  copy is generated for reliable macOS rendering; the original WebP is untouched.
- **App:** transparent borderless floating window; draggable; click-through;
  scale; pause/sleep; per-display position memory; multi-Space; Retina; menu-bar
  controls; and a full **Animation Test Console**.
- **Bridge:** maps 11 Claude Code events → 10 pet states, emitting the minimal
  payload via an atomic state file (default) and optional loopback HTTP.

---

## 2. Exact branch & commits

- **Branch:** `claude/khosrow-macos-app-lu36vm` (pushed to `origin`)
- **Commits (newest first):**

| SHA | Summary |
|-----|---------|
| `9128861` | Fix macOS build: make `ClosedRange.clamp` public |
| `2d44b68` | Phase 4: CI workflows + asset-integrity gate |
| `d066457` | Phase 3: Claude Code event bridge (privacy-preserving) |
| `20fbd3b` | Phase 2: native macOS Swift app (KhosrowKit + KhosrowApp) |
| `39cbef2` | Phase 1: asset inspection, analysis tooling, runtime derivation |

(A final docs commit adds the Phase 5 documentation; see the branch history for
its SHA.)

---

## 3. Test results

### Swift — `KhosrowKit` (macOS CI, run #2, commit `9128861`)

```
Executed 43 tests, with 0 failures      (arm64e-apple-macos, Swift 6.3.2)
```

Suites: ManifestDecoding (8), FrameGeometry (6), StateMapping (8),
AnimationPlayer (11), SettingsMerge (7), RuntimeAsset (3, incl. ImageIO
dimension + alpha checks).

> On Linux 41 of these run (the 2 ImageIO-only asset tests are macOS-only); on
> the macOS runner all 43 run.

### Python — bridge (`bridge/tests`)

```
Ran 23 tests ... OK
```

Includes an adversarial **redaction** test that stuffs a payload with passwords,
API keys, SSH paths, commands, and file contents and proves none leak.

### Asset integrity (`scripts/verify_assets.py`)

```
OK  original pet.json sha256 matches
OK  original spritesheet.webp sha256 matches
OK  runtime PNG dimensions (1536, 2288)
OK  runtime PNG alpha preserved (transparent=True, partial=True)
OK  runtime PNG is pixel-identical to the original WebP
```

---

## 4. CI results

Workflow: `.github/workflows/ci.yml` — **latest run: success** (both jobs green).

**macOS job (`macos-latest`)** — all steps ✅
`swift package resolve` → `swift build` → `swift test` (43 tests) →
`shasum -c` originals (`pet.json: OK`, `spritesheet.webp: OK`) →
sips check (`runtime PNG: 1536x2288 hasAlpha=yes`).

**Bridge job (`ubuntu-latest`)** — all steps ✅
23 Python tests → Pillow asset integrity → deterministic manifest re-derivation →
originals-untouched checksum guard.

---

## 5. Remaining limitations (honest)

1. **Not visually verified on macOS.** The cloud environment is Linux and cannot
   run/inspect an AppKit app. The app **compiles and its tests pass in macOS CI**,
   but the on-screen look and window behavior (transparency, float, drag,
   click-through, multi-monitor) have **not** been seen. Use
   [docs/LOCAL-MAC-VERIFICATION.md](docs/LOCAL-MAC-VERIFICATION.md).
2. **No `.app`/code signing.** Dev build runs via `swift run`; an optional
   unsigned `.app` recipe is in [INSTALL.md](INSTALL.md). No notarization.
3. **Animation names are inferred.** `pet.json` has no clip names; identities are
   inferred from the contact sheet and the Claude-state map is a tunable design
   choice ([docs/ANIMATION-MAPPING.md](docs/ANIMATION-MAPPING.md)). Two states
   reuse a clip (documented) since the sheet lacks dedicated poses.
4. **Hooks not installed here.** The installer was validated in a sandbox but
   never run against a real `~/.claude` (per constraints).

---

## 6. Exact steps on your Mac

### 6a. Prerequisites

```bash
xcode-select --install     # if needed; provides the Swift toolchain
swift --version            # expect 5.9+ (6.x fine)
```

### 6b. Get the code

```bash
git clone https://github.com/seanmodd/Claude-Khosrow-Pet.git
cd Claude-Khosrow-Pet
git checkout claude/khosrow-macos-app-lu36vm
```

### 6c. Launch & visually test Khosrow

```bash
cd app
swift run KhosrowApp
```

- A 🦁 appears in the menu bar; Khosrow appears near the lower-right of the main
  display.
- Work through [docs/LOCAL-MAC-VERIFICATION.md](docs/LOCAL-MAC-VERIFICATION.md):
  transparency, float-on-top, drag, click-through, scale, pause/sleep,
  multi-monitor, and the **Animation Test Console** (🦁 → *Animation Test
  Console…*).
- See every animation without Claude Code:
  ```bash
  python3 bridge/simulate_states.py --cycle
  ```

### 6d. Install the Claude Code hooks

```bash
cd bridge
./install_hooks.sh --dry-run    # preview the exact settings merge (writes nothing)
./install_hooks.sh              # install (timestamped backup + merge, never overwrite)
```

Then **restart Claude Code** so it reloads settings. Start a task and watch
Khosrow react. Verify the payload is minimal:

```bash
cat ~/.claude-pet/state.json
# -> {"state": "...", "toolCategory": "...", "timestamp": "...", "success": ...}
```

Exact settings changes: [docs/CLAUDE-HOOKS.md](docs/CLAUDE-HOOKS.md).
Privacy guarantees: [PRIVACY.md](PRIVACY.md).

### 6e. Uninstall

```bash
cd bridge
./uninstall_hooks.sh            # remove ONLY the pet hooks (backup first)
./uninstall_hooks.sh --purge    # also delete ~/.claude-pet (bridge + state)
```

Quit the app from 🦁 → **Quit Khosrow**.

---

## 7. If you want to change the animation ↔ state mapping

One editable place drives the app, tests, and simulators:

```bash
# edit the CLIPS / STATES tables:
$EDITOR scripts/build_runtime_manifest.py
python3 scripts/build_runtime_manifest.py     # regenerate khosrow.runtime.json
python3 scripts/verify_assets.py              # integrity gate
cd app && swift test                          # confirm still valid
```

---

## 8. File map

```
pet.json, spritesheet.webp        ORIGINALS (untouched)
app/                              Swift package (KhosrowKit + KhosrowApp + tests)
bridge/                          Python hook bridge, simulators, installer, tests
scripts/                         deterministic asset tooling + verify_assets.py
docs/                            inventory, schema, animation map, hooks, verify
artifacts/                       contact sheet, analysis, checksums
.github/workflows/ci.yml         macOS + Ubuntu CI
README, INSTALL, ARCHITECTURE, PRIVACY, TROUBLESHOOTING, HANDOFF
```
