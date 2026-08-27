#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${TMPDIR:-/tmp}/MoriDocumentStoreSmoke"
OUTPUT="$OUTPUT_DIR/document-store-smoke"
TEST_HOME="$OUTPUT_DIR/home-$$"

cd "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR" "$TEST_HOME"
swiftc \
  Sources/Mori/Models.swift \
  Sources/Mori/AppearanceManager.swift \
  Sources/Mori/MermaidRuntime.swift \
  Sources/Mori/MathRuntime.swift \
  Sources/Mori/MarkdownRenderer.swift \
  Sources/Mori/MarkdownExportResources.swift \
  Sources/Mori/MarkdownFileExporter.swift \
  Sources/Mori/DocumentStore.swift \
  Tools/DocumentStoreSmoke/main.swift \
  -framework AppKit \
  -framework CoreText \
  -framework UniformTypeIdentifiers \
  -framework WebKit \
  -o "$OUTPUT"

CFFIXED_USER_HOME="$TEST_HOME" "$OUTPUT"
