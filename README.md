# BG Remover for Mac

A native macOS menu bar app that removes image backgrounds and upscales results — all processed locally on your machine using ML models.

Built with Swift, SwiftUI, and AppKit. No cloud APIs. No subscriptions. Just drag, drop, and download.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **Menu bar app** — lives in your menu bar, always one click away
- **Notch animation** — floating panel appears from the notch with Apple-level spring animations
- **Drag & drop** — drop any image onto the panel
- **Background removal** — powered by U2-Net (via rembg), runs 100% locally
- **Image upscaling** — powered by Real-ESRGAN, enhances output quality
- **Before/after toggle** — compare original vs. processed result
- **Global shortcut** — `⌘⇧B` to toggle the panel from anywhere
- **Privacy first** — all processing happens on-device, nothing leaves your Mac

## How It Works

```
Input Image
  → Background Removal (rembg / U2-Net)
  → Upscaling (Real-ESRGAN 4x)
  → Optimized PNG Output
```

The app bridges to Python ML models via subprocess execution. Images are passed as temporary files — no network calls, no IPC complexity.

## Requirements

- macOS 14 (Sonoma) or later
- Python 3.9+
- ~2 GB disk space for ML models

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/yourusername/bg-remover-mac.git
cd bg-remover-mac
```

### 2. Install ML dependencies

```bash
chmod +x Scripts/setup_ml_models.sh
./Scripts/setup_ml_models.sh
```

This creates a Python virtual environment and installs:
- **rembg** — background removal using U2-Net
- **Real-ESRGAN** — neural network image upscaling
- Pre-downloads all model weights (~500 MB)

### 3. Build and run

```bash
swift build
swift run BGRemover
```

Or open in Xcode:

```bash
open Package.swift
```

## Project Structure

```
App/
├── BGRemoverApp.swift          # App entry point
├── Core/
│   ├── AppDelegate.swift       # Menu bar + window management
│   ├── FloatingPanelController.swift  # Notch-origin floating panel
│   ├── ImageProcessor.swift    # Processing engine
│   └── PipelineManager.swift   # Extensible pipeline orchestrator
├── Services/
│   └── PythonBridge.swift      # Swift ↔ Python subprocess bridge
├── State/
│   └── AppState.swift          # Observable state machine
├── UI/
│   ├── Animations/
│   │   └── NotchAnimator.swift # Spring presets + transitions
│   ├── Components/
│   │   ├── CheckerboardBackground.swift
│   │   └── DropZoneView.swift
│   └── Views/
│       ├── ErrorView.swift
│       ├── IdleView.swift
│       ├── MainContentView.swift
│       ├── ProcessingView.swift
│       └── ResultView.swift
└── Utils/
    ├── FileHelpers.swift
    └── ImageCache.swift

Scripts/
└── setup_ml_models.sh          # One-command ML setup

Resources/                      # ML models (downloaded by setup script)
```

## Architecture

### State Machine

The app uses a simple state machine with four phases:

| Phase | UI | Description |
|-------|-----|-------------|
| `idle` | Drop zone + upload button | Waiting for input |
| `removingBackground` | Compact capsule with progress | Running U2-Net |
| `upscaling` | Compact capsule with progress | Running Real-ESRGAN |
| `complete` | Expanded result view | Shows output + download |

### Animation System

All transitions use physically-based spring animations matching Apple's motion language:
- Panel appears from top-center (notch origin) with scale + opacity
- State transitions use asymmetric scale animations
- Processing indicators use pulse + shimmer effects

### Pipeline Extensibility

The `PipelineManager` accepts any `PipelineStep` conforming type. To add a new processing step:

```swift
struct MyCustomStep: PipelineStep {
    let name = "My Step"
    func process(input: URL) async throws -> URL {
        // Your processing logic
        return outputURL
    }
}
```

## Keyboard Shortcut

Default: **⌘⇧B** — toggles the floating panel.

Configurable via the `KeyboardShortcuts` package.

## Troubleshooting

### "Python 3 not found"
Install Python: `brew install python@3.11`

### "ModuleNotFoundError"
Re-run the setup script: `./Scripts/setup_ml_models.sh`

### "RealESRGAN model not found"
Ensure the `models/` directory contains `RealESRGAN_x4plus.pth`. The setup script downloads this automatically.

### Processing is slow
- First run downloads models and is slower
- GPU acceleration requires PyTorch with MPS support
- Large images (>4K) take longer — the app preserves full resolution

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Credits

- [rembg](https://github.com/danielgatis/rembg) — Background removal
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) — Image upscaling
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — Global hotkeys
