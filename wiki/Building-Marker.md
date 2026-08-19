---
created: 2026-08-19
updated: 2026-08-19
source_sha: 6a247df4f1c7c4836d594c3a528779bf9a688d50
source_paths: Sources/Marker, Sources/MarkerEditor, Sources/MarkerHighlighting, Tests/MarkerTests, Tests/MarkerEditorTests, Tests/MarkerHighlightingTests
source_paths_inferred: false
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
- **`Sources/Marker/`** — the pure engine: block parsing, inline scanning, GFM tables, code-block models, image resolution, outline, editor state/commands.
- **`Sources/MarkerEditor/`** — TextKit 2 render/edit layer: `EditorView`, `CommandPaletteView`, `FormatBar`, wiki-link completion, theming.
- **`Sources/MarkerHighlighting/`** — tree-sitter integration: `CodeHighlighter` and vendored grammars.
- **`Tests/MarkerTests/`** — 195 tests for the core engine and editor logic.
- **`Tests/MarkerEditorTests/`** — tests for geometry, spacing, and rendering in the editor layer.
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

Tests run on Swift strict concurrency, so all Sendable/MainActor constraints are enforced. Total: **234 tests** (195 core + editor logic, 6 highlighting, 33 AppKit editor — styling, TextKit 2 geometry, rendered light/dark).

## Cutting a release

Releases are **annotated git tags + a GitHub Release carrying the notes** (that Release *is* the
changelog — there is no CHANGELOG file). Versions are plain `MAJOR.MINOR.PATCH` with no `v` prefix
(`0.9.0`), and consumers that pin a version (ShabuBox) resolve the tag; TrapperKeeper builds the
local checkout by path and doesn't need it.

1. Green tree: `swift build` with no warnings, `swift test` green across all three test targets.
2. Commit on `main` (small fixes) or merge the branch (larger work). Update `README.md` /
   `docs/Integration.md` if the public surface or guidance changed.
3. Tag: `git tag -a 0.9.0 -m "0.9.0 — one-line summary"`.
4. Push (the repo owner pushes): `git push origin main 0.9.0`.
5. Publish the notes: `gh release create 0.9.0 --title "Marker 0.9.0" --notes "…"` — one paragraph
   in the house style: what changed, why, compatibility note for 0.7.0+ consumers, test count.
6. Bump the consumers and let them test; visual behaviour changes (e.g. a theme default moving)
   go in the notes even when they are source-compatible.

If a tag was created but never pushed, it's fine to re-point it locally (`git tag -f`); never move a
tag that is already on GitHub — cut a patch release instead.



## Development workflow

1. **Make changes** in `Sources/` and `Tests/`.
2. **Build locally**: `swift build`.
3. **Run tests**: `swift test`.
4. **Commit to main** (no branching needed for small fixes; branch for larger work).

**Important**: Do not `git add` the managed tiers (`.memory/`, `wiki/`, `design/`, etc.). These are committed via Memophant's secret-scanned interface. Leave them dirty.

For integration into your app, see **[Consumer Integration](Consumer-Integration)** and the full guide at `docs/Integration.md`.

---
_Last updated: 2026-08-19_