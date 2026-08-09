import Foundation
import SpriteKit

/// One agent on screen: a body, a badge **beside** the head, and a nameplate.
///
/// **Beside, not above, and the reason is 34 px of height.** See
/// `badgeSlotTopAboveFeet`. The slot kept its size, its art, its precedence and
/// its meaning; only where it is drawn changed.
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
/// **Three things are held apart here and they are not variants of each other.**
///
/// - The **costume** is the generator's own overlay sheet at the premade sheet's
///   exact geometry: it registers frame for frame on every pose row including
///   `sit`, with no offset, so there is nothing to place. It says what the agent
///   *is*, which only `agent_type` knows.
/// - The **held object** says what the agent is *doing*, and it is a prop that
///   has to be *placed*. This class used to carry a comment saying there must
///   never be one, on the grounds that the sprites have no per-frame hand
///   anchors. The premise is right about the download and the conclusion did not
///   follow: on the one pose this room draws, **the hands do not move**, so
///   there is a single anchor to measure rather than a per-frame table to
///   invent. It is measured — `x 14...17, y 52...55` in the 32x64 canvas, the
///   same box on every cast variant, every `sit` frame and both facings — and
///   `HeldObject` carries the derivation and the numbers.
/// - The **badge** still carries tool identity. The held object is a colour
///   block inside an existing outline and cannot change the silhouette on this
///   pose; it is deliberately not asked to do the badge's job.
///
/// The two `Books` and `Smartphones` folders remain unusable and the reason is
/// unchanged: they carry ink on one standing front-facing row each, and this
/// room is side-view seated.
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
        /// Costume layers, **inside** one character's own node and therefore
        /// relative to that character's body. `1, 2, …` in the costume's own
        /// order, so they draw over their own body and under everything the
        /// scene sorts by row. A costume can never paint over another
        /// character, and nothing about the desk/body depth tie in `RoomScene`
        /// moves, because the character node's `zPosition` is unchanged.
        public static let costume: CGFloat = 1
        /// The held object, **above every costume layer and still inside the
        /// character's own node**. Above the costume because a thing in your
        /// hands is in front of your clothes; inside the node because it is part
        /// of the body's depth, so a character crossing the aisle carries it in
        /// front of the seated row exactly as it carries its own torso. The gap
        /// to `costume` is wide enough that a costume can never grow into it.
        public static let held: CGFloat = 100
        public static let badge: CGFloat = 4000
        public static let badgeCount: CGFloat = 4001
        public static let nameplate: CGFloat = 5000

        /// Depth for a node standing on row `y`: nearer the camera, further
        /// forward. Desks use this too, so furniture and people sort by the
        /// same rule rather than by a hand-picked constant.
        public static func rowDepth(_ y: Double) -> CGFloat { bodyCeiling - CGFloat(y) }
    }

    public let agentVariant: String
    /// What this character is wearing, or `nil` for the cast's own clothes.
    /// **`let`** — §6 rule 2, and there is deliberately no setter.
    public let agentCostume: String?
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
    /// One node per declared costume layer, in the costume's own back-to-front
    /// order, created once at spawn and never added to or removed from.
    ///
    /// **Fixed at spawn is the enforcement, not a convention.** There is no
    /// method on this class that changes `costume`, so a character cannot change
    /// clothes while it is on screen. [ADR-002 §6 rule 2]
    private var costumeNodes: [SKSpriteNode] = []
    /// The frames each costume layer plays for the state the body is playing,
    /// in the same order and the same count. Indexed with the body's own frame
    /// index, so a costume cannot drift out of phase with the person wearing it.
    private var costumeFrames: [[SKTexture]?] = []
    /// What is in the hands, or nothing. One node, created at spawn, never
    /// added or removed — only its texture and its visibility change.
    private let heldNode = SKSpriteNode()
    private let badgeNode = SKSpriteNode()
    private let badgeCountNode = SKSpriteNode()
    private let nameplateNode = SKSpriteNode()

    /// The badge slot's **top** edge, above the feet. Every picture the slot can
    /// hold hangs from this line — see `placeBadgePicture(width:height:)`.
    private var badgeSlotTopY: Double = 0
    /// The badge slot's **near** edge: the side facing the head. Every picture
    /// the slot can hold is aligned to this line, so a small one is beside the
    /// head rather than adrift in the middle of a 24 px box.
    private var badgeSlotLeftX: Double = 0

    // MARK: Animation

    private var frames: [SKTexture] = []
    /// Which frame of `frames` each step of the loop draws. [`AmbientMotion`]
    ///
    /// The identity sequence for every state except `working`, and for a
    /// `working` character whose badge class is `questionMark` or absent — so a
    /// character walking, idling, delivering or running an unmapped tool plays
    /// exactly the animation this app has always played. For the six mapped
    /// classes it is the class's phrase over the seated art's two positions,
    /// which is the whole of the motion channel.
    private var frameSequence: [Int] = []
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
    /// The one step of a script, if any, over which the character fades out.
    ///
    /// **Only an exit sets it, and an exit always does.** The departure walk
    /// used to end off the side of the frame, where the frame edge did the
    /// hiding for free. It now walks upstage, out through the back of the room,
    /// because that is the only route in the room that crosses nobody's path —
    /// and there is no edge back there, only a flat wall, which gives a
    /// character walking away nothing to disappear behind. So it fades over that
    /// last leg. That is not a dramatisation: the agent is gone, and the fade is
    /// the room saying so rather than a node blinking out of existence. [I1]
    private var fadingStep: Int?
    private var moveFrom = ScenePoint(x: 0, y: 0)
    private var moveTo = ScenePoint(x: 0, y: 0)
    private var moveStartedAt: TimeInterval = 0
    private var moveDuration: TimeInterval = 0

    /// - Parameter costume: what this agent wears, from
    ///   `ThemeSelector.costume(agentID:agentType:in:)`. `nil` — the main
    ///   thread, an untyped subagent, or any agent at all in a manifest that
    ///   declares no wardrobe — builds no layer nodes, so the character is
    ///   byte-for-byte the one this app has always drawn.
    public init(
        variant: String, nameplate: NameplateText, store: TextureStore,
        costume: String? = nil
    ) {
        self.agentVariant = variant
        self.store = store
        self.agentCostume = costume
        super.init()

        let canvas = store.manifest.characters.canvas
        let anchor = store.manifest.characters.anchor
        body.anchorPoint = CGPoint(x: anchor.x, y: anchor.y)
        body.size = CGSize(width: canvas.width, height: canvas.height)
        addChild(body)

        // The costume stack, over the body and far under the badge band. Sized
        // and anchored identically to the body because it *is* the body's
        // geometry: the generator's overlay sheets are the premade sheets'
        // exact dimensions, registered frame for frame, so there is no offset
        // to solve and no anchor to guess. [I1]
        for index in 0..<store.costumeLayerCount(costume) {
            let node = SKSpriteNode()
            node.anchorPoint = body.anchorPoint
            node.size = body.size
            node.zPosition = Layer.costume + CGFloat(index)
            node.isHidden = true
            costumeNodes.append(node)
            addChild(node)
        }

        // The held object, over the costume and far under the badge band.
        // `anchorPoint` is the centre so that facing left is one sign flip on
        // both the position and the scale, rather than a second offset that
        // could disagree with the first.
        heldNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        heldNode.size = CGSize(
            width: HeldObjectArt.canvasWidth, height: HeldObjectArt.canvasHeight)
        heldNode.zPosition = Layer.held
        heldNode.isHidden = true
        addChild(heldNode)

        badgeSlotTopY = Character.badgeSlotTopAboveFeet(
            canvasHeight: canvas.height, headTopPx: store.headTop(variant: variant))
        badgeSlotLeftX = Double(canvas.width) / 2
        badgeNode.anchorPoint = CGPoint(
            x: store.manifest.badges.anchor.x, y: store.manifest.badges.anchor.y)
        badgeNode.zPosition = Layer.badge
        badgeNode.isHidden = true
        addChild(badgeNode)
        placeBadgePicture(
            width: Double(store.manifest.badges.canvas.width),
            height: Double(store.manifest.badges.canvas.height))

        // The `×N` keeps the corner of the slot it has always had — the
        // bottom-right, 3 px inside the bubble's right edge and 2 px above its
        // bottom — so the chip's relationship to the glyph it annotates is
        // untouched by the move. It rides the slot, not the head.
        badgeCountNode.anchorPoint = CGPoint(x: 0, y: 0)
        badgeCountNode.position = CGPoint(
            x: badgeSlotLeftX + Double(store.manifest.badges.canvas.width) - 3,
            y: badgeSlotTopY - Double(store.manifest.badges.canvas.height) + 2)
        badgeCountNode.zPosition = Layer.badgeCount
        badgeCountNode.isHidden = true
        addChild(badgeCountNode)

        // Under the feet, where nothing competes with it — the badge is beside
        // the head rather than over it, so the space above the head is now
        // room, but the plate stays on the floor: it is the wider of the two
        // pictures and the aisle below is the only place a 63 px box fits
        // without meeting a neighbour's.
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

    // MARK: Badge geometry

    /// **The highest pixel the badge slot can put on screen, above the feet.**
    ///
    /// This is the one number the camera's content band takes from a character,
    /// and it is `headTop + 1` — the badge slot's **top** edge now sits one
    /// pixel above the head, where its *bottom* edge used to. That is the whole
    /// of the move from above-the-head to beside-the-head, stated as arithmetic:
    ///
    /// | | above the head | beside the head |
    /// |---|---:|---:|
    /// | slot bottom | `headTop + 1` = 51 | `headTop + 1 − 34` = 17 |
    /// | slot top | `headTop + 1 + 34` = **85** | `headTop + 1` = **51** |
    ///
    /// with `headTop = canvasHeight − headTopPx` = 50 for the highest head in
    /// the cast (variant `19`, `head_top_px` 14), and 34 the badge canvas.
    ///
    /// **34 px is what the move is for.** A 720×400 panel at `2x` frames 200
    /// scene pixels of height, and 108 of them were this number plus the
    /// nameplate — the one term no rearrangement of the floor can touch, which
    /// is why clustering the seats was refuted rather than tried again
    /// [`RoomLayout.isBackRow(seat:)`]. It is also 34 px of *empty air* at `1x`:
    /// nothing but the badge is ever drawn there, so the room was reserving a
    /// character's height above every head to hold a bubble.
    ///
    /// Ask this rather than recomputing it. `RoomScene.contentBand` takes the
    /// **minimum** `head_top_px` over the cast, because the smallest one is the
    /// highest head and therefore the highest slot.
    public nonisolated static func badgeSlotTopAboveFeet(
        canvasHeight: Int, headTopPx: Int
    ) -> Double {
        Double(canvasHeight - headTopPx + 1)
    }

    /// Puts a picture of `width` × `height` in the badge slot.
    ///
    /// **Hung from the slot's top edge and aligned to its near edge**, which is
    /// what makes the slot a *place* rather than a pair of coordinates that each
    /// picture computes for itself. The slot holds two sizes — the 24×34 bubble
    /// and the 9×11 dormancy tab — and they must land in the same corner, or the
    /// tab drifts to the bottom of a box whose top is where the eye is looking.
    ///
    /// - **Top, not bottom.** The head is the landmark and it is at the top of
    ///   the slot. Bottom-aligning the tab would drop it 23 px, beside the
    ///   character's lap and over its desk.
    /// - **Near edge, not centred.** The tab is 9 px wide in a 24 px slot;
    ///   centring it puts 7 px of nothing between it and the head it is about.
    ///   The bubble is the slot's full width, so for the bubble the two rules
    ///   agree and only the tab can tell them apart.
    ///
    /// The node's own anchor comes from the manifest (bottom-centre, because the
    /// bubble's tail is there) and is respected rather than assumed, so a
    /// re-anchored badge sheet moves the picture instead of silently offsetting
    /// it.
    private func placeBadgePicture(width: Double, height: Double) {
        badgeNode.size = CGSize(width: width, height: height)
        let anchor = store.manifest.badges.anchor
        badgeNode.position = CGPoint(
            x: badgeSlotLeftX + width * anchor.x,
            y: badgeSlotTopY - height + height * anchor.y)
    }

    // MARK: Badge

    /// The badge layer. **attention > sleep > tool** — see
    /// `BadgeSelection.isAttention` and `.isSleeping` for why, and why the `×N`
    /// goes with either of the first two. The *precedence* is unchanged by this
    /// method, and it is unchanged by the slot moving beside the head: what the
    /// slot means and when it appears are settled doctrine, and this file only
    /// decides where the pixels land.
    ///
    /// **Two pictures, and the split is the point.** A white speech bubble in
    /// this slot means a tool call — open, just closed inside an ADR-003 beat, or
    /// parked at a gate waiting on you. Nothing else puts one there. Dormancy
    /// gets `SceneBitmaps.dormancyTab` instead, which is small, dark and shaped
    /// like the room's lettering rather than like a bubble; that file carries the
    /// measurement that made it necessary. So at `1x` the question "is this agent
    /// working right now" is answered by *whether there is a bubble*, which is
    /// the one thing the eye gets at that size.
    ///
    /// **Attention keeps the bubble deliberately.** It is the only badge a glance
    /// can act on, and a gated call is a call the agent is still holding — so a
    /// bubble over it is not the inversion this split exists to remove. The one
    /// residue is a *dormant* agent raising attention (`isSleeping` is
    /// `isDormant && !isAttention`, so attention takes the slot): that draws a
    /// bubble over an agent with nothing running. It is rare, it is the more
    /// urgent of two true things, and its precedence is settled — see
    /// `BadgeSelection.isSleeping`.
    ///
    /// If the attention glyph is missing from the manifest nothing is drawn in
    /// its place. That is a *rendering* fallback, not a policy one: the selection
    /// above already decided the order. The dormancy tab cannot go missing — it
    /// is drawn, not loaded, so it survives a checkout with no art.
    public func apply(badge selection: BadgeSelection) {
        guard selection != currentBadge else { return }
        currentBadge = selection
        let attentionTexture = selection.isAttention ? store.attentionTexture() : nil
        let toolTexture = selection.badge.flatMap(store.badgeTexture)
        // The hands follow the badge, in the same call, at the same instant —
        // and before the early return below, so a selection that puts no glyph
        // in the slot still empties the hands.
        refreshHeld()
        // And so does the ambient phrase, for the same reason and in the same
        // place: the motion is a function of (body state, badge class), and this
        // is one of exactly two calls that can change either.
        refreshAmbient()
        // **Dormancy leaves the bubble.** It is the one selection in this slot
        // that is not about a tool call, and while it was drawn from the pack's
        // speech bubble it was 84% of a working badge's footprint in the same
        // shape family — so at `1x` the room's loudest signal fired for
        // *finished* exactly as it fired for *working*. `SceneBitmaps.dormancyTab`
        // carries the measurement and the argument. The tab goes in the same
        // slot, at the tab's own size rather than the badge canvas's, and
        // `placeBadgePicture` is what keeps 9x11 and 24x34 in the same corner of
        // it — the corner beside the head. **The distinction is still extent and
        // not brightness**: the tab covers 99 px of a slot the bubble fills with
        // 816, and moving the slot changed neither number.
        if selection.isSleeping {
            badgeCountNode.isHidden = true
            let bitmap = SceneBitmaps.dormancyTab()
            guard let tab = store.texture(bitmap: bitmap, key: "dormancy") else {
                badgeNode.isHidden = true
                return
            }
            badgeNode.texture = tab
            placeBadgePicture(width: Double(bitmap.width), height: Double(bitmap.height))
            badgeNode.isHidden = false
            return
        }
        // Back to the badge canvas, because the tab above resized the node and a
        // bubble drawn at 9x11 would be the fractional resample I6 exists to
        // prevent. Re-placed rather than only re-sized: the slot is anchored at
        // its top-near corner, so a size change is a position change.
        placeBadgePicture(
            width: Double(store.manifest.badges.canvas.width),
            height: Double(store.manifest.badges.canvas.height))
        guard let texture = attentionTexture ?? toolTexture else {
            badgeNode.isHidden = true
            badgeCountNode.isHidden = true
            return
        }
        badgeNode.texture = texture
        badgeNode.isHidden = false
        // The `×N` annotates a *tool* badge — "N calls, of which this is the
        // lowest ordinal". Pinned to the attention glyph it would read as N
        // notifications, which is not a thing we count. The dormant arm returned
        // above with the count already hidden, so this test is over the two
        // pictures that can still be here.
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

    // MARK: Held object

    /// Centre of the seated hand box, in this node's coordinates.
    ///
    /// **Derived from the measurement, not chosen.** The hands occupy
    /// `x 14...17, y 52...55` of the 32x64 canvas with y counted **down** from
    /// the top — the same box on all six cast variants, all three `sit` frames
    /// and both facings (`HeldObject` records how that was found and
    /// `HeldObjectArtTests.theSeatedHandBoxIsWhereTheArtSaysItIs` re-derives it
    /// from the shipped PNGs). The body is anchored bottom-centre, so:
    ///
    /// - x: the box spans 14 to 18 in canvas x, whose centre is 16, and the
    ///   anchor's x is 16. The offset is **0**, and it is 0 for both facings
    ///   because the box straddles the canvas centre symmetrically — mirroring
    ///   a symmetric box is a no-op.
    /// - y: y-down 52...55 is y-up 8...12 measured from the feet, centre **10**.
    nonisolated static let seatedHandCentre = CGPoint(x: 0, y: 10)

    /// Where the object's own centre goes, relative to the hand centre, for a
    /// character facing **right**. Mirrored in x for `left`.
    ///
    /// **Forward and up, by three pixels and two.** Forward because the hands
    /// are at the near edge of the object rather than behind it — a person holds
    /// a thing in front of themselves, and the room's seated character faces
    /// right at its desk. Up because the hand box's own centre puts the object's
    /// bottom third over the lap, where it read as resting on the knees instead
    /// of being held. With this offset the object occupies canvas
    /// `x 13...24, y 47...56`: its top edge is one pixel under the chin, its
    /// left edge covers the hands, and its bottom clears the trousers.
    ///
    /// Both components are whole pixels, and the canvas is even in both axes, so
    /// every edge of this node lands on a whole pixel at 1x, 2x and 3x. A
    /// half-pixel here would shimmer at exactly the zooms I6 exists to
    /// protect. [I6]
    nonisolated static let heldOffset = CGPoint(x: 3, y: 2)

    /// The object this character is holding, or `nil`.
    ///
    /// Two guards, and each one is an invariant rather than a preference:
    ///
    /// - **The body must be `working`.** [I2] A held object is a body-layer
    ///   claim, so it lives and dies with the ambient loop: a character with no
    ///   open call idles empty-handed, and an ADR-003 closing beat — whose whole
    ///   definition is a badge over an *idle* body — puts nothing in the hands.
    ///   That falls out of this guard rather than being a case handled beside
    ///   it, which is the same structural argument `SceneDirector.body(for:
    ///   badge:)` makes for the working-pose lookup.
    /// - **The badge slot must actually be showing a tool.** `drawn.badge` is
    ///   `nil` while `attention` or `sleep` owns the slot, so a call parked at a
    ///   permission gate empties the hands as well as the badge. That is the
    ///   stricter of the two readings available and it is the one ADR-003 §1
    ///   argues for: a gated `Bash` **is not running**, so drawing the tool over
    ///   it asserts work that is not happening. The body still animates, because
    ///   I2 keys it on the open set alone and that is not this layer's to
    ///   change; the hands do not add a second assertion on top. [I1]
    ///
    /// `questionMark` yields no object at all — see `HeldObject.init(badge:)`.
    private var heldObject: HeldObject? {
        guard currentState == .working else { return nil }
        guard let badge = currentBadge.drawn.badge else { return nil }
        return HeldObject(badge: badge)
    }

    /// Puts `heldObject` on screen. Called from the two places that can change
    /// it — the body state machine and the badge — and from nowhere else, so
    /// the hands cannot get out of step with either.
    private func refreshHeld() {
        guard let object = heldObject,
              let texture = store.texture(
                bitmap: HeldObjectArt.bitmap(object), key: object.textureKey) else {
            heldNode.isHidden = true
            heldNode.texture = nil
            return
        }
        let mirror: CGFloat = currentFacing == .left ? -1 : 1
        heldNode.texture = texture
        heldNode.position = CGPoint(
            x: (Self.seatedHandCentre.x + Self.heldOffset.x) * mirror,
            y: Self.seatedHandCentre.y + Self.heldOffset.y)
        heldNode.xScale = mirror
        heldNode.isHidden = false
    }

    // MARK: Ambient motion

    /// The badge class the ambient phrase is keyed on.
    ///
    /// **`currentBadge.badge`, not `currentBadge.drawn.badge`, and the
    /// difference is decided rather than incidental.** `drawn.badge` is `nil`
    /// while `attention` or `sleep` owns the slot, which is why the *hands* go
    /// empty at a permission gate — an object is a second, larger assertion on
    /// top of a glyph the badge layer is correctly refusing to draw.
    ///
    /// The body is not that layer. `SceneDirector.body(for:badge:)` already
    /// reads the tool class straight through an attention override, on the
    /// grounds that "the attention glyph is about the *badge*, and the body is
    /// about the work", and I2 keys the body on the open-call set alone. A
    /// character blocked at a gate is still holding those calls, so it is still
    /// `working`, and the phrase it plays is the one its calls name. Reading
    /// `drawn` here would silently change *how a working body moves* on a signal
    /// that has nothing to do with the work — and it would put the body and the
    /// working-pose lookup on two different keys.
    private var ambientBadge: ToolBadge? { currentBadge.badge }

    /// Recomputes the phrase without touching `stateStartedAt`.
    ///
    /// **The phase is deliberately not reset.** This class's contract is that a
    /// looping animation is never restarted by an event arriving, which is what
    /// keeps a burst of short calls from stuttering; a phrase swap is an event
    /// arriving. Every phrase is on the same 125 ms grid, so a swap lands on a
    /// step boundary and the body simply continues into the new schedule. [I2]
    private func refreshAmbient() {
        guard !frames.isEmpty else { return }
        frameSequence = AmbientMotion.sequence(
            for: ambientBadge, state: currentState ?? .idle, frameCount: frames.count)
    }

    /// The frame indices this character is playing, for tests that check the
    /// motion rather than the policy.
    var frameSequenceForTesting: [Int] { frameSequence }
    /// Which frame of the current animation is on screen, for the same reason.
    var frameIndexForTesting: Int? {
        guard !frames.isEmpty, let texture = body.texture else { return nil }
        return frames.firstIndex(of: texture)
    }

    /// What is in the hands, for tests that check the picture rather than the
    /// policy. `nil` when the hands are empty.
    public var heldObjectForTesting: HeldObject? { heldNode.isHidden ? nil : heldObject }
    /// The held node's rectangle in the parent's coordinates. Read by the test
    /// that checks the object lands on the hands rather than beside them.
    public var heldRect: CGRect {
        CGRect(
            x: position.x + heldNode.position.x - heldNode.size.width / 2,
            y: position.y + heldNode.position.y - heldNode.size.height / 2,
            width: heldNode.size.width, height: heldNode.size.height)
    }
    public var heldDepth: CGFloat { zPosition + heldNode.zPosition }

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

    /// The badge slot's rectangle in the parent's coordinates — whatever
    /// picture is in it, at that picture's own size. Read by the tests that
    /// check the slot clears the head, the body and the neighbours.
    public var badgeRect: CGRect {
        CGRect(
            x: position.x + badgeNode.position.x
                - badgeNode.size.width * badgeNode.anchorPoint.x,
            y: position.y + badgeNode.position.y
                - badgeNode.size.height * badgeNode.anchorPoint.y,
            width: badgeNode.size.width, height: badgeNode.size.height)
    }

    /// The `×N` chip's rectangle in the parent's coordinates.
    public var badgeCountRect: CGRect {
        CGRect(
            x: position.x + badgeCountNode.position.x,
            y: position.y + badgeCountNode.position.y,
            width: badgeCountNode.size.width, height: badgeCountNode.size.height)
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
        // The phrase, before the first texture is chosen, because the phrase is
        // what chooses it. Every mapped phrase begins `settled`, so this is
        // frame 0 in practice; taking it from the sequence rather than assuming
        // 0 is what keeps the body and the costume on one index from the first
        // frame rather than from the second.
        frameSequence = AmbientMotion.sequence(
            for: ambientBadge, state: state, frameCount: textures.count)
        let firstIndex = frameSequence.first ?? 0
        framesPerSecond = max(1, store.frameRate(variant: agentVariant, state: state))
        framesLoop = store.loops(variant: agentVariant, state: state)
        stateStartedAt = start ?? now
        body.texture = textures[firstIndex]

        // The costume follows the body into the new state, in the same call, at
        // the same instant, with the same frame count. Nothing else in this
        // class may touch these: a costume that could be set from anywhere else
        // would be a second state machine with its own idea of what the
        // character is doing.
        costumeFrames = store.costumeFrames(
            costume: agentCostume, state: state, facing: resolved,
            bodyFrameCount: textures.count)
        for (index, node) in costumeNodes.enumerated() {
            guard index < costumeFrames.count, let textures = costumeFrames[index] else {
                // A layer this costume does not draw for this state — or one
                // whose frame count disagreed with the body's. Hidden, so the
                // character is simply undressed for that layer rather than
                // wearing a coat from another pose.
                node.isHidden = true
                node.texture = nil
                continue
            }
            node.texture = textures[firstIndex]
            node.isHidden = false
        }

        // And the hands, for the same reason and in the same call: the object is
        // a function of (body state, badge), and this is the only place the
        // first of those changes.
        refreshHeld()
    }

    // MARK: Choreography

    public static func duration(from: ScenePoint, to: ScenePoint) -> TimeInterval {
        let distance = ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y))
            .squareRoot()
        return max(0.2, distance / walkSpeed)
    }

    /// Walk in. `spawn` is the walk cycle by construction — the pack ships no
    /// spawn animation and inventing one is not worth the cost.
    /// [04-ART-DIRECTION]
    ///
    /// **The route is a list of waypoints and its first element is where the
    /// character starts**, for the same reason `reportAndReturn` takes one: the
    /// *shape* of the walk is the guarantee, not the endpoints. This one runs
    /// straight up the character's own column and never leaves it, so it cannot
    /// cross another character's station whatever else the room is doing. A
    /// caller that passed a start off to one side would put the plate back on
    /// the aisle and the invariant would be gone with nothing failing, so the
    /// route is built by `RoomLayout.entranceRoute(forSeat:)` and arrives here
    /// already correct.
    public func enter(along route: [ScenePoint]) {
        guard let start = route.first else { return }
        position = CGPoint(x: start.x, y: start.y)
        run(script: route.dropFirst().map { .walk(to: $0, state: .spawn) })
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
    /// **The route is a list of waypoints, not two points, and that is the
    /// aisle invariant made mechanical.** `out` steps down the reporter's own
    /// column to its delivery row and only then moves sideways; `home` reverses
    /// it. Every lateral leg is therefore inside one row and every vertical leg
    /// inside one column, which is exactly the property
    /// `theAisleIsGuaranteedClearAtTheStationsAndNotBetweenThem` proves the
    /// plates out of each other from. A caller that passes a straight
    /// desk-to-anchor diagonal would cut the corner and break it, so the shape
    /// of the route lives in `RoomLayout` and arrives here already correct.
    public func reportAndReturn(
        out: [ScenePoint], facing deliveryFacing: Facing,
        home: [ScenePoint], onFinished: @escaping () -> Void
    ) {
        run(script:
            out.map { .walk(to: $0, state: .walk) }
            + [.play(.deliver, facing: deliveryFacing)]
            + home.map { .walk(to: $0, state: .walk) }
            + [.finish(onFinished)])
    }

    /// The report beat, truncated into an exit: walk to the anchor, hand the
    /// report over, then leave instead of going home.
    ///
    /// Only for a character that reported **and** departed in the same frame —
    /// a `SessionEnd` landing on top of a `SubagentStop`. Both facts are real,
    /// so the character plays the beat it earned and then goes.
    /// The report beat, truncated into an exit: walk the route out, hand the
    /// report over, walk the route back, and then leave instead of sitting down.
    ///
    /// It walks the route *back* rather than cutting to the edge from the
    /// delivery point, because the delivery point is on a delivery row and the
    /// only clear way off a delivery row is the column it came down.
    public func reportAndDepart(
        out: [ScenePoint], facing deliveryFacing: Facing,
        home: [ScenePoint], thenExitAt edge: ScenePoint, onFinished: @escaping () -> Void
    ) {
        apply(badge: .none)
        run(script:
            out.map { .walk(to: $0, state: .walk) }
            + [.play(.deliver, facing: deliveryFacing)]
            + home.map { .walk(to: $0, state: .depart) }
            + [.walk(to: edge, state: .depart), .finish(onFinished)],
            fadingOnLastWalk: true)
    }

    /// Walk off. `depart` is the walk cycle towards the edge, same composition
    /// as `spawn`.
    public func departOffScreen(
        via route: [ScenePoint], to edge: ScenePoint, onFinished: @escaping () -> Void
    ) {
        apply(badge: .none)
        run(script:
            route.map { .walk(to: $0, state: .depart) }
            + [.walk(to: edge, state: .depart), .finish(onFinished)],
            fadingOnLastWalk: true)
    }

    private func run(script steps: [Step], fadingOnLastWalk: Bool = false) {
        script = steps
        stepIndex = 0
        alpha = 1
        fadingStep = fadingOnLastWalk
            ? steps.lastIndex(where: { if case .walk = $0 { return true } else { return false } })
            : nil
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
                if stepIndex == fadingStep { alpha = 1 - progress }
                guard progress >= 1 else { break stepping }
                let finishedAt = moveStartedAt + moveDuration
                stepIndex += 1
                beginCurrentStep(at: finishedAt)
            case .play:
                // The *sequence*'s length, not the frame array's. They are equal
                // for every state a `.play` step can carry — only `working` has
                // a phrase and `deliver` is the only state ever played this way
                // — but reading the thing the clock below actually walks is what
                // keeps the two from disagreeing if that ever stops being true.
                let length = Double(max(frameSequence.count, 1)) / framesPerSecond
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

        guard !frames.isEmpty, !frameSequence.isEmpty else { return }
        let elapsed = max(0, now - stateStartedAt)
        // The **step** on the manifest's 8 fps grid, which is what a phrase is
        // written in. For every state but `working` the sequence is the identity
        // and this is the frame index it always was.
        var step = Int(elapsed * framesPerSecond)
        if framesLoop {
            step %= frameSequence.count
        } else {
            step = min(step, frameSequence.count - 1)
        }
        let index = min(frameSequence[step], frames.count - 1)
        body.texture = frames[index]
        // **The same index, not a second clock.** Every layer was loaded with
        // the body's own frame count in `apply(state:facing:)`, so this cannot
        // be out of range and cannot drift; a costume is always on exactly the
        // frame the person wearing it is on.
        for (layer, textures) in zip(costumeNodes, costumeFrames) {
            guard let textures else { continue }
            layer.texture = textures[index]
        }
    }

    /// The costume layer nodes, for tests that need to check the picture rather
    /// than the policy. Read-only; nothing in the scene depends on it.
    var costumeNodesForTesting: [SKSpriteNode] { costumeNodes }
}
