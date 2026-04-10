"""SAM-guided refinement using lasso input.

The lasso polygon is converted into point prompts + bounding box for SAM.
SAM generates candidate masks; the best one (highest overlap with lasso) is selected.
"""

from __future__ import annotations

import sys
import numpy as np
from PIL import Image

from pipeline.lasso_utils import (
    polygon_to_bbox,
    polygon_to_pixel_mask,
    sample_points_inside,
    sample_points_outside,
)
from pipeline.refine import refine

_predictor = None


def _get_predictor():
    global _predictor
    if _predictor is not None:
        return _predictor

    from segment_anything import sam_model_registry, SamPredictor
    import os, torch

    checkpoint = os.path.expanduser("~/.cache/sam/sam_vit_b_01ec64.pth")
    if not os.path.isfile(checkpoint):
        raise FileNotFoundError(f"SAM checkpoint not found at {checkpoint}")

    sam = sam_model_registry["vit_b"](checkpoint=checkpoint)

    # Use MPS if available, otherwise CPU
    device = "cpu"
    if torch.backends.mps.is_available():
        try:
            sam.to("mps")
            device = "mps"
        except Exception:
            sam.to("cpu")
    else:
        sam.to("cpu")

    print(f"[sam] loaded on {device}", file=sys.stderr)
    _predictor = SamPredictor(sam)
    return _predictor


def refine_with_lasso(
    img: Image.Image,
    lasso_points: list[list[float]],
) -> np.ndarray:
    """Run SAM-guided segmentation using a lasso polygon as hint.

    Args:
        img: RGB PIL image.
        lasso_points: List of [x, y] in normalized [0, 1] coordinates.

    Returns:
        Refined float32 alpha mask in [0, 1] at original resolution.
    """
    predictor = _get_predictor()
    orig_w, orig_h = img.size

    # Convert lasso to prompts
    lasso_mask = polygon_to_pixel_mask(lasso_points, orig_w, orig_h)
    bbox = polygon_to_bbox(lasso_points, orig_w, orig_h)
    pos_points = sample_points_inside(lasso_mask, count=7)
    neg_points = sample_points_outside(lasso_mask, count=3)

    if len(pos_points) == 0:
        raise ValueError("Lasso region is empty — no points to sample")

    # Prepare SAM input
    arr = np.array(img.convert("RGB"))
    predictor.set_image(arr)

    # Combine positive + negative points
    all_points = np.concatenate([pos_points, neg_points], axis=0) if len(neg_points) > 0 else pos_points
    labels = np.array(
        [1] * len(pos_points) + [0] * len(neg_points), dtype=np.int32
    )

    # Run SAM with both point prompts and bounding box
    masks, scores, _ = predictor.predict(
        point_coords=all_points,
        point_labels=labels,
        box=np.array(bbox, dtype=np.float32),
        multimask_output=True,
    )

    if masks is None or len(masks) == 0:
        raise RuntimeError("SAM returned no masks")

    # Select best mask: highest IoU with lasso region
    best_idx = _select_best_mask(masks, scores, lasso_mask)
    mask = masks[best_idx].astype(np.float32)

    # Refine edges
    mask = refine(mask, blur_radius=1, morph_kernel=3)

    return mask


def _select_best_mask(
    masks: np.ndarray,
    scores: np.ndarray,
    lasso_mask: np.ndarray,
) -> int:
    """Select the mask with highest overlap with the lasso region, weighted by SAM score."""
    best_idx = 0
    best_combined = -1.0

    for i, (mask, sam_score) in enumerate(zip(masks, scores)):
        binary = mask.astype(np.uint8)
        intersection = np.logical_and(binary, lasso_mask).sum()
        union = np.logical_or(binary, lasso_mask).sum()
        iou = intersection / max(union, 1)

        # Combined score: 60% IoU with lasso, 40% SAM confidence
        combined = 0.6 * iou + 0.4 * sam_score
        if combined > best_combined:
            best_combined = combined
            best_idx = i

    return best_idx
