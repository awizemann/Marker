# Marker

**Marker is a reusable Markdown engine for native Swift apps** — the editor from
[TrapperKeeper](https://trapperkeeper.co), extracted into a Swift package so other macOS apps can
embed a live-rendering, byte-exact Markdown editor without forking it.

One idea underpins everything: **the document is the file's exact bytes.** Marker never converts
Markdown into a rich model and back. It parses the raw text into *ranges*, styles those ranges in
place, and writes the same bytes out. Your users' files round-trip unchanged by construction.

## What's in the box

| Product | What it is | Depends on |
|---|---|---|
| **Marker** (core) | Block parser, inline scanner, GFM tables, code-block model + language detection, block diffing, document outline, editor state (`EditorModel`) and commands (`EditorCommands`), command-palette model. Foundation only. | — |
| **MarkerEditor** | The TextKit 2 editor for macOS: `EditorView` (live WYSIWYG or raw source), `CommandPaletteView` (⌘K), `FormatBar`, wiki-link completion. Themed via `MarkerTheme`, light and dark. | Marker |
| **MarkerHighlighting** | Tree-sitter syntax colouring for code fences (JSON, JS/TS, Swift, Python, Bash, Go, Rust, HTML). Optional. | Marker |

## Start here

- **New to the codebase?** Read [Architecture Overview](Architecture-Overview), then
  [Text Storage and Addressing](Text-Storage-and-Addressing) — the invariant every file respects.
- **Embedding Marker in an app?** [Consumer Integration](Consumer-Integration) walks through the theme
  and every seam. The full, hand-maintained guide lives in the repo at `docs/Integration.md`.
- **Working on the package?** [Building Marker](Building-Marker) — requirements, layout, tests,
  and how a release is cut.
- **Product deep-dives:** [Marker Core](Marker-Core) · [MarkerEditor](MarkerEditor) ·
  [MarkerHighlighting](MarkerHighlighting).

## Current release

**0.9.0** (2026-08-19) — appearance-adaptive theming (light & dark), task checkboxes drawn per the
TrapperKeeper design, lenient task boxes (`[ x]`), code wells with breathing room. Release notes live
on [GitHub Releases](https://github.com/awizemann/Marker/releases). Platform floor: macOS 14,
Swift 6 language mode with MainActor default isolation.

## Who uses it

TrapperKeeper (writing app — consumes the local checkout by path) and ShabuBox (notes pane inside a
larger app — consumes a versioned tag). Both wire the same seams; see the Consumer Integration page.

## How this wiki is kept

Pages are Markdown in the repo's `wiki/` folder, managed by Memophant and regenerated against the
code (the `source_sha` in each page's frontmatter says which commit it was checked against).
Conventions and the publish secret-scan are in [Wiki Maintenance](Wiki-Maintenance).

---
_Last updated: 2026-08-19_
