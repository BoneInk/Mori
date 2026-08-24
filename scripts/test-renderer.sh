#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${TMPDIR:-/tmp}/MoriRendererSmoke"
OUTPUT="$OUTPUT_DIR/renderer-smoke"

cd "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"
swiftc \
  Sources/Mori/Models.swift \
  Sources/Mori/MermaidRuntime.swift \
  Sources/Mori/MathRuntime.swift \
  Sources/Mori/MarkdownRenderer.swift \
  Tools/RendererSmoke/main.swift \
  -framework AppKit \
  -framework WebKit \
  -o "$OUTPUT"

"$OUTPUT"
