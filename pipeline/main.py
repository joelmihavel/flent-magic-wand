"""Background removal pipeline — clean, model-driven.

Primary: RMBG-1.4
Fallback: SAM (if installed) or BiRefNet
Refinement: minimal edge smoothing + noise removal

Usage:
    python -m pipeline.main input.jpg output.png
    python -m pipeline.main input.jpg output.png --debug
"""

from __future__ import annotations

import sys
import time

import numpy as np
from PIL import Image

from pipeline.rmbg import predict as rmbg_predict
from pipeline.refine import refine
from pipeline.utils import save_debug


# ── Quality check ──────────────────────────────────────────────────

def _check_mask(mask: np.ndarray) -> str | None:
    """Return a failure reason if the mask looks bad, None if acceptable."""
    fg_ratio = float(np.mean(mask > 0.5))

    if fg_ratio > 0.90:
        return f"fg_ratio={fg_ratio:.2f} (likely selected background)"
    if fg_ratio < 0.005:
        return f"fg_ratio={fg_ratio:.3f} (missed subject)"

    # Fragmentation: count connected components
    import cv2
    binary = (mask > 0.5).astype(np.uint8)
    num_labels, _, stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)
    if num_labels > 200:
        return f"fragmented ({num_labels} components)"

    return None


# ── Pipeline ───────────────────────────────────────────────────────

def remove_background(input_path: str, output_path: str, debug_dir: str | None = None):
    """Run the full background removal pipeline."""
    t0 = time.time()

    img = Image.open(input_path).convert("RGB")
    orig_w, orig_h = img.size
    print(f"[pipeline] input: {orig_w}x{orig_h}", file=sys.stderr)

    # Step 1: RMBG primary model
    t1 = time.time()
    mask = rmbg_predict(img)
    print(f"[pipeline] rmbg: {time.time()-t1:.2f}s", file=sys.stderr)
    save_debug("01_rmbg_mask", mask, debug_dir)

    # Step 2: Quality check
    failure = _check_mask(mask)

    if failure:
        print(f"[pipeline] rmbg failed: {failure}", file=sys.stderr)

        # Step 3: SAM fallback
        from pipeline.sam_fallback import predict as sam_predict
        t2 = time.time()
        sam_mask = sam_predict(img)
        if sam_mask is not None:
            print(f"[pipeline] sam fallback: {time.time()-t2:.2f}s", file=sys.stderr)
            save_debug("02_sam_mask", sam_mask, debug_dir)
            mask = sam_mask
        else:
            print("[pipeline] sam unavailable — using rmbg result anyway", file=sys.stderr)

    # Step 4: Refine
    mask = refine(mask)
    save_debug("03_refined", mask, debug_dir)

    # Step 5: Apply alpha and save
    alpha = Image.fromarray((mask * 255).clip(0, 255).astype(np.uint8), mode="L")
    result = img.convert("RGBA")
    result.putalpha(alpha)
    save_debug("04_result", result, debug_dir)

    result.save(output_path, format="PNG")
    print(f"[pipeline] done in {time.time()-t0:.2f}s → {output_path}", file=sys.stderr)
    print("OK")


def refine_with_lasso(
    input_path: str,
    output_path: str,
    lasso_points: list[list[float]],
    debug_dir: str | None = None,
):
    """Refine segmentation using a lasso selection as SAM prompt."""
    t0 = time.time()

    img = Image.open(input_path).convert("RGB")
    orig_w, orig_h = img.size
    print(f"[lasso] input: {orig_w}x{orig_h}, {len(lasso_points)} lasso points", file=sys.stderr)

    from pipeline.sam_refine import refine_with_lasso as sam_lasso
    mask = sam_lasso(img, lasso_points)
    save_debug("lasso_mask", mask, debug_dir)

    # Apply alpha
    alpha = Image.fromarray((mask * 255).clip(0, 255).astype(np.uint8), mode="L")
    result = img.convert("RGBA")
    result.putalpha(alpha)
    save_debug("lasso_result", result, debug_dir)

    result.save(output_path, format="PNG")
    print(f"[lasso] done in {time.time()-t0:.2f}s → {output_path}", file=sys.stderr)
    print("OK")


if __name__ == "__main__":
    args = sys.argv[1:]
    debug_dir = None

    if "--debug" in args:
        args.remove("--debug")
        debug_dir = "/tmp/mw_debug"

    # Lasso refinement mode: --lasso <json_file> input output
    if "--lasso" in args:
        idx = args.index("--lasso")
        args.pop(idx)
        lasso_file = args.pop(idx)
        if len(args) != 2:
            print("Usage: python -m pipeline.main --lasso <points.json> <input> <output> [--debug]", file=sys.stderr)
            sys.exit(1)
        import json
        with open(lasso_file) as f:
            lasso_points = json.load(f)
        refine_with_lasso(args[0], args[1], lasso_points, debug_dir)
    else:
        if len(args) != 2:
            print("Usage: python -m pipeline.main <input> <output> [--debug]", file=sys.stderr)
            sys.exit(1)
        remove_background(args[0], args[1], debug_dir)
