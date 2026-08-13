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

    /// **Automatic** — the only item in the submenu that carries no theme id,
    /// which is what makes it findable without matching on its prose.
    static func automaticItem(_ selector: ProjectSelector) -> NSMenuItem? {
        Self.roomItem(selector)?.submenu?.items.first {
            !$0.isSeparatorItem && $0.representedObject == nil
        }
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theSubmenuListsEveryThemeTheManifestDeclares() throws {
        let selector = Self.selector()
        selector.currentThemeID = "office"
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let room = try #require(Self.roomItem(selector), "no Room submenu in the menu")
        let submenu = try #require(room.submenu)
        let ids = submenu.items.compactMap { $0.representedObject as? String }
        #expect(ids == ["briefing", "mission_control", "office"])
        // The user reads titles, not manifest keys. Everything below the
        // **Automatic** item and its separator, in the catalogue's order.
        #expect(
            submenu.items.dropFirst(2).map(\.title)
                == ["Briefing Room", "Mission Control", "Open Plan Office"])
    }

    /// The complaint this came from was not "I cannot change the room", it was
    /// *"I don't understand how you're deciding what the environment should
    /// look like"*. A submenu titled "Room" answers that only for someone who
    /// opens it, so the name of the room being shown is on the item they are
    /// already looking at.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theRoomItemNamesTheRoomOnScreen() throws {
        let selector = Self.selector()
        selector.currentThemeID = "mission_control"
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        // The title, never the manifest key — the same rule the submenu follows.
        #expect(try #require(Self.roomItem(selector)).title == "Room  ·  Mission Control")
    }

    /// With nothing selected there is no room on screen to name. The theme is a
    /// per-project preference and naming one here would be naming it for
    /// nobody — the same reason the item is disabled.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theRoomItemNamesNothingWithNoProjectSelected() throws {
        let selector = Self.selector()
        selector.currentThemeID = "mission_control"
        selector.update(entries: Self.entries, selected: nil)
        selector.menuNeedsUpdate(selector.menu)

        #expect(try #require(Self.roomItem(selector)).title == "Room")
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

    // MARK: Automatic — the way back out of a pick

    /// A pick that cannot be un-picked is a trap: the only other way back would
    /// be hand-editing `themes.json`, which ADR-002 §3d says that file is not
    /// for. The way back is an item, and it **names the room it would give
    /// you** — "Automatic" on its own is a word the user has to trust, and not
    /// being able to tell what the app had decided is the whole complaint.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theSubmenuOffersTheDerivedRoomBackAndNamesIt() throws {
        let selector = Self.selector()
        selector.currentThemeID = "mission_control"
        selector.derivedThemeID = "briefing"
        selector.isThemePinned = true
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let automatic = try #require(Self.automaticItem(selector))
        #expect(automatic.title == "Automatic  ·  Briefing Room")
        // First, above the list: it is the state every project starts in, not a
        // fourth room.
        #expect(try #require(Self.roomItem(selector)?.submenu).items.first == automatic)
    }

    /// Enabled exactly when there is a choice to forget. This is the one thing
    /// the menu shows that §3c's single function cannot answer — a stored room
    /// and a derived one are indistinguishable as *rooms*, and only one of them
    /// has anything to undo.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func automaticIsOfferedOnlyToAProjectThatHasAPickOfItsOwn() throws {
        let selector = Self.selector()
        selector.currentThemeID = "briefing"
        selector.derivedThemeID = "briefing"
        selector.isThemePinned = false
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let automatic = try #require(Self.automaticItem(selector))
        #expect(!automatic.isEnabled)
        // Still there, and it says why rather than vanishing: an item that
        // disappears is indistinguishable from a feature that broke.
        #expect(automatic.title == "Automatic  ·  Briefing Room  (in use)")

        selector.isThemePinned = true
        selector.menuNeedsUpdate(selector.menu)
        #expect(try #require(Self.automaticItem(selector)).isEnabled)
    }

    /// No project, no `cwd` to key a removal on — the same reason the parent
    /// item is disabled.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func automaticIsDisabledWithNoProjectSelectedEvenIfSomethingIsPinned() throws {
        let selector = Self.selector()
        selector.derivedThemeID = "briefing"
        selector.isThemePinned = true
        selector.update(entries: Self.entries, selected: nil)
        selector.menuNeedsUpdate(selector.menu)

        #expect(try #require(Self.automaticItem(selector)).isEnabled == false)
    }

    /// The tick means "this is the room you are looking at". A derived room's
    /// own row already carries it, so **Automatic** must not carry a second one
    /// — two ticks would claim there are two rooms on screen.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func automaticIsNeverTickedEvenWhenItIsTheRoomInUse() throws {
        let selector = Self.selector()
        selector.currentThemeID = "briefing"
        selector.derivedThemeID = "briefing"
        selector.isThemePinned = false
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let submenu = try #require(Self.roomItem(selector)?.submenu)
        #expect(try #require(Self.automaticItem(selector)).state == .off)
        let on = submenu.items.filter { $0.state == .on }
        #expect(on.count == 1)
        #expect(on.first?.representedObject as? String == "briefing")
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func clickingAutomaticAsksForTheDerivedRoomBack() throws {
        let selector = Self.selector()
        var reverts = 0
        var picked: [String] = []
        selector.onRevertTheme = { reverts += 1 }
        // The two are different intents and must not be confused: reverting is
        // not "pick the derived one", which would write the pin straight back.
        selector.onPickTheme = { picked.append($0) }
        selector.currentThemeID = "mission_control"
        selector.derivedThemeID = "briefing"
        selector.isThemePinned = true
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let automatic = try #require(Self.automaticItem(selector))
        let action = try #require(automatic.action)
        _ = try #require(automatic.target).perform(action, with: automatic)
        #expect(reverts == 1)
        #expect(picked.isEmpty)
    }

    /// A manifest with no themes has no derived room to name either, so the
    /// empty submenu stays exactly one honest line.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func aManifestWithNoThemesOffersNoAutomaticEither() throws {
        let selector = Self.selector(themes: .empty)
        selector.isThemePinned = true
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let submenu = try #require(Self.roomItem(selector)?.submenu)
        #expect(submenu.items.count == 1)
        #expect(submenu.items[0].action == nil)
    }

    // MARK: I8

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

    /// **The tripwire.** [I8]
    ///
    /// The panel is non-activating and receives no keyboard events, ever, so a
    /// key equivalent is not a convenience that happens not to work — it is the
    /// one keyboard path into this app, and it would be added by someone acting
    /// reasonably. The two tests above each walk one level of one menu; this
    /// walks the whole tree, every state the menu has, so an item added to a
    /// submenu nobody thought to check still fails.
    ///
    /// `keyEquivalentModifierMask` is deliberately not asserted: it is
    /// `.command` by default on every item AppKit makes, and it means nothing
    /// while the key equivalent is empty. Asserting it would be a test that
    /// fails for a reason that is not the invariant.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func noItemAnywhereInTheMenuTreeHasAKeyEquivalent() {
        func walk(_ menu: NSMenu, path: String) {
            for item in menu.items {
                let where_ = "\(path) ▸ \(item.title)"
                #expect(item.keyEquivalent.isEmpty, "\(where_) has a key equivalent [I8]")
                if let submenu = item.submenu { walk(submenu, path: where_) }
            }
        }

        // Every state the menu has: with and without a project, with and
        // without a pin, with and without themes to list.
        let catalogues: [ThemeCatalog] = [Self.catalog, .empty]
        let selections: [String?] = ["/work/alpha", nil]
        let hooks: [Bool?] = [true, false, nil]
        for themes in catalogues {
            for selected in selections {
                for pinned in [true, false] {
                    for installed in hooks {
                        let selector = Self.selector(themes: themes)
                        selector.hooksInstalled = installed
                        selector.isThemePinned = pinned
                        selector.currentThemeID = themes.ids.first
                        selector.derivedThemeID = themes.ids.first
                        selector.update(entries: Self.entries, selected: selected)
                        selector.menuNeedsUpdate(selector.menu)
                        walk(selector.menu, path: "menu")
                    }
                }
            }
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
