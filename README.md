# Mori

Mori is a native macOS Markdown editor built for a calm, focused writing experience.

## Features

- Native Markdown editor with lightweight syntax highlighting
- Live rendered preview with three themes
- GitHub-style Markdown tables with alignment and responsive overflow
- Safe inline and block HTML elements, including styled spans, details, media, and relative local images
- Offline syntax highlighting for fenced code blocks across common languages
- Source-line anchored synchronization between editor and preview
- Reader mode for a clean, formatted-only view
- Outline navigation in both editing and reader modes
- Document outline and heading navigation
- Persistent recent-files directory with Finder actions
- Virtualized, recursive folder tree with expandable subdirectories and support for all file types
- Optional Markdown-only folder filter
- In-app Quick Look previews for images, PDFs, code, media, and other macOS-supported files
- Dedicated vertical document-outline column
- Independently closable file-library and outline panels
- Open, drag-and-drop, save, autosave, and Save As
- Focus mode and reading statistics
- HTML export with self-contained styling
- Keyboard shortcuts and native macOS menus

## Build

Requires macOS 14 or newer and the Swift 6 toolchain.

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/Mori.app
```

For development:

```bash
swift run Mori
```

The build script creates `dist/Mori.app` and applies an ad-hoc local signature. No full Xcode installation is required.
