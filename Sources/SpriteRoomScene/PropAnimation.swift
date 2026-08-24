import Foundation
import SpriteKit

/// A prop that idles on its own loop.
///
/// **The whole rule it exists under, from `docs/ADR-002-themed-rooms.md` §14b:**
///
/// > A prop may idle on its own loop and **may never take input from the delta
/// > stream.** A clock that swings is scenery. A clock that swings *faster when
/// > the agent is busy* is scenery asserting something, and that is the fiction
/// > §9 exists to prevent. [I1]
///
/// That rule is kept structurally rather than by discipline, and this file is
/// where the structure lives:
///
/// - **This file does not import `SpriteRoomCore`.** `WorldDelta`, `AgentRef`,
///   `OpenCall` and `AttentionKind` are not in scope here; naming one would not
///   compile. `SpriteIntent` and `BadgeSelection` are in this module and are not
///   named either. A test scans the source and asserts all of it, because "does
///   not import" is exactly the kind of thing a later edit adds without noticing.
/// - **`advance(to:)` is the only mutating entry point and its only parameter is
///   a `TimeInterval`.** There is no other way to change what this draws. Its
///   output is a pure function of the clock, the frame list and the frame rate,
///   all three of which are fixed at construction from the manifest.
/// - **`RoomScene` calls it from `advance(to:)` and from nowhere else.** In
///   particular `apply(_ intent:)` (the only place a delta's consequences reach
///   the scene at all) does not touch it, and a test applies one of every
///   `SpriteIntent` case and asserts no prop texture moved.
///
/// **It is not a per-frame rebuild.** [§6 rule 1] The node is built once, when
/// the room is; this swaps its `texture` and touches nothing else, so the
/// zero-prop-node-rebuild assertion that replays every fixture is unaffected:
/// node *identity* is what that test compares, and identity is what this
/// deliberately does not disturb.
@MainActor
final class PropAnimation {

    private let node: SKSpriteNode
    private let frames: [SKTexture]
    private let framesPerSecond: Double
    /// Always `true` for the one prop that ships (§14b says `loop` has no other
    /// value) but honoured rather than assumed, so a manifest that ever says
    /// otherwise is drawn as it reads instead of silently looped.
    private let loops: Bool

    /// The clock reading of the first `advance(to:)`, so the swing starts on
    /// frame 0 when the room appears rather than at whatever phase the host's
    /// absolute clock happens to be in. `RoomScene.update(_:)` is handed system
    /// uptime; the offscreen harness is handed a number starting at zero. Both
    /// have to look the same.
    private var origin: TimeInterval?

    /// The frame index last actually written to the node, or `nil` before the
    /// first advance.
    ///
    /// **What was drawn, not what would be drawn.** Two rooms in the same theme
    /// hold two texture caches, so their `SKTexture`s for one frame are
    /// different objects and cannot be compared across scenes; this can. It is
    /// also the only honest thing for the equivalence test to read: asking
    /// `frameIndex(at:)` on both would compare a pure function against itself
    /// and pass however the drawing was actually driven.
    private(set) var currentFrame: Int?

    /// - Returns: `nil` when there is nothing to play: one frame, or no rate.
    ///   A still prop then takes the ordinary path, which is what a role with no
    ///   `animation` key does anyway.
    init?(node: SKSpriteNode, frames: [SKTexture], fps: Double, loops: Bool) {
        guard frames.count > 1, fps > 0 else { return nil }
        self.node = node
        self.frames = frames
        self.framesPerSecond = fps
        self.loops = loops
    }

    /// The node this drives. Read-only, and for tests that need to check the
    /// picture rather than the arithmetic.
    var animatedNode: SKSpriteNode { node }
    var frameCount: Int { frames.count }

    /// Which frame is showing at `time`. Separated from the drawing so the
    /// arithmetic can be checked without a node, and so that the *only* input to
    /// the picture is visibly this one number.
    func frameIndex(at time: TimeInterval) -> Int {
        let elapsed = max(0, time - (origin ?? time))
        let raw = Int(elapsed * framesPerSecond)
        return loops ? raw % frames.count : min(raw, frames.count - 1)
    }

    /// Advance to `time`. The only mutating entry point, and a `TimeInterval` is
    /// the only thing it takes.
    func advance(to time: TimeInterval) {
        if origin == nil { origin = time }
        let index = frameIndex(at: time)
        currentFrame = index
        node.texture = frames[index]
    }
}
