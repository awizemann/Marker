---
title: Theme appearance adaptivity (light/dark)
type: note
permalink: marker/architecture/theme-appearance-adaptivity-light-dark
tags: [theme, dark-mode, appearance, MarkerTheme, CodeWellTextView]
source_paths: [Sources/MarkerEditor/MarkerTheme.swift, Sources/MarkerEditor/CodeWellTextView.swift, Tests/MarkerEditorTests/AdaptiveThemeTests.swift, Tests/MarkerEditorTests/RenderedAppearanceTests.swift]
source_paths_inferred: false
source_sha: d4f28a53cc9b8929f50fd64a5a0c3ee605e61d67
created: 2026-08-19
updated: 2026-08-19
---

# Theme appearance adaptivity (light/dark)

Marker (0.9.0+) has no appearance logic of its own. `MarkerTheme` colors are SwiftUI `Color`s; use
sites convert with `NSColor(theme.x)` at style/draw time. Empirically verified (2026-08-19):
`NSColor(Color(nsColor: NSColor(name:nil, dynamicProvider:)))` STAYS dynamic, including when
stored as an attributed-string `.foregroundColor`, so dynamic colors passed by the host re-resolve
under the view's effective appearance with no plumbing.

- `MarkerTheme.adaptive(light:lightAlpha:dark:darkAlpha:)` builds such a color from hex (mirrors
  TrapperKeeper's `TKColor.adaptive`). Consumers may pass static colors; they just don't adapt.
- Accent defaults are `public static let MarkerTheme.default…` (highlightBackground, tableZebra,
  activeLineTint, codeString/Constant/Type, onAccent, checkEmpty) — built once, referenced by the
  public init's default args. Dark values come from the TrapperKeeper dark-mode handoff token families
  (amber/white-hairline/green-lift/dirty-fg/cloud-fg/deep).
- The ONE place a color is frozen is the task-checkbox SF Symbol image cache in CodeWellTextView:
  tints are resolved under the view's `effectiveAppearance` and the cache key includes the appearance
  name + resolved components. `viewDidChangeEffectiveAppearance` invalidates the custom layers.
- Checkbox design: checked = `checkmark.square.fill` palette [onAccent, primary]; empty = `square`
  .medium in checkEmpty. Known gap vs the handoff: SF symbol, not a pixel-exact 19px/6px-radius/1.5px square.
- Headless render gotchas (tests): per-view `appearance` is not enough for `cacheDisplay` — wrap in
  `performAsCurrentDrawingAppearance`; the view must be in a window (checkbox cull uses visibleRect);
  never enable `drawsBackground` on the text view (it paints over wells/checkboxes).

Open question (Alan to decide): the handoff's fenced code blocks are dark `forest` wells with light
code text in BOTH appearances; Marker draws `theme.well` + `inkSoft`. Supporting that needs
`codeWell`/`codeInk` tokens (not added yet).


## Observations
- [architecture] NSColor(Color(nsColor: dynamic)) stays dynamic, even inside attributed strings — Marker needs no draw-time appearance plumbing #dark-mode
- [architecture] MarkerTheme.adaptive(light:dark:) is the public helper for building appearance-adaptive theme colors from hex #MarkerTheme
- [architecture] Accent defaults are public static lets (MarkerTheme.default…) with dark values from the TK dark-mode handoff #MarkerTheme
- [architecture] The checkbox symbol image cache in CodeWellTextView is the one frozen-color site; keyed by appearance name + resolved colors #CodeWellTextView
- [decision] Handoff's forest (dark-in-both-modes) code well is NOT adopted yet — needs codeWell/codeInk tokens; pending Alan's call #open-question
