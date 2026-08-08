import Foundation
import Testing

@testable import SpriteRoomApp

/// Quitting with the hook block still in `~/.claude/settings.json`.
///
/// **The defect.** Hooks are registered at user scope — one registration,
/// routed by `cwd`, which is the design. So they fire for every Claude Code
/// session on the machine, in every project, whether or not SpriteRoom is
/// listening. The moment the app is gone, every tool call in every session
/// POSTs to a dead port and Claude Code reports `ECONNREFUSED`. The maintainer
/// hit this during a restart, in their own session. A status viewer that
/// degrades the thing it watches has inverted its purpose; I5 says the app
/// never surfaces an error into the user's session, and this is that sentence
/// one process boundary further out.
///
/// **The fix has two halves and this file is about the second one.** Offering
/// is easy; the half that has to be right is that *no answer other than
/// "remove" writes anything*. `~/.claude/settings.json` is the user's file, the
/// install path asks, and the removal path has to match — removing silently
/// would be worse than the error, because it would quietly undo a deliberate
/// choice every time somebody quit and relaunched.
///
/// Every test here asserts on the **bytes of the file afterwards**, the same
/// rule `HookInstallerTests` sets, and none of them touch the real settings
/// file: each builds its own in a temporary directory.
struct HookQuitTests {

    typealias Sandbox = HookInstallerTests.Sandbox

    /// Records whether the question was put at all — which matters as much as
    /// the answer, because a dialog that appears when there is nothing of ours
    /// in the file is a dialog interrupting a quit for no reason.
    final class Asker {
        private(set) var asked = 0
        let answer: HookQuit?

        init(_ answer: HookQuit?) { self.answer = answer }

        func ask() -> HookQuit? {
            asked += 1
            return answer
        }
    }

    // MARK: Nothing of ours

    @Test func aFileWithNoHooksOfOursIsNeverEvenAskedAbout() throws {
        let sandbox = Sandbox()
        sandbox.write(HookInstallerTests.realistic)
        let before = try #require(sandbox.bytes)

        let asker = Asker(.remove)
        let outcome = sandbox.installer().atQuit(ask: asker.ask)

        #expect(outcome == .notInstalled)
        #expect(asker.asked == 0, "asked about hooks that are not in the file")
        #expect(sandbox.bytes == before)
    }

    @Test func anAbsentSettingsFileIsNotCreatedByQuitting() {
        let sandbox = Sandbox()
        let asker = Asker(.remove)

        #expect(sandbox.installer().atQuit(ask: asker.ask) == .notInstalled)
        #expect(asker.asked == 0)
        #expect(FileManager.default.fileExists(atPath: sandbox.settings.path) == false)
    }

    // MARK: The answers that write nothing

    /// Nobody to ask — a harness, a non-interactive run, `--no-quit-prompt`.
    ///
    /// The same rule the install path has, pointing the other way: a write to
    /// the user's configuration with nobody present is a write nobody agreed
    /// to. Not removing *is* the do-nothing answer, so silence lands on it.
    @Test func silenceLeavesTheHooksExactlyWhereTheyAre() throws {
        let sandbox = Sandbox()
        sandbox.write(HookInstallerTests.realistic)
        let installer = sandbox.installer()
        try installer.install()
        let installed = try #require(sandbox.bytes)

        let asker = Asker(nil)
        #expect(installer.atQuit(ask: asker.ask) == .kept)
        #expect(asker.asked == 1)
        #expect(sandbox.bytes == installed, "a nil answer wrote to the settings file")
        #expect(try installer.state() == .installed(port: 8787))
    }

    @Test func keepingThemWritesNothingAtAll() throws {
        let sandbox = Sandbox()
        sandbox.write(HookInstallerTests.realistic)
        let installer = sandbox.installer()
        try installer.install()
        let installed = try #require(sandbox.bytes)

        let asker = Asker(.keep)
        #expect(installer.atQuit(ask: asker.ask) == .kept)
        #expect(asker.asked == 1)
        #expect(sandbox.bytes == installed)
        #expect(try installer.state() == .installed(port: 8787))
    }

    // MARK: The answer that does

    /// Removal goes through `HookInstaller.remove()` and nowhere else, so it
    /// inherits the byte-for-byte restore from the install-time backup. There
    /// is deliberately no second write path: a quit-time path that
    /// re-serialised the file would normalise key order and whitespace, and
    /// "I only changed what I said I would" would stop being checkable with
    /// `diff`.
    @Test func removingThemPutsTheFileBackByteForByte() throws {
        let sandbox = Sandbox()
        sandbox.write(HookInstallerTests.realistic)
        let original = try #require(sandbox.bytes)
        let installer = sandbox.installer()
        try installer.install()
        #expect(sandbox.bytes != original)

        let asker = Asker(.remove)
        #expect(installer.atQuit(ask: asker.ask) == .removed)
        #expect(asker.asked == 1)
        #expect(sandbox.bytes == original, "the file is not what it was before we touched it")
        #expect(try installer.state() == .absent)
    }

    /// A machine that never had a settings file must not be left holding one.
    @Test func removingThemFromAMachineThatHadNoSettingsFileLeavesNone() throws {
        let sandbox = Sandbox()
        let installer = sandbox.installer()
        try installer.install()
        #expect(FileManager.default.fileExists(atPath: sandbox.settings.path))

        #expect(installer.atQuit(ask: { .remove }) == .removed)
        #expect(
            FileManager.default.fileExists(atPath: sandbox.settings.path) == false,
            "an empty settings file was left behind")
    }

    // MARK: Ours, at the wrong port

    /// Entries pointing at some other port are still ours, and they still cost
    /// the user a failed POST on every tool call. Offering only the exact-port
    /// case would leave the commonest stale install — an earlier run on a
    /// different `--port` — quietly unhandled.
    @Test func hooksPointingAtAnotherPortAreStillOffered() throws {
        let sandbox = Sandbox()
        sandbox.write(HookInstallerTests.realistic)
        try sandbox.installer(port: 9999).install()

        let installer = sandbox.installer(port: 8787)
        #expect(try installer.state() == .installedAtOtherPort(ports: [9999]))

        let asker = Asker(.remove)
        #expect(installer.atQuit(ask: asker.ask) == .removed)
        #expect(asker.asked == 1)
        #expect(try installer.state() == .absent)
    }

    // MARK: Somebody else's hooks

    /// Another tool's entries survive. `remove` matches ours by shape — an HTTP
    /// hook posting to `/hook` on loopback — and everything else in the file is
    /// somebody else's business.
    @Test func quittingDoesNotRemoveHooksThatAreNotOurs() throws {
        let sandbox = Sandbox()
        sandbox.write("""
            {
              "hooks": {
                "PreToolUse": [
                  {
                    "matcher": "*",
                    "hooks": [{"type": "command", "command": "echo not ours"}]
                  }
                ]
              }
            }
            """)
        let installer = sandbox.installer()
        try installer.install()

        #expect(installer.atQuit(ask: { .remove }) == .removed)

        let hooks = try #require(sandbox.object?["hooks"] as? [String: Any])
        let pre = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(pre.count == 1)
        let inner = try #require(pre[0]["hooks"] as? [[String: Any]])
        #expect(inner[0]["command"] as? String == "echo not ours")
    }

    // MARK: The flags that drive it

    /// `--quit-answer` is how a run with nobody to click a modal exercises the
    /// branch that writes. It is never a default, for the same reason
    /// `--consent` is not.
    @Test func theQuitAnswerFlagParsesBothAnswersAndNothingElse() {
        #expect(parse(["--quit-answer", "remove"])?.quitAnswer == .remove)
        #expect(parse(["--quit-answer", "keep"])?.quitAnswer == .keep)
        #expect(parse(["--quit-answer", "maybe"]) == nil)
        #expect(parse(["--quit-answer"]) == nil)
        // Absent is absent — not "keep", not "remove". Nothing may infer an
        // answer from the flag not being there.
        #expect(parse([])?.quitAnswer == nil)
        #expect(parse([])?.quitPrompt == true)
        #expect(parse(["--no-quit-prompt"])?.quitPrompt == false)
    }

    @Test func helpNamesTheWayOutOfTheDialog() {
        let text = usage()
        #expect(text.contains("--no-quit-prompt"))
        #expect(text.contains("--quit-answer"))
    }
}
