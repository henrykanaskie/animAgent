import AppKit
import Testing
@testable import SpriteRoomApp

/// The project selector lives in the menu bar, not in the panel. These tests
/// drive the real `NSMenu` the status item shows.
@MainActor
struct ProjectSelectorTests {

    static let entries = [
        ProjectRegistry.Entry(project: "/work/alpha", displayName: "alpha", population: 3),
        ProjectRegistry.Entry(project: "/work/beta", displayName: "beta", population: 0),
    ]

    static func selector() -> ProjectSelector {
        _ = NSApplication.shared
        return ProjectSelector(credit: "Art by LimeZu", creditURL: "https://limezu.itch.io")
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func themenuListsEveryProjectAndTicksTheSelectedOne() {
        let selector = Self.selector()
        selector.update(entries: Self.entries, selected: "/work/beta")
        selector.menuNeedsUpdate(selector.menu)

        let items = selector.menu.items.filter { $0.representedObject is String }
        #expect(items.count == 2)
        #expect(items[0].representedObject as? String == "/work/alpha")
        #expect(items[0].state == .off)
        #expect(items[1].representedObject as? String == "/work/beta")
        #expect(items[1].state == .on)
        // The population is the glance-value; a project with nobody in it does
        // not get a "0" hung off it.
        #expect(items[0].title.contains("3"))
        #expect(items[1].title == "beta")
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func pickingAProjectReportsItsCwdNotItsDisplayName() {
        let selector = Self.selector()
        var picked: [String] = []
        selector.onSelect = { picked.append($0) }
        selector.update(entries: Self.entries, selected: "/work/alpha")
        selector.menuNeedsUpdate(selector.menu)

        let item = selector.menu.items.first { $0.representedObject as? String == "/work/beta" }
        #expect(item != nil)
        if let item, let action = item.action {
            _ = item.target?.perform(action, with: item)
        }
        #expect(picked == ["/work/beta"])
    }

    /// [I8] — pointer-only. A key equivalent anywhere in this menu would be a
    /// keyboard path into the app, which is the thing the invariant forbids
    /// designing.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func nothingInTheMenuHasAKeyboardShortcut() {
        let selector = Self.selector()
        selector.update(entries: Self.entries, selected: nil)
        selector.menuNeedsUpdate(selector.menu)
        for item in selector.menu.items {
            #expect(item.keyEquivalent.isEmpty, "\(item.title) has a key equivalent")
        }
    }

    /// Read-only, always. Nothing in this menu may touch a running agent.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theMenuOffersNoControlOverAnyAgent() {
        let selector = Self.selector()
        selector.update(entries: Self.entries, selected: nil)
        selector.menuNeedsUpdate(selector.menu)
        let forbidden = ["stop", "pause", "resume", "kill", "cancel", "restart"]
        for item in selector.menu.items {
            let title = item.title.lowercased()
            for word in forbidden {
                #expect(!title.contains(word), "menu item '\(item.title)' looks like a control")
            }
        }
    }

    /// The consent dialog promises "you can take them out at any time from the
    /// menu bar item". That promise has to be true, and it has to still be
    /// true when the answer was no.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theHookItemOffersTheOppositeOfWhateverIsInstalled() throws {
        for installed in [true, false] {
            let selector = Self.selector()
            selector.hooksInstalled = installed
            var toggled: [Bool] = []
            selector.onToggleHooks = { toggled.append($0) }
            selector.update(entries: Self.entries, selected: nil)
            selector.menuNeedsUpdate(selector.menu)

            // The promise is only kept if the item is there *and* it is
            // clickable. Both are requirements, not expectations: there is
            // nothing left to check about a menu item that does not exist or
            // that cannot be invoked.
            let item = try #require(
                selector.menu.items.first { $0.title.contains("Hooks") },
                "no Hooks item in the menu when hooksInstalled == \(installed)")
            #expect(item.title.hasPrefix(installed ? "Remove" : "Register"))

            let action = try #require(item.action, "the Hooks item has no action")
            let target = try #require(item.target, "the Hooks item has no target")
            _ = target.perform(action, with: item)
            #expect(toggled == [installed])
        }
    }

    /// Outside live mode the question is not meaningful, so it is not asked.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func thereIsNoHookItemWhenWeAreNotListening() {
        let selector = Self.selector()
        selector.update(entries: Self.entries, selected: nil)
        selector.menuNeedsUpdate(selector.menu)
        #expect(!selector.menu.items.contains { $0.title.contains("Hooks") })
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func anEmptyRosterSaysSoRatherThanShowingNothing() {
        let selector = Self.selector()
        selector.update(entries: [], selected: nil)
        selector.menuNeedsUpdate(selector.menu)
        #expect(selector.menu.items.contains { $0.title.contains("No sessions") })
    }
}
