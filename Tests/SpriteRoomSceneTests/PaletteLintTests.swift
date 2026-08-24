import Foundation
import Testing
@testable import SpriteRoomScene

/// **I7's stated enforcement, actually run.**
///
/// `CLAUDE.md` says the palette invariant is "enforced by lint over the asset
/// manifest, not by good intentions". The lint is real (
/// `scripts/lint-palette.py`, four checks) but until this file **nothing
/// invoked it**: no test shelled out to it, there is no CI directory in the
/// repository, and no hook calls it. Its only caller was a line in `README.md`
/// telling a human to type the command.
///
/// So `swift test` passing said nothing whatever about I7 over the shipped art.
/// It has been green because somebody remembered to type it, which is precisely
/// the "good intentions" the invariant claims not to rest on. Found by auditing
/// which invariants have enforcing tests; I7 was the only one of the eight whose
/// declared mechanism ran nowhere.
///
/// # Why this is the only test in the suite that spawns a process
///
/// It is a deliberate exception and should stay a lone one. The lint reads
/// `assets/manifest.json` and the processed art: the half of I7 that Swift
/// cannot see, because those bitmaps are pack files rather than anything the
/// scene draws. The complementary half (the bitmaps this repository authors:
/// badges, nameplate, `DeskWorkArt`, `HeldObjectArt`) is checked natively in
/// `DeskWorkArtTests` and `HeldObjectArtTests`, and needs no subprocess.
///
/// # Two gates, for two different absences
///
/// - **The art.** `assets/` is gitignored, so a fresh clone has the manifest and
///   none of the art it names. The lint would correctly fail there, and that
///   failure would be about the checkout rather than about the palette.
/// - **`python3`.** Skipped rather than failed if the interpreter is missing:
///   this suite's contract is Swift, and a machine without Python has not broken
///   the palette. `SPRITE_ROOM_REQUIRE_ART=1` already turns missing art into a
///   hard failure through `ArtAvailabilityTests`, which is the knob for a
///   release machine that must check everything.
struct PaletteLintTests {

    /// `/usr/bin/env python3`, or `nil` when there is no interpreter to find.
    static var hasPython: Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        probe.arguments = ["python3", "--version"]
        probe.standardOutput = Pipe()
        probe.standardError = Pipe()
        do {
            try probe.run()
            probe.waitUntilExit()
            return probe.terminationStatus == 0
        } catch {
            return false
        }
    }

    @Test(.enabled(if: SceneArt.isAvailable && PaletteLintTests.hasPython))
    func theI7PaletteLintPasses() throws {
        let script = SceneFixtures.repositoryRoot
            .appending(path: "scripts").appending(path: "lint-palette.py")
        #expect(FileManager.default.fileExists(atPath: script.path),
                "scripts/lint-palette.py has moved; I7 lost its only enforcement again")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path]
        process.currentDirectoryURL = SceneFixtures.repositoryRoot
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()

        // Read before waiting: the lint prints a per-theme table, and a pipe
        // that fills while nobody drains it deadlocks the child.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? "<unreadable output>"
        #expect(process.terminationStatus == 0, Comment(rawValue:
            "scripts/lint-palette.py exited \(process.terminationStatus). [I7]\n" + text))
    }
}
