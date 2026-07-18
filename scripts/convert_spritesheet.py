#!/usr/bin/env python3
"""
convert_spritesheet.py — Deterministic WebP -> PNG runtime-asset conversion.

WHY: NSImage/ImageIO only decode WebP reliably on macOS 14+. To support an
earlier deployment target (macOS 12+) and to guarantee identical pixels across
machines, the app ships a PNG *runtime copy* of the spritesheet. The ORIGINAL
spritesheet.webp is never modified, resized, recompressed, or renamed — this
script only reads it and writes a NEW file.

The conversion is lossless and pixel-exact: same dimensions, same RGBA values,
same alpha. PNG is written with no additional filtering ambiguity so the output
is byte-reproducible on any machine with the same Pillow.

Outputs (by default):
  app/Sources/KhosrowApp/Resources/khosrow-spritesheet.png

Verifies and prints: dimensions, mode, alpha presence, and that every RGBA
pixel matches the source after round-trip.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image
import numpy as np

DEFAULT_OUT = "app/Sources/KhosrowApp/Resources/khosrow-spritesheet.png"


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--webp", default="spritesheet.webp")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--report", default="artifacts/conversion-report.json")
    args = ap.parse_args()

    root = Path(__file__).resolve().parent.parent
    src = root / args.webp
    out = root / args.out
    out.parent.mkdir(parents=True, exist_ok=True)

    src_bytes = src.read_bytes()
    im = Image.open(src)
    src_mode = im.mode
    rgba = im.convert("RGBA")
    src_arr = np.array(rgba)

    # Write PNG, forcing RGBA, deterministic settings.
    rgba.save(out, format="PNG", optimize=False)

    # Round-trip verify: reopen PNG and compare pixels exactly.
    back = np.array(Image.open(out).convert("RGBA"))
    identical = bool(src_arr.shape == back.shape and (src_arr == back).all())
    alpha = back[:, :, 3]

    report = {
        "generator": "scripts/convert_spritesheet.py",
        "source": {"path": args.webp, "sha256": sha256_bytes(src_bytes),
                   "mode": src_mode, "size": list(im.size)},
        "output": {"path": args.out, "sha256": sha256_bytes(out.read_bytes()),
                   "size": list(Image.open(out).size), "mode": "RGBA",
                   "bytes": out.stat().st_size},
        "pixel_identical_after_roundtrip": identical,
        "alpha": {
            "min": int(alpha.min()), "max": int(alpha.max()),
            "has_true_alpha": bool(((alpha > 0) & (alpha < 255)).any()),
            "fully_transparent": int((alpha == 0).sum()),
            "partial": int(((alpha > 0) & (alpha < 255)).sum()),
        },
    }
    (root / args.report).parent.mkdir(parents=True, exist_ok=True)
    (root / args.report).write_text(json.dumps(report, indent=2))

    print(f"Source WebP : {im.size[0]}x{im.size[1]} {src_mode}")
    print(f"Output PNG  : {report['output']['size'][0]}x{report['output']['size'][1]} RGBA "
          f"({report['output']['bytes']} bytes)")
    print(f"Alpha       : min={report['alpha']['min']} max={report['alpha']['max']} "
          f"true_alpha={report['alpha']['has_true_alpha']}")
    print(f"Pixel-exact : {identical}")
    if not identical:
        raise SystemExit("ERROR: PNG does not match source pixels!")
    print(f"Wrote {out.relative_to(root)}")
    print(f"Wrote {(root / args.report).relative_to(root)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
