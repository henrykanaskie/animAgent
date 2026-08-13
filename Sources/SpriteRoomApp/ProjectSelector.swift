import AppKit

/// Which `cwd` group the panel shows. A menu bar item — **not** a control
/// inside the panel.
///
/// The panel is a display surface; the moment it grows a control it also grows
/// a reason to be clicked, and a reason to be clicked is a reason to take
/// focus. Putting the one piece of state the user owns in the menu bar is what
/// lets the panel stay `ignoresMouseEvents` and never become key. [I8]
///
/// Note what is *not* in this menu: anything that touches a running agent.
/// Read-only, always — there is no stop, no pause, no restart.
@MainActor
final class ProjectSelector: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    /// Internal rather than private so the tests can read what the menu
    /// actually contains — including that nothing in it has a key equivalent.
    let menu = NSMenu()
    private var entries: [ProjectRegistry.Entry] = []
    private var selected: String?
    /// Required by the Modern Interiors licence, so it has to be visible
    /// somewhere in the app. M2 kept it in the window title; there is no title
    /// bar any more, so it lives here.
    private let credit: String
    private let creditURL: String

    var onSelect: ((String) -> Void)?

    /// Whether our hook block is currently in `~/.claude/settings.json`, and
    /// what to do about it. `nil` while we are not in live mode, where the
    /// question is not meaningful.
    ///
    /// This is the "removed on request" half of hook installation, and it is
    /// the one place in the app where a menu item writes anything. It does not
    /// touch a running agent — it changes what the *next* session reports to
    /// us — so it does not breach the read-only rule.
    var hooksInstalled: Bool?
    var onToggleHooks: ((Bool) -> Void)?

    /// The themes the manifest declares. `docs/ADR-002-themed-rooms.md` §8
    /// item 9: the submenu lists **every** one of them. The `assignable` flag
    /// governs what the derived default may draw, not what a person may pick.
    var themes: ThemeCatalog = .empty
    /// The theme the selected project is currently showing — a stored choice or
    /// a derived one, indistinguishable here, because §3c is one function and
    /// the room is always showing whatever it returned.
    var currentThemeID: String?
    /// The room the app *derives* for the selected project — what **Automatic**
    /// gives back. Equal to `currentThemeID` whenever the project has no pick
    /// of its own, which is the ordinary case and is why the two are separate
    /// properties rather than one.
    var derivedThemeID: String?
    /// Whether the selected project's room is a pick of its own. The one thing
    /// the menu shows that §3c's single function cannot answer, and the only
    /// thing it governs is whether **Automatic** is something to click.
    var isThemePinned = false
    /// The second menu item in this app that writes anything, and it is
    /// justified the same way the hooks toggle is: it does not touch a running
    /// agent. It changes what the room is *made of*. The panel stays a pure
    /// display surface and keeps `ignoresMouseEvents`; nothing about I8 moves.
    var onPickTheme: ((String) -> Void)?
    /// **Automatic** — forget this project's pick and go back to the room the
    /// app derives from its `cwd`. The same kind of write as `onPickTheme` and
    /// justified identically; it removes a key rather than adding one.
    var onRevertTheme: (() -> Void)?

    init(credit: String, creditURL: String) {
        self.credit = credit
        self.creditURL = creditURL
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            if let image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "Sprite Room") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "▟▙"
            }
            button.toolTip = "Sprite Room"
        }
        menu.delegate = self
        // Off, so an item that says it is disabled is disabled. AppKit's
        // automatic enabling decides for itself — it would enable the **Room**
        // item whenever its submenu had anything clickable in it, which is
        // precisely the case where "no project is selected" has to win.
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // No `deinit` that removes the status item: `deinit` is nonisolated and
    // `removeStatusItem` is main-actor work, and asserting isolation from a
    // deallocation that could happen anywhere is a crash waiting for a quiet
    // afternoon. The selector lives as long as the app does, and the item goes
    // away when the process does.

    /// Push, from the delta stream. The selector never asks anything upstream.
    func update(entries: [ProjectRegistry.Entry], selected: String?) {
        self.entries = entries
        self.selected = selected
        if menu.numberOfItems > 0 { rebuild() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Project", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if entries.isEmpty {
            let empty = NSMenuItem(title: "  No sessions yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for entry in entries {
            // An ended project is marked, not deleted. This is a status
            // surface: "has anything finished" is one of the three things the
            // PRD says you want at a glance, and a project that silently
            // vanished would leave the user unable to tell a finished session
            // from a broken hook. It stops being shown eventually — see
            // `ProjectRegistry.forgottenAfter` — but not the instant it dies.
            let title: String
            switch entry.liveness {
            case .live:
                title = entry.population > 0
                    ? "\(entry.displayName)  ·  \(entry.population)"
                    : entry.displayName
            case .ended:
                title = "\(entry.displayName)  ·  ended"
            }
            // No key equivalent, anywhere in this menu. [I8]
            let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.project
            item.toolTip = entry.liveness == .ended
                ? "\(entry.project) — no session running"
                : entry.project
            item.state = entry.project == selected ? .on : .off
            if entry.liveness == .ended {
                // Greyed by drawing, not by disabling. Disabling would take
                // away the ability to switch *to* it — which is the only way
                // to look at a room and confirm it really is empty — and,
                // worse, the ability to switch *away* from it, which is what
                // unpins it and lets it leave.
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor])
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(roomItem())

        if let hooksInstalled {
            menu.addItem(.separator())
            let item = NSMenuItem(
                title: hooksInstalled ? "Remove Claude Code Hooks" : "Register Claude Code Hooks…",
                action: #selector(toggleHooks),
                keyEquivalent: "")
            item.target = self
            item.toolTip = hooksInstalled
                ? "Stop every Claude Code session reporting to Sprite Room"
                : "Let Claude Code sessions report to Sprite Room"
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if !credit.isEmpty {
            let item = NSMenuItem(
                title: credit, action: #selector(openCredit), keyEquivalent: "")
            item.target = self
            item.isEnabled = !creditURL.isEmpty
            menu.addItem(item)
        }
        let quit = NSMenuItem(title: "Quit Sprite Room", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    /// **Room ▸** — which of the manifest's themes dresses the selected
    /// project. [ADR-002 §8 item 9]
    ///
    /// A theme is a per-project preference, so with no project selected there
    /// is nothing to key it on and the item is disabled rather than writing
    /// somewhere it would have had to invent a key for.
    ///
    /// The submenu is built even when it is disabled, and even when the
    /// manifest declares nothing: the same reason an ended project is marked
    /// rather than deleted, and an empty roster says "No sessions yet" instead
    /// of showing a blank. A menu item that disappears is indistinguishable
    /// from a feature that broke.
    ///
    /// **The parent item names the room it is showing**, when there is one to
    /// name. The maintainer's complaint that started this was not "I cannot
    /// change it", it was *"I don't understand how you're deciding what the
    /// environment should look like"* — and a submenu called "Room" answers
    /// that only for someone who opens it. The title carries the answer to the
    /// level of the menu they are already looking at, in the same
    /// `name  ·  fact` shape the project rows use.
    private func roomItem() -> NSMenuItem {
        // Only with a project selected: the theme is a per-project preference,
        // so with nothing selected there is no room being shown and naming one
        // would be naming a room for nobody.
        let showing = selected == nil ? nil : currentThemeID.flatMap { themes.title(for: $0) }
        let item = NSMenuItem(
            title: showing.map { "Room  ·  \($0)" } ?? "Room", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Room")
        submenu.autoenablesItems = false
        item.submenu = submenu
        item.isEnabled = selected != nil && !themes.isEmpty

        guard !themes.isEmpty else {
            item.toolTip = "This manifest declares no themes"
            let empty = NSMenuItem(
                title: "  No themes in this manifest", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return item
        }
        item.toolTip = selected == nil
            ? "Pick a project first — the room is a per-project choice"
            : "What this project's room is made of"

        submenu.addItem(automaticItem())
        submenu.addItem(.separator())

        for theme in themes.themes {
            // No key equivalent, anywhere in this menu. [I8]
            let entry = NSMenuItem(
                title: theme.title, action: #selector(pickTheme(_:)), keyEquivalent: "")
            entry.target = self
            // The manifest id, never the title: the title is prose and may be
            // reworded; the id is what is written to `themes.json`.
            entry.representedObject = theme.id
            entry.state = theme.id == currentThemeID ? .on : .off
            entry.isEnabled = selected != nil
            submenu.addItem(entry)
        }
        return item
    }

    /// **Automatic** — the way back out of a pick.
    ///
    /// A preference that can be set and not un-set is a trap: the only other
    /// exit would be hand-editing `themes.json`, which ADR-002 §3d says is not
    /// what that file is for. So the derived room is an item like any other,
    /// and it *names* the room it would give you — "Automatic" alone would be a
    /// word the user has to trust, and the whole complaint behind this change
    /// was not being able to tell what the app had decided.
    ///
    /// **No checkmark, deliberately.** The tick in this submenu means "this is
    /// the room you are looking at", and §3c makes a derived room and a chosen
    /// one indistinguishable in that respect — the derived theme's own row is
    /// already ticked when it is in use, and a second tick here would claim
    /// there are two rooms on screen. What this item carries instead is whether
    /// there is anything to undo, and it carries it the way the rest of this
    /// menu does: by being enabled or not, and by saying so in the title.
    ///
    /// It is never hidden. An item that disappears is indistinguishable from a
    /// feature that broke — the same reason an ended project is marked rather
    /// than deleted and an empty roster says "No sessions yet".
    private func automaticItem() -> NSMenuItem {
        // The room the app derives, by name. `nil` only if the manifest gave us
        // an id it does not itself declare, in which case saying nothing beats
        // showing a raw key.
        let derived = derivedThemeID.flatMap { themes.title(for: $0) }
        let named = derived.map { "Automatic  ·  \($0)" } ?? "Automatic"
        // No key equivalent, anywhere in this menu. [I8]
        let item = NSMenuItem(
            title: isThemePinned ? named : "\(named)  (in use)",
            action: #selector(revertTheme),
            keyEquivalent: "")
        item.target = self
        // Enabled exactly when there is a choice to forget. With no project
        // there is no `cwd` to key the removal on, which is the same reason the
        // parent item is disabled.
        item.isEnabled = selected != nil && isThemePinned
        item.toolTip = item.isEnabled
            ? "Forget this project's choice and go back to the room derived from its folder"
            : "This project already uses the room derived from its folder"
        if !item.isEnabled {
            // Greyed by drawing as well as by state, the way an ended project
            // is: `autoenablesItems` is off, so nothing else would draw it.
            item.attributedTitle = NSAttributedString(
                string: item.title,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        }
        return item
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? String else { return }
        onSelect?(project)
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let themeID = sender.representedObject as? String else { return }
        onPickTheme?(themeID)
    }

    @objc private func revertTheme() {
        onRevertTheme?()
    }

    @objc private func toggleHooks() {
        guard let installed = hooksInstalled else { return }
        onToggleHooks?(installed)
    }

    @objc private func openCredit() {
        guard let url = URL(string: creditURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
