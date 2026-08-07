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
            let title = entry.population > 0
                ? "\(entry.displayName)  ·  \(entry.population)"
                : entry.displayName
            // No key equivalent, anywhere in this menu. [I8]
            let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.project
            item.toolTip = entry.project
            item.state = entry.project == selected ? .on : .off
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

    @objc private func pick(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? String else { return }
        onSelect?(project)
    }

    @objc private func openCredit() {
        guard let url = URL(string: creditURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
