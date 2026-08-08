import Foundation
import Testing

@testable import SpriteRoomApp

/// `themes.json` is the **first thing this app has ever persisted**
/// (ADR-002 §3d), so these tests are about what survives and what refuses to
/// become fatal — not about what any call returned.
///
/// The whole of §3d's failure list is here, and every one of them has the same
/// answer: the app launches, nothing throws, and every project takes its
/// derived default. A desk skin is never worth a dialog, and it is certainly
/// never worth a crash.
///
/// None of them touch the real `~/Library/Application Support/SpriteRoom/`.
/// That directory holds `settings-backup.json` while hooks are installed, and
/// that file is how `--remove-hooks` puts the user's configuration back byte
/// for byte; a test that wrote there could destroy it.
@MainActor
struct ThemeStoreTests {

    // MARK: Scaffolding

    final class Sandbox {
        let directory: URL
        var themes: URL { directory.appending(path: "themes.json") }
        var bad: URL { directory.appending(path: "themes.json.bad") }

        init() {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "spriteroom-themes-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        deinit {
            // A test that made the directory read-only has to hand it back
            // before the harness can clean up after itself.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        func write(_ text: String) {
            try? Data(text.utf8).write(to: themes)
        }

        var bytes: Data? { try? Data(contentsOf: themes) }
        var text: String? { bytes.map { String(decoding: $0, as: UTF8.self) } }

        @MainActor func store() -> ThemeStore { ThemeStore(url: themes) }

        /// Freeze the directory so any write into it fails.
        func sealDirectory() {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o500], ofItemAtPath: directory.path)
        }
    }

    /// Stands in for what §7's contract will produce once the manifest declares
    /// themes. Theme *names* are allowed to appear here and nowhere in
    /// `Sources/` — ADR-002 §8 item 5.
    static let catalog = ThemeCatalog(
        themes: [
            ThemeCatalog.Theme(id: "briefing", title: "Briefing Room", isAssignable: true),
            ThemeCatalog.Theme(
                id: "mission_control", title: "Mission Control", isAssignable: false),
            ThemeCatalog.Theme(id: "office", title: "Open Plan Office", isAssignable: true),
        ],
        defaultThemeID: "office")

    /// A stand-in for §8 item 2's `rendezvous`, which lives in
    /// `SpriteRoomScene`. Deterministic and obviously not a hash, so a test
    /// that passes because of this closure cannot be mistaken for a test of the
    /// real selection.
    static let derive: (String, [String]) -> String? = { _, pool in pool.first }

    /// The theme a project ends up with. Nothing else in the app is allowed to
    /// answer this question.
    static func resolve(_ cwd: String, _ store: ThemeStore) -> String? {
        catalog.themeID(for: cwd, stored: store.stored, derive: derive)
    }

    // MARK: §3d — every failure degrades to the derived default

    @Test func aMissingFileIsTheFirstRunCaseAndNotAFailure() {
        let sandbox = Sandbox()
        let store = sandbox.store()

        #expect(store.stored.isEmpty)
        #expect(store.load == .fresh)
        // Nothing was invented on disk just by asking.
        #expect(sandbox.bytes == nil)
        #expect(Self.resolve("/work/alpha", store) == "briefing")
    }

    @Test func aTruncatedFileIsSetAsideRatherThanWedgingThePicker() throws {
        let sandbox = Sandbox()
        let original = #"{"schema": 1, "themes": {"/work/alpha": "lib"#
        sandbox.write(original)

        let store = sandbox.store()
        #expect(store.stored.isEmpty)
        guard case .discarded = store.load else {
            Issue.record("a truncated file should be discarded, got \(store.load)")
            return
        }
        #expect(Self.resolve("/work/alpha", store) == "briefing")

        // "the user's bytes are still on disk if they want them" — §3d.
        let kept = try #require(try? Data(contentsOf: sandbox.bad))
        #expect(String(decoding: kept, as: UTF8.self) == original)
    }

    /// §3d lists five ways this file can be unusable and gives them all one
    /// answer. They are checked together because the point is that no one of
    /// them is special.
    @Test(arguments: [
        #"{"schema": 2, "themes": {"/work/alpha": "briefing"}}"#,
        #"{"schema": 1, "themes": []}"#,
        #"{"schema": 1}"#,
        #"["schema", 1]"#,
        "not json at all",
        "",
    ])
    func everyUnusableShapeMeansNoStoredChoices(_ contents: String) {
        let sandbox = Sandbox()
        sandbox.write(contents)

        let store = sandbox.store()
        #expect(store.stored.isEmpty, "\(contents) should have yielded no stored choices")
        #expect(Self.resolve("/work/alpha", store) == "briefing")
    }

    /// An entry naming a theme the manifest does not have falls back "*for that
    /// project only*, and the entry is left in the file, because the theme may
    /// come back" — §3d.
    @Test func anUnknownThemeIdFallsBackForThatProjectAloneAndIsNotDeleted() {
        let sandbox = Sandbox()
        sandbox.write("""
            {"schema": 1, "themes": {"/work/alpha": "rocket_lab", "/work/beta": "office"}}
            """)

        let store = sandbox.store()
        #expect(store.stored.count == 2)
        #expect(Self.resolve("/work/alpha", store) == "briefing")
        // The project whose choice we *can* honour is untouched by its
        // neighbour's bad entry.
        #expect(Self.resolve("/work/beta", store) == "office")
        // Still on disk, and still in memory, so it comes back with the theme.
        #expect(store["/work/alpha"] == "rocket_lab")
        #expect(sandbox.text?.contains("rocket_lab") == true)
    }

    /// Nothing in §3d may throw. The store is constructed on the launch path,
    /// before the first project is displayed.
    @Test func nothingAboutAnUnreadableFileIsFatal() {
        let sandbox = Sandbox()
        // A directory where the file should be: not missing, not readable,
        // not JSON. The nastiest of the five and the one most likely to be
        // handled by a `try!` somewhere.
        try? FileManager.default.createDirectory(
            at: sandbox.themes, withIntermediateDirectories: true)

        let store = sandbox.store()
        #expect(store.stored.isEmpty)
        #expect(Self.resolve("/work/alpha", store) == "briefing")
    }

    // MARK: A user pick round-trips

    @Test func aPickIsOnDiskInTheShapeTheAdrSpecifies() throws {
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.choose("mission_control", for: "/work/alpha")

        #expect(store.writeFailures == 0)
        let bytes = try #require(sandbox.bytes)
        let object = try #require(
            try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["schema"] as? Int == 1)
        #expect(object["themes"] as? [String: String] == ["/work/alpha": "mission_control"])
        // "Nothing else in the file." — §3d.
        #expect(Set(object.keys) == ["schema", "themes"])
    }

    @Test func aPickSurvivesARelaunch() {
        let sandbox = Sandbox()
        sandbox.store().choose("mission_control", for: "/work/alpha")

        // A second store over the same path is what the next launch does.
        let reread = sandbox.store()
        #expect(reread["/work/alpha"] == "mission_control")
        #expect(reread.load == .loaded(count: 1))
        #expect(Self.resolve("/work/alpha", reread) == "mission_control")
    }

    /// "No eviction." — §3d. A project you have not opened in a year is
    /// exactly the one whose choice you would be annoyed to lose.
    @Test func choosingForOneProjectKeepsEveryOtherProjectsChoice() {
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.choose("briefing", for: "/work/alpha")
        store.choose("office", for: "/work/beta")
        store.choose("mission_control", for: "/work/alpha")

        let reread = sandbox.store()
        #expect(reread.stored == ["/work/alpha": "mission_control", "/work/beta": "office"])
    }

    /// Keys are "the exact `cwd` strings the events carried" — §3d. The theme
    /// inherits the app's existing bucketing and invents no normalisation, so
    /// a trailing slash is a different project here exactly as it is
    /// everywhere else.
    @Test func theKeyIsTheCwdExactlyAsReceived() {
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.choose("briefing", for: "/work/alpha")
        store.choose("office", for: "/work/alpha/")

        // Through the file, not just through the dictionary: the exactness has
        // to survive a serialise and a parse, which is where a well-meaning
        // path cleanup would get applied.
        let reread = sandbox.store()
        #expect(reread["/work/alpha"] == "briefing")
        #expect(reread["/work/alpha/"] == "office")
        #expect(reread.stored.count == 2)
    }

    // MARK: The write is atomic

    /// §3d: "Write to a sibling temp file and `rename` over the target, so a
    /// crash mid-write cannot leave a truncated file."
    ///
    /// The observable form of that promise: a write that cannot complete leaves
    /// the previous good file exactly as it was — not truncated, not empty, not
    /// missing.
    @Test func aFailedWriteLeavesTheExistingGoodFileByteForByte() throws {
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.choose("briefing", for: "/work/alpha")
        let good = try #require(sandbox.bytes)

        sandbox.sealDirectory()
        store.choose("office", for: "/work/beta")

        #expect(sandbox.bytes == good)
        // "Write failures are counted, not surfaced." — §3d. The picker still
        // works for this launch; it forgets on the next.
        #expect(store.writeFailures == 1)
        #expect(store["/work/beta"] == "office")
        #expect(Self.resolve("/work/beta", store) == "office")

        // And what is on disk is still a *usable* file, not a survivor.
        let reread = sandbox.store()
        #expect(reread.stored == ["/work/alpha": "briefing"])
    }

    /// The temp file is a sibling and it does not outlive the write. A
    /// leftover would accumulate one file per pick in a directory the user did
    /// not ask us to fill.
    @Test func aSuccessfulWriteLeavesNothingBesideTheFile() throws {
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.choose("briefing", for: "/work/alpha")
        store.choose("office", for: "/work/alpha")

        let left = try FileManager.default.contentsOfDirectory(atPath: sandbox.directory.path)
        #expect(left == ["themes.json"], "left behind: \(left)")
    }

    /// The directory is created if it is not there — but only when there is
    /// something to write, and never on the read path.
    @Test func theSupportDirectoryIsMadeOnDemandAndNotOnLaunch() {
        let sandbox = Sandbox()
        let nested = sandbox.directory.appending(path: "SpriteRoom")
        let store = ThemeStore(url: nested.appending(path: "themes.json"))
        #expect(!FileManager.default.fileExists(atPath: nested.path))

        store.choose("briefing", for: "/work/alpha")
        #expect(FileManager.default.fileExists(atPath: nested.appending(path: "themes.json").path))
        #expect(store.writeFailures == 0)
    }

    /// The default location, stated once so a refactor that moves it is a
    /// failing test rather than a lost preference file. It sits beside
    /// `settings-backup.json` in a directory we already own — §3d, "no new
    /// location is introduced".
    @Test func theDefaultLocationIsBesideTheHookBackup() {
        #expect(ThemeStore.defaultURL().lastPathComponent == "themes.json")
        #expect(
            ThemeStore.defaultURL().deletingLastPathComponent().standardizedFileURL.path
                == HookInstaller.supportDirectory().standardizedFileURL.path)
    }
}

/// §3c, resolved in `SpriteRoomApp` only as far as it can be without the hash
/// that lives in `SpriteRoomScene`.
@MainActor
struct ThemeCatalogTests {

    static let catalog = ThemeStoreTests.catalog

    @Test func aStoredChoiceTheManifestStillHasWins() {
        #expect(
            Self.catalog.themeID(
                for: "/work/alpha",
                stored: ["/work/alpha": "mission_control"],
                derive: ThemeStoreTests.derive) == "mission_control")
    }

    /// The derived default draws from `assignable: true` only — §3e. A hash
    /// that picks a theme reading as a claim about the work has said something
    /// the user did not.
    @Test func theDerivedDefaultIsOfferedOnlyTheAssignablePool() {
        var seen: [String] = []
        _ = Self.catalog.themeID(for: "/work/alpha", stored: [:]) { _, pool in
            seen = pool
            return pool.first
        }
        #expect(seen == ["briefing", "office"])
    }

    /// §3c's last line. This is not a corner: it is today's manifest, and it is
    /// every user who has not run the import scripts.
    @Test func anEmptyPoolFallsAllTheWayToTheManifestDefault() {
        #expect(
            Self.catalog.themeID(for: "/work/alpha", stored: [:]) { _, _ in nil } == "office")
    }

    /// A manifest that declares no themes at all is the room this app ships
    /// today. There is no theme id to name, so there is none to return.
    @Test func anEmptyCatalogResolvesToNoThemeRatherThanAnInventedOne() {
        #expect(ThemeCatalog.empty.isEmpty)
        #expect(ThemeCatalog.empty.ids.isEmpty)
        #expect(
            ThemeCatalog.empty.themeID(
                for: "/work/alpha",
                stored: ["/work/alpha": "office"],
                derive: ThemeStoreTests.derive) == nil)
    }
}
