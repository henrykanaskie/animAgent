import AppKit
import SpriteKit
import SpriteRoomCore
import SpriteRoomScene

/// An `SKView` that is not a keyboard responder.
///
/// Found by the focus probe, which walks the panel's view tree looking for
/// anything that would accept first responder status: a stock `SKView` says
/// yes, because SpriteKit forwards key events to the scene. It could never
/// actually receive one — the panel is never key — but "no view in this window
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
/// further — one project on screen at a time is a v1 non-goal, not an
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

    /// Fires when the menu bar needs to redraw. Push, never pull.
    var onRosterChanged: (([ProjectRegistry.Entry], String?) -> Void)?

    init(manifest: Manifest, viewport: CGSize) {
        self.manifest = manifest
        self.viewport = viewport
        self.view = RoomView(frame: CGRect(origin: .zero, size: viewport))
        view.ignoresSiblingOrder = true
        // The room is the only thing in the panel; nothing here is clickable.
        view.allowsTransparency = false
        binding = SceneBinding(manifest: manifest, viewport: viewport)
        view.presentScene(binding.scene)
    }

    var unmappedTools: [String: Int] { binding.unmappedTools }
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
    func consume(_ deltas: [WorldDelta], at now: Date) {
        var rosterChanged = registry.absorb(deltas, at: now)

        // First project seen wins the screen. A user who has never chosen gets
        // the room that is actually doing something rather than a blank panel.
        if selected == nil, let first = registry.projects.first {
            selected = first
        }
        if !deltas.isEmpty, let selected {
            binding.apply(deltas.filter { $0.projectKey == selected })
        }
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
        binding = SceneBinding(manifest: manifest, viewport: viewport)
        view.presentScene(binding.scene)
        binding.apply(registry.reconstruct(project))
        onRosterChanged?(registry.entries, selected)
    }
}
