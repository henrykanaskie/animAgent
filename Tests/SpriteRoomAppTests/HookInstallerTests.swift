import Foundation
import Testing

@testable import SpriteRoomApp

/// The installer edits the user's live Claude Code configuration. A bad write
/// here does not break our app; it breaks every session on the machine at
/// once, including ones already running. So every one of these tests is about
/// what the file looks like *afterwards*, not about what the installer
/// returned.
///
/// None of them touch `~/.claude/settings.json`: each builds its own file in a
/// temporary directory. That is not squeamishness, it is the same rule
/// `docs/03-EVENT-MODEL.md` sets for capturing fixtures.
struct HookInstallerTests {

    // MARK: Scaffolding

    final class Sandbox {
        let directory: URL
        var settings: URL { directory.appending(path: "settings.json") }

        init() {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "spriteroom-installer-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func write(_ text: String) {
            try? Data(text.utf8).write(to: settings)
        }

        var bytes: Data? { try? Data(contentsOf: settings) }

        var object: [String: Any]? {
            guard let bytes else { return nil }
            return try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        }

        func installer(port: UInt16 = 8787) -> HookInstaller {
            HookInstaller(settingsURL: settings, port: port)
        }
    }

    /// Shaped like the real thing: keys we must not disturb, in an order and a
    /// formatting we have no business normalising.
    static let realistic = """
        {
          "permissions": {
            "allow": [
              "Bash(/some/python -c \\"import main\\")"
            ]
          },
          "model": "opus",
          "effortLevel": "high",
          "tui": "fullscreen",
          "theme": "dark",
          "remoteControlAtStartup": true
        }

        """

    // MARK: Additive

    @Test func installAddsOnlyTheHooksKeyAndChangesNoValue() throws {
        let sandbox = Sandbox()
        sandbox.write(Self.realistic)
        let before = try #require(sandbox.object)

        try sandbox.installer().install()
        let after = try #require(sandbox.object)

        #expect(Set(after.keys) == Set(before.keys).union(["hooks"]))
        for key in before.keys {
            #expect(
                NSDictionary(dictionary: [key: before[key]!]).isEqual(to: [key: after[key]!]),
                "\(key) was changed")
        }
    }

    @Test func installRegistersExactlyTheEventsWeConsume() throws {
        let sandbox = Sandbox()
        sandbox.write(Self.realistic)
        try sandbox.installer(port: 4242).install()

        let hooks = try #require(sandbox.object?["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.events))

        for (event, value) in hooks {
            let registrations = try #require(value as? [[String: Any]])
            #expect(registrations.count == 1)
            let entry = try #require(registrations.first)
            // `PostToolBatch` was captured working without a matcher and is
            // the only close path a permission-denied call has. It keeps the
            // shape it was observed under.
            if HookInstaller.eventsWithoutMatcher.contains(event) {
                #expect(entry["matcher"] == nil)
            } else {
                #expect(entry["matcher"] as? String == "*")
            }
            let hook = try #require((entry["hooks"] as? [[String: Any]])?.first)
            #expect(hook["type"] as? String == "http")
            #expect(hook["url"] as? String == "http://127.0.0.1:4242/hook")
            // There is no `async` field on the HTTP hook schema; the session
            // blocks on our answer, so this is a hard floor under our own
            // failure. [I5]
            #expect(hook["timeout"] as? Int == HookInstaller.timeout)
        }
    }

    /// Somebody else's hook on an event we also register must survive, and
    /// must survive the removal too.
    @Test func aForeignHookOnTheSameEventIsNeitherOverwrittenNorRemoved() throws {
        let sandbox = Sandbox()
        sandbox.write("""
            {
              "model": "opus",
              "hooks": {
                "PreToolUse": [
                  { "matcher": "Bash", "hooks": [{ "type": "command", "command": "echo hi" }] }
                ],
                "PreCompact": [
                  { "matcher": "*", "hooks": [{ "type": "command", "command": "tidy" }] }
                ]
              }
            }
            """)

        try sandbox.installer().install()
        var hooks = try #require(sandbox.object?["hooks"] as? [String: Any])
        var preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(preToolUse.count == 2)
        #expect(preToolUse.contains { ($0["hooks"] as? [[String: Any]])?
            .first?["command"] as? String == "echo hi" })

        #expect(try sandbox.installer().remove())
        hooks = try #require(sandbox.object?["hooks"] as? [String: Any])
        preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(preToolUse.count == 1)
        #expect((preToolUse[0]["hooks"] as? [[String: Any]])?
            .first?["command"] as? String == "echo hi")
        // An event we never touched is untouched.
        #expect((hooks["PreCompact"] as? [[String: Any]])?.count == 1)
    }

    // MARK: Reversible

    @Test func removeRestoresTheFileByteForByte() throws {
        let sandbox = Sandbox()
        sandbox.write(Self.realistic)
        let original = try #require(sandbox.bytes)

        try sandbox.installer().install()
        #expect(sandbox.bytes != original, "install wrote nothing")

        #expect(try sandbox.installer().remove())
        #expect(sandbox.bytes == original, "remove did not restore the original bytes")
    }

    /// The byte-exact restore must not be a way to silently discard somebody
    /// else's edit. Change the file while our hooks are in it and removal
    /// falls back to taking only our entries out.
    @Test func anEditMadeWhileInstalledSurvivesTheRemoval() throws {
        let sandbox = Sandbox()
        sandbox.write(Self.realistic)
        try sandbox.installer().install()

        var edited = try #require(sandbox.object)
        edited["theme"] = "light"
        edited["statusLine"] = ["type": "command"]
        try JSONSerialization.data(withJSONObject: edited, options: [.prettyPrinted])
            .write(to: sandbox.settings)

        #expect(try sandbox.installer().remove())
        let after = try #require(sandbox.object)
        #expect(after["theme"] as? String == "light")
        #expect(after["statusLine"] != nil)
        #expect(after["hooks"] == nil)
        #expect(after["model"] as? String == "opus")
    }

    @Test func removeIsANoOpWhenNothingOfOursIsThere() throws {
        let sandbox = Sandbox()
        sandbox.write(Self.realistic)
        let original = try #require(sandbox.bytes)
        #expect(try sandbox.installer().remove() == false)
        #expect(sandbox.bytes == original)
    }

    /// First run on a machine that has never had a settings file. We created
    /// it, so putting things back means it is gone again, not left behind
    /// empty.
    @Test func installingIntoNothingAndRemovingLeavesNothing() throws {
        let sandbox = Sandbox()
        #expect(sandbox.bytes == nil)
        try sandbox.installer().install()
        #expect(sandbox.object?["hooks"] != nil)
        #expect(try sandbox.installer().remove())
        #expect(FileManager.default.fileExists(atPath: sandbox.settings.path) == false)
    }

    // MARK: Idempotence

    @Test func reinstallingOnANewPortReplacesRatherThanAccumulates() throws {
        let sandbox = Sandbox()
        sandbox.write(Self.realistic)
        try sandbox.installer(port: 8787).install()
        try sandbox.installer(port: 9001).install()

        let hooks = try #require(sandbox.object?["hooks"] as? [String: Any])
        for (_, value) in hooks {
            let registrations = try #require(value as? [[String: Any]])
            #expect(registrations.count == 1)
        }
        #expect(try sandbox.installer(port: 9001).state() == .installed(port: 9001))
        #expect(try sandbox.installer(port: 8787).state()
            == .installedAtOtherPort(ports: [9001]))
    }

    @Test func stateIsAbsentUntilWeWriteAndAbsentAgainAfterWeRemove() throws {
        let sandbox = Sandbox()
        sandbox.write(Self.realistic)
        #expect(try sandbox.installer().state() == .absent)
        try sandbox.installer().install()
        #expect(try sandbox.installer().state() == .installed(port: 8787))
        #expect(try sandbox.installer().remove())
        #expect(try sandbox.installer().state() == .absent)
    }

    /// Recognition is by shape, so a hand-edited file still cleans up, and a
    /// hook that merely looks similar is left alone.
    @Test func recognitionIsByShapeAndDoesNotOverreach() {
        func entry(_ hook: [String: Any]) -> [String: Any] { ["hooks": [hook]] }
        let installer = HookInstaller(
            settingsURL: URL(fileURLWithPath: "/dev/null"), port: 8787)

        #expect(installer.isOurs(entry([
            "type": "http", "url": "http://127.0.0.1:8787/hook"])))
        // Another port is still ours: it is a stale install, and leaving it
        // behind is how a session ends up posting into nothing.
        #expect(installer.isOurs(entry([
            "type": "http", "url": "http://127.0.0.1:9999/hook"])))

        #expect(!installer.isOurs(entry([
            "type": "command", "command": "curl 127.0.0.1:8787/hook"])))
        #expect(!installer.isOurs(entry([
            "type": "http", "url": "http://127.0.0.1:8787/other"])))
        // Not loopback, not ours, and not something to delete on a user's
        // behalf.
        #expect(!installer.isOurs(entry([
            "type": "http", "url": "http://example.com:8787/hook"])))
    }

    // MARK: The block matches the documented one

    /// `.claude/settings.example.json` is what the repository tells a reader
    /// we write. If the two drift, one of them is a lie.
    @Test func theExampleBlockMatchesWhatWeActuallyWrite() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let example = root.appending(path: ".claude/settings.example.json")
        let data = try Data(contentsOf: example)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try #require(object["hooks"] as? [String: Any])

        #expect(Set(hooks.keys) == Set(HookInstaller.events))
        for (event, value) in hooks {
            let registrations = try #require(value as? [[String: Any]])
            let entry = try #require(registrations.first)
            #expect(
                (entry["matcher"] == nil) == HookInstaller.eventsWithoutMatcher.contains(event),
                "\(event): the example's matcher disagrees with the installer's")
            let hook = try #require((entry["hooks"] as? [[String: Any]])?.first)
            #expect(hook["type"] as? String == "http")
            #expect(hook["timeout"] as? Int == HookInstaller.timeout)
        }
    }
}

/// The first-run decision, separated from the dialog that asks it.
///
/// The branch that writes to `~/.claude/settings.json` is the part that has to
/// be right, and it should not need a screen to prove. The `NSAlert` itself
/// holds no logic and is not tested here.
struct HookFirstRunTests {

    private func sandbox() -> HookInstallerTests.Sandbox {
        let sandbox = HookInstallerTests.Sandbox()
        sandbox.write(HookInstallerTests.realistic)
        return sandbox
    }

    @Test func decliningWritesNothingAtAll() throws {
        let sandbox = sandbox()
        let original = try #require(sandbox.bytes)
        #expect(sandbox.installer().firstRun { .decline } == .declined)
        #expect(sandbox.bytes == original)
    }

    /// Nobody to ask is not the same as being told yes.
    @Test func noOneToAskIsNotConsent() throws {
        let sandbox = sandbox()
        let original = try #require(sandbox.bytes)
        #expect(sandbox.installer().firstRun { nil } == .declined)
        #expect(sandbox.bytes == original)
    }

    @Test func consentingWritesTheBlockAndTheQuestionIsNotAskedAgain() throws {
        let sandbox = sandbox()
        #expect(sandbox.installer().firstRun { .install } == .installed)
        #expect(try sandbox.installer().state() == .installed(port: 8787))

        var askedAgain = false
        let outcome = sandbox.installer().firstRun {
            askedAgain = true
            return .decline
        }
        #expect(outcome == .alreadyInstalled)
        #expect(!askedAgain, "an already-installed block must not re-ask")
    }

    /// A block left pointing at a port we are no longer on is a session
    /// posting into nothing. Fixing it is still a write, so it still asks.
    @Test func aStaleInstallOnAnotherPortIsOfferedAgain() throws {
        let sandbox = sandbox()
        try sandbox.installer(port: 8787).install()

        var asked = false
        let outcome = sandbox.installer(port: 9100).firstRun {
            asked = true
            return .install
        }
        #expect(asked)
        #expect(outcome == .reinstalled(from: [8787]))
        #expect(try sandbox.installer(port: 9100).state() == .installed(port: 9100))
    }

    @Test func aStaleInstallDeclinedIsLeftExactlyAsItWas() throws {
        let sandbox = sandbox()
        try sandbox.installer(port: 8787).install()
        let installed = try #require(sandbox.bytes)
        #expect(sandbox.installer(port: 9100).firstRun { .decline } == .declined)
        #expect(sandbox.bytes == installed)
    }
}
