import AppKit
import Foundation
import SpriteRoomCore
import SpriteRoomScene
import Testing

@testable import SpriteRoomApp

/// **The whole path, end to end:** menu item → `ProjectSelector` callback →
/// `RoomHost` → `ThemeStore` → disk → the next launch.
///
/// The defect these are written against was not in any one of those pieces. The
/// menu listed the themes, `ThemeStore` could write, `RoomHost` could rebuild —
/// and `themes.json` was still never written by anything, so every project was
/// a pure function of its `cwd` for the life of the app and the maintainer saw
/// the same room every time they looked. Each piece was fine; the path was not
/// there. So these tests drive `connect(host:selector:)` — the app's own
/// wiring, not a copy of it — and finish by reading the file back through a
/// second `ThemeStore`, which is exactly what the next launch does.
///
/// **Window-server gated.** `RoomHost` builds an `SKView` and `ProjectSelector`
/// builds an `NSStatusItem`; neither exists without a logged-in GUI session.
/// See `PanelFixtures.swift` — these move `expectedGatedTestCount`.
///
/// Nothing here writes to the real
/// `~/Library/Application Support/SpriteRoom/`. That directory holds
/// `settings-backup.json`, which is how `--remove-hooks` puts the user's
/// configuration back byte for byte.
@MainActor
struct ThemePickTests {

    // MARK: Scaffolding

    /// The committed manifest. `assets/manifest.json` is in the checkout even
    /// when the art is not, so the theme *ids* are real on any machine; nothing
    /// here reads a pixel.
    static let manifest: Manifest? = try? Manifest.load(root: Manifest.developmentRoot())

    /// A real captured `cwd`, from `fixtures/`. Ground truth beats a path
    /// invented to make a hash land somewhere convenient — and the derived
    /// answer below is whatever the pinned FNV-1a says it is, never a literal.
    static func fixtureCwd() throws -> String {
        let url = Manifest.developmentRoot().appending(path: "fixtures/three-subagents.jsonl")
        let entries = try HookLog.load(contentsOf: url)
        // Bound first: a trailing closure inside `#require` confuses the macro
        // into reading `?.` as chaining on the array.
        let found = entries.compactMap { $0.event?.cwd }.first
        return try #require(found)
    }

    /// One launch of the app, as far as the theme is concerned: a store over a
    /// sandboxed file, a host, a selector, and the app's own wiring between
    /// them.
    @MainActor
    struct Launch {
        let store: ThemeStore
        let host: RoomHost
        let selector: ProjectSelector

        /// Drives the menu item rather than calling `chooseTheme` directly, so
        /// a callback that stops being connected fails this.
        func pickFromTheMenu(_ themeID: String) throws {
            selector.menuNeedsUpdate(selector.menu)
            let submenu = try #require(ThemeMenuTests.roomItem(selector)?.submenu)
            let item = try #require(
                submenu.items.first { $0.representedObject as? String == themeID },
                "no menu item for theme \(themeID)")
            try Self.click(item)
        }

        func clickAutomatic() throws {
            selector.menuNeedsUpdate(selector.menu)
            let item = try #require(ThemeMenuTests.automaticItem(selector))
            #expect(item.isEnabled, "Automatic is disabled; there is nothing to click")
            try Self.click(item)
        }

        /// What AppKit does when the pointer lands on the item. There is no
        /// other way in: the panel is non-activating and this menu has no key
        /// equivalent anywhere. [I8]
        static func click(_ item: NSMenuItem) throws {
            let action = try #require(item.action)
            let target = try #require(item.target)
            _ = target.perform(action, with: item)
        }
    }

    static func launch(_ sandbox: ThemeStoreTests.Sandbox, manifest: Manifest) -> Launch {
        _ = NSApplication.shared
        let store = ThemeStore(url: sandbox.themes)
        let host = RoomHost(
            manifest: manifest,
            viewport: PanelSize.room.cgSize,
            themes: ThemeCatalog.declared(in: manifest),
            themeStore: store)
        let selector = ProjectSelector(
            credit: manifest.credit.text, creditURL: manifest.credit.url)
        connect(host: host, selector: selector)
        return Launch(store: store, host: host, selector: selector)
    }

    /// Some theme that is not the one this project would get anyway — the pick
    /// has to be observable, and picking the derived room proves nothing about
    /// whether anything was written.
    static func aDifferentTheme(from current: String?, in manifest: Manifest) throws -> String {
        try #require(
            manifest.themes.orderedIDs.first { $0 != current },
            "this manifest declares fewer than two themes, so a pick cannot be observed")
    }

    // MARK: The derived room, for a project that has never been picked for

    /// The state every project starts in, and the one the maintainer has only
    /// ever seen: `stored` is empty, so §3c falls to the rendezvous hash.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func aProjectWithNoPickShowsTheRoomDerivedFromItsCwd() throws {
        let manifest = try #require(Self.manifest)
        let sandbox = ThemeStoreTests.Sandbox()
        let cwd = try Self.fixtureCwd()

        let launch = Self.launch(sandbox, manifest: manifest)
        launch.host.select(cwd)

        // The one function that owns the mapping, in the module whose pinned
        // FNV-1a vector guards it. Not a literal id — a literal here would go
        // on passing after the hash changed under it.
        let derived = ThemeSelector.theme(for: cwd, stored: [:], manifest: manifest)
        #expect(launch.host.themeID == derived)
        #expect(launch.host.derivedThemeID == derived)
        #expect(!launch.host.isThemePinned)
        // Read once at launch, written only on a pick — looking at a room
        // creates no file. [ADR-002 §3d]
        #expect(sandbox.bytes == nil)
    }

    // MARK: A pick is written, and comes back

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func aPickFromTheMenuIsWrittenThroughTheStore() throws {
        let manifest = try #require(Self.manifest)
        let sandbox = ThemeStoreTests.Sandbox()
        let cwd = try Self.fixtureCwd()

        let launch = Self.launch(sandbox, manifest: manifest)
        launch.host.select(cwd)
        let wanted = try Self.aDifferentTheme(from: launch.host.themeID, in: manifest)
        try launch.pickFromTheMenu(wanted)

        #expect(launch.host.themeID == wanted)
        #expect(launch.host.isThemePinned)
        #expect(launch.store[cwd] == wanted)
        #expect(launch.store.writeFailures == 0)
        // On disk, under the exact `cwd` the events carried — not a tidied one.
        #expect(sandbox.text?.contains(cwd) == true)
    }

    /// The half that was missing: the room outlives the process. A second
    /// `ThemeStore` over the same path *is* the next launch.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func aPickIsStillThereOnTheNextLaunch() throws {
        let manifest = try #require(Self.manifest)
        let sandbox = ThemeStoreTests.Sandbox()
        let cwd = try Self.fixtureCwd()

        let first = Self.launch(sandbox, manifest: manifest)
        first.host.select(cwd)
        let derived = try #require(first.host.derivedThemeID)
        let wanted = try Self.aDifferentTheme(from: derived, in: manifest)
        try first.pickFromTheMenu(wanted)

        let second = Self.launch(sandbox, manifest: manifest)
        second.host.select(cwd)
        #expect(second.store.load == .loaded(count: 1))
        #expect(second.host.themeID == wanted)
        #expect(second.host.isThemePinned)
        // And the derived answer has not moved — it is simply no longer the
        // one in use. That is what makes Automatic able to name it.
        #expect(second.host.derivedThemeID == derived)
    }

    /// The pin is per project, keyed on `cwd`. A neighbour is untouched, and
    /// switching to it shows a different room in the same process.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func aPickDoesNotFollowTheUserToAnotherProject() throws {
        let manifest = try #require(Self.manifest)
        let sandbox = ThemeStoreTests.Sandbox()
        let cwd = try Self.fixtureCwd()
        let other = cwd + "-elsewhere"

        let launch = Self.launch(sandbox, manifest: manifest)
        launch.host.select(cwd)
        let wanted = try Self.aDifferentTheme(from: launch.host.themeID, in: manifest)
        try launch.pickFromTheMenu(wanted)

        launch.host.select(other)
        #expect(!launch.host.isThemePinned)
        #expect(
            launch.host.themeID
                == ThemeSelector.theme(for: other, stored: [:], manifest: manifest))
        #expect(launch.store[other] == nil)
    }

    // MARK: And a pick can be taken back

    /// A picked theme that cannot be un-picked is a trap. This is the way out,
    /// and it goes all the way to the file: the entry is gone, not overwritten
    /// with a sentinel, so §3c's first line is exactly as written.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func automaticGivesTheDerivedRoomBackAndForgetsThePick() throws {
        let manifest = try #require(Self.manifest)
        let sandbox = ThemeStoreTests.Sandbox()
        let cwd = try Self.fixtureCwd()

        let launch = Self.launch(sandbox, manifest: manifest)
        launch.host.select(cwd)
        let derived = try #require(launch.host.derivedThemeID)
        try launch.pickFromTheMenu(try Self.aDifferentTheme(from: derived, in: manifest))
        #expect(launch.host.themeID != derived)

        try launch.clickAutomatic()

        #expect(launch.host.themeID == derived)
        #expect(!launch.host.isThemePinned)
        #expect(launch.store[cwd] == nil)
        #expect(sandbox.text?.contains(cwd) == false)

        // And on the launch after that, which is where a revert that only lived
        // in memory would come undone.
        let next = Self.launch(sandbox, manifest: manifest)
        next.host.select(cwd)
        #expect(next.host.themeID == derived)
        #expect(!next.host.isThemePinned)
    }

    /// Picking the room the project would have derived anyway still pins it —
    /// the user said *this room*, not "whatever the hash says today" — and
    /// Automatic still takes it back. The two are different states even though
    /// they draw the same room, which is why `isThemePinned` exists at all.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func pickingTheDerivedRoomPinsItAndAutomaticStillUnpinsIt() throws {
        let manifest = try #require(Self.manifest)
        let sandbox = ThemeStoreTests.Sandbox()
        let cwd = try Self.fixtureCwd()

        let launch = Self.launch(sandbox, manifest: manifest)
        launch.host.select(cwd)
        let derived = try #require(launch.host.derivedThemeID)
        try launch.pickFromTheMenu(derived)

        #expect(launch.host.isThemePinned)
        #expect(launch.store[cwd] == derived)
        #expect(launch.host.themeID == derived)

        try launch.clickAutomatic()
        #expect(!launch.host.isThemePinned)
        #expect(launch.store[cwd] == nil)
        #expect(launch.host.themeID == derived)
    }

    // MARK: The room is rebuilt, and the cast is not disturbed

    /// §6 rule 4: a theme change is a **rebuild**, not a transition. The scene
    /// the panel is showing is a different object afterwards, dressed in the
    /// theme that was picked — and the view is presenting that one, not the
    /// old one still sitting in a variable.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func aPickAndARevertEachRebuildTheRoom() throws {
        let manifest = try #require(Self.manifest)
        let sandbox = ThemeStoreTests.Sandbox()
        let cwd = try Self.fixtureCwd()

        let launch = Self.launch(sandbox, manifest: manifest)
        launch.host.select(cwd)
        let before = launch.host.scene
        let derived = try #require(launch.host.derivedThemeID)
        #expect(before.store.themeID == derived)

        let wanted = try Self.aDifferentTheme(from: derived, in: manifest)
        try launch.pickFromTheMenu(wanted)
        let picked = launch.host.scene
        #expect(picked !== before)
        #expect(picked.store.themeID == wanted)
        #expect(launch.host.view.scene === picked)

        try launch.clickAutomatic()
        let reverted = launch.host.scene
        #expect(reverted !== picked)
        #expect(reverted.store.themeID == derived)
        #expect(launch.host.view.scene === reverted)
    }

    /// **The cast is not disturbed.** `ThemeSceneTests` owns this contract for
    /// two scenes built side by side; what it cannot see is the app's own
    /// rebuild path, where the characters come back from
    /// `ProjectRegistry.reconstruct` rather than from the delta stream. Same
    /// agents, same seats, same plates, same badges — the room changed and
    /// nobody in it moved.
    ///
    /// Real deltas, from a real capture, through the real `WorldModel`.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func changingTheRoomFromTheMenuMovesNobodyInIt() async throws {
        let manifest = try #require(Self.manifest)
        let sandbox = ThemeStoreTests.Sandbox()

        let url = Manifest.developmentRoot().appending(path: "fixtures/three-subagents.jsonl")
        let entries = try HookLog.load(contentsOf: url)
        let model = WorldModel()
        var deltas: [WorldDelta] = []
        for entry in entries {
            guard let event = entry.event else { continue }
            deltas += await model.ingest(event, at: entry.receivedAt)
        }
        let cwd = try #require(deltas.compactMap { $0.projectKey }.first)
        // Up to the first departure. The capture ends with its session, so the
        // whole stream leaves an empty room — and an empty room compares equal
        // to an empty room whatever the theme did to it.
        let occupied = Array(deltas.prefix {
            if case .agentDeparted = $0 { return false }
            return true
        })

        let launch = Self.launch(sandbox, manifest: manifest)
        let t0 = try #require(entries.first?.receivedAt)
        launch.host.consume(occupied, at: t0)
        // Long enough that every walk has landed: a character still crossing
        // the floor would be compared against one that had arrived, and the
        // failure would be about the clock rather than about the theme.
        launch.host.consume([], at: t0.addingTimeInterval(60))

        func cast() -> [String] {
            let agents = occupied.compactMap { delta -> AgentRef? in
                if case .agentAppeared(let agent, _, _) = delta { return agent }
                return nil
            }
            return agents.compactMap { agent in
                guard let character = launch.host.scene.character(for: agent) else { return nil }
                return [
                    "\(agent)", character.agentVariant,
                    "\(Int(character.position.x)),\(Int(character.position.y))",
                    character.badgeSelection.badge?.rawValue ?? "-",
                    "\(Int(character.nameplateRect.width))",
                ].joined(separator: "|")
            }
        }

        let before = cast()
        #expect(before.count >= 3, "the fixture put nobody on screen, so this compares nothing")

        let derived = try #require(launch.host.derivedThemeID)
        #expect(launch.host.selected == cwd)
        try launch.pickFromTheMenu(try Self.aDifferentTheme(from: derived, in: manifest))
        launch.host.consume([], at: t0.addingTimeInterval(60))
        #expect(cast() == before)

        try launch.clickAutomatic()
        launch.host.consume([], at: t0.addingTimeInterval(60))
        #expect(cast() == before)
    }

    // MARK: The menu says which room, without being asked

    /// The selector never reads the host. Everything it shows about the theme
    /// arrives on the roster callback, and this is the assertion that the three
    /// values arrive together — a stale `isThemePinned` would offer a way out
    /// of a pick that is not there.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theMenuIsToldWhichRoomItIsShowingWithoutAskingTheHost() throws {
        let manifest = try #require(Self.manifest)
        let sandbox = ThemeStoreTests.Sandbox()
        let cwd = try Self.fixtureCwd()

        let launch = Self.launch(sandbox, manifest: manifest)
        launch.host.select(cwd)
        let derived = try #require(launch.host.derivedThemeID)
        #expect(launch.selector.currentThemeID == derived)
        #expect(launch.selector.derivedThemeID == derived)
        #expect(launch.selector.isThemePinned == false)

        let wanted = try Self.aDifferentTheme(from: derived, in: manifest)
        try launch.pickFromTheMenu(wanted)
        #expect(launch.selector.currentThemeID == wanted)
        #expect(launch.selector.derivedThemeID == derived)
        #expect(launch.selector.isThemePinned)

        // The parent item now names the room the user just chose, so a glance
        // at the menu answers "which room am I in".
        launch.selector.menuNeedsUpdate(launch.selector.menu)
        let title = try #require(manifest.themes.theme(wanted)?.title)
        #expect(ThemeMenuTests.roomItem(launch.selector)?.title == "Room  ·  \(title)")

        try launch.clickAutomatic()
        #expect(launch.selector.currentThemeID == derived)
        #expect(launch.selector.isThemePinned == false)
    }
}
