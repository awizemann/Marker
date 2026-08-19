---
id: t-fef7f866
title: Dark mode P2 — checkbox glyph per handoff (onAccent / checkEmpty tokens)
status: done
added: 2026-08-19
priority: high
---

## Description

Marker 0.9.0 dark mode, phase 2. Per the handoff prototype (TrapperKeeper Editor.dc.html lines ~399-400, 467): a CHECKED task is a filled primary-green rounded square with a checkmark in onAccent (white on light, #062012 on dark); an EMPTY task is a rounded square outlined 1.5px in check-empty (#C7D0C9 light / #48584F dark). Marker's 0.8.2 checkbox draws SF `square` (muted) / `checkmark.square.fill` (primary). Bring it to the design with two new optional MarkerTheme tokens: onAccent (default adaptive white/#062012) and checkEmpty (default adaptive #C7D0C9/#48584F). Depends on P1's adaptive helper and appearance-keyed image cache.

## Plan

1. Add onAccent + checkEmpty to MarkerTheme (public init default args, additive/non-breaking). 2. CodeWellTextView.checkboxImage: checked = checkmark.square.fill with palette [onAccent, primary]; unchecked = `square` in checkEmpty (weight .medium to approximate the 1.5px stroke). Cache keyed on (checked, side, effectiveAppearance name) and resolve colors under the view's effectiveAppearance when rendering the image. 3. Update TaskCheckbox gating tests if needed; add a test that the image differs between aqua and darkAqua. 4. build/test; fresh-eye audit.

## Artifacts

MarkerTheme.onAccent + checkEmpty tokens; CodeWellTextView checkbox palette [onAccent, primary] checked / checkEmpty .medium empty, cache keyed on all resolved colors; Tests/MarkerEditorTests/TaskCheckboxGlyphTests.swift (7 tests, incl. empirical palette-order probe). Known gap: SF symbol, not a pixel-exact 19px/6px-radius/1.5px design square.

