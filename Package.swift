// swift-tools-version: 6.2
import PackageDescription

// Marker — a reusable Markdown engine for native Swift apps.
//
// Born from TrapperKeeper's editor (phase 1 of the extraction plan): the PURE core — block
// parser, inline scanner, GFM tables, code-block model + language detection, block diffing,
// image path/remote resolution, and the editor state/command engine. Foundation-level
// frameworks only (Foundation/Observation/CoreGraphics); no AppKit, no UI, no
// syntax-highlighting dependencies.
//
// Central design principle (inherited, non-negotiable): RAW-STRING STORAGE. The document text
// is the file's exact bytes; every model type addresses it by range and never mutates it, so a
// consumer's markdown round-trips byte-exact by construction.
//
// Sibling products (phase 2): MarkerEditor (the TextKit 2 gentle-syntax WYSIWYG layer, themed via
// `MarkerTheme` + the `CodeTokenProviding` seam) and MarkerHighlighting (tree-sitter code-fence
// highlighting) — kept out of this core so light consumers stay dependency-free. MarkerEditor
// depends on the core ONLY; MarkerHighlighting carries the tree-sitter payload and plugs into the
// editor through the seam.
//
// Settings mirror TrapperKeeperCore exactly (Swift 6.2, MainActor default isolation) so the
// extracted sources compile identically in their new home.
let markerSwiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "Marker",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "Marker", targets: ["Marker"]),
        .library(name: "MarkerEditor", targets: ["MarkerEditor"]),
        .library(name: "MarkerHighlighting", targets: ["MarkerHighlighting"]),
    ],
    dependencies: [
        // Syntax highlighting for fenced code blocks (t-7def242d): tree-sitter gives (range, capture)
        // tokens the editor maps to theme colors as attributes over the byte-exact storage.
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", from: "0.21.0"),
        // swift + python are NOT SPM deps: their grammar packages don't link cleanly as dependencies
        // (swift ships no generated src/parser.c; python's Package.swift adds scanner.c via a RELATIVE
        // `FileManager.fileExists` that fails when consumed as a dep → undefined external-scanner
        // symbols). We instead VENDOR their generated parser.c + scanner.c into local C targets below
        // (CTreeSitterSwift / CTreeSitterPython), which bypasses both bugs. css remains dropped (same
        // fileExists bug, low value for notes). JavaScript is served by the TypeScript grammar (JS ⊂ TS).
    ],
    targets: [
        .target(
            name: "Marker",
            swiftSettings: markerSwiftSettings
        ),
        // The TextKit 2 render/edit layer: EditorView + EditorStyler + code wells + grid tables.
        // Depends on the Marker core ONLY — no tree-sitter; code-fence coloring arrives through the
        // `CodeTokenProviding` seam (pass MarkerHighlighting's CodeHighlighter, or nothing).
        .target(
            name: "MarkerEditor",
            dependencies: ["Marker"],
            swiftSettings: markerSwiftSettings
        ),
        .target(
            name: "MarkerHighlighting",
            dependencies: [
                "Marker",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterGo", package: "tree-sitter-go"),
                .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                "CTreeSitterPython",
                "CTreeSitterSwift",
            ],
            // Vendored tree-sitter highlight queries (one `.scm` per language), loaded via
            // `Bundle.module` — robust in both `swift test` and the xcodebuild app (unlike reaching
            // into each grammar package's own bundle). Provenance/licences noted in queries/README.
            resources: [.copy("Resources/queries")],
            swiftSettings: markerSwiftSettings
        ),
        .testTarget(
            name: "MarkerTests",
            dependencies: ["Marker"],
            swiftSettings: markerSwiftSettings
        ),
        .testTarget(
            name: "MarkerHighlightingTests",
            dependencies: ["MarkerHighlighting"],
            swiftSettings: markerSwiftSettings
        ),
        // Vendored tree-sitter grammars as local C targets (see the dependencies note). Each mirrors
        // its upstream layout: generated src/parser.c + src/scanner.c, private headers under
        // src/tree_sitter, and a public `tree_sitter_<lang>()` header under include/.
        .target(
            name: "CTreeSitterPython",
            path: "Sources/CTreeSitterPython",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "CTreeSitterSwift",
            path: "Sources/CTreeSitterSwift",
            exclude: ["NOTICE.md"],
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
    ],
    cLanguageStandard: .c11
)
