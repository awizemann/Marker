// swift-tools-version: 6.2
import PackageDescription

// Marker — a reusable Markdown engine for native Swift apps.
//
// Born from TrapperKeeper's editor (phase 1 of the extraction plan): the PURE core — block
// parser, inline scanner, GFM tables, code-block model + language detection, block diffing,
// image path/remote resolution, and the editor state/command engine. Foundation/Observation
// only; no AppKit, no UI, no syntax-highlighting dependencies.
//
// Central design principle (inherited, non-negotiable): RAW-STRING STORAGE. The document text
// is the file's exact bytes; every model type addresses it by range and never mutates it, so a
// consumer's markdown round-trips byte-exact by construction.
//
// Planned sibling products (phase 2+): MarkerEditor (the TextKit 2 gentle-syntax WYSIWYG layer,
// themed via a token protocol) and MarkerHighlighting (tree-sitter code-fence highlighting) —
// kept out of this core so light consumers stay dependency-free.
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
    ],
    targets: [
        .target(
            name: "Marker",
            swiftSettings: markerSwiftSettings
        ),
        .testTarget(
            name: "MarkerTests",
            dependencies: ["Marker"],
            swiftSettings: markerSwiftSettings
        ),
    ]
)
