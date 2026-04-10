#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Magic Wand — ML Environment Setup
# ──────────────────────────────────────────────
# Creates a Python venv and installs BiRefNet
# (state-of-the-art background removal).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$PROJECT_ROOT/venv"

echo "╔══════════════════════════════════════════╗"
echo "║   Magic Wand — ML Setup                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. Check Python ──────────────────────────
echo "→ Checking Python 3..."
if ! command -v python3 &>/dev/null; then
    echo "✗ Python 3 not found."
    echo "  Install via: brew install python@3.11"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
echo "  Found Python $PYTHON_VERSION"

# ── 2. Create virtual environment ────────────
echo ""
echo "→ Creating virtual environment..."
if [ -d "$VENV_DIR" ]; then
    echo "  Virtual environment already exists. Updating..."
else
    python3 -m venv "$VENV_DIR"
    echo "  Created at $VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

# ── 3. Upgrade pip ───────────────────────────
echo ""
echo "→ Upgrading pip..."
pip install --upgrade pip --quiet

# Fix SSL certificates
pip install certifi --quiet
export SSL_CERT_FILE=$(python3 -c "import certifi; print(certifi.where())")

# ── 4. Install BiRefNet dependencies ────────
echo ""
echo "→ Installing BiRefNet (state-of-the-art background removal)..."
pip install torch torchvision transformers Pillow numpy einops kornia timm --quiet
echo "  ✓ BiRefNet dependencies installed"

# ── 5. Pre-download BiRefNet model ──────────
echo ""
echo "→ Downloading BiRefNet model (~400MB)..."
python3 -c "
from transformers import AutoModelForImageSegmentation
model = AutoModelForImageSegmentation.from_pretrained(
    'ZhengPeng7/BiRefNet', trust_remote_code=True
)
print('  ✓ BiRefNet model ready')
"

# ── 6. Verify installation ──────────────────
echo ""
echo "→ Verifying installation..."
python3 -c "
import torch
print('  ✓ torch:', torch.__version__)
device = 'MPS (Apple Silicon GPU)' if torch.backends.mps.is_available() else 'CPU'
print('  ✓ device:', device)
"
python3 -c "
from transformers import AutoModelForImageSegmentation
print('  ✓ BiRefNet: OK')
"
python3 -c "
from PIL import Image
print('  ✓ Pillow: OK')
"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   ✓ Setup complete!                       ║"
echo "║                                            ║"
echo "║   Run the app:                             ║"
echo "║   swift build && swift run BGRemover       ║"
echo "╚══════════════════════════════════════════╝"
