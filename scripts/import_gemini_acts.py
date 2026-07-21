#!/usr/bin/env python3
"""Import the Gemini "Khosrow Mood States" artwork into the app's managed assets.

The six source illustrations live in a user Documents folder and are treated as
READ-ONLY inputs — this script never modifies them. Each source is a single
illustrated figure (or, for Attentive/Writing, a shared 2x2 "mood sheet") painted
on an *opaque* dark-navy / near-black starfield. Khosrow floats in a borderless,
transparent window, so we must cut the figure out to real transparency.

Pipeline (PIL only — numpy is intentionally not required):
  1. Optionally crop one pose out of the shared montage (Attentive / Writing).
  2. Remove the background:
       a. border flood-fill from every edge where the pixel is navy-like, so
          the outer background (and its subtle vignette) is keyed out while
          interior figure shadows — which are never border-connected — survive.
       b. an interior grid pass that floods *strictly* navy pockets (enclosed
          negative space such as the gaps beside Praying's raised arms) without
          touching brown hair or the blue robe.
  3. Keep only the largest connected opaque region, dropping isolated stars and
     the little sparkle glyph.
  4. Erode 1px to shave the anti-aliased navy fringe, then feather slightly.
  5. Auto-trim to the figure's bounding box with a small margin.
  6. Downscale so the longest side is <= MAX_SIDE (keeps the bundle small; the
     art is painterly and scales smoothly).

Usage:
    python3 scripts/import_gemini_acts.py [--src DIR] [--out DIR] [--review]

Default --out is app/Sources/KhosrowKit/Resources. Pass --review to write to a
scratch dir instead (for eyeballing before committing).
"""
from __future__ import annotations

import argparse
import os
import sys
from collections import deque

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    sys.exit("This script needs Pillow (PIL). Install with: python3 -m pip install Pillow")

MAX_SIDE = 768
SENTINEL = (255, 0, 255)  # magenta marker for "this is background"

# Which source file feeds each mood. Each source is a single illustrated figure
# on an opaque navy/near-black starfield; crop is a fraction box (l, t, r, b) for
# the rare case a source needs trimming, else None to use the whole image.
PLAN = {
    # mood id  -> (source stem, crop fraction or None, interior seed fractions)
    "attentive": ("Gemini-Khosrow-Attentive", None, []),
    "writing":   ("Gemini-Khosrow-Writing",   None, []),
    "searching": ("Gemini-Khosrow-Searching", None, []),
    "waiting":   ("Gemini-Khosrow-Waiting",   None, []),
    "running":   ("Gemini-Khosrow-Running",   None, []),
    # Praying: hands raised, so the pockets beside the arms/head are enclosed.
    "praying":   ("Gemini-Khosrow-Praying",   None,
                  [(0.28, 0.18), (0.72, 0.18), (0.24, 0.28), (0.76, 0.28),
                   (0.30, 0.10), (0.70, 0.10)]),
}


def sample_bg(im: Image.Image) -> tuple[int, int, int]:
    """The background color — the darkest of the four corners (most navy)."""
    w, h = im.size
    px = im.load()
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    corners = [c[:3] for c in corners]
    return min(corners, key=lambda c: c[0] + c[1] + c[2])


def is_navy(p, bg, tol) -> bool:
    """A dark, blue-leaning, low-red pixel — background, never robe/skin/brown."""
    r, g, b = p[0], p[1], p[2]
    if r > 95 or g > 95:      # skin / brown boots / gold crown
        return False
    if b > 120:               # bright blue robe
        return False
    d = abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2])
    return d <= tol


def remove_background(im: Image.Image, interior_seeds=None) -> Image.Image:
    """Non-destructive keying. Border flood-fill removes the outer background
    (never interior figure pixels, which aren't border-connected). A *very*
    strict interior pass floods only true-navy enclosed pockets — so tight it
    can't spread into the blue robe/trousers (the bug that gouged white holes
    into the tunic). `interior_seeds` are optional per-image (fx, fy) fractions
    pointing at enclosed background (e.g. the gaps beside Praying's raised arms).
    """
    im = im.convert("RGB")
    w, h = im.size
    bg = sample_bg(im)
    flood = im.copy()
    px = flood.load()

    # (a) Dense border seeds — flood the outer background from every edge.
    step = max(6, min(w, h) // 90)
    border_pts = []
    for x in range(0, w, step):
        border_pts.append((x, 0)); border_pts.append((x, h - 1))
    for y in range(0, h, step):
        border_pts.append((0, y)); border_pts.append((w - 1, y))
    for pt in border_pts:
        if px[pt] != SENTINEL and is_navy(px[pt], bg, tol=70):
            ImageDraw.floodfill(flood, pt, SENTINEL, thresh=48)

    # (b) Explicit interior seeds for enclosed pockets (per image). Strict flood.
    for (fx, fy) in (interior_seeds or []):
        gx, gy = int(fx * w), int(fy * h)
        p = px[gx, gy]
        if p != SENTINEL and is_navy(p, bg, tol=42):
            ImageDraw.floodfill(flood, (gx, gy), SENTINEL, thresh=30)

    # (c) A conservative auto interior pass: flood only pixels that are *nearly
    #     identical* to the background (tol 18) with a tight spread (thresh 20),
    #     so enclosed navy is removed but the darkest robe blues are untouched.
    grid = max(8, min(w, h) // 120)
    for gy in range(grid, h, grid):
        for gx in range(grid, w, grid):
            p = px[gx, gy]
            if p != SENTINEL and is_navy(p, bg, tol=18):
                ImageDraw.floodfill(flood, (gx, gy), SENTINEL, thresh=20)

    # Alpha: opaque everywhere except the flooded background.
    alpha = Image.new("L", (w, h), 255)
    ap = alpha.load()
    for y in range(h):
        for x in range(w):
            if px[x, y] == SENTINEL:
                ap[x, y] = 0

    alpha = keep_significant_regions(alpha)

    # HOLE REPAIR — the guarantee that makes interior transparency impossible:
    # background is ONLY what connects to the image border through transparent
    # pixels. Any transparent pocket enclosed by the figure (a beard shadow,
    # the waist sash, a dark fold the keyer mistook for navy) is restored to
    # full opacity. Deliberate enclosed pockets (e.g. between raised arms)
    # survive only if their pixels truly match the background colour.
    from collections import deque as _dq
    outside = bytearray(w * h)
    q = _dq()
    for x in range(w):
        for y in (0, h - 1):
            if ap[x, y] < 128 and not outside[y * w + x]:
                outside[y * w + x] = 1; q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if ap[x, y] < 128 and not outside[y * w + x]:
                outside[y * w + x] = 1; q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
            if 0 <= nx < w and 0 <= ny < h and not outside[ny*w+nx] and ap[nx, ny] < 128:
                outside[ny*w+nx] = 1; q.append((nx, ny))
    src = im.load()
    for y in range(h):
        for x in range(w):
            if ap[x, y] < 255 and not outside[y*w+x]:
                p_ = src[x, y]
                d = abs(p_[0]-bg[0]) + abs(p_[1]-bg[1]) + abs(p_[2]-bg[2])
                if d > 36:                     # real art, wrongly keyed: restore
                    ap[x, y] = 255
                # else: genuine enclosed background pocket — keep transparent

    # Gentle edge feather only (NO erosion — erosion was eating figure detail).
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.5))

    out = im.convert("RGBA")
    out.putalpha(alpha)
    return out


def keep_significant_regions(alpha: Image.Image, rel=0.03, absmin=500) -> Image.Image:
    """Keep every opaque blob whose area is a meaningful fraction of the largest,
    dropping only tiny specks (stray stars, the sparkle glyph). A big figure that
    the flood happens to split into two parts — e.g. Praying's torso and legs,
    severed by the shadow under the tunic hem — keeps *both* halves; only the
    little floating decorations are removed."""
    w, h = alpha.size
    ap = alpha.load()
    seen = bytearray(w * h)
    comps: list[list[tuple[int, int]]] = []
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
    threshold = max(absmin, int(rel * largest))
    keep_pixels = set()
    for c in comps:
        if len(c) >= threshold:
            keep_pixels.update(c)
    if not keep_pixels:
        return alpha
    out = Image.new("L", (w, h), 0)
    op = out.load()
    for (x, y) in keep_pixels:
        op[x, y] = ap[x, y]
    # Restore anti-aliased edge pixels adjacent to any kept blob.
    for (x, y) in keep_pixels:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and 0 < ap[nx, ny] < 128:
                op[nx, ny] = ap[nx, ny]
    return out


def autotrim(im: Image.Image, margin_frac=0.03) -> Image.Image:
    bbox = im.getbbox()
    if not bbox:
        return im
    l, t, r, b = bbox
    mw = int((r - l) * margin_frac)
    mh = int((b - t) * margin_frac)
    l = max(0, l - mw); t = max(0, t - mh)
    r = min(im.width, r + mw); b = min(im.height, b + mh)
    return im.crop((l, t, r, b))


def downscale(im: Image.Image, max_side=MAX_SIDE) -> Image.Image:
    w, h = im.size
    s = min(1.0, max_side / max(w, h))
    if s < 1.0:
        im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    return im


def process(src_path: str, crop_frac, interior_seeds=None) -> Image.Image:
    im = Image.open(src_path).convert("RGBA")
    if crop_frac:
        w, h = im.size
        l, t, r, b = crop_frac
        im = im.crop((int(l * w), int(t * h), int(r * w), int(b * h)))
    im = remove_background(im, interior_seeds=interior_seeds)
    im = autotrim(im)
    im = downscale(im)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.expanduser("~/Documents/Gemini's Khosrow Mood States"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..",
                                                  "app/Sources/KhosrowKit/Resources"))
    ap.add_argument("--review", action="store_true",
                    help="write to a scratch review dir instead of Resources")
    args = ap.parse_args()

    out_dir = args.out
    if args.review:
        out_dir = os.environ.get("KHOSROW_REVIEW_DIR", "/tmp/khosrow-gemini-review")
    os.makedirs(out_dir, exist_ok=True)

    for mood, (stem, crop, seeds) in PLAN.items():
        src = os.path.join(args.src, stem + ".png")
        if not os.path.exists(src):
            sys.exit(f"Missing source: {src}")
        out = process(src, crop, interior_seeds=seeds)
        dest = os.path.join(out_dir, f"gemini-{mood}.png")
        out.save(dest)
        print(f"  gemini-{mood:10s} {out.size[0]}x{out.size[1]:<4}  <- {stem}.png"
              + (f" (crop {crop})" if crop else ""))
    print(f"Wrote 6 acts to {out_dir}")


if __name__ == "__main__":
    main()
