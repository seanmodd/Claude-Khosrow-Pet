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
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.4))
    out = cell.convert("RGBA")
    out.putalpha(alpha)
    return despill(out)


def despill(im: Image.Image) -> Image.Image:
    """Soften residual magenta fringe on edge pixels: pull excess red/blue
    (over green) down on semi-transparent or boundary pixels."""
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r > 150 and b > 150 and g < 120:
                # magenta-cast pixel on the edge: neutralize toward its green level
                m = (r + b) // 2
                excess = m - g
                if excess > 40:
                    px[x, y] = (max(0, r - excess // 2), g, max(0, b - excess // 2), a)
    return im


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
        if len(c) >= thr:
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("--mood", required=True)
    ap.add_argument("--rows", type=int, default=2)
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--fps", type=float, default=6)
    ap.add_argument("--inset", type=float, default=0.015,
                    help="fraction of each cell trimmed on every side (grid borders)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    sheet = Image.open(args.sheet).convert("RGB")
    W, H = sheet.size
    cw, ch = W / args.cols, H / args.rows

    frames = []
    for r in range(args.rows):
        for c in range(args.cols):
            ix, iy = int(cw * args.inset) , int(ch * args.inset)
            box = (int(c * cw) + ix, int(r * ch) + iy,
                   int((c + 1) * cw) - ix, int((r + 1) * ch) - iy)
            frames.append(key_cell(sheet.crop(box)))

    # Union bbox across all frames -> one steady canvas.
    boxes = [f.getbbox() for f in frames if f.getbbox()]
    if not boxes:
        sys.exit("No content found after keying")
    l = min(b[0] for b in boxes); t = min(b[1] for b in boxes)
    r_ = max(b[2] for b in boxes); btm = max(b[3] for b in boxes)
    mw, mh = int((r_ - l) * 0.02), int((btm - t) * 0.02)
    l = max(0, l - mw); t = max(0, t - mh)
    r_ = min(frames[0].width, r_ + mw); btm = min(frames[0].height, btm + mh)

    outs = []
    for i, f in enumerate(frames, 1):
        f = f.crop((l, t, r_, btm))
        s = min(CANVAS_W / f.width, CANVAS_H / f.height)
        nw, nh = max(1, round(f.width * s)), max(1, round(f.height * s))
        f = f.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
        canvas.paste(f, ((CANVAS_W - nw) // 2, CANVAS_H - nh), f)   # bottom-center
        p = os.path.join(args.out, f"khosrow-{args.mood}-{i}.png")
        canvas.save(p)
        outs.append(canvas)
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
