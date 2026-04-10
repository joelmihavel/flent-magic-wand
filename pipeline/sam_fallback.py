"""Fallback segmentation using SAM (Segment Anything Model).

Used only when RMBG produces a clearly bad result.
Strategy: prompt SAM with a small grid of points, select the most compact mask.
"""

from __future__ import annotations

import os
import sys
import numpy as np
from PIL import Image

_sam_predictor = None
_available = None


def is_available() -> bool:
    """Check if SAM model is installed and ready."""
    global _available
    if _available is not None:
        return _available
    try:
        from segment_anything import sam_model_registry
        # Check for checkpoint
        checkpoint = _find_checkpoint()
        _available = checkpoint is not None
    except ImportError:
        _available = False
    return _available


def _find_checkpoint() -> str | None:
    """Locate SAM checkpoint on disk."""
    candidates = [
        os.path.expanduser("~/.cache/sam/sam_vit_b_01ec64.pth"),
        os.path.expanduser("~/.cache/sam/sam_vit_b.pth"),
        os.path.join(os.path.dirname(__file__), "..", "models", "sam_vit_b.pth"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return None


def _get_predictor():
    global _sam_predictor
    if _sam_predictor is not None:
        return _sam_predictor

    from segment_anything import sam_model_registry, SamPredictor

    checkpoint = _find_checkpoint()
    if checkpoint is None:
        raise RuntimeError("SAM checkpoint not found")

    sam = sam_model_registry["vit_b"](checkpoint=checkpoint)
    device = "cpu"  # SAM on MPS can be unstable
    sam.to(device)

    _sam_predictor = SamPredictor(sam)
    return _sam_predictor


def predict(img: Image.Image) -> np.ndarray | None:
    """Run SAM with center + grid point prompts. Returns float32 mask [0,1] or None on failure."""
    if not is_available():
        print("[sam] not available — skipping fallback", file=sys.stderr)
        return None

    try:
        predictor = _get_predictor()
    except Exception as e:
        print(f"[sam] failed to load: {e}", file=sys.stderr)
        return None

    arr = np.array(img.convert("RGB"))
    h, w = arr.shape[:2]
    predictor.set_image(arr)

    # Generate point prompts: center + 4 grid points
    points = np.array([
        [w // 2, h // 2],          # center
        [w // 3, h // 3],          # upper-left third
        [2 * w // 3, h // 3],      # upper-right third
        [w // 3, 2 * h // 3],      # lower-left third
        [2 * w // 3, 2 * h // 3],  # lower-right third
    ], dtype=np.float32)
    labels = np.ones(len(points), dtype=np.int32)  # all foreground

    masks, scores, _ = predictor.predict(
        point_coords=points,
        point_labels=labels,
        multimask_output=True,
    )

    if masks is None or len(masks) == 0:
        return None

    # Select most compact mask (highest score, reasonable size)
    best_idx = -1
    best_score = -1.0
    for i, (mask, score) in enumerate(zip(masks, scores)):
        fg_ratio = mask.sum() / mask.size
        if 0.005 < fg_ratio < 0.90:
            if score > best_score:
                best_score = score
                best_idx = i

    if best_idx < 0:
        # Fall back to highest-scoring mask
        best_idx = int(np.argmax(scores))

    return masks[best_idx].astype(np.float32)
