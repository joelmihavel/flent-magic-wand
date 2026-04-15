# Magic Wand

A native macOS menu bar app for image cleanup. Remove backgrounds, compress to WebP, or compress to AVIF — all on-device, with a 30 KB size budget that keeps quality as high as it can fit.

Built with Swift, SwiftUI, and AppKit. No cloud APIs. No Python. No model downloads. Drag-drop installable.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **Menu bar app** — one click (or `⌘⇧B`) from anywhere
- **Three actions per image** — Remove Background / Compress to WebP / Compress to AVIF
- **Bulk upload** — drop or pick many images, processed in order
- **Budget-aware compression** — binary-searches the highest quality that fits under 30 KB, then progressively downscales if needed
- **ICC color profile preservation** — reads the source file through `CGImageSource` so color stays true
- **On-device only** — Apple Vision for background removal, ImageIO for AVIF, bundled `cwebp` for WebP
- **Before/after toggle** — compare original vs. background-removed result
- **Privacy first** — nothing leaves your Mac

## How It Works

| Action | Engine |
|--------|--------|
| Remove Background | Apple Vision (`VNGenerateForegroundInstanceMaskRequest`) → transparent PNG |
| Compress to WebP  | Bundled `cwebp` (libwebp) with quality binary search + downscale fallback |
| Compress to AVIF  | `CGImageDestination` (ImageIO, hardware-accelerated on Apple silicon) |

No Python, no ML model downloads, no network calls.

## Requirements

- macOS 14 (Sonoma) or later
- Apple silicon recommended (the bundled `cwebp` is arm64)

## Install (end users)

1. Download `Magic Wand.zip` from Releases (or build it yourself, below)
2. Unzip and drag `Magic Wand.app` to `/Applications`
3. Right-click → Open the first time (macOS Gatekeeper will warn; the app is ad-hoc signed)
4. The wand icon appears in your menu bar. Press `⌘⇧B` or click to open.

## Build from source

```bash
git clone https://github.com/joelmihavel/flent-magic-wand.git
cd flent-magic-wand
brew install webp            # provides cwebp for bundling
./Scripts/build_app.sh
```

Output:
- `dist/Magic Wand.app` — the app bundle
- `dist/Magic Wand.zip` — shareable archive

Or for dev:

```bash
swift run BGRemover
```

## Project Structure

```
App/
├── BGRemoverApp.swift              # App entry point
├── Core/
│   ├── AppDelegate.swift           # Menu bar + window management
│   ├── FloatingPanelController.swift
│   ├── ImageProcessor.swift        # Vision-based BG removal
│   └── ImageConverter.swift        # WebP (cwebp) + AVIF (ImageIO) encoders
├── State/
│   └── AppState.swift              # Observable state machine
└── UI/
    ├── Animations/NotchAnimator.swift
    ├── Components/                 # DropZoneView, CheckerboardBackground, …
    └── Views/                      # Idle / ActionChoice / Processing / Result / Error

Scripts/
└── build_app.sh                    # Universal build + bundles cwebp + codesigns
```

## Compression Budget

WebP and AVIF both target 30 KB per image:

1. Encode at `q=20` (floor). If it's still too big at source resolution, skip to step 3.
2. Binary-search quality in `[20, 95]` for the highest value that fits the budget.
3. If step 2 fails, downscale to 85% / 70% / 55% / 40% / 30% / 20% and retry the search.
4. Last resort: 15% scale at minimum quality.

The goal is "the best-looking image that fits," not "always 30 KB."

## Keyboard Shortcut

Default **⌘⇧B** — toggles the floating panel. Configurable via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).

## Troubleshooting

**"Magic Wand is damaged and can't be opened"** — Gatekeeper blocking ad-hoc signing. Run:
```bash
xattr -dr com.apple.quarantine "/Applications/Magic Wand.app"
```
Then right-click → Open.

**Build fails with "cwebp not found"** — install libwebp: `brew install webp`

## License

MIT License. See [LICENSE](LICENSE).

## Credits

- [libwebp / cwebp](https://chromium.googlesource.com/webm/libwebp) — WebP encoder (bundled)
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkeys
