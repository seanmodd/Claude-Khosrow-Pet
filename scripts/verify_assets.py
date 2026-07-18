#!/usr/bin/env python3
"""
verify_assets.py — asset-integrity gate for CI and local use.

Checks, in order:
  1. The ORIGINAL pet.json and spritesheet.webp match their locked SHA-256s
     (they must NEVER be modified, resized, recompressed, or renamed).
  2. The generated runtime PNG exists with the exact expected dimensions.
  3. The runtime PNG still carries a real alpha channel (transparency preserved).
  4. The runtime PNG is pixel-identical to the original WebP (lossless convert).

Exits non-zero on any failure. Requires Pillow for the image checks; if Pillow
is unavailable, image checks are skipped with a clear warning (checksum checks
still run) so a minimal environment can at least enforce the integrity contract.
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Locked integrity contract for the ORIGINAL assets.
EXPECTED = {
    "pet.json": "e62d3eda10ff3104212797c7539200c4531a333ee5e9b80a0d675fba1e78dfee",
    "spritesheet.webp": "bc19c4a1a1579ce5993d360b6fcca85f4feaf6db2270352bfa5f7d02f229ff47",
}

RUNTIME_PNG = "app/Sources/KhosrowKit/Resources/khosrow-spritesheet.png"
EXPECTED_W, EXPECTED_H = 1536, 2288


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    failures: list[str] = []

    # 1. Original checksums
    for name, expected in EXPECTED.items():
        p = ROOT / name
        if not p.exists():
            failures.append(f"missing original: {name}")
            continue
        actual = sha256(p)
        if actual != expected:
            failures.append(f"{name} checksum changed!\n   expected {expected}\n   actual   {actual}")
        else:
            print(f"OK  original {name} sha256 matches")

    # 2-4. Runtime PNG image checks (need Pillow)
    png = ROOT / RUNTIME_PNG
    if not png.exists():
        failures.append(f"missing runtime PNG: {RUNTIME_PNG}")
    else:
        try:
            from PIL import Image
            import numpy as np
            im = Image.open(png)
            if im.size != (EXPECTED_W, EXPECTED_H):
                failures.append(f"runtime PNG is {im.size}, expected {(EXPECTED_W, EXPECTED_H)}")
            else:
                print(f"OK  runtime PNG dimensions {im.size}")

            rgba = im.convert("RGBA")
            alpha = np.array(rgba)[:, :, 3]
            has_partial = bool(((alpha > 0) & (alpha < 255)).any())
            has_transparent = bool((alpha == 0).any())
            if not (has_partial or has_transparent):
                failures.append("runtime PNG has no transparency (alpha lost)")
            else:
                print(f"OK  runtime PNG alpha preserved "
                      f"(transparent={has_transparent}, partial={has_partial})")

            # 4. lossless vs original WebP
            src = Image.open(ROOT / "spritesheet.webp").convert("RGBA")
            if np.array(src).shape == np.array(rgba).shape and (np.array(src) == np.array(rgba)).all():
                print("OK  runtime PNG is pixel-identical to the original WebP")
            else:
                failures.append("runtime PNG is NOT pixel-identical to the original WebP")
        except ImportError:
            print("WARN Pillow/numpy unavailable — skipped runtime PNG image checks")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print("  ✗", f)
        return 1
    print("\nAll asset-integrity checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
