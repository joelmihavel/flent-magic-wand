"""Convert an image to WebP or AVIF using Pillow.

Preserves ICC color profile + EXIF orientation. When a target size (KB) is
given, the encoder iteratively searches for the highest quality that fits
within the budget, downscaling the image only if even the lowest quality at
full resolution would exceed it.

Usage: python -m pipeline.convert <input> <output> <format> [quality] [target_kb]
  format:    webp | avif
  quality:   0-100 (default 85) — used when target_kb is 0/absent
  target_kb: 0 for "off", or target size in KB (e.g. 30)
"""

import io
import sys
from typing import Optional

from PIL import Image, ImageOps

# --- Encoder --------------------------------------------------------------

def _encode_bytes(img: Image.Image, fmt: str, quality: int, icc: Optional[bytes], exif: Optional[bytes]) -> bytes:
    buf = io.BytesIO()
    kwargs = {"quality": int(max(1, min(100, quality)))}
    if icc:
        kwargs["icc_profile"] = icc
    if exif:
        kwargs["exif"] = exif

    if fmt == "webp":
        kwargs["method"] = 6
        kwargs["lossless"] = False
        img.save(buf, format="WEBP", **kwargs)
    elif fmt == "avif":
        kwargs["speed"] = 6  # faster encode; size barely changes vs slower speeds
        img.save(buf, format="AVIF", **kwargs)
    else:
        raise ValueError(f"Unsupported format: {fmt}")

    return buf.getvalue()


# --- Budget search --------------------------------------------------------

def _best_quality_within(img: Image.Image, fmt: str, budget: int,
                         icc: Optional[bytes], exif: Optional[bytes],
                         q_lo: int = 20, q_hi: int = 95) -> Optional[bytes]:
    """Return encoded bytes at the highest quality that fits within `budget`
    bytes, or None if even `q_lo` exceeds the budget."""
    lo, hi = q_lo, q_hi
    best: Optional[bytes] = None
    # Bound: ensure floor actually fits before searching
    floor_data = _encode_bytes(img, fmt, q_lo, icc, exif)
    if len(floor_data) > budget:
        return None
    best = floor_data

    while lo <= hi:
        mid = (lo + hi) // 2
        data = _encode_bytes(img, fmt, mid, icc, exif)
        if len(data) <= budget:
            best = data
            lo = mid + 1
        else:
            hi = mid - 1
    return best


def encode_within_budget(img: Image.Image, fmt: str, target_bytes: int,
                         icc: Optional[bytes], exif: Optional[bytes]) -> bytes:
    """Encode `img` into `fmt` output below `target_bytes`. Tries the original
    resolution first, then downscales in 10% steps until the budget is met."""
    # Stage 1: quality search at original resolution
    attempt = _best_quality_within(img, fmt, target_bytes, icc, exif)
    if attempt is not None:
        return attempt

    # Stage 2: progressively downscale
    base_w, base_h = img.size
    for pct in (0.85, 0.7, 0.55, 0.4, 0.3, 0.2):
        new_w = max(32, int(round(base_w * pct)))
        new_h = max(32, int(round(base_h * pct)))
        scaled = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
        attempt = _best_quality_within(scaled, fmt, target_bytes, icc, exif, q_lo=20, q_hi=90)
        if attempt is not None:
            return attempt

    # Last resort: tiniest image, lowest quality
    tiny_w = max(32, int(base_w * 0.15))
    tiny_h = max(32, int(base_h * 0.15))
    tiny = img.resize((tiny_w, tiny_h), Image.Resampling.LANCZOS)
    return _encode_bytes(tiny, fmt, 10, icc, exif)


# --- Entrypoint -----------------------------------------------------------

def convert(input_path: str, output_path: str, fmt: str, quality: int, target_kb: int) -> None:
    fmt = fmt.lower()
    if fmt not in {"webp", "avif"}:
        raise ValueError(f"Unsupported format: {fmt}")

    with Image.open(input_path) as opened:
        img = ImageOps.exif_transpose(opened)
        icc = img.info.get("icc_profile") if img.info else None
        exif = img.info.get("exif") if img.info else None

        # WebP/AVIF require modes RGB or RGBA. Convert palette/LA/etc.
        if img.mode not in ("RGB", "RGBA"):
            img = img.convert("RGBA" if "A" in img.mode else "RGB")

        if target_kb and target_kb > 0:
            # Use decimal KB (1000 bytes) — matches how Finder/ByteCountFormatter
            # reports size, so "30 KB target" is safe under either convention.
            data = encode_within_budget(img, fmt, target_kb * 1000, icc, exif)
        else:
            data = _encode_bytes(img, fmt, quality, icc, exif)

    with open(output_path, "wb") as f:
        f.write(data)


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print("Usage: convert.py <input> <output> <format> [quality] [target_kb]", file=sys.stderr)
        return 2

    input_path = argv[1]
    output_path = argv[2]
    fmt = argv[3]
    quality = int(argv[4]) if len(argv) > 4 else 85
    target_kb = int(argv[5]) if len(argv) > 5 else 0

    convert(input_path, output_path, fmt, quality, target_kb)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
