#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${TMPDIR:-/tmp}/MirrorDocumentStoreSmoke"
OUTPUT="$OUTPUT_DIR/document-store-smoke"
TEST_HOME="$OUTPUT_DIR/home-$$"

cd "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR" "$TEST_HOME"
swiftc \
  Sources/Mirror/Models.swift \
  Sources/Mirror/LegacyBrandMigration.swift \
  Sources/Mirror/AppearanceManager.swift \
  Sources/Mirror/MermaidRuntime.swift \
  Sources/Mirror/MathRuntime.swift \
  Sources/Mirror/MarkdownRenderer.swift \
  Sources/Mirror/MarkdownExportResources.swift \
  Sources/Mirror/MarkdownFileExporter.swift \
  Sources/Mirror/DocumentStore.swift \
  Tools/DocumentStoreSmoke/main.swift \
  -framework AppKit \
  -framework CoreText \
  -framework UniformTypeIdentifiers \
  -framework WebKit \
  -o "$OUTPUT"

CFFIXED_USER_HOME="$TEST_HOME" "$OUTPUT"
