#!/usr/bin/env python3
"""
build_runtime_manifest.py — Produce the project's runtime animation atlas.

The original pet.json (ChatGPT "spriteVersionNumber": 2) contains ONLY identity
fields (id, displayName, description, spriteVersionNumber, spritesheetPath). It
has NO grid, frame, fps, anchor, or animation-name data. This script combines:

  * pet.json                    (identity — used verbatim, never modified)
  * artifacts/atlas-analysis.json  (empirically-derived grid + per-cell facts)
  * the CLIP + STATE tables below  (this project's design decisions)

...into ONE machine-readable runtime manifest consumed by the Swift app, the
Swift tests, and the bridge simulators:

  app/Sources/KhosrowKit/Resources/khosrow.runtime.json

CLIP identities are inferred from visual inspection of the contact sheet and are
clearly marked as such. The STATE map (Claude Code state -> clip) is a tunable
UX decision, documented in docs/ANIMATION-MAPPING.md.
"""
from __future__ import annotations

import json
from pathlib import Path

# --- Clip table -------------------------------------------------------------
# One entry per spritesheet ROW. "identity" names are INFERRED from visually
# inspecting artifacts/contact-sheet.png (Phase 1). "facing" is derived from the
# character silhouette/pose. frame_count is authoritative (from pixel analysis).
#   loop mode: "loop" | "once" (play once, hold last frame)
CLIPS = [
    # row, id,            facing,  fps, loop,   description (visual)
    (0,  "idle",          "front",  6, "loop", "Neutral standing stance, sword sheathed; near-static breathing."),
    (1,  "walk_left",     "left",  12, "loop", "Striding walk cycle, body angled to the left."),
    (2,  "run_left",      "left",  14, "loop", "Energetic run cycle, long strides, to the left."),
    (3,  "cheer",         "front", 12, "once", "Right arm raised high in a wave / triumphant salute."),
    (4,  "crouch",        "front",  9, "once", "Lowers into a deep squat / crouch."),
    (5,  "bow",           "front", 10, "once", "Deep ceremonial bow, folding head and torso forward/down."),
    (6,  "present",       "front", 10, "loop", "Both arms open outward in a presenting / explaining gesture."),
    (7,  "idle_guard",    "front",  7, "loop", "Alert front stance holding the sword; calm standby."),
    (8,  "ready",         "front", 10, "loop", "Grips and handles the sword in front; 'working' posture."),
    (9,  "walk_right",    "right", 12, "loop", "Side-profile walk cycle facing right; scanning."),
    (10, "run_right",     "right", 14, "loop", "Side-profile run cycle facing right, head dipping."),
]

# --- State map --------------------------------------------------------------
# Claude Code normalized pet-state -> clip id. This is a DESIGN decision (tunable
# in one place). Where the sheet lacks a dedicated pose, a documented reuse is
# noted. "dim" lowers window opacity for low-energy states.
#   state,               clip,          override_fps, dim,   rationale
STATES = [
    ("idle",                 "idle",        None,  False, "Default resting stance."),
    ("attentive",            "present",     None,  False, "Engaged and attentive — Gemini illustrated pose (gemini-attentive, hand to chin); falls back to the open-armed 'present' clip if the still is absent."),
    ("writing",              "idle_guard",  None,  False, "Composing a response to your prompt — dedicated Gemini illustrated pose (gemini-writing, writing in an open book). No longer reuses the reading art; falls back to the calm idle_guard clip."),
    ("reading",              "idle_guard",  None,  False, "Reads an open book: bundled hand-drawn khosrow-reading-* frames (falls back to the calm idle_guard clip if absent)."),
    ("searching",            "walk_right",  None,  False, "Scanning the codebase — Gemini illustrated pose (gemini-searching, hand shading his eyes); falls back to the walk_right clip."),
    ("editing",              "ready",       None,  False, "Handling the sword = actively editing files."),
    ("runningCommand",       "run_left",    None,  False, "Executing a command — Gemini illustrated pose (gemini-running, on horseback at a gallop); falls back to the run_left clip."),
    ("waitingForPermission", "present",     9,     False, "Waiting for you — Gemini illustrated pose (gemini-waiting, checking his wrist); falls back to the 'present' clip."),
    ("praying",              "idle_guard",  None,  False, "Praying / reflecting — a first-class built-in mood with its own Gemini illustrated pose (gemini-praying, hands raised in reverence). It has NO automatic hook trigger by default; it is shown only when manually previewed or by a user-created rule. Falls back to the calm idle_guard clip if the still is absent."),
    ("success",              "cheer",       None,  False, "Raises his sword in triumph: bundled hand-drawn khosrow-success-* frames (falls back to the cheer clip if absent)."),
    ("failure",              "bow",         None,  False, "Head-down bow reads as apology/defeat on failure."),
    ("sleeping",             "idle",        4,     False, "Sleeps in a hand-drawn bed: bundled khosrow-sleeping-* frames (falls back to the idle clip if absent)."),
]

DEFAULT_STATE = "idle"


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    analysis = json.loads((root / "artifacts/atlas-analysis.json").read_text())
    pet = json.loads((root / "pet.json").read_text())

    grid = analysis["grid"]
    rows = {r["row"]: r for r in analysis["rows"]}

    clips = {}
    for row, cid, facing, fps, loop, desc in CLIPS:
        rinfo = rows[row]
        clips[cid] = {
            "id": cid,
            "row": row,
            "frameCount": rinfo["frame_count"],
            "facing": facing,
            "fps": fps,
            "loop": loop == "loop",
            "description": desc,
        }

    states = {}
    for sid, clip, ofps, dim, rationale in STATES:
        assert clip in clips, f"state {sid} -> unknown clip {clip}"
        states[sid] = {
            "state": sid,
            "clip": clip,
            "fpsOverride": ofps,
            "dim": dim,
            "rationale": rationale,
        }

    manifest = {
        "schemaVersion": 1,
        "generatedBy": "scripts/build_runtime_manifest.py",
        "note": (
            "Runtime atlas for the Khosrow macOS app. Grid + frameCounts are "
            "derived from pixels; clip identities are inferred from the contact "
            "sheet; the state map is a tunable UX decision. pet.json is the "
            "identity source of truth and is embedded verbatim below."
        ),
        # Identity copied verbatim from the ORIGINAL pet.json (never modified).
        "pet": {
            "id": pet.get("id"),
            "displayName": pet.get("displayName"),
            "description": pet.get("description"),
            "spriteVersionNumber": pet.get("spriteVersionNumber"),
            "spritesheetPath": pet.get("spritesheetPath"),
        },
        "sheet": {
            "originalWebP": "spritesheet.webp",
            "runtimePNG": "khosrow-spritesheet.png",
            "width": grid["sheet_w"],
            "height": grid["sheet_h"],
            "cols": grid["cols"],
            "rows": grid["rows"],
            "cellWidth": grid["cell_w"],
            "cellHeight": grid["cell_h"],
            # Content occupies y=5..202 within each 208px cell (feet baseline),
            # centered horizontally. Full-cell cropping preserves anchoring.
            "contentTopPad": 5,
            "contentBottomPad": 5,
            "anchor": "bottom-center",
        },
        "defaultState": DEFAULT_STATE,
        "clips": clips,
        "states": states,
    }

    out = root / "app/Sources/KhosrowKit/Resources/khosrow.runtime.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Wrote {out.relative_to(root)}")
    print(f"Clips: {len(clips)}  States: {len(states)}  "
          f"Total frames: {sum(c['frameCount'] for c in clips.values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
