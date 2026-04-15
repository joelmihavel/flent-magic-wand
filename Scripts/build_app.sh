#!/usr/bin/env bash
#
# Build Magic Wand.app (ad-hoc signed) and package it for distribution.
#
# Output: dist/Magic Wand/Magic Wand.app + Scripts/ + pipeline/ + README.txt
#         dist/Magic Wand.zip (shareable archive)
#
# Users still need to run Scripts/setup_ml_models.sh inside the unzipped
# folder once to create the Python venv. The app itself is ready to launch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Magic Wand"
BUNDLE_ID="com.flent.magic-wand"
VERSION="1.0.0"
EXECUTABLE="BGRemover"
DIST_DIR="$ROOT/dist"
STAGE_DIR="$DIST_DIR/$APP_NAME"
APP_DIR="$STAGE_DIR/$APP_NAME.app"

echo "==> Cleaning dist/"
rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "==> Building release binary (universal)"
swift build -c release \
    --arch arm64 \
    --arch x86_64

# SwiftPM places the universal binary here when multiple arches are requested.
UNIVERSAL_BIN=""
for candidate in \
    "$ROOT/.build/apple/Products/Release/$EXECUTABLE" \
    "$ROOT/.build/release/$EXECUTABLE"; do
    if [ -f "$candidate" ]; then
        UNIVERSAL_BIN="$candidate"
        break
    fi
done

if [ -z "$UNIVERSAL_BIN" ]; then
    echo "ERROR: Could not locate built binary. Looked in:"
    echo "  .build/apple/Products/Release/$EXECUTABLE"
    echo "  .build/release/$EXECUTABLE"
    exit 1
fi

echo "==> Using binary: $UNIVERSAL_BIN"
file "$UNIVERSAL_BIN" | sed 's/^/    /'

cp "$UNIVERSAL_BIN" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE"

# Copy SwiftPM resource bundles alongside the binary (if any).
shopt -s nullglob
for bundle in "$ROOT"/.build/apple/Products/Release/*.bundle \
              "$ROOT"/.build/release/*.bundle; do
    cp -R "$bundle" "$APP_DIR/Contents/Resources/" 2>/dev/null || true
done
shopt -u nullglob

echo "==> Writing Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --deep --sign - --options runtime "$APP_DIR" || \
    codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR" || true

echo "==> Staging sidecar files (Scripts/, pipeline/)"
cp -R "$ROOT/Scripts" "$STAGE_DIR/Scripts"
cp -R "$ROOT/pipeline" "$STAGE_DIR/pipeline"
# Drop compiled caches
find "$STAGE_DIR" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$STAGE_DIR" -name "*.pyc" -delete 2>/dev/null || true

cat > "$STAGE_DIR/README.txt" <<'README'
Magic Wand — macOS background removal + WebP/AVIF compression
==============================================================

FIRST-TIME SETUP
----------------
1. Move this entire "Magic Wand" folder wherever you want it to live
   (e.g. ~/Applications/Magic Wand/). Keep all the files together —
   the .app needs its siblings (Scripts/, pipeline/, venv/).

2. Open Terminal and run the one-time setup (installs Python deps +
   ML models into a local venv/, ~2 GB):

       cd "<path-to-folder>/Magic Wand"
       ./Scripts/setup_ml_models.sh

3. Launch the app: right-click "Magic Wand.app" -> Open.
   macOS will warn that the developer is unverified — click Open anyway.
   (Only needed the first time; after that, double-click works.)

DAILY USE
---------
• The app lives in your menu bar. Click the wand icon, or press ⌘⇧B.
• Drop one or many images onto the panel, then pick an action:
  Remove Background / Compress to WebP / Compress to AVIF.
• WebP/AVIF outputs are capped at ~30 KB each with the best quality
  that fits the budget.

REQUIREMENTS
------------
• macOS 14 (Sonoma) or later
• Python 3.9+ installed (the setup script needs it to build the venv)
• ~2 GB free disk for ML models

TROUBLESHOOTING
---------------
• "damaged, can't be opened" — this is macOS Gatekeeper blocking the
  ad-hoc-signed app. Fix:
      xattr -dr com.apple.quarantine "Magic Wand.app"
  Then right-click -> Open.
• "Python not found" — re-run ./Scripts/setup_ml_models.sh from the
  folder containing the .app.
README

echo "==> Creating zip archive"
cd "$DIST_DIR"
# Use ditto for macOS-aware archiving (preserves signatures + metadata)
ditto -c -k --keepParent --sequesterRsrc "$APP_NAME" "$APP_NAME.zip"
cd "$ROOT"

echo ""
echo "✔ Build complete"
echo ""
echo "  App bundle:   $APP_DIR"
echo "  Shareable:    $DIST_DIR/$APP_NAME.zip"
echo ""
echo "  Send the zip to your users. Tell them to unzip, run"
echo "  ./Scripts/setup_ml_models.sh once, then right-click -> Open"
echo "  the app."
