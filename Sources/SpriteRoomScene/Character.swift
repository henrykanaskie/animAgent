import Foundation
import SpriteKit

/// One agent on screen: a body, a badge above the head, and a nameplate.
///
/// **Time is a parameter, not a reading.** The animation and the choreography
/// are both driven by `advance(to:)` rather than by `SKAction`, for the same
/// reason `WorldModel` takes its instant as an argument: it makes the whole
/// thing deterministic and renderable without a window. (`SKRenderer` was
/// measured not to evaluate the action tree at all, so an `SKAction`-based
/// character is invisible to any offscreen check — the milestone that has to
/// prove nameplates are legible cannot afford that.)
///
/// The state machine is deliberately tiny, and `apply(state:facing:)` is a
/// no-op when nothing changed. A looping animation is never restarted by an
/// event arriving, which is what keeps a burst of short calls from stuttering.
/// [I2/I3]
///
/// **Nothing is held.** The sprites have no per-frame hand anchors, so tool
/// identity lives entirely in the badge and the body stays in its pose. There
/// is no held-object layer here and there must not be one.
@MainActor
public final class Character: SKNode {

    /// Z bands, in accumulated `zPosition`.
    ///
    /// Bodies are sorted by row (`rowDepth`), so whoever is nearer the camera
    /// draws in front — that is what lets a character cross the aisle without
    /// cutting through the seated row. **The badge and the nameplate are not
    /// in that competition.** They sit in a band far above every body, so no
    /// character can ever paint over another character's identity.
    ///
    /// This is not a cosmetic preference. M0 measured that this cast is not
    /// separable by silhouette — the best six-variant subset differs by 7.3%
    /// of outline and several premades are identical — so the nameplate *is*
    /// the identity, and the badge *is* the tool. A body occluding either one
    /// is a loss of information, not a loss of polish. [criterion 5]
    public enum Layer {
        /// Bodies occupy `rowDepth`, which is bounded by this.
        public static let bodyCeiling: CGFloat = 1000
        public static let badge: CGFloat = 4000
        public static let badgeCount: CGFloat = 4001
        public static let nameplate: CGFloat = 5000

        /// Depth for a node standing on row `y`: nearer the camera, further
        /// forward. Desks use this too, so furniture and people sort by the
        /// same rule rather than by a hand-picked constant.
        public static func rowDepth(_ y: Double) -> CGFloat { bodyCeiling - CGFloat(y) }
    }

    public let agentVariant: String
    /// Walk speed in unscaled scene pixels per second. **The same for every
    /// walk, at every distance.**
    ///
    /// There used to be a `maximumWalkDuration` of 4 s on top of it, so a walk
    /// longer than 288 px was run faster to fit. That made speed a function of
    /// distance, which nothing in the data says and which has a consequence:
    /// two characters leaving in the same direction converge, because the one
    /// with further to go is the one that has been sped up. `SessionEnd` departs
    /// the whole cast in a single frame, so that is not a corner — it is what
    /// the end of every session looks like.
    ///
    /// What the cap was guarding against — "a character that takes fifteen
    /// seconds to cross the room reads as broken" — is bounded by the routes
    /// that exist rather than by a clamp. The longest walk the layout can
    /// produce is a departure from the centre seat to the far edge, 432 px, six
    /// seconds; every other route is a seat pitch, a delivery, or an entrance,
    /// and none of them reaches four. The cost of removing the cap is that a
    /// leaver's node lives a second or two longer after it is out of frame,
    /// which nobody can see.
    public static let walkSpeed: Double = 72

    private let store: TextureStore
    private let body = SKSpriteNode()
    private let badgeNode = SKSpriteNode()
    private let badgeCountNode = SKSpriteNode()
    private let nameplateNode = SKSpriteNode()

    // MARK: Animation

    private var frames: [SKTexture] = []
    private var framesPerSecond: Double = 8
    private var framesLoop = true
    private var stateStartedAt: TimeInterval = 0
    private var currentState: BodyState?
    private var currentFacing: Facing = .right
    private var currentBadge: BadgeSelection = .none
    private var now: TimeInterval = 0
    private var started = false

    /// The state the *data* says this character is in. A running script owns
    /// the body until it finishes; this is what the body returns to.
    private var restingState: BodyState = .idle

    // MARK: Choreography

    /// A scripted beat. Only three exist, and every one of them corresponds to
    /// something the event stream actually said happened. [I1]
    private enum Step {
        case walk(to: ScenePoint, state: BodyState)
        case play(BodyState, facing: Facing)
        case finish(() -> Void)
    }

    private var script: [Step] = []
    private var stepIndex = 0
    private var moveFrom = ScenePoint(x: 0, y: 0)
    private var moveTo = ScenePoint(x: 0, y: 0)
    private var moveStartedAt: TimeInterval = 0
    private var moveDuration: TimeInterval = 0

    public init(variant: String, nameplate: NameplateText, store: TextureStore) {
        self.agentVariant = variant
        self.store = store
        super.init()

        let canvas = store.manifest.characters.canvas
        let anchor = store.manifest.characters.anchor
        body.anchorPoint = CGPoint(x: anchor.x, y: anchor.y)
        body.size = CGSize(width: canvas.width, height: canvas.height)
        addChild(body)

        let headTopY = Double(canvas.height - store.headTop(variant: variant))
        let badgeAnchor = store.manifest.badges.anchor
        badgeNode.anchorPoint = CGPoint(x: badgeAnchor.x, y: badgeAnchor.y)
        badgeNode.size = CGSize(
            width: store.manifest.badges.canvas.width,
            height: store.manifest.badges.canvas.height)
        badgeNode.position = CGPoint(x: 0, y: headTopY + 1)
        badgeNode.zPosition = Layer.badge
        badgeNode.isHidden = true
        addChild(badgeNode)

        badgeCountNode.anchorPoint = CGPoint(x: 0, y: 0)
        badgeCountNode.position = CGPoint(
            x: Double(store.manifest.badges.canvas.width) / 2 - 3,
            y: headTopY + 3)
        badgeCountNode.zPosition = Layer.badgeCount
        badgeCountNode.isHidden = true
        addChild(badgeCountNode)

        // Under the feet. The badge owns the space above the head — the emote
        // bubble's tail points down at it by design — so the nameplate goes
        // below, on the floor, where nothing competes with it.
        nameplateNode.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        nameplateNode.position = CGPoint(x: 0, y: -2)
        nameplateNode.zPosition = Layer.nameplate
        addChild(nameplateNode)
        setNameplate(nameplate)

        apply(state: .idle, facing: .right)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: Nameplate

    public func setNameplate(_ text: NameplateText) {
        let accent = store.accent(variant: agentVariant)
        let bitmap = SceneBitmaps.nameplate(text, accent: accent)
        guard let texture = store.texture(
            bitmap: bitmap, key: "nameplate:\(agentVariant):\(text.textureKey)") else { return }
        nameplateNode.texture = texture
        nameplateNode.size = CGSize(width: bitmap.width, height: bitmap.height)
    }

    // MARK: Badge

    /// The badge layer. Attention wins the slot when it is set — see
    /// `BadgeSelection.isAttention` for why, and why the `×N` goes with it.
    ///
    /// If the attention art is missing from the manifest the tool badge is
    /// drawn instead. That is a *rendering* fallback, not a policy one: the
    /// selection above already decided attention outranks the tool, and losing
    /// both to a missing file would hide information we have. A manifest test
    /// asserts the key is declared, so this path only fires on a manifest
    /// older than this change.
    public func apply(badge selection: BadgeSelection) {
        guard selection != currentBadge else { return }
        currentBadge = selection
        let attentionTexture = selection.isAttention ? store.attentionTexture() : nil
        let toolTexture = selection.badge.flatMap(store.badgeTexture)
        guard let texture = attentionTexture ?? toolTexture else {
            badgeNode.isHidden = true
            badgeCountNode.isHidden = true
            return
        }
        badgeNode.texture = texture
        badgeNode.isHidden = false
        if attentionTexture == nil, selection.count > 1 {
            let bitmap = SceneBitmaps.badgeCount(selection.count)
            if let countTexture = store.texture(bitmap: bitmap, key: "count:\(selection.count)") {
                badgeCountNode.texture = countTexture
                badgeCountNode.size = CGSize(width: bitmap.width, height: bitmap.height)
                badgeCountNode.isHidden = false
            }
        } else {
            badgeCountNode.isHidden = true
        }
    }

    public var badgeSelection: BadgeSelection { currentBadge }
    public var isBadgeVisible: Bool { !badgeNode.isHidden }
    public var isBadgeCountVisible: Bool { !badgeCountNode.isHidden }
    public var isNameplateVisible: Bool { nameplateNode.texture != nil }
    /// The texture currently in the badge slot. Read by tests that need to
    /// check *which* glyph is up rather than that one is.
    var badgeTextureForTesting: SKTexture? { badgeNode.texture }

    // MARK: Geometry, for tests that check the picture rather than the policy

    /// The nameplate's rectangle in the parent's coordinates.
    public var nameplateRect: CGRect {
        CGRect(
            x: position.x + nameplateNode.position.x - nameplateNode.size.width / 2,
            y: position.y + nameplateNode.position.y - nameplateNode.size.height,
            width: nameplateNode.size.width,
            height: nameplateNode.size.height)
    }

    /// The body's rectangle in the parent's coordinates.
    public var bodyRect: CGRect {
        CGRect(
            x: position.x - body.size.width / 2, y: position.y,
            width: body.size.width, height: body.size.height)
    }

    /// Accumulated depth of the nameplate and of the body. The first must
    /// always exceed every character's second — see `Layer`.
    public var nameplateDepth: CGFloat { zPosition + nameplateNode.zPosition }
    public var badgeDepth: CGFloat { zPosition + badgeNode.zPosition }
    public var bodyDepth: CGFloat { zPosition + body.zPosition }

    // MARK: Body

    public var state: BodyState? { currentState }
    public var facing: Facing { currentFacing }
    public var isScripted: Bool { stepIndex < script.count }

    /// The state the data says this character is in. Applied immediately unless
    /// a scripted move owns the body, in which case it lands when the script
    /// ends.
    public func setResting(_ state: BodyState, facing: Facing) {
        restingState = state
        guard !isScripted else { return }
        apply(state: state, facing: facing)
    }

    /// The whole state machine. Same state and facing means no work — the
    /// running animation keeps running rather than restarting from frame zero.
    public func apply(state: BodyState, facing: Facing, startingAt start: TimeInterval? = nil) {
        let resolved = state == .working ? facing.seated : facing
        guard state != currentState || resolved != currentFacing else { return }
        let textures = store.frames(variant: agentVariant, state: state, facing: resolved)
        guard !textures.isEmpty else { return }
        currentState = state
        currentFacing = resolved
        frames = textures
        framesPerSecond = max(1, store.frameRate(variant: agentVariant, state: state))
        framesLoop = store.loops(variant: agentVariant, state: state)
        stateStartedAt = start ?? now
        body.texture = textures[0]
    }

    // MARK: Choreography

    public static func duration(from: ScenePoint, to: ScenePoint) -> TimeInterval {
        let distance = ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y))
            .squareRoot()
        return max(0.2, distance / walkSpeed)
    }

    /// Walk in from the room edge. `spawn` is the walk cycle by construction —
    /// the pack ships no spawn animation and inventing one is not worth the
    /// cost. [04-ART-DIRECTION]
    /// Walks in along the aisle, then steps back to the desk. Two beats
    /// because a character that walks along the desk row walks *through*
    /// whoever is already sitting there.
    public func enter(from edge: ScenePoint, approach: ScenePoint, seat: ScenePoint) {
        position = CGPoint(x: edge.x, y: edge.y)
        run(script: [
            .walk(to: approach, state: .spawn),
            .walk(to: seat, state: .spawn),
        ])
    }

    /// The `SubagentStop` beat: step into the aisle, walk to the anchor, hand
    /// the report over, walk back and sit down again.
    ///
    /// The one dramatisation the event model licenses — and it is licensed
    /// because the underlying event genuinely happened. No dialogue, no bubble
    /// with content, nothing about what was said. [I1]
    ///
    /// **A round trip, because a stop is a turn boundary and not a death.** This
    /// used to be the front half of `reportAndDepart`: the walk-off was carried
    /// by the `agentDeparted` that followed `reportDelivered` on the same event.
    /// The agent now goes dormant in its own seat, so the walk has to bring it
    /// home itself.
    ///
    /// **The badge is not touched here**, unlike the two exits. A character that
    /// leaves takes its badge with it and nothing can be stale afterwards; a
    /// character that comes back would be sitting under whatever this method
    /// last forced, disagreeing with the director's suppression memory. The
    /// director already emits the badge change in this same batch, off the
    /// `callAbandoned` deltas `SubagentStop` produces. Animate state, not
    /// events. [I2/I3]
    public func reportAndReturn(
        via approach: ScenePoint, to delivery: ScenePoint, facing deliveryFacing: Facing,
        home homeApproach: ScenePoint, seat: ScenePoint, onFinished: @escaping () -> Void
    ) {
        run(script: [
            .walk(to: approach, state: .walk),
            .walk(to: delivery, state: .walk),
            .play(.deliver, facing: deliveryFacing),
            .walk(to: homeApproach, state: .walk),
            .walk(to: seat, state: .walk),
            .finish(onFinished),
        ])
    }

    /// The report beat, truncated into an exit: walk to the anchor, hand the
    /// report over, then leave instead of going home.
    ///
    /// Only for a character that reported **and** departed in the same frame —
    /// a `SessionEnd` landing on top of a `SubagentStop`. Both facts are real,
    /// so the character plays the beat it earned and then goes.
    public func reportAndDepart(
        via approach: ScenePoint, to delivery: ScenePoint, facing deliveryFacing: Facing,
        thenExitAt edge: ScenePoint, onFinished: @escaping () -> Void
    ) {
        apply(badge: .none)
        run(script: [
            .walk(to: approach, state: .walk),
            .walk(to: delivery, state: .walk),
            .play(.deliver, facing: deliveryFacing),
            .walk(to: edge, state: .depart),
            .finish(onFinished),
        ])
    }

    /// Walk off. `depart` is the walk cycle towards the edge, same composition
    /// as `spawn`.
    public func departOffScreen(
        via approach: ScenePoint, to edge: ScenePoint, onFinished: @escaping () -> Void
    ) {
        apply(badge: .none)
        run(script: [
            .walk(to: approach, state: .depart),
            .walk(to: edge, state: .depart),
            .finish(onFinished),
        ])
    }

    private func run(script steps: [Step]) {
        script = steps
        stepIndex = 0
        beginCurrentStep(at: now)
    }

    /// Starts whatever step is now current, timed from `start` rather than from
    /// `now`. Passing the instant the previous step *finished* rather than the
    /// instant this frame happens to land on keeps a multi-step script from
    /// drifting by up to a frame per beat.
    private func beginCurrentStep(at start: TimeInterval) {
        while stepIndex < script.count {
            switch script[stepIndex] {
            case let .walk(destination, state):
                moveFrom = ScenePoint(x: Double(position.x), y: Double(position.y))
                moveTo = destination
                moveStartedAt = start
                moveDuration = Self.duration(from: moveFrom, to: destination)
                apply(
                    state: state,
                    facing: Facing.forHorizontalTravel(
                        destination.x - moveFrom.x, current: currentFacing),
                    startingAt: start)
                return
            case let .play(state, facing):
                moveDuration = 0
                apply(state: state, facing: facing, startingAt: start)
                return
            case let .finish(handler):
                stepIndex += 1
                handler()
                continue
            }
        }
        // Script over: fall back to whatever the data says.
        script = []
        stepIndex = 0
        apply(state: restingState, facing: currentFacing.seated, startingAt: start)
    }

    // MARK: Clock

    /// Advances the character to `time`. Called once per frame by `RoomScene`.
    public func advance(to time: TimeInterval) {
        if !started {
            started = true
            now = time
            stateStartedAt = time
            moveStartedAt = time
        }
        now = time

        // A step can finish and the next one can also finish inside a single
        // call — a large time step, or the very short beats of a script. The
        // loop drains them; the bound is a guard against a script that somehow
        // never consumes time.
        var beats = 0
        stepping: while stepIndex < script.count, beats < 32 {
            beats += 1
            switch script[stepIndex] {
            case .walk:
                let progress = moveDuration <= 0
                    ? 1 : min(1, max(0, (now - moveStartedAt) / moveDuration))
                position = CGPoint(
                    x: moveFrom.x + (moveTo.x - moveFrom.x) * progress,
                    y: moveFrom.y + (moveTo.y - moveFrom.y) * progress)
                guard progress >= 1 else { break stepping }
                let finishedAt = moveStartedAt + moveDuration
                stepIndex += 1
                beginCurrentStep(at: finishedAt)
            case .play:
                let length = Double(frames.count) / framesPerSecond
                guard now - stateStartedAt >= length else { break stepping }
                let finishedAt = stateStartedAt + length
                stepIndex += 1
                beginCurrentStep(at: finishedAt)
            case .finish:
                beginCurrentStep(at: now)
            }
        }

        // Depth by row: whoever is nearer the camera draws in front. This is
        // what lets a character cross the aisle without cutting through the
        // seated row.
        zPosition = Layer.rowDepth(Double(position.y))

        guard !frames.isEmpty else { return }
        let elapsed = max(0, now - stateStartedAt)
        var index = Int(elapsed * framesPerSecond)
        if framesLoop {
            index %= frames.count
        } else {
            index = min(index, frames.count - 1)
        }
        body.texture = frames[index]
    }
}
