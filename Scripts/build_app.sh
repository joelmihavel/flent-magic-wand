#!/usr/bin/env bash
#
# Build Magic Wand.app (ad-hoc signed, self-contained) for distribution.
#
# Output: dist/Magic Wand.app  — drag-drop installable, no setup required.
#         dist/Magic Wand.zip  — shareable archive.
#
# The .app bundles `cwebp` for WebP encoding. AVIF + background removal
# use native macOS frameworks (ImageIO + Vision), so no Python / no models.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Magic Wand"
BUNDLE_ID="com.flent.magic-wand"
VERSION="1.0.0"
EXECUTABLE="BGRemover"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

echo "==> Cleaning dist/"
rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/bin"

echo "==> Building release binary (universal)"
swift build -c release \
    --arch arm64 \
    --arch x86_64

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

echo "==> Bundling cwebp"
CWEBP_SRC=""
for candidate in /opt/homebrew/bin/cwebp /usr/local/bin/cwebp; do
    if [ -x "$candidate" ]; then
        CWEBP_SRC="$candidate"
        break
    fi
done

if [ -z "$CWEBP_SRC" ]; then
    echo "ERROR: cwebp not found. Install with: brew install webp"
    exit 1
fi

cp "$CWEBP_SRC" "$APP_DIR/Contents/Resources/bin/cwebp"
chmod +x "$APP_DIR/Contents/Resources/bin/cwebp"
echo "    bundled from: $CWEBP_SRC"
file "$APP_DIR/Contents/Resources/bin/cwebp" | sed 's/^/    /'

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

echo "==> Ad-hoc signing nested cwebp first, then app"
codesign --force --sign - "$APP_DIR/Contents/Resources/bin/cwebp"
codesign --force --deep --sign - --options runtime "$APP_DIR" || \
    codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR" || true

echo "==> Creating zip archive"
cd "$DIST_DIR"
ditto -c -k --keepParent --sequesterRsrc "$APP_NAME.app" "$APP_NAME.zip"
cd "$ROOT"

echo ""
echo "✔ Build complete"
echo ""
echo "  App bundle:   $APP_DIR"
echo "  Shareable:    $DIST_DIR/$APP_NAME.zip"
echo ""
echo "  Users: unzip, drag Magic Wand.app to /Applications, right-click → Open"
echo "  (only needed the first time; macOS remembers after that)."
