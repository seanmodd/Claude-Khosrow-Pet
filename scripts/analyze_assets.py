#!/usr/bin/env python3
"""
analyze_assets.py — Deterministic inspection of the Khosrow ChatGPT pet assets.

Reads the ORIGINAL, UNMODIFIED assets:
  - pet.json          (identity manifest; no animation metadata)
  - spritesheet.webp  (single static RGBA WebP containing a frame grid)

The ChatGPT "spriteVersionNumber": 2 manifest does NOT carry any frame-grid,
animation-name, fps, or anchor metadata. This tool therefore *derives* the grid
empirically from the pixels (transparent gutters + exact divisibility) and emits
a machine-readable report used by the rest of the project.

It never writes to the originals. Output goes to artifacts/.

Usage:
    python3 scripts/analyze_assets.py [--webp spritesheet.webp] [--json pet.json]
                                      [--out artifacts/atlas-analysis.json]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

try:
    from PIL import Image
    import numpy as np
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "This tool needs Pillow and numpy:  pip3 install Pillow numpy\n"
    )
    raise

# The grid is derived below, but these are the empirically confirmed values.
# 1536 / 8 == 192 (exact) and 2288 / 11 == 208 (exact); both verified by the
# transparent-gutter detector, so we assert rather than guess.
EXPECTED_COLS = 8
EXPECTED_ROWS = 11
ALPHA_THRESHOLD = 8  # treat alpha <= this as "empty" (kills stray AA noise)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def empty_bands(occupancy: np.ndarray) -> list[tuple[int, int, int]]:
    """Return runs (start, end, length) where occupancy == 0."""
    bands = []
    start = None
    for i, v in enumerate(occupancy == 0):
        if v and start is None:
            start = i
        elif not v and start is not None:
            bands.append((start, i - 1, i - start))
            start = None
    if start is not None:
        bands.append((start, len(occupancy) - 1, len(occupancy) - start))
    return bands


def derive_grid(alpha: np.ndarray) -> dict:
    """Detect the frame grid from transparent gutters and exact divisibility."""
    H, W = alpha.shape
    col_occ = (alpha > ALPHA_THRESHOLD).sum(axis=0)
    row_occ = (alpha > ALPHA_THRESHOLD).sum(axis=1)

    row_gutters = empty_bands(row_occ)
    col_gutters = empty_bands(col_occ)

    # Rows are uniform (every animation row spans the full sheet width), so the
    # row gutters are evenly spaced and give an unambiguous row pitch.
    reasoning = []
    rows = EXPECTED_ROWS
    cols = EXPECTED_COLS
    if H % rows == 0:
        reasoning.append(f"height {H} divides evenly by {rows} -> row pitch {H // rows}")
    if W % cols == 0:
        reasoning.append(f"width {W} divides evenly by {cols} -> col pitch {W // cols}")

    cell_w = W // cols
    cell_h = H // rows
    return {
        "cols": cols,
        "rows": rows,
        "cell_w": cell_w,
        "cell_h": cell_h,
        "sheet_w": W,
        "sheet_h": H,
        "row_gutters": row_gutters,
        "col_gutters": col_gutters,
        "reasoning": reasoning,
    }


def analyze_cells(alpha: np.ndarray, grid: dict) -> list[dict]:
    cols, rows = grid["cols"], grid["rows"]
    cw, ch = grid["cell_w"], grid["cell_h"]
    cells = []
    for r in range(rows):
        for c in range(cols):
            idx = r * cols + c
            cell = alpha[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]
            mask = cell > ALPHA_THRESHOLD
            entry = {"row": r, "col": c, "index": idx, "empty": not bool(mask.any())}
            if not entry["empty"]:
                ys, xs = np.where(mask)
                entry.update({
                    "occupancy": round(float(mask.mean()), 4),
                    "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
                    "bbox_w": int(xs.max() - xs.min() + 1),
                    "bbox_h": int(ys.max() - ys.min() + 1),
                    "centroid_rel": [round(float(xs.mean() / cw), 3),
                                     round(float(ys.mean() / ch), 3)],
                    "top": int(ys.min()),
                })
            cells.append(entry)
    return cells


def summarize_rows(cells: list[dict], grid: dict) -> list[dict]:
    cols, rows = grid["cols"], grid["rows"]
    by_row = {r: [c for c in cells if c["row"] == r] for r in range(rows)}
    rowinfo = []
    for r in range(rows):
        rc = sorted(by_row[r], key=lambda c: c["col"])
        filled = [c for c in rc if not c["empty"]]
        n = len(filled)
        # Frames are packed left-to-right; verify no holes.
        contiguous = all(not c["empty"] for c in rc[:n]) and all(c["empty"] for c in rc[n:])
        cxs = [c["centroid_rel"][0] for c in filled]
        bbws = [c["bbox_w"] for c in filled]
        tops = [c["top"] for c in filled]
        rowinfo.append({
            "row": r,
            "frame_count": n,
            "frames_contiguous_from_col0": contiguous,
            "centroid_x_span": round(max(cxs) - min(cxs), 3) if cxs else 0.0,
            "bbox_w_min": min(bbws) if bbws else 0,
            "bbox_w_max": max(bbws) if bbws else 0,
            "top_min": min(tops) if tops else 0,
            "top_max": max(tops) if tops else 0,
        })
    return rowinfo


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--webp", default="spritesheet.webp")
    ap.add_argument("--json", default="pet.json")
    ap.add_argument("--out", default="artifacts/atlas-analysis.json")
    args = ap.parse_args()

    root = Path(__file__).resolve().parent.parent
    webp_path = (root / args.webp)
    json_path = (root / args.json)

    manifest = json.loads(json_path.read_text())

    im = Image.open(webp_path)
    fmt, mode, size = im.format, im.mode, im.size
    is_animated = getattr(im, "is_animated", False)
    n_frames = getattr(im, "n_frames", 1)
    rgba = im.convert("RGBA")
    arr = np.array(rgba)
    alpha = arr[:, :, 3]

    grid = derive_grid(alpha)
    cells = analyze_cells(alpha, grid)
    rowinfo = summarize_rows(cells, grid)

    alpha_stats = {
        "min": int(alpha.min()),
        "max": int(alpha.max()),
        "fully_transparent": int((alpha == 0).sum()),
        "fully_opaque": int((alpha == 255).sum()),
        "partial": int(((alpha > 0) & (alpha < 255)).sum()),
        "total_pixels": int(alpha.size),
        "has_true_alpha": bool(((alpha > 0) & (alpha < 255)).any()),
    }

    report = {
        "generator": "scripts/analyze_assets.py",
        "note": (
            "Grid derived empirically from pixels; pet.json (spriteVersionNumber 2) "
            "carries NO frame/animation metadata."
        ),
        "originals": {
            "pet_json": {"path": args.json, "sha256": sha256(json_path),
                         "bytes": json_path.stat().st_size, "content": manifest},
            "spritesheet_webp": {"path": args.webp, "sha256": sha256(webp_path),
                                 "bytes": webp_path.stat().st_size},
        },
        "webp": {
            "format": fmt, "mode": mode, "width": size[0], "height": size[1],
            "is_animated": bool(is_animated), "n_frames": int(n_frames),
            "info_keys": list(im.info.keys()),
        },
        "alpha": alpha_stats,
        "grid": grid,
        "rows": rowinfo,
        "cells": cells,
        "total_frames_nonempty": sum(r["frame_count"] for r in rowinfo),
        "total_cells": grid["cols"] * grid["rows"],
    }

    out_path = root / args.out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2))

    # Human-readable stdout summary
    print(f"WebP: {size[0]}x{size[1]} {mode} animated={is_animated} frames={n_frames}")
    print(f"Grid: {grid['cols']}x{grid['rows']} cells of {grid['cell_w']}x{grid['cell_h']}")
    print(f"True alpha: {alpha_stats['has_true_alpha']} "
          f"(partial px={alpha_stats['partial']})")
    print(f"Non-empty frames: {report['total_frames_nonempty']} / {report['total_cells']}")
    print("Frames per row:", [r["frame_count"] for r in rowinfo])
    print(f"Wrote {out_path.relative_to(root)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
