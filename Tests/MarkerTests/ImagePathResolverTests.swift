import Testing
import Foundation
@testable import Marker

@Suite("Image path resolver")
struct ImagePathResolverTests {
    private let docDir = URL(fileURLWithPath: "/docs/notes", isDirectory: true)

    @Test("http(s) destinations classify as .remote (never fetched in v1)")
    func remote() {
        #expect(ImagePathResolver.resolve("https://ex.com/a.png", relativeTo: docDir) == .remote)
        #expect(ImagePathResolver.resolve("http://ex.com/a.png", relativeTo: nil) == .remote)
    }

    @Test("relative paths resolve against the document directory")
    func relative() {
        #expect(ImagePathResolver.resolve("cat.png", relativeTo: docDir)
                == .relative(URL(fileURLWithPath: "cat.png", relativeTo: docDir).standardizedFileURL))
        #expect(ImagePathResolver.resolve("img/cat.png", relativeTo: docDir)
                == .relative(URL(fileURLWithPath: "img/cat.png", relativeTo: docDir).standardizedFileURL))
        // `..` is collapsed by standardization; real reachability is enforced later by the sandbox scope.
        #expect(ImagePathResolver.resolve("../shared/cat.png", relativeTo: docDir).fileURL?.path == "/docs/shared/cat.png")
    }

    @Test("absolute POSIX / tilde / file:// classify as .absolute")
    func absolute() {
        #expect(ImagePathResolver.resolve("/abs/cat.png", relativeTo: docDir)
                == .absolute(URL(fileURLWithPath: "/abs/cat.png").standardizedFileURL))
        #expect(ImagePathResolver.resolve("file:///abs/cat.png", relativeTo: nil)
                == .absolute(URL(string: "file:///abs/cat.png")!.standardizedFileURL))
        #expect(ImagePathResolver.resolve("~/Pictures/cat.png", relativeTo: nil).fileURL?.path
                == ("~/Pictures/cat.png" as NSString).expandingTildeInPath)
    }

    @Test("empty, whitespace, or relative-without-a-doc-dir is .unreachable")
    func unreachable() {
        #expect(ImagePathResolver.resolve("", relativeTo: docDir) == .unreachable)
        #expect(ImagePathResolver.resolve("   ", relativeTo: docDir) == .unreachable)
        #expect(ImagePathResolver.resolve("cat.png", relativeTo: nil) == .unreachable)
        // DISCRIMINATION: fails if a relative path is silently accepted without a base dir (would later
        // resolve against the process CWD — wrong + outside any granted scope).
    }
}
