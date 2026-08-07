import Foundation

/// The six body states the manifest ships.
///
/// Six, not seven: `read` was dropped at M0 because Modern Interiors has no
/// `read a book` animation, and `attention` is badge-only by design because no
/// honest body animation exists for it. Repurposing an unrelated pose to fill
/// either gap would be fiction. [I1]
public enum BodyState: String, Sendable, Hashable, CaseIterable {
    /// Standing, no open calls.
    case idle
    /// The seated pose. Side-view only — see `Facing.seated`.
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
