import Testing
import Foundation
@testable import Marker

@Suite("Markdown code-language detection")
struct MarkdownCodeLanguageTests {

    @Test("detects JavaScript from a bare (untagged) block — the reported paste")
    func javascriptFromBareBlock() {
        let code = """
        // Classic anti-pattern: error caught, logged, dropped
        async function getOrder(orderId) {
          const user = await fetchUser(orderId);
          console.error("Error:", err);
        }
        """
        #expect(MarkdownCodeLanguage.detect(code) == "javascript")
        // DISCRIMINATION: the exact bug — pasted JS wrapped in a bare ``` fence rendered without color.
        // Fails if the C-like signals (const/async/await/console.) aren't recognized.
    }

    @Test("TypeScript is split off from JS by type annotations")
    func typescriptByAnnotations() {
        #expect(MarkdownCodeLanguage.detect("const n: number = 1\nfunction f(): void {}") == "typescript")
        #expect(MarkdownCodeLanguage.detect("const n = 1\nconsole.log(n)") == "javascript")
        // DISCRIMINATION: fails if TS annotations don't route to the TS grammar, or plain JS is over-claimed as TS.
    }

    @Test("JSON is distinguished from a JS object literal")
    func jsonVsObjectLiteral() {
        #expect(MarkdownCodeLanguage.detect("{\n  \"name\": \"Ada\",\n  \"age\": 36\n}") == "json")
        // A JS object literal has code-y tokens (arrow/const) → NOT json.
        #expect(MarkdownCodeLanguage.detect("const o = { fn: () => 1 };") == "javascript")
        // DISCRIMINATION: fails if any `{`-leading text is called JSON (a JS literal would be mis-detected).
    }

    @Test("Swift and Python detect from bare blocks, without stealing Go/JS")
    func swiftAndPython() {
        #expect(MarkdownCodeLanguage.detect("func greet(name: String) -> String {\n  return \"hi\"\n}") == "swift")
        #expect(MarkdownCodeLanguage.detect("guard let x = y else { return }") == "swift")
        #expect(MarkdownCodeLanguage.detect("import SwiftUI\n\nstruct V: View {}") == "swift")
        #expect(MarkdownCodeLanguage.detect("def add(a, b):\n    return a + b") == "python")
        #expect(MarkdownCodeLanguage.detect("class Foo:\n    pass") == "python")
        // Neighbours must NOT be misclassified:
        #expect(MarkdownCodeLanguage.detect("package main\n\nfunc main() {}") == "go")   // Go func, not Swift
        #expect(MarkdownCodeLanguage.detect("const f = () => 1") == "javascript")         // arrow → JS, not Swift
        // DISCRIMINATION: fails if Swift's `func` steals Go, or the JS `=>`/`console.` guard is missing.
    }

    @Test("shared let/var/func don't cause cross-language misclassification (audit fixes)")
    func sharedKeywordsDontMisfire() {
        // Swift value type with only stored properties → swift (bare `let` is no longer a JS signal).
        #expect(MarkdownCodeLanguage.detect("struct Point {\n  let x = 1\n  var y = 2\n}") == "swift")
        // A braced Go handler with `func` + `var` must NOT be read as Swift (no Swift `->`).
        #expect(MarkdownCodeLanguage.detect("func handler(w http.ResponseWriter) {\n  var buf bytes.Buffer\n}") != "swift")
        // Rust `let mut` without `fn` must NOT be read as JavaScript.
        #expect(MarkdownCodeLanguage.detect("let mut v = vec![1, 2];") != "javascript")
        // DISCRIMINATION: fails if `let `/`var ` re-enter the JS signals, or the Swift `func` clause is
        // broad enough to grab a braced Go func — the exact over-eager cases the audit found.
    }

    @Test("markup, go, rust, and shell each detect on a distinctive signal")
    func otherLanguages() {
        #expect(MarkdownCodeLanguage.detect("<div class=\"x\">hi</div>") == "html")
        #expect(MarkdownCodeLanguage.detect("package main\n\nfunc main() {}") == "go")
        #expect(MarkdownCodeLanguage.detect("fn main() {\n  println!(\"hi\");\n}") == "rust")
        #expect(MarkdownCodeLanguage.detect("#!/bin/bash\necho $HOME") == "bash")
        #expect(MarkdownCodeLanguage.detect("export PATH=$PATH:/x\necho done") == "bash")   // leading command + $var
    }

    @Test("ambiguous or prose content returns nil (stays uncolored, never mis-highlighted)")
    func ambiguousIsNil() {
        #expect(MarkdownCodeLanguage.detect("just some english words here") == nil)
        #expect(MarkdownCodeLanguage.detect("npm install left-pad") == nil)   // no confident signal
        #expect(MarkdownCodeLanguage.detect("   ") == nil)
        // DISCRIMINATION: fails if the detector guesses on weak/ambiguous input — a wrong grammar would
        // mis-color prose. Conservative nil is the whole point.
    }
}
