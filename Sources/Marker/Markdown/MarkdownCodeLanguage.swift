//
//  MarkdownCodeLanguage.swift
//  TrapperKeeperCore — Markdown
//
//  Best-effort language guess for a fenced code block that has NO explicit ```lang tag, so the editor
//  can still syntax-highlight it (like GitHub auto-detecting a bare fence). It's a RENDER decision —
//  attributes only, the source bytes are never changed — and deliberately CONSERVATIVE: it returns a
//  language only on a distinctive signal, otherwise nil, so an ambiguous snippet stays plain rather
//  than mis-highlighted. Scoped to the grammars we can actually highlight; an explicit fence language
//  always wins over this.
//

import Foundation

public enum MarkdownCodeLanguage {

    /// A canonical language id (matching `CodeHighlighter`) for `code`, or nil when nothing is a
    /// confident match. Order matters: the most distinctive shapes (data/markup) are ruled in first,
    /// and the C-like family (JS/TS) is the last, broadest bucket.
    public static func detect(_ code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // HTML/XML — a closing tag or doctype is unmistakable markup.
        if lower.hasPrefix("<!doctype") || contains(code, #"</[a-zA-Z]"#) {
            return "html"
        }

        // JSON — starts like data ({ or [), is quoted, and carries none of the code-y tokens that a JS
        // object literal would (functions, arrows, comments, declarations).
        if let first = trimmed.first, first == "{" || first == "[" {
            let codey = ["function", "=>", "const ", "let ", "var ", "//", "/*"].contains { code.contains($0) }
            if !codey && trimmed.contains("\"") { return "json" }
        }

        // Shell — a shebang, or a line that begins with a common command AND uses a $variable.
        if trimmed.hasPrefix("#!") && lower.contains("sh") { return "bash" }
        if contains(code, #"(?m)^\s*(echo|export|sudo|cd|grep|cat|mkdir|rm|cp|mv|curl) "#) && code.contains("$") {
            return "bash"
        }

        // Go — a package declaration, or `func` together with the `:=` short-var operator.
        if contains(code, #"(?m)^\s*package \w"#) { return "go" }
        if code.contains("func ") && code.contains(":=") { return "go" }

        // Rust — `fn` alongside a Rust-ism (return arrow, `let mut`, a `!` macro, or path `::`).
        if code.contains("fn ") &&
            (code.contains("->") || code.contains("let mut ") || code.contains("println!") || code.contains("::")) {
            return "rust"
        }

        // Python — def/class at a line start (colon-blocks, no braces or semicolons), or a leading
        // import/from with a colon-terminated block. `def`/`class` are unmistakable vs the brace langs.
        if contains(code, #"(?m)^\s*(def|class|async def|elif) "#) && !code.contains("{") && !code.contains(";") {
            return "python"
        }
        if contains(code, #"(?m)^\s*(import|from) \w"#) && !code.contains("{") && !code.contains(";")
            && contains(code, #"(?m):\s*$"#) {
            return "python"
        }

        // Swift — `func`/`guard`/a Swift import or property-wrapper attribute, and NONE of the JS/TS
        // tells (`=>`, `console.`, `function `). `func` (not `function`) + no `:=` also separates it
        // from Go (ruled in above), so reaching here with those signals means Swift.
        if !code.contains("=>") && !code.contains("console.") && !code.contains("function ") &&
            (code.contains("guard ") ||
             contains(code, #"(?m)^\s*import (Foundation|SwiftUI|UIKit|Combine|SwiftData|OSLog)\b"#) ||
             contains(code, #"@(State|Binding|Observable|MainActor|Published|Environment|StateObject)\b"#) ||
             (code.contains("func ") && code.contains("->")) ||     // Swift return arrow (Go/JS don't use `->`)
             ((code.contains("struct ") || code.contains("enum ")) && code.contains("{")   // value type w/ members
              && (code.contains("let ") || code.contains("var ") || code.contains("func ")))) {
            return "swift"
        }

        // JS/TS — the C-like family. Require a real JS signal (NOT bare `let`/`var`, which Swift/Rust
        // share — those alone stay ambiguous → nil rather than a wrong colour), then split TS by annotations.
        let jsSignals = ["=>", "const ", "function", "console.", "await ", "async ", "document.", "require(", "export "]
        if jsSignals.contains(where: code.contains) {
            let tsSignals = [": string", ": number", ": boolean", ": void", "interface ", "<T>", "as string", "as number"]
            return tsSignals.contains(where: code.contains) ? "typescript" : "javascript"
        }
        return nil
    }

    private static func contains(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
