import AppKit
import SpriteKit
import SpriteRoomCore
import SpriteRoomScene

/// An `SKView` that is not a keyboard responder.
///
/// Found by the focus probe, which walks the panel's view tree looking for
/// anything that would accept first responder status: a stock `SKView` says
/// yes, because SpriteKit forwards key events to the scene. It could never
/// actually receive one (the panel is never key), but "no view in this window
/// can take a keystroke" is a much easier invariant to keep true over time than
/// "no view in this window can take a keystroke, given three other facts". [I8]
final class RoomView: SKView {
    override var acceptsFirstResponder: Bool { false }
    override func becomeFirstResponder() -> Bool { false }
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
}

/// The view inside the panel, and the one project it is showing.
///
/// Deltas for other projects are folded into `ProjectRegistry` and go no
/// further: one project on screen at a time is a v1 non-goal, not an
/// oversight. When the selection changes the scene is rebuilt from scratch and
/// re-seeded from the registry's projection, because a `SceneDirector` holds
/// per-character presentation state and there is no honest way to reinterpret
/// project A's seating as project B's.
@MainActor
final class RoomHost {

    let view: SKView
    private let manifest: Manifest
    private let viewport: CGSize
    private var registry = ProjectRegistry()
    private var binding: SceneBinding

    private(set) var selected: String?

    /// The instant of the most recent frame, as `consume` was told it. Held only
    /// so `rebuild()` has a clock to hand the binding without reading one.
    private var lastFrame = Date.distantPast

    /// The themes the manifest declares, and the user's stored picks among
    /// them. [ADR-002 §3c, §3d]
    let themes: ThemeCatalog
    private let themeStore: ThemeStore

    /// **Seam.** ADR-002 §8 item 2's `rendezvous(key:over:)`, which lives in
    /// `SpriteRoomScene` beside the `fnv1a64` its pinned test vector guards.
    ///
    /// Until it is wired the assignable pool is empty anyway (`Manifest` does
    /// not decode §7's themes yet), so §3c falls straight to its last line and
    /// this closure is never consulted. It must never grow a hash of its own:
    /// two implementations of that mapping is how every user's room quietly
    /// redecorates on the day someone refactors one of them. [§11 item 7]
    var derive: (_ cwd: String, _ assignablePool: [String]) -> String? = { _, _ in nil }

    /// Fires when the menu bar needs to redraw. Push, never pull.
    var onRosterChanged: (([ProjectRegistry.Entry], String?) -> Void)?

    init(
        manifest: Manifest,
        viewport: CGSize,
        themes: ThemeCatalog = .empty,
        themeStore: ThemeStore? = nil
    ) {
        self.manifest = manifest
        self.viewport = viewport
        self.themes = themes
        self.themeStore = themeStore ?? ThemeStore()
        self.view = RoomView(frame: CGRect(origin: .zero, size: viewport))
        view.ignoresSiblingOrder = true
        // The room is the only thing in the panel; nothing here is clickable.
        view.allowsTransparency = false
        // `themeID` is derived from the selection, and nothing is selected yet,
        // so it is `nil` here by definition, not by omission. The first
        // `select(_:)` rebuilds with the project's theme.
        binding = SceneBinding(manifest: manifest, themeID: nil, viewport: viewport)
        view.presentScene(binding.scene)
    }

    /// The theme the room on screen is dressed in: a stored choice or a
    /// derived one, and the menu does not distinguish them because §3c is one
    /// function. `nil` when nothing is selected, or when the manifest declares
    /// no themes at all and the room is the single one this app has always
    /// drawn.
    var themeID: String? {
        guard let selected else { return nil }
        return themes.themeID(for: selected, stored: themeStore.stored, derive: derive)
    }

    /// The room §3c would derive for the selected project **if it had no stored
    /// pick**: the answer the second and third lines of that function give.
    ///
    /// Resolved through the same `themeID(for:stored:derive:)` with an empty
    /// `stored`, rather than by calling `derive` directly, so the floor under
    /// an empty assignable pool is the same floor the real answer uses. A
    /// second path to a theme id is how the menu ends up naming a room the app
    /// would not actually draw.
    ///
    /// The menu names it, so "Automatic" is a room the user can see rather than
    /// a word they have to trust.
    var derivedThemeID: String? {
        guard let selected else { return nil }
        return themes.themeID(for: selected, stored: [:], derive: derive)
    }

    /// Whether the room on screen is this project's own pick. Drives whether
    /// there is anything for **Automatic** to undo, and nothing else.
    var isThemePinned: Bool {
        guard let selected else { return false }
        return themeStore.hasChoice(for: selected)
    }

    /// The user picked a room off the menu bar.
    ///
    /// Writes through `ThemeStore` and rebuilds. **A theme change is a rebuild,
    /// not a transition**; §6 rule 4: no cross-fade, no prop animating in. The
    /// room is simply the other room, and the user just caused the
    /// discontinuity themselves.
    ///
    /// Ignored without a selected project: the preference is keyed on `cwd`,
    /// and there is no `cwd` to key it on. The menu already disables the item,
    /// so this is the belt to that braces.
    func chooseTheme(_ themeID: String) {
        guard let selected, themes.contains(themeID) else { return }
        themeStore.choose(themeID, for: selected)
        rebuild()
    }

    /// The user asked for the derived room back.
    ///
    /// The same write-then-rebuild as `chooseTheme`, and deliberately so: from
    /// the room's point of view there is no difference between the two, because
    /// §3c is one function and the only thing that changed is which of its
    /// lines answers. A pick that cannot be un-picked is a trap: the only
    /// other way out would be editing `themes.json` by hand, which §3d says is
    /// not what that file is for.
    ///
    /// Ignored when this project never had a pick: the menu already disables
    /// the item, and a write with nothing to write is a file created for
    /// nothing.
    func revertTheme() {
        guard let selected, themeStore.hasChoice(for: selected) else { return }
        themeStore.clearChoice(for: selected)
        rebuild()
    }

    /// Throw the scene away and build the room again from the same inputs.
    ///
    /// The same thing `select` does, for the same reason: `SceneDirector` holds
    /// per-character presentation state and the honest way to change what the
    /// room is made of is to make it again. Stations are recomputed from the
    /// same inputs by the same function, so every agent lands on the
    /// corresponding station of the new theme: a rebuild, not a §6 rule 2
    /// rewrite.
    ///
    /// The theme reaches the scene through the two `SceneBinding` constructions
    /// and nowhere else, which is what keeps a theme change a rebuild rather
    /// than a mutation. `SceneBinding` hands the same id to both the scene and
    /// the director; giving them different ids would seat a character at a
    /// station the room is not dressed for.
    private func rebuild() {
        binding = SceneBinding(manifest: manifest, themeID: themeID, viewport: viewport)
        view.presentScene(binding.scene)
        if let selected {
            // The last instant `consume` was handed, not a clock this type
            // reads: `RoomHost` has never observed one and a rebuild is not the
            // place to start. A reconstruction carries no close, so it arms no
            // beat, and the beat a rebuild throws away is thrown away with the
            // director that held it. [ADR-003 §3]
            binding.apply(registry.reconstruct(selected), at: lastFrame)
        }
        onRosterChanged?(registry.entries, selected)
    }

    var unmappedTools: [String: Int] { binding.unmappedTools }
    /// What the pilot lamp is drawing, or `nil` when this run has no listener
    /// and therefore no lamp. Read by the capture harness only.
    var lampPhase: LivenessLamp.Phase? { binding.lampPhase }
    /// The scene currently presented. Read by the capture harness only.
    var scene: RoomScene { binding.scene }
    var entries: [ProjectRegistry.Entry] { registry.entries }

    /// One frame's deltas, and the instant that frame happened.
    ///
    /// Called every frame, **including frames with no deltas at all**, which is
    /// the whole reason it takes a clock. A project that has stopped reporting
    /// stops producing deltas by definition, so anything that only ran when
    /// deltas arrived could never notice it had gone; the entry would sit in
    /// the menu at population 0 for the life of the process. Ageing is driven
    /// by what the deltas already said plus this number, and never by asking
    /// the model anything.
    /// - Parameter liveness: what this process has proved about its own
    ///   listener, or `nil` when it has no listener at all. Drives the pilot
    ///   lamp and nothing else. It is a parameter rather than something this
    ///   type reads, for the reason `now` is: the room is downstream of
    ///   everything and asks nothing upstream. [architecture]
    func consume(_ deltas: [WorldDelta], at now: Date, liveness: Liveness? = nil) {
        var rosterChanged = registry.absorb(deltas, at: now)

        // First project seen wins the screen. A user who has never chosen gets
        // the room that is actually doing something rather than a blank panel.
        if selected == nil, let first = registry.projects.first {
            selected = first
        }
        // **Unguarded on purpose.** The scene binding runs every frame, deltas
        // or none, because `SceneDirector` is a function of deltas and time as
        // of ADR-003 and a closing beat ends on a frame that usually carries
        // nothing. The precedent is four lines above: `registry.absorb` already
        // takes this clock for exactly the same reason.
        lastFrame = now
        if let selected {
            binding.apply(deltas.filter { $0.projectKey == selected }, at: now)
        }
        // **Outside the selection, deliberately.** The lamp is about this
        // process, not about the project on screen, so it is drawn on a panel
        // showing nothing at all, which is the case that most needs it, since
        // a room with no project selected is the emptiest picture this app can
        // draw and the one that looks most like a crash.
        binding.showLiveness(liveness, at: now)
        // The selection is pinned: whatever the user is looking at is never
        // dropped out from under them. It can still be marked ended.
        if registry.sweep(at: now, pinning: selected) {
            rosterChanged = true
        }
        if rosterChanged {
            onRosterChanged?(registry.entries, selected)
        }
    }

    /// Switch which `cwd` group is on screen. Driven by the menu bar item.
    func select(_ project: String) {
        guard project != selected else { return }
        selected = project
        // The theme changes with the project, and it changes by rebuild for
        // exactly the reason the scene does. §6 rule 4.
        rebuild()
    }
}
