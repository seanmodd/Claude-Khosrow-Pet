#!/usr/bin/env python3
"""
make_contact_sheet.py — Render a labeled contact sheet of every frame.

Each of the 88 grid cells (8 cols x 11 rows) is composited over a checkerboard
(so alpha transparency is visible) and labeled with:
    r<row> c<col>   (top-left)
    #<index>        (top-right, sequential row-major index)
Empty cells are marked "EMPTY". A per-row band on the left shows the row number
and its frame count.

Reads only the original spritesheet.webp; writes artifacts/contact-sheet.png.
Does not modify any original.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

COLS, ROWS = 8, 11
GUTTER = 6          # px between cells in the contact sheet
MARGIN = 44         # left margin for row labels / top for header
CHECK = 12          # checkerboard square size
LIGHT = (210, 210, 214, 255)
DARK = (170, 170, 176, 255)
LINE = (40, 40, 48, 255)
LABEL_BG = (0, 0, 0, 170)
LABEL_FG = (255, 255, 255, 255)
EMPTY_FG = (200, 60, 60, 255)
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def load_font(size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except OSError:
        return ImageFont.load_default()


def checker(w: int, h: int) -> Image.Image:
    tile = Image.new("RGBA", (w, h), LIGHT)
    d = ImageDraw.Draw(tile)
    for y in range(0, h, CHECK):
        for x in range(0, w, CHECK):
            if (x // CHECK + y // CHECK) % 2:
                d.rectangle([x, y, x + CHECK - 1, y + CHECK - 1], fill=DARK)
    return tile


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--webp", default="spritesheet.webp")
    ap.add_argument("--out", default="artifacts/contact-sheet.png")
    ap.add_argument("--cell-scale", type=float, default=1.0,
                    help="scale each frame cell (1.0 keeps native 192x208)")
    args = ap.parse_args()

    root = Path(__file__).resolve().parent.parent
    sheet = Image.open(root / args.webp).convert("RGBA")
    W, H = sheet.size
    cw, ch = W // COLS, H // ROWS

    scw, sch = int(cw * args.cell_scale), int(ch * args.cell_scale)
    font = load_font(max(11, int(13 * args.cell_scale)))
    small = load_font(max(10, int(11 * args.cell_scale)))

    out_w = MARGIN + COLS * (scw + GUTTER) + GUTTER
    out_h = MARGIN + ROWS * (sch + GUTTER) + GUTTER
    canvas = Image.new("RGBA", (out_w, out_h), (28, 28, 32, 255))
    draw = ImageDraw.Draw(canvas)

    # Column headers
    for c in range(COLS):
        x = MARGIN + GUTTER + c * (scw + GUTTER) + scw // 2
        draw.text((x, 6), f"col {c}", font=small, fill=(180, 180, 190, 255), anchor="mm")

    check_tile = checker(scw, sch)

    for r in range(ROWS):
        row_frames = 0
        for c in range(COLS):
            cell = sheet.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            if args.cell_scale != 1.0:
                cell = cell.resize((scw, sch), Image.NEAREST)
            x = MARGIN + GUTTER + c * (scw + GUTTER)
            y = MARGIN + GUTTER + r * (sch + GUTTER)

            bbox = cell.getbbox()
            is_empty = bbox is None

            base = check_tile.copy()
            base.alpha_composite(cell)
            canvas.paste(base, (x, y))
            draw.rectangle([x, y, x + scw - 1, y + sch - 1], outline=LINE, width=1)

            idx = r * COLS + c
            if is_empty:
                draw.text((x + scw // 2, y + sch // 2), "EMPTY",
                          font=font, fill=EMPTY_FG, anchor="mm")
            else:
                row_frames += 1
            # top-left r/c label with backing box
            tl = f"r{r}c{c}"
            tb = draw.textbbox((0, 0), tl, font=small)
            draw.rectangle([x + 1, y + 1, x + 1 + (tb[2] - tb[0]) + 4,
                            y + 1 + (tb[3] - tb[1]) + 4], fill=LABEL_BG)
            draw.text((x + 3, y + 2), tl, font=small, fill=LABEL_FG)
            # top-right sequential index
            ir = f"#{idx}"
            ib = draw.textbbox((0, 0), ir, font=small)
            iw = ib[2] - ib[0]
            draw.rectangle([x + scw - iw - 5, y + 1, x + scw - 1,
                            y + 1 + (ib[3] - ib[1]) + 4], fill=LABEL_BG)
            draw.text((x + scw - iw - 3, y + 2), ir, font=small, fill=LABEL_FG)

        # Row label (left margin)
        ry = MARGIN + GUTTER + r * (sch + GUTTER) + sch // 2
        draw.text((MARGIN // 2, ry), f"r{r}", font=font, fill=(230, 230, 235, 255), anchor="mm")
        draw.text((MARGIN // 2, ry + 16), f"{row_frames}f", font=small,
                  fill=(150, 200, 150, 255), anchor="mm")

    out_path = root / args.out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out_path)
    print(f"Wrote {out_path.relative_to(root)}  ({out_w}x{out_h})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
