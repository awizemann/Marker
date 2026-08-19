---
created: 2026-08-19
updated: 2026-08-19
---

# Building Marker

## Requirements

- Swift 6.2 or later
- macOS 14.0 or later
- Xcode 15.1 or later (recommended)

Swift 6.2's strict concurrency and MainActor default isolation are required. macOS 14 is the floor for `Observation` framework and `@Observable`/`@Bindable` (used throughout `EditorModel` and editor components).

For more on platform and concurrency constraints, see [[marker/architecture/platform-and-concurrency-settings]].

## Building from source

```bash
git clone https://github.com/awizemann/Marker.git
cd Marker

# Build the package
swift build

# Run tests
swift test

# Build for release (optimized)
swift build -c release
```

## Project structure

The repo is organized into managed tiers (managed by Memophant) and product targets:

- **`.memory/`** — structured decision records and architecture notes. Managed tier; do not git add.
- **`wiki/`** — this wiki. Managed tier; do not git add.
- **`Sources/Marker/`** — the pure engine: block parsing, inline scanning, GFM tables, code-block models, image resolution, editor state/commands.
- **`Sources/MarkerEditor/`** — TextKit 2 render/edit layer: `EditorView`, `CommandPaletteView`, `FormatBar`, wiki-link completion, theming.
- **`Sources/MarkerHighlighting/`** — tree-sitter integration: `CodeHighlighter` and vendored grammars.
- **`Tests/MarkerTests/`** — 182 tests for the core engine and editor logic.
- **`Tests/MarkerEditorTests/`** — 6 tests for geometry and spacing in the editor layer.
- **`Tests/MarkerHighlightingTests/`** — tests for syntax highlighting.
- **`docs/`** — integration guide and consumer documentation (hand-authored).

For full details on the managed tiers and development system, see [[marker/operations/repository-structure-memory-and-development-system]].

## Running tests

```bash
# All tests
swift test

# Core engine only
swift test --test-product MarkerTests

# Editor layer only
swift test --test-product MarkerEditorTests

# Highlighting only
swift test --test-product MarkerHighlightingTests

# Single test (example)
swift test --test-product MarkerTests CommandPaletteModelTests
```

Tests run on Swift strict concurrency, so all Sendable/MainActor constraints are enforced. Total: 188 tests (182 core/editor, 6 highlighting).

## Development workflow

1. **Make changes** in `Sources/` and `Tests/`.
2. **Build locally**: `swift build`.
3. **Run tests**: `swift test`.
4. **Commit to main** (no branching needed for small fixes; branch for larger work).

**Important**: Do not `git add` the managed tiers (`.memory/`, `wiki/`, `design/`, etc.). These are committed via Memophant's secret-scanned interface. Leave them dirty.

For integration into your app, see **[Consumer Integration](Consumer-Integration)** and the full guide at `docs/Integration.md`.

---
_Last updated: 2026-08-19_