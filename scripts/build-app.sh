#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="${1:-release}"
APP_DIR="$PROJECT_DIR/dist/Mori.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"

if [[ "$BUILD_MODE" == "release" ]]; then
  ARCHITECTURES=(x86_64 arm64)
  ARCH_BINARIES=()
  for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
    SCRATCH_DIR="$PROJECT_DIR/.build-$ARCHITECTURE"
    swift build -c release \
      --triple "$ARCHITECTURE-apple-macosx14.0" \
      --scratch-path "$SCRATCH_DIR"
    ARCH_BINARIES+=("$SCRATCH_DIR/$ARCHITECTURE-apple-macosx/release/Mori")
  done
  mkdir -p "$PROJECT_DIR/.build-universal/release"
  xcrun lipo -create "${ARCH_BINARIES[@]}" -output "$PROJECT_DIR/.build-universal/release/Mori"
  BUILT_EXECUTABLE="$PROJECT_DIR/.build-universal/release/Mori"
else
  swift build -c "$BUILD_MODE"
  BUILT_EXECUTABLE="$PROJECT_DIR/.build/$BUILD_MODE/Mori"
fi

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BUILT_EXECUTABLE" "$CONTENTS_DIR/MacOS/Mori"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns" 2>/dev/null || true
cp -R "$PROJECT_DIR/Resources/Mermaid" "$CONTENTS_DIR/Resources/Mermaid"
cp -R "$PROJECT_DIR/Resources/KaTeX" "$CONTENTS_DIR/Resources/KaTeX"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "$APP_DIR"
