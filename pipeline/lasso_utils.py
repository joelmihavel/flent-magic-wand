"""Utilities for converting lasso input into SAM prompts."""

from __future__ import annotations

import numpy as np


def polygon_to_bbox(points: list[list[float]], img_w: int, img_h: int) -> list[int]:
    """Convert normalized [0,1] polygon points to pixel bounding box [x1, y1, x2, y2]."""
    pts = np.array(points)
    xs = pts[:, 0] * img_w
    ys = pts[:, 1] * img_h
    return [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]


def polygon_to_pixel_mask(
    points: list[list[float]], img_w: int, img_h: int
) -> np.ndarray:
    """Rasterize normalized polygon into a binary mask at (img_h, img_w)."""
    import cv2

    pts = np.array(points)
    pixel_pts = np.column_stack([pts[:, 0] * img_w, pts[:, 1] * img_h]).astype(np.int32)
    mask = np.zeros((img_h, img_w), dtype=np.uint8)
    cv2.fillPoly(mask, [pixel_pts], 1)
    return mask


def sample_points_inside(
    mask: np.ndarray, count: int = 7, seed: int = 42
) -> np.ndarray:
    """Sample random pixel coordinates inside a binary mask.

    Returns array of shape (N, 2) with (x, y) coordinates.
    """
    ys, xs = np.where(mask > 0)
    if len(xs) == 0:
        return np.empty((0, 2), dtype=np.float32)

    rng = np.random.RandomState(seed)
    count = min(count, len(xs))
    indices = rng.choice(len(xs), size=count, replace=False)
    return np.column_stack([xs[indices], ys[indices]]).astype(np.float32)


def sample_points_outside(
    mask: np.ndarray, count: int = 3, margin: int = 20, seed: int = 123
) -> np.ndarray:
    """Sample random pixel coordinates outside the mask but near its boundary.

    Returns array of shape (N, 2) with (x, y) coordinates.
    """
    import cv2

    h, w = mask.shape
    # Dilate to find near-boundary region
    dilated = cv2.dilate(mask, None, iterations=margin)
    outside_band = (dilated > 0) & (mask == 0)

    ys, xs = np.where(outside_band)
    if len(xs) == 0:
        return np.empty((0, 2), dtype=np.float32)

    rng = np.random.RandomState(seed)
    count = min(count, len(xs))
    indices = rng.choice(len(xs), size=count, replace=False)
    return np.column_stack([xs[indices], ys[indices]]).astype(np.float32)
