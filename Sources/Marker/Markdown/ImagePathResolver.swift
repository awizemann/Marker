//
//  ImagePathResolver.swift
//  Marker — (ex TrapperKeeperCore) Markdown (Images v1, t-c6f28efb)
//
//  Pure classification of a Markdown image destination (the `url` in `![alt](url)`) into what v1 can
//  do with it. NO I/O and NO security scope here — this only turns the raw string into a candidate
//  file URL (or a remote/unreachable verdict); the actual scoped read happens in the repository. Kept
//  Foundation-only + `nonisolated` so it's trivially unit-testable off any actor.
//

import Foundation

/// What an image destination resolves to. `relative`/`absolute` carry a candidate file URL whose
/// READABILITY still depends on a granted security scope (decided at read time); `remote` and
/// `unreachable` never read anything (v1 renders a placeholder for both).
public nonisolated enum ImageSource: Sendable, Equatable {
    /// A path relative to the open document's directory, resolved to a file URL.
    case relative(URL)
    /// An absolute file path (POSIX `/…`, `~/…`, or `file://…`).
    case absolute(URL)
    /// An `http(s)://` URL — not fetched in v1 (no network).
    case remote
    /// Empty, or a relative path with no document directory to resolve against.
    case unreachable

    /// The candidate file URL for a local source (relative/absolute); nil for remote/unreachable.
    public var fileURL: URL? {
        switch self {
        case .relative(let url), .absolute(let url): return url
        case .remote, .unreachable: return nil
        }
    }
}

public nonisolated enum ImagePathResolver {

    /// Classify a raw image destination. `documentDirectory` is the folder of the open document, used
    /// to resolve a relative path (nil when unknown → a relative path is `.unreachable`).
    public static func resolve(_ raw: String, relativeTo documentDirectory: URL?) -> ImageSource {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unreachable }

        // Remote — an explicit http(s) scheme. (Other schemes fall through and end up unreachable.)
        if let scheme = URL(string: trimmed)?.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" { return .remote }
            if scheme == "file" {
                if let url = URL(string: trimmed), url.isFileURL { return .absolute(url.standardizedFileURL) }
                return .unreachable
            }
        }

        // Absolute POSIX path.
        if trimmed.hasPrefix("/") {
            return .absolute(URL(fileURLWithPath: trimmed).standardizedFileURL)
        }
        // Home-relative.
        if trimmed.hasPrefix("~") {
            return .absolute(URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL)
        }

        // Relative — needs the document's directory. `standardizedFileURL` collapses any `..`; whether
        // the result is actually readable is enforced later by the security scope (an escaping `..`
        // simply won't fall inside a granted scope), so no containment check is needed here.
        guard let documentDirectory else { return .unreachable }
        return .relative(URL(fileURLWithPath: trimmed, relativeTo: documentDirectory).standardizedFileURL)
    }
}
