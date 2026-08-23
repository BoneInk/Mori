#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="${1:-release}"
APP_DIR="$PROJECT_DIR/dist/Mori.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
swift build -c "$BUILD_MODE"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp ".build/$BUILD_MODE/Mori" "$CONTENTS_DIR/MacOS/Mori"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns" 2>/dev/null || true

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "$APP_DIR"
