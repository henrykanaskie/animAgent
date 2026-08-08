import Foundation
import Testing

@testable import SpriteRoomApp
import SpriteRoomCore
import SpriteRoomScene

/// `--render` and the room it draws.
///
/// **The defect.** `--render` built a `RoomScene` with no theme and handed the
/// `SceneDirector` no theme either, so it always drew the plain office. Theme
/// selection lived only in `RoomHost`, which only the `--live` path constructs.
/// That made the offscreen renderer unable to show what the app will actually
/// draw — and `--render` is the *safe* alternative to `--panel-render`, which
/// reveals the real panel over whatever you are doing. So the harness you are
/// told to use instead was the one that could not answer the question.
///
/// Two things are asserted here and they are different claims:
///
/// 1. **The default is derived, not the manifest default.** With no `--theme`,
///    the room is what `ThemeSelector.theme(for:stored:manifest:)` returns for
///    the fixture's `cwd` — the same function the app itself uses, in the same
///    module, guarded by the same pinned FNV-1a vector. Anything else is the
///    renderer quietly drawing a different room from the app.
/// 2. **Both halves get the same id.** The scene draws the props and the
///    director resolves the stations. Different ids seat a character at a
///    station the room is not dressed for, silently, because each half is
///    individually valid. [ADR-002 §8 item 5] That one is *not* tested here,
///    because it is no longer testable as a behaviour: `SceneBinding` lost its
///    `themeID:` parameter and reads the id back off the scene it was handed,
///    so there is no second value for a caller to get wrong. A structural fix
///    beats an assertion.
///
/// The `cwd` values come from `fixtures/`, which is ground truth. Nothing here
/// invents a payload.
struct RenderThemeTests {

    static let manifest: Manifest? = try? Manifest.load(root: Manifest.developmentRoot())

    /// Two real fixtures whose captured `cwd` differs. That is what makes
    /// "derived from the fixture's cwd" a testable claim rather than a comment.
    static let mainCapture = "fixtures/three-subagents.jsonl"
    static let otherCapture = "fixtures/four-subagents.jsonl"

    static func entries(_ path: String) throws -> [HookLogEntry] {
        try HookLog.load(
            contentsOf: Manifest.developmentRoot().appending(path: path))
    }

    static func cwd(_ path: String) throws -> String {
        let found = try entries(path).compactMap { $0.event?.cwd }.first
        return try #require(found)
    }

    static func options(theme: String? = nil) -> Options {
        var options = Options()
        options.themeID = theme
        return options
    }

    // MARK: The default

    @Test func withNoThemeFlagTheRoomIsTheOneTheAppWouldDeriveFromTheFixturesCwd() throws {
        let manifest = try #require(Self.manifest)
        let entries = try Self.entries(Self.mainCapture)
        let cwd = try Self.cwd(Self.mainCapture)

        guard case .theme(let drawn) = resolveTheme(
            options: Self.options(), manifest: manifest, entries: entries)
        else { Issue.record("no theme resolved"); return }

        // Not "some theme" — *the* theme, from the one function that owns the
        // mapping. Reimplementing the rule here would leave the pinned FNV-1a
        // vector guarding half of it. [ADR-002 §11 item 7]
        let expected = ThemeSelector.theme(for: cwd, stored: [:], manifest: manifest)
        #expect(drawn == expected)
    }

    /// The bug, stated as a test: silently drawing the default room instead of
    /// the derived one. This passes only because they happen to differ for this
    /// fixture — so it is written to fail loudly if that ever stops being true,
    /// rather than to quietly stop proving anything.
    @Test func theDerivedRoomIsNotJustTheManifestDefault() throws {
        let manifest = try #require(Self.manifest)
        try #require(manifest.themes.orderedIDs.count > 1)
        let entries = try Self.entries(Self.mainCapture)

        guard case .theme(let drawn) = resolveTheme(
            options: Self.options(), manifest: manifest, entries: entries)
        else { Issue.record("no theme resolved"); return }

        #expect(
            drawn != manifest.themes.defaultID,
            Comment(rawValue: "this fixture's cwd now derives to the manifest default"
                + " (\(manifest.themes.defaultID ?? "nil")), so this test no longer"
                + " distinguishes a derived room from a defaulted one — point it at a"
                + " fixture whose cwd does not"))
    }

    /// Two fixtures, two captured `cwd`s, two rooms. If the renderer ignored
    /// `cwd` — which is exactly what it used to do — these would be equal.
    @Test func twoFixturesWithDifferentCwdsDrawDifferentRooms() throws {
        let manifest = try #require(Self.manifest)
        let first = try Self.cwd(Self.mainCapture)
        let second = try Self.cwd(Self.otherCapture)
        try #require(first != second, "the two fixtures no longer differ in cwd")

        guard case .theme(let a) = resolveTheme(
                options: Self.options(),
                manifest: manifest,
                entries: try Self.entries(Self.mainCapture)),
              case .theme(let b) = resolveTheme(
                options: Self.options(),
                manifest: manifest,
                entries: try Self.entries(Self.otherCapture))
        else { Issue.record("no theme resolved"); return }

        #expect(a != b, "two different cwds drew the same room")
    }

    /// S6: the same project draws the same room on every launch. The renderer
    /// inherits that, and the way it inherits it is by not consulting anything
    /// that varies — no stored picks, no clock, no process-seeded hash.
    @Test func theSameFixtureResolvesToTheSameRoomEveryTime() throws {
        let manifest = try #require(Self.manifest)
        let entries = try Self.entries(Self.mainCapture)
        var seen: Set<String> = []
        for _ in 0..<8 {
            guard case .theme(let drawn) = resolveTheme(
                options: Self.options(), manifest: manifest, entries: entries)
            else { Issue.record("no theme resolved"); return }
            seen.insert(drawn ?? "<none>")
        }
        #expect(seen.count == 1, "the renderer drew \(seen.sorted()) across identical calls")
    }

    /// An empty fixture has no `cwd` to key on, so there is nothing to derive
    /// from and the manifest's own default is the honest answer. Not a corner:
    /// `--render` on a fixture whose lines are all unroutable lands here.
    @Test func withNoCwdAtAllTheRoomIsTheManifestsDefault() throws {
        let manifest = try #require(Self.manifest)
        guard case .theme(let drawn) = resolveTheme(
            options: Self.options(), manifest: manifest, entries: [])
        else { Issue.record("no theme resolved"); return }
        #expect(drawn == manifest.themes.defaultID)
    }

    // MARK: Naming one

    @Test func theThemeFlagNamesTheRoomAndOverridesTheDerivedOne() throws {
        let manifest = try #require(Self.manifest)
        let entries = try Self.entries(Self.mainCapture)

        for id in manifest.themes.orderedIDs {
            guard case .theme(let drawn) = resolveTheme(
                options: Self.options(theme: id), manifest: manifest, entries: entries)
            else { Issue.record("--theme \(id) resolved to nothing"); continue }
            #expect(drawn == id)
        }
    }

    /// A typo must not fall back to a room. Drawing the default because the
    /// name was misspelled is the same silence this whole fix is about.
    @Test func anUnknownThemeIsRefusedRatherThanQuietlyDefaulted() throws {
        let manifest = try #require(Self.manifest)
        let entries = try Self.entries(Self.mainCapture)

        guard case .unknown(let requested, let declared) = resolveTheme(
            options: Self.options(theme: "not-a-theme"), manifest: manifest, entries: entries)
        else { Issue.record("an unknown theme was accepted"); return }

        #expect(requested == "not-a-theme")
        #expect(declared == manifest.themes.orderedIDs)

        // And it stops the run rather than rendering something.
        guard case .stop(let code) = themeToDraw(
            options: Self.options(theme: "not-a-theme"), manifest: manifest, entries: entries)
        else { Issue.record("an unknown theme did not stop the render"); return }
        #expect(code == 2)
    }

    @Test func theThemeFlagCanAskWhatThereIs() throws {
        let manifest = try #require(Self.manifest)
        guard case .list(let declared) = resolveTheme(
            options: Self.options(theme: "list"), manifest: manifest, entries: [])
        else { Issue.record("--theme list did not list"); return }
        #expect(declared == manifest.themes.orderedIDs)

        guard case .stop(let code) = themeToDraw(
            options: Self.options(theme: "list"), manifest: manifest, entries: [])
        else { Issue.record("--theme list rendered something"); return }
        #expect(code == 0, "listing is not an error")
    }

    // MARK: The flags

    @Test func theThemeFlagParses() {
        #expect(parse(["--theme", "library"])?.themeID == "library")
        #expect(parse(["--theme"]) == nil)
        #expect(parse([])?.themeID == nil)
    }

    @Test func helpDocumentsTheThemeFlag() {
        let text = usage()
        #expect(text.contains("--theme"))
        #expect(text.contains("derives from the fixture's cwd"))
    }
}
