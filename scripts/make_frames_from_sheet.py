#!/usr/bin/env python3
"""Turn a Gemini-generated magenta-keyed sprite-sheet grid into pet-ready
animation frames (and a preview GIF).

Input: ONE image containing rows×cols cells, each one animation frame of the
same character on a solid hot-magenta background (the format we prompt Gemini
for — same as the original hand-made sleeping/reading/success sets).

Pipeline per cell:
  1. slice the grid cell (trimming a small inset to drop grid border lines)
  2. key out magenta (chroma test against the cell's own border color)
  3. drop tiny speckles/border remnants (keep significant components)
Then across ALL frames:
  4. take the UNION content bbox so every frame shares one steady canvas
     (no per-frame auto-crop = no jitter between frames)
  5. scale to fit the pet's 192x208 cell, anchored bottom-center
  6. write khosrow-<mood>-1..N.png + <mood>-contact.png + <mood>.gif

Usage:
  python3 scripts/make_frames_from_sheet.py SHEET.png --mood writing \
      [--rows 2 --cols 3] [--fps 6] --out DIR
"""
from __future__ import annotations

import argparse
import os
import sys
from collections import deque

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("Needs Pillow: python3 -m pip install Pillow")

CANVAS_W, CANVAS_H = 192, 208


def is_magenta(p, ref, tol=95) -> bool:
    r, g, b = p[0], p[1], p[2]
    # magenta family: strong red+blue, weak green — plus near the sampled ref
    if r > 150 and b > 150 and g < 110 and (r - g) > 60 and (b - g) > 60:
        return True
    return abs(r - ref[0]) + abs(g - ref[1]) + abs(b - ref[2]) <= tol


def cell_ref_color(cell: Image.Image):
    """The background color of this cell — the most common border pixel."""
    w, h = cell.size
    px = cell.load()
    from collections import Counter
    c = Counter()
    for x in range(0, w, 3):
        c[px[x, 1][:3]] += 1
        c[px[x, h - 2][:3]] += 1
    for y in range(0, h, 3):
        c[px[1, y][:3]] += 1
        c[px[w - 2, y][:3]] += 1
    return c.most_common(1)[0][0]


def key_cell(cell: Image.Image) -> Image.Image:
    cell = cell.convert("RGB")
    w, h = cell.size
    ref = cell_ref_color(cell)
    alpha = Image.new("L", (w, h), 255)
    ap = alpha.load()
    px = cell.load()
    for y in range(h):
        for x in range(w):
            if is_magenta(px[x, y], ref):
                ap[x, y] = 0
    alpha = keep_significant(alpha)
    alpha = erase_grid_lines(cell, alpha)
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.4))
    out = cell.convert("RGBA")
    out.putalpha(alpha)
    return despill(out)


def despill(im: Image.Image) -> Image.Image:
    """Remove the magenta halo: strongly magenta-cast pixels that touch
    transparency are background blend — make them transparent; milder casts
    get neutralized toward their green level."""
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            cast = (r + b) // 2 - g
            if cast <= 40:
                continue
            edge = any(
                0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1),
                               (x + 1, y + 1), (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1)))
            if edge and cast > 90 and r > 120 and b > 110:
                px[x, y] = (0, 0, 0, 0)          # halo pixel: kill it
            else:
                px[x, y] = (max(0, r - cast // 2), g, max(0, b - cast // 2), a)
    return im


def erase_grid_lines(cell: Image.Image, alpha: Image.Image) -> Image.Image:
    """Erase grid-border remnants AND generator "speed-line" streaks: dark
    horizontal (or vertical) runs that are long but vertically THIN. Thickness
    is checked before erasing, so broad dark areas like the cape are safe —
    only runs whose dark region is <= ~6px thick get removed."""
    w, h = cell.size
    cp = cell.load()
    ap = alpha.load()

    def dark(x, y):
        r, g, b = cp[x, y][:3]
        return r < 105 and g < 85 and b < 150 and (r + g + b) < 300

    def thin_at(x, y, vertical=False, limit=7):
        """Thickness of the dark region crossing (x, y) perpendicular to the run."""
        n = 1
        if vertical:
            i = x - 1
            while i >= 0 and dark(i, y) and n <= limit: n += 1; i -= 1
            i = x + 1
            while i < w and dark(i, y) and n <= limit: n += 1; i += 1
        else:
            i = y - 1
            while i >= 0 and dark(x, i) and n <= limit: n += 1; i -= 1
            i = y + 1
            while i < h and dark(x, i) and n <= limit: n += 1; i += 1
        return n

    def sweep(horizontal=True, minrun=45):
        outer, inner = (h, w) if horizontal else (w, h)
        for o in range(outer):
            run_px = []
            for i in range(inner + 1):
                x, y = (i, o) if horizontal else (o, i)
                if i < inner and ap[x, y] > 0 and dark(x, y):
                    run_px.append((x, y))
                else:
                    if len(run_px) >= minrun:
                        # Per-pixel: erase only where the dark region is locally
                        # thin. A border line that CROSSES the figure still gets
                        # erased on its thin stretches while the figure (locally
                        # thick) is untouched.
                        for (px_, py_) in run_px:
                            if thin_at(px_, py_, vertical=not horizontal) <= 6:
                                for d in (-2, -1, 0, 1, 2):
                                    xx = px_ if horizontal else px_ + d
                                    yy = py_ + d if horizontal else py_
                                    if 0 <= xx < w and 0 <= yy < h and ap[xx, yy] > 0 and dark(xx, yy):
                                        ap[xx, yy] = 0
                    run_px = []

    sweep(horizontal=True)
    sweep(horizontal=False, minrun=24)   # vertical border stubs are shorter
    return alpha


def keep_significant(alpha: Image.Image, rel=0.02, absmin=120) -> Image.Image:
    w, h = alpha.size
    ap = alpha.load()
    seen = bytearray(w * h)
    comps = []
    for sy in range(0, h, 2):
        for sx in range(0, w, 2):
            if ap[sx, sy] < 128 or seen[sy * w + sx]:
                continue
            comp = []
            q = deque([(sx, sy)])
            seen[sy * w + sx] = 1
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and ap[nx, ny] >= 128:
                        seen[ny * w + nx] = 1
                        q.append((nx, ny))
            comps.append(comp)
    if not comps:
        return alpha
    largest = max(len(c) for c in comps)
    thr = max(absmin, int(rel * largest))
    keep = set()
    for c in comps:
        if len(c) < thr:
            continue
        xs = [p[0] for p in c]; ys = [p[1] for p in c]
        bw = max(xs) - min(xs) + 1; bh = max(ys) - min(ys) + 1
        thin, long_ = min(bw, bh), max(bw, bh)
        if long_ > 6 * thin and thin <= 14:
            continue          # a stray grid border line, not figure
        # Detached debris from a neighbouring cell: a blob living entirely in
        # the top sliver (their boots) or the bottom sliver (their crown or a
        # floor-reflection ghost) of this cell, never touching the middle band
        # where the figure always lives.
        if max(ys) < h * 0.22 or min(ys) > h * 0.85:
            continue
        keep.update(c)
    out = Image.new("L", (w, h), 0)
    op = out.load()
    for (x, y) in keep:
        op[x, y] = ap[x, y]
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and 0 < ap[nx, ny] < 128:
                op[nx, ny] = ap[nx, ny]
    return out


def checker(w, h, sq=12):
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            c = 205 if ((x // sq) + (y // sq)) % 2 == 0 else 110
            px[x, y] = (c, c, c)
    return im


def is_contentish(p, ref) -> bool:
    """A pixel that belongs to the figure: not background magenta, not a
    near-black grid border line."""
    r, g, b = p[0], p[1], p[2]
    if is_magenta(p, ref):
        return False
    if r < 55 and g < 55 and b < 55:      # grid border / black line
        return False
    return True


def auto_cells(sheet: Image.Image):
    """Find frame cells in an *irregular* grid by recursively splitting on
    content-free gutters (magenta background or border lines), alternating
    axes. Thin bridges (a tail wisp crossing a border) are tolerated: any
    row/column whose figure coverage is under ~4%% of the span counts as a
    gutter."""
    w, h = sheet.size
    px = sheet.load()
    ref = cell_ref_color(sheet)

    def bands(counts, span, minrun):
        thr = max(2, int(span * 0.04))     # tolerate thin bridges
        spans, start = [], None
        for i, n in enumerate(counts):
            if n > thr:
                if start is None:
                    start = i
            else:
                if start is not None:
                    if i - start >= minrun:
                        spans.append((start, i))
                    start = None
        if start is not None and len(counts) - start >= minrun:
            spans.append((start, len(counts)))
        # Grow each band over adjacent low-count rows that still hold content
        # (a narrow crown or hoof the bridge threshold would otherwise eat).
        # Growth stops at truly-empty lines and is capped so bands never merge.
        grown = []
        n = len(counts)
        for (s, e) in spans:
            cap = max(6, int((e - s) * 0.8))
            gs, ge = s, e
            steps = 0
            while gs > 0 and counts[gs - 1] > 0 and steps < cap:
                gs -= 1; steps += 1
            steps = 0
            while ge < n and counts[ge] > 0 and steps < cap:
                ge += 1; steps += 1
            grown.append((gs, ge))
        # Clamp overlaps introduced by growth.
        for i in range(1, len(grown)):
            if grown[i][0] < grown[i - 1][1]:
                mid = (grown[i - 1][1] + grown[i][0]) // 2
                grown[i - 1] = (grown[i - 1][0], mid)
                grown[i] = (mid, grown[i][1])
        return grown

    def split(box, axis, depth):
        l, t, r_, b = box
        if depth > 4:
            return [box]
        if axis == "y":
            counts = [sum(1 for x in range(l, r_, 2) if is_contentish(px[x, y], ref))
                      for y in range(t, b)]
            found = bands(counts, r_ - l, minrun=max(12, (b - t) // 25))
            boxes = [(l, t + s, r_, t + e) for (s, e) in found]
        else:
            counts = [sum(1 for y in range(t, b, 2) if is_contentish(px[x, y], ref))
                      for x in range(l, r_)]
            found = bands(counts, b - t, minrun=max(12, (r_ - l) // 25))
            boxes = [(l + s, t, l + e, b) for (s, e) in found]
        if len(boxes) <= 1:
            # no split on this axis: try the other once, else this IS a cell
            if depth % 2 == 0 or len(boxes) == 1:
                other = "x" if axis == "y" else "y"
                sub = split(boxes[0] if boxes else box, other, depth + 1)
                return sub
            return [box]
        out = []
        for bx in boxes:
            out.extend(split(bx, "x" if axis == "y" else "y", depth + 1))
        return out

    cells = split((0, 0, w, h), "y", 0)
    # sort reading order: by row band (top), then x
    cells.sort(key=lambda c: (round(c[1] / max(1, h * 0.08)), c[0]))

    # Merge fragments: cells in the same row band separated by a sliver gap
    # (< 2.5% of sheet width) are parts of ONE frame that a magenta crack split.
    merged = []
    for c in cells:
        if merged:
            p = merged[-1]
            same_band = abs(p[1] - c[1]) < h * 0.12 or abs(p[3] - c[3]) < h * 0.12
            if same_band and c[0] - p[2] < w * 0.025:   # sliver gap OR overlap
                merged[-1] = (p[0], min(p[1], c[1]), c[2], max(p[3], c[3]))
                continue
        merged.append(c)
    # Drop residual specks (well under half the median area).
    areas = sorted((c[2] - c[0]) * (c[3] - c[1]) for c in merged)
    med = areas[len(areas) // 2]
    return [c for c in merged if (c[2] - c[0]) * (c[3] - c[1]) >= med * 0.35]




def _mask(im, scale=4):
    """Quarter-scale 0/255 alpha mask for fast comparisons."""
    a = im.split()[3].point(lambda v: 255 if v >= 96 else 0)
    return a.resize((max(1, im.width // scale), max(1, im.height // scale)), Image.NEAREST)


def _xor_count(a, b):
    from PIL import ImageChops
    d = ImageChops.difference(a, b)
    return sum(i * n for i, n in enumerate(d.histogram()[:256]) if n) // 255


def auto_face(frames):
    """Mirror any frame whose silhouette matches frame 1 better when flipped
    (keeps e.g. a gallop consistently left-facing)."""
    ref = _mask(frames[0])
    out = [frames[0]]
    flipped_n = 0
    for f in frames[1:]:
        m = _mask(f).resize(ref.size, Image.NEAREST)
        fl = _mask(f.transpose(Image.FLIP_LEFT_RIGHT)).resize(ref.size, Image.NEAREST)
        if _xor_count(fl, ref) + int(0.02 * ref.size[0] * ref.size[1] * 0) < _xor_count(m, ref) * 0.92:
            out.append(f.transpose(Image.FLIP_LEFT_RIGHT))
            flipped_n += 1
        else:
            out.append(f)
    if flipped_n:
        print(f"auto-face: mirrored {flipped_n} frame(s) to match frame 1")
    return out


def register_frames(frames, region="lower"):
    """Offsets (per frame) aligning everything to frame 1 using the static
    part of the silhouette: "lower" (legs) for standing figures, "upper"
    (rider/torso) for a gallop whose legs move, or "full"."""
    def low_mask(im):
        a = im.split()[3].point(lambda v: 255 if v >= 96 else 0)
        if region == "lower":
            return a.crop((0, int(im.height * 0.55), im.width, im.height))
        if region == "upper":
            return a.crop((0, 0, im.width, int(im.height * 0.55)))
        return a

    ref_full = low_mask(frames[0])
    offsets = [(0, 0)]
    for f in frames[1:]:
        m = low_mask(f)
        best, best_off = None, (0, 0)
        rng_x = max(6, frames[0].width // 8)
        rng_y = max(4, frames[0].height // 16)
        # coarse at 1/4 scale
        ref4 = ref_full.resize((max(1, ref_full.width // 4), max(1, ref_full.height // 4)), Image.NEAREST)
        m4 = m.resize((max(1, m.width // 4), max(1, m.height // 4)), Image.NEAREST)
        for dy in range(-rng_y // 4, rng_y // 4 + 1):
            for dx in range(-rng_x // 4, rng_x // 4 + 1):
                c = Image.new("L", ref4.size, 0)
                c.paste(m4, (dx, dy))
                v = _xor_count(c, ref4)
                if best is None or v < best:
                    best, best_off = v, (dx * 4, dy * 4)
        # refine at full res
        bx, by = best_off
        best = None
        fine = (0, 0)
        for dy in range(by - 3, by + 4):
            for dx in range(bx - 3, bx + 4):
                c = Image.new("L", ref_full.size, 0)
                c.paste(m, (dx, dy))
                v = _xor_count(c, ref_full)
                if best is None or v < best:
                    best, fine = v, (dx, dy)
        offsets.append(fine)
    return offsets


def temporal_debris_filter(placed):
    """Kill flickering generator debris: opaque pixels lying outside the
    dilated everyone-agrees silhouette AND belonging to small components.
    Moving limbs are large connected components, so they survive."""
    from PIL import ImageFilter as IF
    n = len(placed)
    W, H = placed[0].size
    # majority mask: opaque in >= half the frames
    acc = [0] * (W * H)
    masks = []
    for f in placed:
        a = f.split()[3].point(lambda v: 1 if v >= 96 else 0)
        masks.append(a)
        data = a.tobytes()
        for idx, byte in enumerate(data):
            if byte:
                acc[idx] += 1
    maj = Image.frombytes("L", (W, H), bytes(255 if c * 2 >= n else 0 for c in acc))
    maj = maj.filter(IF.MaxFilter(9))          # dilate
    majp = maj.load()

    total_fig = max(1, sum(1 for c in acc if c * 2 >= n))
    small_thr = max(60, int(total_fig * 0.02))

    out = []
    for f in placed:
        px = f.load()
        a = f.split()[3]
        ap = a.load()
        seen = bytearray(W * H)
        for sy in range(0, H, 2):
            for sx in range(0, W, 2):
                if ap[sx, sy] < 96 or seen[sy * W + sx]:
                    continue
                comp = []
                q = deque([(sx, sy)])
                seen[sy * W + sx] = 1
                outside = 0
                while q:
                    x, y = q.popleft()
                    comp.append((x, y))
                    if majp[x, y] == 0:
                        outside += 1
                    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                        if 0 <= nx < W and 0 <= ny < H and not seen[ny * W + nx] and ap[nx, ny] >= 96:
                            seen[ny * W + nx] = 1
                            q.append((nx, ny))
                if len(comp) <= small_thr and outside > len(comp) * 0.6:
                    for (x, y) in comp:            # debris: erase (plus halo)
                        for ddx in (-1, 0, 1):
                            for ddy in (-1, 0, 1):
                                xx, yy = x + ddx, y + ddy
                                if 0 <= xx < W and 0 <= yy < H:
                                    px[xx, yy] = (0, 0, 0, 0)
        out.append(f)
    return out


def report_stability(outs):
    """Objective loop-stability metrics: silhouette drift between consecutive
    frames (and wraparound). Big numbers = jumpy animation."""
    ms = [_mask(f, scale=2) for f in outs]
    diffs = []
    for i in range(len(ms)):
        j = (i + 1) % len(ms)
        a, b = ms[i], ms[j]
        if a.size != b.size:
            b = b.resize(a.size, Image.NEAREST)
        diffs.append(_xor_count(a, b))
    area = max(1, outs[0].size[0] * outs[0].size[1] // 4)
    pct = [round(100 * d / area, 1) for d in diffs]
    print("frame-to-frame silhouette change % (incl. loop seam):", pct)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("--mood", required=True)
    ap.add_argument("--rows", type=int, default=2)
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--auto", action="store_true",
                    help="auto-detect cells from content gaps (handles irregular grids)")
    ap.add_argument("--files", default="",
                    help="comma list of single-frame images (cel mode; overrides slicing)")
    ap.add_argument("--cells", default="",
                    help="explicit cell boxes as JSON [[l,t,r,b],...] (overrides --auto/--rows/--cols)")
    ap.add_argument("--register", default="lower", choices=["lower", "upper", "full"],
                    help="which silhouette band anchors frame registration")
    ap.add_argument("--auto-face", action="store_true", dest="auto_face",
                    help="mirror frames whose silhouette matches frame 1 better flipped")
    ap.add_argument("--flip", default="",
                    help="comma list of 1-based frame indices to mirror horizontally")
    ap.add_argument("--fps", type=float, default=6)
    ap.add_argument("--inset", type=float, default=0.015,
                    help="fraction of each cell trimmed on every side (grid borders)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    if args.files:
        sheet, W, H = None, 0, 0          # cel mode: no sheet to slice
    else:
        sheet = Image.open(args.sheet).convert("RGB")
        W, H = sheet.size

    frames = []
    if args.files:
        for fp in args.files.split(","):
            frames.append(key_cell(Image.open(fp.strip()).convert("RGB")))
    elif args.cells:
        import json as _json
        pad = 4
        for (l, t, r_, b) in _json.loads(args.cells):
            box = (max(0, l - pad), max(0, t - pad), min(W, r_ + pad), min(H, b + pad))
            frames.append(key_cell(sheet.crop(box)))
    elif args.auto:
        cells = auto_cells(sheet)
        print(f"auto-detected {len(cells)} cells: {cells}")
        pad = 4
        for (l, t, r_, b) in cells:
            box = (max(0, l - pad), max(0, t - pad), min(W, r_ + pad), min(H, b + pad))
            frames.append(key_cell(sheet.crop(box)))
    else:
        cw, ch = W / args.cols, H / args.rows
        for r in range(args.rows):
            for c in range(args.cols):
                ix, iy = int(cw * args.inset), int(ch * args.inset)
                box = (int(c * cw) + ix, int(r * ch) + iy,
                       int((c + 1) * cw) - ix, int((r + 1) * ch) - iy)
                frames.append(key_cell(sheet.crop(box)))

    flips = {int(i) for i in args.flip.split(",") if i.strip().isdigit()}
    if flips:
        frames = [f.transpose(Image.FLIP_LEFT_RIGHT) if (i + 1) in flips else f
                  for i, f in enumerate(frames)]

    # ---- Stabilization stage -------------------------------------------
    # The generator draws each cell with small position/scale variance; naive
    # per-frame bottom-center anchoring made crowns bob and feet wobble. Fix:
    #   1. normalize scale to the median frame
    #   2. REGISTER every frame against frame 1 on the static lower body
    #   3. compose on one shared canvas with fixed margins (headroom!)
    #   4. temporal debris vote: opaque pixels far from the everyone-agrees
    #      figure that belong to small components are generator debris
    frames = [f.crop(f.getbbox()) if f.getbbox() else f for f in frames]

    if args.auto_face:
        frames = auto_face(frames)

    ws = sorted(f.width for f in frames)
    hs = sorted(f.height for f in frames)
    med_w, med_h = ws[len(ws) // 2], hs[len(hs) // 2]
    primary_is_width = med_w >= med_h
    norm = []
    for f in frames:
        cur = f.width if primary_is_width else f.height
        target = med_w if primary_is_width else med_h
        lo, hi = (0.5, 2.0) if args.files else (0.65, 1.35)   # cel reframes need full equalization
        sc = max(lo, min(hi, target / max(1, cur)))
        if abs(sc - 1) > 0.02:
            f = f.resize((max(1, round(f.width * sc)), max(1, round(f.height * sc))), Image.LANCZOS)
        norm.append(f)
    frames = norm

    offsets = register_frames(frames, region=args.register)
    # Registration must EARN its keep: if the frames were already aligned
    # (some sheets are), shifting them adds wobble instead of removing it.
    def total_drift(offs):
        W_ = max(o[0] + f.width for f, o in zip(frames, offs)) - min(o[0] for o in offs)
        H_ = max(o[1] + f.height for f, o in zip(frames, offs)) - min(o[1] for o in offs)
        mx, my = min(o[0] for o in offs), min(o[1] for o in offs)
        ms = []
        for f, (ox, oy) in zip(frames, offs):
            c = Image.new("L", (W_, H_), 0)
            c.paste(f.split()[3].point(lambda v: 255 if v >= 96 else 0), (ox - mx, oy - my))
            ms.append(c.resize((max(1, W_ // 3), max(1, H_ // 3)), Image.NEAREST))
        vals = [_xor_count(ms[i], ms[(i + 1) % len(ms)]) for i in range(len(ms))]
        return sum(vals) + 2 * max(vals)
    zero = [(0, 0)] * len(frames)
    # bottom-align the zero-offset variant (previous behaviour)
    zoffs = [(0, max(fr.height for fr in frames) - f.height) for f in frames]
    if total_drift(zoffs) <= total_drift(offsets):
        offsets = zoffs
        print("registration skipped (frames already aligned)")
    else:
        print("registration applied")

    # Shared workspace: place every frame at its registered offset.
    minx = min(o[0] for o in offsets); miny = min(o[1] for o in offsets)
    maxx = max(o[0] + f.width for f, o in zip(frames, offsets))
    maxy = max(o[1] + f.height for f, o in zip(frames, offsets))
    W2, H2 = maxx - minx, maxy - miny
    placed = []
    for f, (ox, oy) in zip(frames, offsets):
        c = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
        c.paste(f, (ox - minx, oy - miny), f)
        placed.append(c)

    placed = temporal_debris_filter(placed)

    # Union bbox + margins (extra headroom protects the crown from looking
    # clipped at the canvas top).
    boxes = [f.getbbox() for f in placed if f.getbbox()]
    l = min(b[0] for b in boxes); t = min(b[1] for b in boxes)
    r_ = max(b[2] for b in boxes); btm = max(b[3] for b in boxes)
    mw = max(3, int((r_ - l) * 0.04))
    mt = max(6, int((btm - t) * 0.06))
    l = max(0, l - mw); r_ = min(W2, r_ + mw)
    t = max(0, t - mt); btm = min(H2, btm + 3)
    placed = [f.crop((l, t, r_, btm)) for f in placed]

    # ONE shared scale onto the pet canvas, bottom-centered.
    cw, chh = placed[0].width, placed[0].height
    shared = min(CANVAS_W / cw, CANVAS_H / chh)
    outs = []
    for i, f in enumerate(placed, 1):
        nw, nh = max(1, round(cw * shared)), max(1, round(chh * shared))
        f = f.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
        canvas.paste(f, ((CANVAS_W - nw) // 2, CANVAS_H - nh), f)
        p_ = os.path.join(args.out, f"khosrow-{args.mood}-{i}.png")
        canvas.save(p_)
        outs.append(canvas)

    report_stability(outs)
    print(f"wrote {len(outs)} frames -> {args.out}/khosrow-{args.mood}-N.png")

    # Contact sheet on checkerboard for review.
    cs = checker((CANVAS_W + 8) * len(outs) + 8, CANVAS_H + 16)
    for i, f in enumerate(outs):
        cs.paste(f, (8 + i * (CANVAS_W + 8), 8), f)
    cs_path = os.path.join(args.out, f"{args.mood}-contact.png")
    cs.save(cs_path)

    # Preview / README GIF (transparent background, loops).
    dur = int(1000 / args.fps)
    gif_frames = []
    for f in outs:
        g = f.convert("P", palette=Image.ADAPTIVE, colors=255)
        gif_frames.append(g)
    gif_path = os.path.join(args.out, f"{args.mood}.gif")
    gif_frames[0].save(gif_path, save_all=True, append_images=gif_frames[1:],
                       duration=dur, loop=0, disposal=2, transparency=0)
    print(f"wrote {cs_path} and {gif_path}")


if __name__ == "__main__":
    main()
