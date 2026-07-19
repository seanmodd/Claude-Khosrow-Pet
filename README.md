<div align="center">

<img src="docs/media/app-icon.png" alt="Khosrow" width="168" />

# Khosrow

**A regal Sasanian warrior‑king who lives on your macOS desktop — and reacts, in real time, to whatever Claude Code is doing.**

Native AppKit · transparent, borderless, always‑on‑top · **no Electron, no web view, no changes to Claude Desktop.**

[![CI](https://github.com/seanmodd/Claude-Khosrow-Pet/actions/workflows/ci.yml/badge.svg)](https://github.com/seanmodd/Claude-Khosrow-Pet/actions/workflows/ci.yml) &nbsp; ![macOS 12+](https://img.shields.io/badge/macOS-12%2B-000000?logo=apple&logoColor=white) &nbsp; ![Swift · AppKit](https://img.shields.io/badge/Swift-AppKit-F05138?logo=swift&logoColor=white) &nbsp; ![No Electron](https://img.shields.io/badge/no-Electron-1b1f23) &nbsp; ![Privacy first](https://img.shields.io/badge/privacy-first-2ea44f)

</div>

---

Khosrow is a tiny **desktop companion**. He idles, walks, works, cheers, bows, and sleeps — mirroring what Claude Code is doing through a privacy‑preserving hook bridge. He's rendered by a floating, transparent window that stays out of your way (and can be made click‑through so it never gets in it).

<div align="center">
<img src="docs/media/states/idle.gif" width="150" alt="idle">
<img src="docs/media/states/editing.gif" width="150" alt="editing">
<img src="docs/media/states/runningCommand.gif" width="150" alt="running a command">
<img src="docs/media/states/success.gif" width="150" alt="success">
</div>

---

## 🎬 His ten moods

> Every mood is a real animation pulled straight from Khosrow's sprite sheet — exactly what you see on your desktop. He switches automatically based on Claude Code activity, or you can pin any one by hand from the menu.

<table>
  <tr>
    <td align="center"><img src="docs/media/states/idle.gif" width="140"><br><b>idle</b><br><sub>resting</sub></td>
    <td align="center"><img src="docs/media/states/attentive.gif" width="140"><br><b>attentive</b><br><sub>listening</sub></td>
    <td align="center"><img src="docs/media/states/reading.gif" width="140"><br><b>reading</b><br><sub>reading a file</sub></td>
    <td align="center"><img src="docs/media/states/searching.gif" width="140"><br><b>searching</b><br><sub>scanning code</sub></td>
    <td align="center"><img src="docs/media/states/editing.gif" width="140"><br><b>editing</b><br><sub>editing files</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/media/states/runningCommand.gif" width="140"><br><b>runningCommand</b><br><sub>running a command</sub></td>
    <td align="center"><img src="docs/media/states/waitingForPermission.gif" width="140"><br><b>waitingForPermission</b><br><sub>awaiting you</sub></td>
    <td align="center"><img src="docs/media/states/success.gif" width="140"><br><b>success</b><br><sub>it worked!</sub></td>
    <td align="center"><img src="docs/media/states/failure.gif" width="140"><br><b>failure</b><br><sub>something broke</sub></td>
    <td align="center"><img src="docs/media/states/sleeping.gif" width="140"><br><b>sleeping</b><br><sub>session over</sub></td>
  </tr>
</table>

### What each mood means

| Mood | Animation | Khosrow shows it when… | Reads as |
|------|-----------|------------------------|----------|
| 🧍 **idle** | `idle` | nothing's happening, or a tool just finished cleanly | calm default |
| 🙌 **attentive** | `present` | you submit a prompt, a session starts, or Claude spins up a sub‑task | *"I'm listening."* |
| 📖 **reading** | `idle_guard` | Claude reads a file — `Read`, `NotebookRead` | focused standby |
| 🔎 **searching** | `walk_right` | Claude searches or browses — `Grep`, `Glob`, `LS`, `WebFetch`, `WebSearch` | scanning the codebase |
| ✍️ **editing** | `ready` | Claude edits or writes — `Edit`, `Write`, `MultiEdit`, `NotebookEdit`… | hands on the sword = working |
| 🏃 **runningCommand** | `run_left` | Claude runs a shell command — `Bash`, `BashOutput`… | literally *running* |
| ✋ **waitingForPermission** | `present` | a permission prompt or notification appears | *"awaiting your call."* |
| 🎉 **success** | `cheer` | a task finishes successfully (`Stop`) | arm‑raised triumph |
| 🙇 **failure** | `bow` | a tool/command errors, or a task ends in failure | head‑down apology |
| 😴 **sleeping** | `idle` · rotated flat · *dimmed* | the session ends (`SessionEnd`) | lies down on the ground and fades to rest |

<sub>Two moods deliberately share a pose — **attentive** and **waitingForPermission** both use the open‑armed *present* clip, and **sleeping** lays the *idle* pose flat on the ground (rotated 90°, slowed + dimmed) — because the source art has no dedicated frames for them. The full, tunable map lives in <a href="docs/ANIMATION-MAPPING.md">docs/ANIMATION-MAPPING.md</a>.</sub>

---

## ✅ What he can do &nbsp;·&nbsp; 🚫 what he can't (yet)

<table>
<tr><th width="50%">✅ &nbsp;Can</th><th width="50%">🚫 &nbsp;Can't (yet)</th></tr>
<tr>
<td valign="top">

- **Float** above every window — transparent & borderless
- **Drag** him anywhere; he stays where you drop him
- **Remembers his spot per display** (Retina + multi‑monitor aware)
- **Click‑through** mode — clicks pass to whatever's beneath
- **Reacts live** to Claude Code across **10 moods**
- **Menu‑bar control center** (the Faravahar glyph)
- **Scale 25% → 400%**, crisp at every size
- **Show on all Spaces** / over full‑screen apps
- **Animation Test Console** — preview every clip, verify transparency
- Runs **completely standalone** — hooks are optional
- **100% native AppKit** — no Electron, no web view, never touches Claude Desktop

</td>
<td valign="top">

- Runs on **macOS 12+** only (it's a native app)
- The optional double‑click `.app` is **unsigned** — first launch needs right‑click → **Open**; no notarization, App Store, or sandbox
- **Never reads your prompts, code, or output** — so he can show the *kind* of activity but not *what* you're doing (that's the privacy trade‑off, on purpose)
- Hooks are **opt‑in** and edit `~/.claude/settings.json` (auto‑backed‑up, fully reversible); you must **restart Claude Code** for them to load
- **One character**, no in‑app skin switcher — swap the art by regenerating the runtime assets
- No sound; doesn't auto‑launch at login (add it yourself if you'd like)

</td>
</tr>
</table>

---

## 🎛️ The Faravahar menu

<img src="docs/media/menubar-faravahar-highfidelity.png" align="right" height="46" alt="Faravahar menu-bar icon">

Every control lives behind the **Faravahar** glyph in your menu bar:

- **Pause / Resume** — freeze or resume the animation
- **Sleep / Wake** — curl up & dim, or return to idle
- **State ▸** — *Follow Claude Code*, or pin any of the 10 moods by hand
- **Click‑through** — let the mouse pass beneath him
- **Float on top** · **Show on all Spaces** — window‑behavior toggles
- **Scale ▸** — 25% … 400%
- **Animation Test Console…** — preview every clip, step frames, check the alpha cut‑out
- **Reset Position** — bring him home (a lifesaver on a multi‑display setup)
- **Quit Khosrow**

---

## 🚀 Quick start

```bash
git clone https://github.com/seanmodd/Claude-Khosrow-Pet.git
cd Claude-Khosrow-Pet/app
swift run KhosrowApp        # the Faravahar appears in the menu bar; Khosrow near the lower-right
```

**Make him react to Claude Code** (optional):

```bash
cd ../bridge
./install_hooks.sh --dry-run   # preview the exact settings merge — writes nothing
./install_hooks.sh             # timestamped backup + merge; then restart Claude Code
```

**See every mood without Claude Code:**

```bash
python3 bridge/simulate_states.py --cycle              # visit all 10 moods
python3 bridge/simulate_events.py --scenario session   # a scripted work session
```

Full walkthrough → **[INSTALL.md](INSTALL.md)** · on‑Mac visual checklist → **[docs/LOCAL-MAC-VERIFICATION.md](docs/LOCAL-MAC-VERIFICATION.md)**

---

## 🔒 Privacy, in one line

The bridge only ever writes this — and nothing else:

```json
{ "state": "editing", "toolCategory": "file-edit", "timestamp": "2026-07-18T03:54:27Z", "success": true }
```

No prompts, code, file paths, commands, or command output ever leave your machine. An adversarial redaction test stuffs a payload full of passwords, API keys, and SSH paths and proves none of it leaks. Details → **[PRIVACY.md](PRIVACY.md)** · **[docs/CLAUDE-HOOKS.md](docs/CLAUDE-HOOKS.md)**

---

## 🧩 Under the hood

| Layer | What it is |
|-------|------------|
| **UI** | Swift + AppKit — one borderless, transparent, floating window |
| **Core** | `KhosrowKit` — pure, cross‑platform logic (manifest, frame math, state map), unit‑tested |
| **Bridge** | stdlib‑only Python hooks → a minimal, non‑sensitive state file |
| **Art** | 1536×2288 sheet · 8×11 grid · **11 clips / 74 frames** |

```
app/       Swift package — KhosrowKit (logic) + KhosrowApp (AppKit UI) + tests
bridge/    Claude Code hook bridge, event/state simulators, safe installer
scripts/   deterministic asset tooling (Pillow)
docs/      inventory, schema, animation map, hooks, verification, media
```

Deeper reading → [ARCHITECTURE.md](ARCHITECTURE.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md) · [HANDOFF.md](HANDOFF.md)

---

## Attribution

The character art (`spritesheet.webp`), `pet.json`, and the app icon are the owner's own custom pet assets. The menu‑bar glyph is the **Faravahar**, an ancient Zoroastrian symbol. The application, bridge, and tooling in this repository are provided for use with those assets.

<div align="center"><sub><br>Built for macOS with Swift &amp; AppKit — and driven, fittingly, by Claude Code.</sub></div>
