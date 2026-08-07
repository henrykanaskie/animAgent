import Foundation
import Testing

/// `SpriteRoomCore` is what makes the interesting logic testable without a
/// screen, and the only thing keeping that true is that nobody imports a UI
/// framework into it. CLAUDE.md says this is checked; this is the check.
@Suite struct ImportBoundaryTests {

    /// Walk up from this file to the repository root.
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SpriteRoomCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    static let forbidden = ["AppKit", "SpriteKit", "SwiftUI", "UIKit", "Cocoa"]

    @Test func coreImportsNoUIFramework() throws {
        let core = Self.repoRoot.appending(path: "Sources/SpriteRoomCore")
        let files = try Self.swiftFiles(under: core)

        #expect(!files.isEmpty, "found no Swift files under \(core.path)")

        var violations: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                let module = trimmed
                    .dropFirst("import ".count)
                    .trimmingCharacters(in: .whitespaces)
                if Self.forbidden.contains(module) {
                    let name = file.path.replacingOccurrences(
                        of: Self.repoRoot.path + "/", with: "")
                    violations.append("\(name): import \(module)")
                }
            }
        }

        #expect(violations.isEmpty, """
            SpriteRoomCore must not import a UI framework:
            \(violations.joined(separator: "\n"))
            """)
    }

    static func swiftFiles(under directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
