import Foundation

/// The six body states the manifest ships.
///
/// Six, not seven: `read` was dropped at M0 because Modern Interiors has no
/// `read a book` animation, and `attention` is badge-only because no pose in the
/// pack means *waiting on a human*. **Repurposing an unrelated pose to fill
/// either gap would be fiction** — `punch` for a blocked agent asserts something
/// the data never said, and that is what I1 forbids. [I1]
///
/// **What that argument does not reach, because this comment used to claim it
/// did.** It said filling those gaps "would be fiction under I1", full stop, and
/// that has been read as a budget ceiling for this project's whole life. It is
/// not one. I1 governs what *triggers* a visible behaviour, not who drew the
/// pixels: the room may not assert data the hooks did not give it, and it says
/// nothing whatever about the provenance of the art. This repository authors art
/// in code in four places already — `scripts/generate-art.py` draws four of the
/// seven badges, `SceneBitmaps` draws every nameplate and the `×N` chip and the
/// dormancy tab pixel by pixel, `PixelFont.standard` is authored outright, and
/// `HeldObject.swift` draws all six carried objects from an ASCII grid, with the
/// rule written down in its own doc comment. So *the pack has no such animation*
/// is a reason we cannot **reuse** one. It is not a reason we cannot **make**
/// one. [ADR-005 §0]
public enum BodyState: String, Sendable, Hashable, CaseIterable {
    /// Standing. **No turn in progress** — not "no open calls".
    ///
    /// This is a standing pose out in the walkway, away from the desk, so
    /// drawing it says the agent left its workstation. It used to be what a
    /// character drew between two tool calls of one turn, which asserted that
    /// an agent got up 1.3 s after a `Read` and sat back down 1.4 s later; the
    /// median tool call in `fixtures/` is 23 ms and the median gap between two
    /// calls is 2.35 s, so the room's loudest body event fired twice per call
    /// and carried nothing. It is now reached only by a turn boundary — a
    /// `SubagentStop`, or a character that has not started one.
    /// [ADR-005, `SceneDirector.Presentation.body`]
    case idle
    /// The seated pose, at the desk: **a turn is in progress**. Whether anything
    /// is *running* is carried by the motion over it, not by this state —
    /// `AmbientMotion.sequence(for:state:openCalls:frameCount:)` holds one still
    /// frame for a character with no open call, so seated-and-still is "at their
    /// desk, not running anything" and seated-and-moving is "a call of this
    /// badge class is open". [I2, ADR-005 §3]
    ///
    /// Side-view only — see `Facing.seated`.
    case working
    /// Moving across the room.
    case walk
    /// The handing-over beat. Plays once, does not loop. `SubagentStop` only.
    case deliver
    /// Composed: the walk cycle, entering from the room edge.
    case spawn
    /// Composed: the walk cycle, leaving for the room edge.
    case depart

    /// `deliver` is the only one-shot. Everything else loops for as long as the
    /// underlying state lasts — which is what lets a 3 ms `Read` and a
    /// four-minute `Bash` both render with no queue and no minimum duration.
    /// [I2/I3]
    public var loopsByDefault: Bool { self != .deliver }
}

/// Sheet direction order, measured at M0: `right, up, left, down`.
public enum Facing: String, Sendable, Hashable, CaseIterable {
    case right
    case up
    case left
    case down

    /// The nearest side view. `working` exists in `right` and `left` only —
    /// both sit rows in the pack are side art in all four blocks — so a seated
    /// character can only ever face sideways. [04-ART-DIRECTION]
    public var seated: Facing {
        switch self {
        case .right, .up: return .right
        case .left, .down: return .left
        }
    }

    public var isSideView: Bool { self == .right || self == .left }

    /// Facing implied by horizontal travel. Zero keeps the current facing, so a
    /// vertical-only move does not spin the character.
    public static func forHorizontalTravel(_ dx: Double, current: Facing) -> Facing {
        if dx > 0 { return .right }
        if dx < 0 { return .left }
        return current
    }
}
