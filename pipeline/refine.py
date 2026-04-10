"""Mask refinement — edge smoothing and noise removal."""

from __future__ import annotations

import numpy as np
import cv2


def refine(mask: np.ndarray, blur_radius: int = 1, morph_kernel: int = 3) -> np.ndarray:
    """Refine a [0, 1] float32 mask: close holes, smooth edges, remove noise."""
    mask_u8 = (mask * 255).clip(0, 255).astype(np.uint8)

    # Morphological closing — fill small holes
    if morph_kernel > 0:
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (morph_kernel, morph_kernel))
        mask_u8 = cv2.morphologyEx(mask_u8, cv2.MORPH_CLOSE, kernel)

    # Light Gaussian blur on edge region only
    if blur_radius > 0:
        dilated = cv2.dilate(mask_u8, None, iterations=blur_radius)
        eroded = cv2.erode(mask_u8, None, iterations=blur_radius)
        edge_region = (dilated - eroded) > 0
        ksize = blur_radius * 2 + 1
        blurred = cv2.GaussianBlur(mask_u8, (ksize, ksize), 0)
        mask_u8 = np.where(edge_region, blurred, mask_u8)

    # Remove small noise blobs (< 0.3% of image area)
    mask_u8 = _remove_small_components(mask_u8, min_ratio=0.003)

    return mask_u8.astype(np.float32) / 255.0


def _remove_small_components(mask_u8: np.ndarray, min_ratio: float) -> np.ndarray:
    """Zero out connected components smaller than min_ratio of image area."""
    h, w = mask_u8.shape
    min_pixels = int(h * w * min_ratio)

    binary = (mask_u8 > 127).astype(np.uint8)
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)

    keep = np.zeros_like(binary)
    for i in range(1, num_labels):
        if stats[i, cv2.CC_STAT_AREA] >= min_pixels:
            keep[labels == i] = 1

    return mask_u8 * keep
