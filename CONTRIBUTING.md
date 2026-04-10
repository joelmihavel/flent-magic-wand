# Contributing to BG Remover

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

1. Follow the [README](README.md) setup instructions
2. Open `Package.swift` in Xcode for the best development experience
3. The app runs as a menu bar agent — look for the wand icon in your menu bar

## Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI for all new UI work
- Use `async/await` for concurrency (no completion handlers)
- Keep files focused — one primary type per file

## Adding a New Processing Step

The pipeline is designed for extensibility:

1. Create a new type conforming to `PipelineStep` in `App/Core/PipelineManager.swift`
2. Implement `process(input:) async throws -> URL`
3. Add it to the pipeline configuration in `AppState`

## Adding a New ML Model

1. Add the Python integration to `PythonBridge.swift`
2. Add the model download to `Scripts/setup_ml_models.sh`
3. Update the README with new requirements

## Pull Requests

- Keep PRs focused on a single change
- Include a description of what and why
- Test on macOS 14+ before submitting
- Screenshots appreciated for UI changes

## Reporting Issues

Include:
- macOS version
- Python version (`python3 --version`)
- Steps to reproduce
- Console output if applicable

## Architecture Decisions

- **Python bridge over CoreML**: We use Python subprocess for ML models because rembg and Real-ESRGAN have mature Python implementations. CoreML conversions are welcome as PRs but must match output quality.
- **No Electron/WebView**: This is a native app. All UI must be SwiftUI or AppKit.
- **Local processing only**: No network calls for image processing. Privacy is a core feature.
