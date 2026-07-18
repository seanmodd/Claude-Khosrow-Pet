# Local Mac Verification

**Why this doc exists:** the project was implemented in a Linux cloud
environment, which **cannot run or visually inspect an AppKit application**. The
logic, assets, and bridge are all automatically tested (see [HANDOFF.md](../HANDOFF.md)),
and the macOS app **compiles and its tests pass in CI on a macOS runner** — but
the *visual* look and window behavior have **not** been verified on screen.

This checklist is what to do on your Mac to confirm the on-screen behavior. None
of it is destructive.

## 0. Build & launch

```bash
cd app
swift run KhosrowApp
```

Expect a 🦁 in the menu bar and Khosrow near the lower-right of the main display.

## 1. Window & rendering ✅ / ❌

- [ ] The pet has **no title bar, border, or background box** — only the
      character is visible.
- [ ] The area around the character is **fully transparent** (you can see the
      desktop/other windows through it), with **clean anti-aliased edges** (no
      white/black halo).
- [ ] The pet **floats above** a normal window (put a Finder window in front —
      the pet stays on top when "Float on top" is on).
- [ ] On a **Retina** display the art is crisp, not blurry or pixel-doubled.

## 2. Interaction

- [ ] **Drag** the pet around; it follows the cursor and stays where you drop it.
- [ ] Menu 🦁 → **Click-through** ON: clicks now pass to the window beneath;
      the pet ignores the mouse. Toggle OFF to grab it again.
- [ ] Menu 🦁 → **Scale** → try 50% / 200%: the pet resizes and stays anchored
      at the bottom.
- [ ] Menu 🦁 → **Pause**: animation freezes; **Resume**: it continues.
- [ ] Menu 🦁 → **Sleep**: pet curls/dims; **Wake**: returns to idle.

## 3. Multi-monitor & Spaces (if applicable)

- [ ] Drag the pet to a **second display**; quit and relaunch — it returns to
      that display's remembered position.
- [ ] With **Show on all Spaces** on, switch Spaces / enter a full-screen app —
      the pet remains visible.

## 4. Every animation (test console)

Open 🦁 → **Animation Test Console…**:

- [ ] **State** dropdown: select each of the 10 states; the pet switches clips.
- [ ] **Direction** dropdown (front/left/right) filters clips; **Clip** dropdown
      selects one directly.
- [ ] **Next / Prev / Rewind** step frames; the info line shows
      `clip / row / col / frame / seq#` — cross-check against
      `artifacts/contact-sheet.png`.
- [ ] **Speed** and **Scale** sliders change playback and size live.
- [ ] **Checkerboard (verify alpha)** toggles the backdrop — confirm the sprite
      is cleanly cut out (transparency correct) against the checker.

## 5. Claude Code reactions

Without Claude Code:

```bash
python3 bridge/simulate_states.py --cycle          # visits all 10 states
python3 bridge/simulate_events.py --scenario session   # a scripted work session
```

- [ ] The pet visibly changes as each state/event is emitted.

With Claude Code (after `bridge/install_hooks.sh` and restarting Claude Code):

- [ ] Start a task; the pet shows `attentive` on prompt, `reading`/`searching`/
      `editing`/`runningCommand` as tools run, `waitingForPermission` on a
      permission prompt, and `success`/`sleeping` at the end.
- [ ] `cat ~/.claude-pet/state.json` updates in step, and contains **only**
      `state / toolCategory / timestamp / success`.

## 6. Report back

If anything in sections 1–4 looks wrong, it's almost always in the small,
clearly-delimited AppKit layer (`PetWindow`, `PetView`, `PetController`), because
all the frame math, timing, and mapping are unit-tested. Note which checkbox
failed and what you saw; the [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) guide
maps common symptoms to fixes.
