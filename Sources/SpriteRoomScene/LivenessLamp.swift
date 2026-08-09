import Foundation
import SpriteKit
import SpriteRoomCore

/// **The pilot lamp: the one thing on screen that is about the app rather than
/// about the session.**
///
/// # The defect it exists for
///
/// M7c stopped the idle body animating, so that movement in the room means an
/// open tool call and nothing else. That was the right change — an idle
/// character had been measured moving *more* than a working one, 196 404 px
/// against 181 080 over eight frames, so the motion channel carried no
/// busy/idle signal at all — and it left one thing behind, recorded rather than
/// bodged around:
///
/// > A room where nobody is working is now a room where nothing moves at all.
///
/// That is the truth about such a room. It is also, at a glance, indis-
/// tinguishable from a room whose listener has died, whose session ended, or
/// whose panel has stopped updating. The user could not tell *my agents are
/// idle* from *this app is broken*, and no amount of looking harder at the
/// characters could tell them, because the characters are correct.
///
/// # Why this is not the fiction I1 and I2 forbid
///
/// A blinking light on a timer would be. It would keep blinking with the
/// listener dead, the queue wedged and the hooks uninstalled, which is a
/// visible behaviour that traces to nothing — and "filling dead air with
/// invented activity" is I2's own phrase for it.
///
/// This lamp is driven by `Liveness`, and `Liveness.beats` moves **only**
/// because `ListenerHeartbeat` POSTed to the bound listener and got a `202`
/// back. Every frame of every phase below traces to a completed round trip that
/// really happened, at an instant that was really observed. Kill the listener
/// and the beats stop; the lamp goes dark within `holdDuration` and stays dark.
/// The negative is not an argument, it is a test:
/// `LivenessTests.theHeartbeatStopsWhenTheListenerStops`.
///
/// **It is not a character and it is not in the room.** [I2] I2 governs the
/// *body* of an agent — ADR-003 §7 already had to write that down, when the
/// badge slot turned out to be governed separately, and the clause it added is
/// the shape of the carve-out this needs:
///
/// > I2 governs the body. The badge slot is governed separately and may carry a
/// > fact the body does not, provided the body is truthful for every frame.
///
/// The lamp needs the same sentence read one layer out, and it needs it stated
/// as explicitly as ADR-003 stated its own, so nobody later reads this file as
/// a licence for something else:
///
/// > **I2 governs what a character does. The panel may show one indicator that
/// > is about the app itself — not seated, not named, not at a station, drawn
/// > in the room's lettering rather than in the cast's art — provided every
/// > frame of it traces to a fact about this process that was measured rather
/// > than assumed, and provided it says nothing about any agent.**
///
/// The three conditions are each checked below and none of them is decorative.
/// *Not a character*: it is a 9 px square of chrome pinned to the frame, in the
/// nameplate's two colours, at a corner no seat, station, aisle or delivery row
/// reaches. *Traces to a measured fact*: `Liveness` and nothing else, with no
/// clock allowed to add to it. *Says nothing about any agent*: it does not
/// change with population, with open calls, or with which project is on screen
/// — a room with six working agents and a room with none draw the same lamp,
/// which is exactly the property that keeps it from becoming a second, quieter
/// activity channel competing with the cast.
///
/// # The motion budget, argued rather than inherited
///
/// `04-ART-DIRECTION.md`'s prop ceiling is 1461 px/s, justified by the sentence
/// *"an idling character is the quietest thing the cast can legitimately be
/// while still on screen, and the room has to be under that"*. **An idling
/// character now moves 0 px/s, so that justification is false**, and the
/// document already marks it REVISIT WITH DATA. This lamp does not get to
/// inherit the number, and it does not need to:
///
/// - **What it spends.** One transition is 5×5 → 3×3, which is 16 changed
///   pixels, and there are two of them per beat. At `ListenerHeartbeat.interval`
///   = 1 s that is **32 px/s**, placed, for the whole room, forever — it does
///   not scale with population, theme, or anything else.
/// - **The ceiling that actually governs it.** Not "quieter than an idling
///   character", which is now 0 and which nothing can be under. The honest
///   requirement is that the lamp must never be able to mask the distinction it
///   was built to protect, and that is a comparison against a *working*
///   character: the quietest ambient phrase in `AmbientMotion` is `magnifier`'s
///   1000 ms bar, two position changes per second over a 2 px lift of the upper
///   body, which is on the order of 1300 px/s. 32 px/s is **2.5%** of the
///   quietest thing a working character does.
/// - **Why that is sufficient rather than merely small.** The lamp draws the
///   *same* 32 px/s whether the room is empty or full. It is a constant added
///   to both sides of the busy/idle comparison, so it cannot change the sign of
///   that comparison at any population — which is precisely the failure M7c
///   fixed, where the idle side was the larger one. A signal that moved *with*
///   activity would reopen it; this one cannot.
///
/// **This does not reprice the prop ceiling.** The lamp is not a prop, is not
/// in the manifest, and is not counted by `scripts/lint-palette.py`'s motion
/// check, which measures what a *theme* animates. 1461 px/s still governs
/// props, it is still resting on a sentence that is now false, and re-deriving
/// it is still open work — see the note appended to `notes.md`. Nothing here
/// touches the accepted prop set.
///
/// # What it cannot do, stated before anyone hopes otherwise
///
/// It cannot detect a frozen renderer *in a single frame*. If the panel stops
/// drawing, the last frame it drew stays on screen, lamp and all, and a still
/// picture of a lit lamp is what a healthy idle room looks like at that
/// instant. The wink is what closes this, and it closes it over time rather
/// than at an instant: a live app contracts the core twice a second, so one
/// second of *watching* separates a live panel from a frozen one. There is no
/// version of this that a single frame could answer, because a frozen panel by
/// definition shows a frame that was true when it was drawn.
///
/// It also says nothing about whether the hooks are installed, whether Claude
/// Code is running, or whether the user's sessions are pointed at this port. A
/// lit lamp means the listener answers. That is a smaller claim than "everything
/// works" and it is the only one the evidence supports. [I1]
@MainActor
public final class LivenessLamp {

    /// The three pictures. See `SceneBitmaps.pilotLamp` for why they differ by
    /// extent rather than by value.
    public enum Phase: String, Sendable, Hashable, CaseIterable {
        /// A round trip completed within `holdDuration`.
        case lit
        /// …and within `winkDuration`. The pulse.
        case wink
        /// None did. The listener is not answering.
        case dark

        /// How wide the ink core is, in pixels.
        var core: Int {
            switch self {
            case .lit: return 5
            case .wink: return 3
            case .dark: return 0
            }
        }
    }

    /// How long the core stays contracted after a beat.
    ///
    /// **125 ms — one animation frame on the manifest's own 8 fps grid**, which
    /// is the same floor ADR-003 §4 derived for the closing beat and is taken
    /// from there rather than re-tasted. A change shorter than one animation
    /// frame is briefer than anything else this room draws; a change longer
    /// than that spends more of the second contracted for no gain, since the
    /// pulse only has to be *seen*, not read.
    public static let winkDuration: TimeInterval = 0.125

    /// How long a beat keeps the lamp lit.
    ///
    /// **Two seconds — two `ListenerHeartbeat.interval`s, and the number is the
    /// interval rather than a judgement about attention spans.** One interval
    /// would make a single dropped beat — a scheduler hiccup, a machine coming
    /// back from sleep — draw a dead listener, which is a false alarm on the
    /// one indicator whose whole value is that it is not crying wolf. Two
    /// tolerates exactly one miss and no more, so a listener that has genuinely
    /// stopped is dark inside two seconds.
    ///
    /// The asymmetry is deliberate and it is ADR-003's polarity argument read
    /// here: this lamp's *lit* state is the positive assertion, so a late
    /// darkening is the fiction and an early one is only a miss. Two intervals
    /// is the smallest value that survives a single hiccup.
    public static let holdDuration: TimeInterval = 2.0

    /// Air between the lamp and the two frame edges it sits against.
    public static let margin: CGFloat = 4

    /// Which picture a `Liveness` calls for at an instant.
    ///
    /// **Pure, and time is a parameter.** The same discipline `WorldModel.sweep`
    /// and `SceneDirector.apply` already keep: nothing here reads a clock, so
    /// every phase in the table above is testable without waiting for one.
    public static func phase(lastBeatAt: Date?, now: Date) -> Phase {
        guard let lastBeatAt else { return .dark }
        let elapsed = now.timeIntervalSince(lastBeatAt)
        // A beat stamped in the future is a clock that moved, not a listener
        // that failed. It is still evidence that a round trip completed, so it
        // lights the lamp rather than darkening it. [I1]
        guard elapsed >= 0 else { return .lit }
        guard elapsed <= holdDuration else { return .dark }
        return elapsed < winkDuration ? .wink : .lit
    }

    /// Where the lamp goes, in the frame's own coordinates, given the size of
    /// the frame.
    ///
    /// **Bottom-left, pinned to the frame rather than placed in the room.**
    /// Pinned because it is a statement about the app and would be a lie if it
    /// scrolled away with the room; bottom-left because that corner is the one
    /// the room reaches least — the delivery rows are the lowest thing a
    /// character can stand on and they are occupied only during a report, by
    /// one character, walking. It is not a guarantee: a report from the
    /// outermost left seat can put a nameplate under the lamp for the length of
    /// a walk, and the lamp draws over it, which costs a few pixels of a plate
    /// that is still legible. The alternative — a corner the room cannot reach
    /// at all — does not exist at `1x`, where the frame is cropped to the
    /// content on every axis.
    public static func position(inFrameOf size: CGSize) -> CGPoint {
        CGPoint(
            x: (-size.width / 2 + margin).rounded(),
            y: (-size.height / 2 + margin).rounded())
    }

    /// Above every character, plate and badge. It is chrome: nothing in the
    /// room may cover it, or the one frame it was covered in is a frame that
    /// said nothing.
    public static let depth: CGFloat = Character.Layer.nameplate + 1000

    private let node = SKSpriteNode()
    private let textures: [Phase: SKTexture]
    private weak var scene: SKScene?

    /// The phase currently drawn. Read by tests; the node itself is the truth.
    public private(set) var phase: Phase = .dark

    /// Hangs the lamp off `scene`'s camera, so it stays where it is put while
    /// the room pans and scales underneath it.
    ///
    /// `nil` when the lamp's own bitmaps will not turn into textures, which is
    /// the same answer `RoomScene` gives for a prop whose art will not load:
    /// draw nothing rather than draw something that is not the thing. [I1]
    ///
    /// It attaches to the camera when there is one and to the scene otherwise.
    /// A scene with no camera does not pan, so the two are the same placement.
    public init?(scene: SKScene) {
        var built: [Phase: SKTexture] = [:]
        for phase in Phase.allCases {
            guard let texture = PixelImage.texture(
                from: SceneBitmaps.pilotLamp(core: phase.core)) else { return nil }
            built[phase] = texture
        }
        self.textures = built
        self.scene = scene

        node.anchorPoint = CGPoint(x: 0, y: 0)
        node.size = CGSize(
            width: SceneBitmaps.pilotLampSize, height: SceneBitmaps.pilotLampSize)
        node.zPosition = Self.depth
        node.texture = built[.dark]
        (scene.camera ?? scene).addChild(node)
        node.position = Self.position(inFrameOf: scene.size)
    }

    /// One frame. Cheap enough to call unconditionally, and it is: the panel's
    /// pump calls it every frame including frames with no deltas, because the
    /// wink ends by the clock passing an instant and not by anything arriving.
    public func update(_ liveness: Liveness, at now: Date) {
        let wanted = Self.phase(lastBeatAt: liveness.lastBeatAt, now: now)
        if wanted != phase {
            phase = wanted
            node.texture = textures[wanted]
        }
        if let scene {
            let point = Self.position(inFrameOf: scene.size)
            if node.position != point { node.position = point }
        }
    }

    /// Takes the lamp down. Called when the panel loses the thing that was
    /// proving liveness — after which the app has nothing true to say about
    /// itself, and says nothing. [I1]
    public func remove() {
        node.removeFromParent()
    }
}
