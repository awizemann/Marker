---
title: Platform and Concurrency Settings
type: note
permalink: marker/architecture/platform-and-concurrency-settings
tags: [platform, swift, concurrency]
source_paths: [Package.swift]
source_paths_inferred: false
source_sha: b48441f70845423f7ecfb76d5cad6fb1d52d557d
created: 2026-08-19
updated: 2026-08-19
reviewed: 2026-08-19
reviewed_by: audit:claude-haiku-4-5
---

## Observations
- [decision] macOS 14.0 is the actual platform floor (not birthplace's 26). Observation/@Observable + @Bindable require 14; SwiftUI `onKeyPress` (CommandPaletteView) requires 14. Verify via Package.swift `platforms: [.macOS("14.0")]`. #minimum #platform #minimum
- [decision] Swift 6.2 with strict concurrency. MainActor default isolation (inherited from TrapperKeeperCore). Settings via `swiftLanguageMode(.v6)` + `.defaultIsolation(MainActor.self)`. Quote from Package.swift: 'Settings mirror TrapperKeeperCore exactly (Swift 6.2, MainActor default isolation)'. #concurrency #concurrency #isolation
- [adaptation] macOS 26-isms handled per-site: `glassEffect` availability-gated in CommandPaletteView (material + hairline below 26); WikiCompletionController's `isolated deinit` (macOS 15.4+ runtime) became explicit teardown via `EditorView.dismantleNSView`. #adaptation #compatibility #workaround
