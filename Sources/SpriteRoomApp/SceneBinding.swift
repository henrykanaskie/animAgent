import Foundation
import SpriteRoomCore
import SpriteRoomScene

/// One scene and the director that feeds it.
///
/// The last link in the one-way chain: deltas in, sprite intents out, nothing
/// ever going back the other way. It exists as its own object because the panel
/// throws one away and builds another every time the displayed project changes,
/// and doing that has to be one line.
@MainActor
final class SceneBinding {

    let scene: RoomScene

    /// **One director per project, made beside that project's room.**
    /// [M9 Phase 4]
    ///
    /// It has to be one each rather than one shared, and the reason is the seat
    /// map: `SceneDirector.claimSeat` gives seat 0 to a main thread and walks
    /// upward while a seat is taken, so a second project's main agent sharing a
    /// director would silently land in seat 1, a subagent's chair, with its
    /// report anchor still pointing at seat 0. That is measured, not feared:
    /// `TwoProjectDirectorTests` drives the shipped director with the
    /// unfiltered `two-projects` stream and prints exactly that.
    ///
    /// A director per project makes each seat map its own, which is what "a
    /// room per project" means one layer down.
    private var directors: [String: SceneDirector] = [:]

    /// Which room a project's deltas are drawn in. Handed in because the theme
    /// is the app's business: it comes from the user's stored pick or from the
    /// hash of the `cwd`, and neither is anything the scene may know. [ADR-002]
    var themeForProject: (String) -> String? = { _ in nil }

    /// The pilot lamp, built on the first frame that has anything true to say
    /// about this process's liveness and never before.
    ///
    /// **A run with no listener never builds one, and that is the I1 answer
    /// rather than an optimisation.** `--render` replays a fixture off disk;
    /// there is no bound port, nothing is receiving, and a lamp in that picture
    /// could only be reporting on a listener that does not exist. When you
    /// cannot represent something truthfully, show nothing.
    ///
    /// It is also what keeps `scripts/preview-theme.py --verify` an honest
    /// check: that harness compares its own composition against `spriteroom
    /// --render` pixel for pixel with an empty register, so a lamp drawn in a
    /// listener-less render would fail the I7 gate, correctly, because it
    /// would be a pixel the room cannot account for.
    private var lamp: LivenessLamp?

    /// The scene and the director must be given the **same** id. The scene
    /// draws the theme's props; the director resolves each agent's station
    /// within it. Hand them different ids and a character sits at a station the
    /// room is not dressed for, silently, because both halves are
    /// individually valid. [ADR-002 §8 item 5]
    ///
    /// **So there is no id parameter here.** This used to take one alongside
    /// the scene, which meant every caller had to remember to pass the same
    /// value twice, and `--render` did not: it built an unthemed scene, passed
    /// no id, and drew the plain office no matter what. The id is now read back
    /// off the scene that was actually built, so "both halves agree" is not a
    /// rule a caller can break: there is nothing left to get wrong.
    init(scene: RoomScene) {
        self.scene = scene
    }

    /// The director for `project`, made with that project's own room, or made
    /// on the spot if this is the first delta it has ever sent.
    private func director(for project: String) -> SceneDirector {
        if let existing = directors[project] { return existing }
        let theme = themeForProject(project)
        let world = scene.room(for: project, themeID: theme)
        let made = SceneDirector(
            manifest: world.store.manifest,
            themeID: world.store.themeID,
            layout: world.layout)
        directors[project] = made
        return made
    }

    convenience init(manifest: Manifest, themeID: String? = nil, viewport: CGSize) {
        let scene = RoomScene(manifest: manifest, themeID: themeID)
        scene.setViewport(viewport)
        self.init(scene: scene)
    }

    /// The room both halves were built for. One value, one source.
    var themeID: String? { scene.store.themeID }

    /// Pooled across every project's director: the count is about the tool
    /// vocabulary, which is one thing however many rooms are drawing.
    var unmappedTools: [String: Int] {
        directors.values.reduce(into: [:]) { total, director in
            for (tool, count) in director.unmappedTools { total[tool, default: 0] += count }
        }
    }

    /// One frame's deltas, and the instant that frame happened.
    ///
    /// **The empty-batch guard is gone and its absence is load-bearing.**
    /// `SceneDirector` is a function of deltas *and time* as of ADR-003: the
    /// closing beat ends by the clock passing its expiry, and the frame that
    /// ends it is almost always a frame with nothing in it: an agent whose
    /// open-call set has just emptied is by definition not producing deltas.
    /// Guarding on `!deltas.isEmpty` would leave the beat up until that agent's
    /// next event, which the M7a capture measures at a mean of 18.5 s.
    /// **`--render-scale`: hold the camera at one rung of the ladder.**
    ///
    /// `nil` (the default and the only value the shipped app ever has) means
    /// the population decides, which is `RoomCamera.scale(forPopulation:)`.
    ///
    /// It exists for `scripts/preview-theme.py --verify`, which compares the
    /// room `--render` draws against its own composition **pixel for pixel** and
    /// has to register the two pictures on the tile field they both paint. That
    /// registration needs the whole field inside the frame, and the field is
    /// 1344×672 unscaled: at `1x` it fits a 1600×900 render with margin, at `2x`
    /// it is 2688×1344 and cannot fit any frame that tool would want to compare
    /// over. An *empty* room (which is the only room that harness compares,
    /// because a character on stage is ink it does not model) takes `2x` from
    /// `defaultComfortablePopulation`, so the check had no way to see the room
    /// at all.
    ///
    /// It was passing anyway, against a **stale `.build/release/spriteroom`**:
    /// `spriteroom_binary()` prefers the release build, and the one on the
    /// maintainer's disk predated the camera policy that made an empty room
    /// `2x`. Rebuilding it is what surfaced this. So the check has been
    /// comparing a current room against an old binary rather than failing, which
    /// is the same class of defect as M6e's two agreeing transcriptions and is
    /// recorded here for the same reason.
    ///
    /// Pinning the scale is honest for what this check measures. Placement is in
    /// **scene** coordinates and a scale is a property of the camera, not of the
    /// room; the real `RoomScene` still draws through the real `SKRenderer`, and
    /// `1x` is the rung the shipped panel uses for any room with four or more
    /// agents in it. Nothing but the harness sets it.
    var pinnedScale: Int? {
        didSet {
            guard let pinnedScale else { return }
            scene.apply([.setScale(pinnedScale)])
        }
    }

    /// **Every project's deltas go to that project's own director and room.**
    ///
    /// The empty-batch case is not a special case: every director that already
    /// exists is stepped on every frame, deltas or none, because `SceneDirector`
    /// is a function of deltas **and time** as of ADR-003 and a closing beat
    /// ends on a frame that usually carries nothing. Routing only the projects
    /// that spoke this frame would strand every other room's beat.
    @discardableResult
    func apply(_ deltas: [WorldDelta], at now: Date) -> [SpriteIntent] {
        var byProject: [String: [WorldDelta]] = [:]
        for delta in deltas { byProject[delta.projectKey, default: []].append(delta) }
        // Make a room for any project that is new this frame, before stepping,
        // so a project's first frame is drawn in its own room rather than in
        // whichever one happened to exist.
        for project in byProject.keys where directors[project] == nil {
            _ = director(for: project)
        }

        var produced: [SpriteIntent] = []
        for project in directors.keys.sorted() {
            var director = directors[project]!
            var intents = director.apply(byProject[project] ?? [], at: now)
            directors[project] = director
            if let pinnedScale {
                intents = intents.map {
                    if case .setScale = $0 { return .setScale(pinnedScale) }
                    return $0
                }
            }
            guard !intents.isEmpty else { continue }
            scene.apply(intents, to: project)
            produced += intents
        }
        return produced
    }

    /// One frame of the pilot lamp.
    ///
    /// `nil` means this run has no listener to report on (a replay, a render,
    /// a capture), and the lamp is taken down if one was ever up. It does not
    /// mean "the listener is down": that case arrives as a `Liveness` whose
    /// `lastBeatAt` has gone stale, which is a lamp drawn `dark`, and the
    /// difference between *no answer* and *nothing to answer for* is exactly
    /// the difference between a dark lamp and no lamp.
    func showLiveness(_ liveness: Liveness?, at now: Date) {
        guard let liveness else {
            lamp?.remove()
            lamp = nil
            return
        }
        if lamp == nil { lamp = LivenessLamp(scene: scene) }
        lamp?.update(liveness, at: now)
    }

    /// What the lamp is currently drawing, or `nil` when there is no lamp.
    /// Read by tests and by the capture harness; nothing depends on it.
    var lampPhase: LivenessLamp.Phase? { lamp?.phase }
}
