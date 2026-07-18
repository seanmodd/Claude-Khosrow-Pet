# Asset Inventory — Khosrow Pet

This document records the results of inspecting the two **original, unmodified**
assets shipped in this repository. All numbers here were produced
deterministically by `scripts/analyze_assets.py` (report:
`artifacts/atlas-analysis.json`) and confirmed by visual inspection of
`artifacts/contact-sheet.png`.

> **Originals are never modified.** Everything the app needs at runtime is
> derived into *separate* files under `artifacts/` and
> `app/Sources/KhosrowApp/Resources/`.

## 1. Original files

| File | Bytes | SHA-256 |
|------|-------|---------|
| `pet.json` | 253 | `e62d3eda10ff3104212797c7539200c4531a333ee5e9b80a0d675fba1e78dfee` |
| `spritesheet.webp` | 1,973,054 | `bc19c4a1a1579ce5993d360b6fcca85f4feaf6db2270352bfa5f7d02f229ff47` |

These checksums are treated as an integrity contract and are re-verified in CI
(`.github/workflows/macos-ci.yml`) so that no build step can silently mutate an
original.

## 2. `spritesheet.webp` — pixel facts

| Property | Value |
|----------|-------|
| Container | RIFF / WebP |
| Pixel dimensions | **1536 × 2288** (W × H) |
| Color mode | **RGBA** (8 bits/channel) |
| Animated? | **No** — single static image (`n_frames = 1`, `is_animated = false`) |
| Alpha channel | **Yes, true alpha** (values span the full 0–255 range) |

### Alpha breakdown (of 3,514,368 pixels)

| Category | Pixels | Fraction |
|----------|--------|----------|
| Fully transparent (α = 0) | 2,818,443 | 80.2% |
| Fully opaque (α = 255) | 524,571 | 14.9% |
| Partial (0 < α < 255) | 171,354 | 4.9% |

The large partial-alpha population is anti-aliased character edges — it confirms
the sheet has genuine soft transparency, so any renderer **must** composite with
premultiplied/straight alpha correctly (no color-key / no flatten-to-white).

> **WebP is one static image, not an animated WebP.** The "animation" is the
> classic sprite-sheet layout: many frames tiled in a grid inside a single
> image. `info` keys (`loop`, `background`, `timestamp`, `duration`) are default
> single-frame values and carry **no** usable per-frame timing.

## 3. Frame grid (derived, not declared)

`pet.json` declares **no** grid. The grid was recovered from the pixels two
independent ways that agree exactly:

1. **Transparent gutters.** Row occupancy (non-transparent pixels per scan-line)
   is zero in 11 evenly-spaced 10-px bands — a clean, regular vertical rhythm.
2. **Exact divisibility.** `2288 / 11 = 208` and `1536 / 8 = 192`, both exact
   integers.

| Property | Value |
|----------|-------|
| Columns | **8** |
| Rows | **11** |
| Total cells | **88** |
| Cell size | **192 × 208** px |
| Column pitch | 192 px (no horizontal padding between columns) |
| Row pitch | 208 px |
| Within-cell content band | y = 5 … 202 (≈198 px tall) |
| Transparent padding per cell | 5 px top + 5 px bottom (→ 10 px inter-row gutter) |
| Anchor (all frames) | **bottom-center** — feet sit at y ≈ 202 in every cell |

Because the feet baseline (y ≈ 202) and horizontal center (≈ 0.5) are consistent
across every cell, the renderer can **crop full 192 × 208 cells and draw them at
one fixed anchor** — no per-frame offset table is required. The character's
bounding box varies per pose (thin side-profiles vs. wide action poses) but
always stays inside its cell.

## 4. Animation rows (frame counts)

Each **row is one animation clip**; frames are packed left-to-right and unused
trailing cells are fully transparent. Verified contiguous (no interior holes).

| Row | Y-offset | Frames | Filled columns | Inferred clip | Facing |
|-----|----------|--------|----------------|---------------|--------|
| 0 | 0 | 7 | 0–6 | `idle` | front |
| 1 | 208 | 8 | 0–7 | `walk_left` | left |
| 2 | 416 | 8 | 0–7 | `run_left` | left |
| 3 | 624 | 4 | 0–3 | `cheer` | front |
| 4 | 832 | 5 | 0–4 | `crouch` | front |
| 5 | 1040 | 8 | 0–7 | `bow` | front |
| 6 | 1248 | 6 | 0–5 | `present` | front |
| 7 | 1456 | 6 | 0–5 | `idle_guard` | front |
| 8 | 1664 | 6 | 0–5 | `ready` | front |
| 9 | 1872 | 8 | 0–7 | `walk_right` | right |
| 10 | 2080 | 8 | 0–7 | `run_right` | right |

**Total real frames: 74** of 88 cells (14 trailing cells are intentionally
empty).

Clip *identities* (the names in the table) are **inferred from visual
inspection** of the labeled contact sheet, not declared by `pet.json`. See
`docs/ANIMATION-MAPPING.md` for the evidence behind each name and the
confidence level. Frame *counts*, grid, and geometry are measured facts.

## 5. Directional / state content

Visual inspection confirms the sheet encodes:

- **Direction:** front-facing (rows 0, 3–8), left-facing (rows 1–2), and
  right-facing side-profiles (rows 9–10).
- **Idle vs. motion:** row 0 is near-static (0.2% inter-frame pixel change —
  breathing idle); rows 1–2 and 9–10 are locomotion cycles; rows 3–6 are
  discrete gestures (raise arm, crouch, bow, present).
- **Signature action:** row 5 (`bow`) folds the figure forward so its bounding
  box widens from 67 px to 182 px — the most dramatic pose change on the sheet.

## 6. Conversion requirement

`NSImage`/ImageIO decode WebP reliably only on **macOS 14+**. To support an
earlier deployment target (macOS 12+) and to guarantee identical pixels on every
machine, the app ships a **PNG runtime copy**, produced by
`scripts/convert_spritesheet.py`:

| Runtime asset | Size | Mode | Notes |
|---------------|------|------|-------|
| `app/Sources/KhosrowApp/Resources/khosrow-spritesheet.png` | 1536 × 2288 | RGBA | Lossless, **pixel-identical** to source (round-trip verified), alpha preserved |

The original `spritesheet.webp` is read-only input to this process and is left
byte-for-byte unchanged (checksum re-verified afterward). Conversion evidence:
`artifacts/conversion-report.json`.

## 7. Reproducing this inventory

```bash
pip3 install Pillow numpy
python3 scripts/analyze_assets.py        # -> artifacts/atlas-analysis.json
python3 scripts/make_contact_sheet.py    # -> artifacts/contact-sheet.png
python3 scripts/convert_spritesheet.py   # -> runtime PNG + conversion-report.json
python3 scripts/build_runtime_manifest.py# -> khosrow.runtime.json
```
