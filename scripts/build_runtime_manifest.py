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
    ("attentive",            "present",     None,  False, "Arms open, engaged right after a prompt."),
    ("reading",              "idle_guard",  None,  False, "Calm, focused standby while reading files."),
    ("searching",            "walk_right",  None,  False, "Moves/scans while searching the codebase."),
    ("editing",              "ready",       None,  False, "Handling the sword = actively editing files."),
    ("runningCommand",       "run_left",    None,  False, "Literally running = executing a command."),
    ("waitingForPermission", "present",     9,     False, "Engaged, awaiting your input (shares 'present' with attentive; no dedicated pose)."),
    ("success",              "cheer",       None,  False, "Arm-raised triumph on success."),
    ("failure",              "bow",         None,  False, "Head-down bow reads as apology/defeat on failure."),
    ("sleeping",             "idle",        4,     False, "Tucks into a bed and sleeps: a drawn bed scene overlays the idle clip (the sheet has no dedicated sleep frames)."),
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
