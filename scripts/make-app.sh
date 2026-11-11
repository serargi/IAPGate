#!/bin/bash
# Packages the built IAPGateApp executable into an IAPGate.app bundle
# and ad-hoc code-signs it so it can own windows during development.
#
# Usage:
#   ./scripts/make-app.sh [debug|release]
#
# Produces: ./build/IAPGate.app (plus ./build/IAPGate.zip for release).
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="IAPGate"
BUNDLE_ID="com.iapgate.mac"

echo "==> Building ($CONFIG)…"
if [ "$CONFIG" = "release" ]; then
    swift build -c release --product IAPGateApp
    BIN_DIR="$(swift build -c release --show-bin-path)"
else
    swift build --product IAPGateApp
    BIN_DIR="$(swift build --show-bin-path)"
fi

APP="$ROOT/build/$APP_NAME.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_DIR/IAPGateApp" "$APP/Contents/MacOS/IAPGateApp"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Copy any SwiftPM resource bundles (e.g. the asset catalog that carries
# the official Google sign-in button). In an .app, Bundle.module looks
# them up via Bundle.main.resourceURL, i.e. Contents/Resources/.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    echo "==> Bundling resources: $(basename "$bundle")"
    cp -R "$bundle" "$APP/Contents/Resources/"
done
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc code signing"
# Ad-hoc signature (-) is enough for local runs so the app can own
# windows. Distributable release builds use a Developer ID identity and
# notarization (see docs/RELEASE.md).
codesign --force --deep --sign - \
    --identifier "$BUNDLE_ID" \
    "$APP"

# For release builds, also produce a distributable zip to attach to a
# GitHub Release (what end users download).
if [ "$CONFIG" = "release" ]; then
    ZIP="$ROOT/build/IAPGate.zip"
    rm -f "$ZIP"
    # ditto preserves the bundle structure and resource forks.
    ( cd "$ROOT/build" && ditto -c -k --keepParent "$APP_NAME.app" "IAPGate.zip" )
    echo "==> Release zip: $ZIP"
fi

echo "==> Done: $APP"
echo "Launch with:  open \"$APP\""
