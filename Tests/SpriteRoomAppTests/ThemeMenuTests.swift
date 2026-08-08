import AppKit
import Testing

@testable import SpriteRoomApp

/// The **Room ▸** submenu — ADR-002 §8 item 9.
///
/// It is in the menu bar for the same reason the project list is: the panel is
/// a display surface and stays `ignoresMouseEvents`. Nothing about I8 moves,
/// and the last test here is what says so.
///
/// This is the second menu item in the app that *writes* anything. The
/// precedent is the hooks toggle, justified on the grounds that it does not
/// touch a running agent — a theme picker does not touch one either.
@MainActor
struct ThemeMenuTests {

    static let entries = [
        ProjectRegistry.Entry(project: "/work/alpha", displayName: "alpha", population: 3),
        ProjectRegistry.Entry(project: "/work/beta", displayName: "beta", population: 0),
    ]

    static let catalog = ThemeStoreTests.catalog

    static func selector(themes: ThemeCatalog = catalog) -> ProjectSelector {
        _ = NSApplication.shared
        let selector = ProjectSelector(credit: "Art by LimeZu", creditURL: "https://limezu.itch.io")
        selector.themes = themes
        return selector
    }

    static func roomItem(_ selector: ProjectSelector) -> NSMenuItem? {
        selector.menu.items.first { $0.submenu != nil }
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theSubmenuListsEveryThemeTheManifestDeclares() throws {
        let selector = Self.selector()
        selector.currentThemeID = "office"
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let room = try #require(Self.roomItem(selector), "no Room submenu in the menu")
        #expect(room.title == "Room")
        let submenu = try #require(room.submenu)
        let ids = submenu.items.compactMap { $0.representedObject as? String }
        #expect(ids == ["briefing", "mission_control", "office"])
        // The user reads titles, not manifest keys.
        #expect(
            submenu.items.map(\.title)
                == ["Briefing Room", "Mission Control", "Open Plan Office"])
    }

    /// Every theme is *choosable*; only some are *assignable*. §3e is about
    /// what the hash may draw, not about what the user may pick — "The picker
    /// lists everything."
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theSubmenuOffersThemesTheDerivedDefaultIsNotAllowedToDraw() throws {
        let selector = Self.selector()
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let submenu = try #require(Self.roomItem(selector)?.submenu)
        let unassignable = try #require(
            submenu.items.first { $0.representedObject as? String == "mission_control" })
        #expect(unassignable.isEnabled)
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theCurrentThemeIsTheOneThatIsChecked() throws {
        let selector = Self.selector()
        selector.currentThemeID = "mission_control"
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let submenu = try #require(Self.roomItem(selector)?.submenu)
        let on = submenu.items.filter { $0.state == .on }
        #expect(on.count == 1)
        #expect(on.first?.representedObject as? String == "mission_control")
    }

    /// A derived default is still the current theme. There is no third state
    /// for "the user has not picked yet" — §3c is one function, and the room is
    /// always showing whatever it returned.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func aDerivedThemeIsCheckedJustLikeAChosenOne() throws {
        let selector = Self.selector()
        selector.currentThemeID = "briefing"
        selector.update(entries: Self.entries, selected: "/work/beta")
        selector.menuNeedsUpdate(selector.menu)

        let submenu = try #require(Self.roomItem(selector)?.submenu)
        #expect(submenu.items.first { $0.state == .on }?.representedObject as? String == "briefing")
    }

    /// "enabled only when a project is selected" — §8 item 9. The theme is a
    /// *per-project* preference; with no project there is nothing to key it on,
    /// and a picker that wrote somewhere anyway would be inventing a key.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theSubmenuIsDisabledWithNoProjectSelected() throws {
        let selector = Self.selector()
        selector.update(entries: Self.entries, selected: nil)
        selector.menuNeedsUpdate(selector.menu)

        let room = try #require(Self.roomItem(selector))
        #expect(!room.isEnabled)
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theSubmenuIsEnabledOnceAProjectIsSelected() throws {
        let selector = Self.selector()
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let room = try #require(Self.roomItem(selector))
        #expect(room.isEnabled)
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func pickingAThemeReportsItsManifestIdNotItsTitle() throws {
        let selector = Self.selector()
        var picked: [String] = []
        selector.onPickTheme = { picked.append($0) }
        selector.currentThemeID = "office"
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let submenu = try #require(Self.roomItem(selector)?.submenu)
        let item = try #require(
            submenu.items.first { $0.representedObject as? String == "briefing" })
        let action = try #require(item.action)
        let target = try #require(item.target)
        _ = target.perform(action, with: item)
        #expect(picked == ["briefing"])
    }

    /// A manifest that declares no themes is the room this app ships today.
    /// The honest menu says so, in the same shape the empty project roster
    /// already uses — a disabled line, not a missing one.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func aManifestWithNoThemesSaysSoRatherThanShowingAnEmptySubmenu() throws {
        let selector = Self.selector(themes: .empty)
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let room = try #require(Self.roomItem(selector))
        #expect(!room.isEnabled)
        let submenu = try #require(room.submenu)
        #expect(submenu.items.contains { $0.title.contains("No themes") })
        #expect(!submenu.items.contains { $0.representedObject is String })
    }

    /// [I8] — pointer-only, and the submenu is not an exception.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func nothingInTheSubmenuHasAKeyboardShortcut() throws {
        let selector = Self.selector()
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let submenu = try #require(Self.roomItem(selector)?.submenu)
        for item in submenu.items {
            #expect(item.keyEquivalent.isEmpty, "\(item.title) has a key equivalent")
        }
    }

    /// Read-only, always. A theme picker changes what the room is made of; it
    /// must not look like — or grow into — anything that reaches an agent.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theSubmenuOffersNoControlOverAnyAgent() throws {
        let selector = Self.selector()
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let submenu = try #require(Self.roomItem(selector)?.submenu)
        let forbidden = ["stop", "pause", "resume", "kill", "cancel", "restart"]
        for item in submenu.items {
            let title = item.title.lowercased()
            for word in forbidden {
                #expect(!title.contains(word), "'\(item.title)' looks like a control")
            }
        }
    }
}
