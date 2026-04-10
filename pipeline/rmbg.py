"""Primary background removal model — RMBG-1.4.

Single-model, single-pass inference. No heuristics.
"""

from __future__ import annotations

import os
import numpy as np
import torch
from PIL import Image
from torchvision import transforms

_model = None
_device = None

MODEL_ID = "briaai/RMBG-1.4"
FALLBACK_ID = "ZhengPeng7/BiRefNet"


def _get_model():
    global _model, _device
    if _model is not None:
        return _model, _device

    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")

    from transformers import AutoModelForImageSegmentation

    # Try RMBG-1.4 first, fall back to BiRefNet
    model_id = MODEL_ID
    try:
        model = AutoModelForImageSegmentation.from_pretrained(
            MODEL_ID, trust_remote_code=True, local_files_only=True
        )
    except Exception:
        model = AutoModelForImageSegmentation.from_pretrained(
            FALLBACK_ID, trust_remote_code=True, local_files_only=True
        )
        model_id = FALLBACK_ID

    model.float().eval()
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    model.to(device)

    _model = model
    _device = device
    return _model, _device


def _extract_prediction(model_output) -> torch.Tensor:
    """Extract the finest prediction tensor from model output.

    Handles both RMBG-1.4 format (tuple of lists) and BiRefNet format (list of tensors).
    """
    if isinstance(model_output, (tuple, list)) and isinstance(model_output[0], list):
        return model_output[0][0].sigmoid().cpu()
    elif isinstance(model_output, (tuple, list)):
        return model_output[-1].sigmoid().cpu()
    return model_output.sigmoid().cpu()


def _normalize_mask(raw: np.ndarray) -> np.ndarray:
    """Normalize mask to [0, 1] and auto-correct inversion.

    RMBG-1.4 can output narrow ranges (e.g. 0.5–0.73) and sometimes inverts
    foreground/background. This handles both issues.
    """
    vmin, vmax = raw.min(), raw.max()
    if vmax - vmin > 1e-4:
        raw = (raw - vmin) / (vmax - vmin)
    else:
        return np.zeros_like(raw)

    # Detect inversion: border should be background (low), center should be foreground (high).
    h, w = raw.shape
    border = np.concatenate([raw[0, :], raw[-1, :], raw[:, 0], raw[:, -1]])
    center = raw[h // 4 : 3 * h // 4, w // 4 : 3 * w // 4]

    if border.mean() > center.mean() + 0.05:
        raw = 1.0 - raw

    return raw


def predict(img: Image.Image) -> np.ndarray:
    """Run RMBG inference. Returns a float32 alpha mask in [0, 1] at original resolution."""
    model, device = _get_model()
    orig_w, orig_h = img.size

    transform = transforms.Compose([
        transforms.Resize((1024, 1024)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])

    tensor = transform(img).unsqueeze(0).to(device)

    with torch.no_grad():
        out = model(tensor)

    pred = _extract_prediction(out)
    if pred.dim() == 4:
        pred = pred.squeeze(0)

    # Resize to original
    mask = transforms.functional.resize(
        pred, [orig_h, orig_w],
        interpolation=transforms.InterpolationMode.BILINEAR,
    )

    return _normalize_mask(mask[0].numpy().astype(np.float32))
