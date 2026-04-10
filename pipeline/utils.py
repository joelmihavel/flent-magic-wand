"""Shared utilities for the background removal pipeline."""

from __future__ import annotations

import os
import sys
import numpy as np
from PIL import Image


def resize_max_dim(img: Image.Image, max_dim: int = 1024) -> Image.Image:
    """Resize so the longest side is max_dim, preserving aspect ratio.

    Returns the original if already smaller.
    """
    w, h = img.size
    if max(w, h) <= max_dim:
        return img
    scale = max_dim / max(w, h)
    return img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)


def save_debug(name: str, data, debug_dir: str | None = None):
    """Save an intermediate image when debug mode is active."""
    if debug_dir is None:
        return
    os.makedirs(debug_dir, exist_ok=True)
    path = os.path.join(debug_dir, f"{name}.png")
    if isinstance(data, np.ndarray):
        Image.fromarray((data * 255).clip(0, 255).astype(np.uint8)).save(path)
    elif isinstance(data, Image.Image):
        data.save(path)
    print(f"[debug] {path}", file=sys.stderr)
