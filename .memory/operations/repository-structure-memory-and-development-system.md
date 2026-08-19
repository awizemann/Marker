---
title: Repository Structure: Memory and Development System
type: note
permalink: marker/operations/repository-structure-memory-and-development-system
tags: [memory, git, managed-tiers]
source_paths: [CLAUDE.md]
source_paths_inferred: false
source_sha: b48441f70845423f7ecfb76d5cad6fb1d52d557d
created: 2026-08-19
updated: 2026-08-19
reviewed: 2026-08-19
reviewed_by: audit:claude-haiku-4-5
---

## Observations
- [rule] Do NOT `git add`/`commit` the managed tiers: `.memory/`, `wiki/`, `design/`, `code/`, `sessions/`, `documents/`, `vendors/`, `templates/`, `TASKS.md`, `tasks/`. User commits each via Memophant's per-tier secret-scanned bar. Leave them dirty. #git #git #managed
- [rule] Memory is the source of truth. Search before assuming; record durable decisions/learnings as memory notes or wiki pages — never in session-private/model memory. Edit existing note (`edit_memory`) rather than forking duplicates. #memory #memory #single-source
- [rule] Prefer `memophant` MCP tools for all read/write. Tool/app entry points carry guards (slug-gen, structure validation, write-time secret scan). #tooling #tools
- [rule] Secrets to Keychain via `set_vendor_credential` (fetch with `get_vendor_credential`). Never leave loose in chat or files. #secrets #secrets #security
- [rule] Agent artifacts (plans/reports/briefs) go to `documents/` (exact lowercase) via `write_tier_file(tier: "documents", path: …)`. Never to repo's `docs/` folder (that's the project's own docs) and never a case-variant like `Documents/`. #artifacts #artifacts #documents
- [rule] File memory notes under one of six folders: architecture, conventions, decisions, operations, project, roadmap — never the root. When grounded in code, pass `source_paths` (repo files it depends on) so Memory Health can drift-check. Unanchored code notes cannot be kept current. #structure #structure #drift-checking
