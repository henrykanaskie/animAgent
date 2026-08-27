import Foundation
import SpriteKit
import SpriteRoomCore

/// **The view: a camera, an integer scale, and the room it is pointed at.**
///
/// This class used to be the room as well, which is why there could only ever
/// be one. M9 Phase 4 needs several at once, one per project, so everything
/// that is *about a room* moved to `RoomWorld` and everything that is about the
/// **view** stayed here. The public API did not move: every member below either
/// forwards to the room or is one of the three things that were always the
/// scene's own.
///
/// **What is genuinely the view's, and why each one is:**
///
/// - **the camera**, because there is one of it however many rooms there are;
/// - **the viewport and the integer scale**, because `.fill` maps `size` onto
///   the whole view and the magnification is therefore a property of the pair,
///   not of any room [I6];
/// - **the frame**, which the overflow plate is clamped into. The room owns the
///   plate and the arithmetic; it is handed the rectangle because it no longer
///   has any way to ask for one.
///
/// **The extraction moved no behaviour and that is checkable rather than
/// asserted.** `scripts/lint-palette.py`'s scene-agreement check renders this
/// scene through the real `SKRenderer` and compares it, per theme, pixel for
/// pixel against an independent transcription with an empty defect register.
/// A refactor that moved a single prop would fail it.
public final class RoomScene: SKScene {

    /// **The rooms, in the order they were first seen.** [M9 Phase 4]
    ///
    /// One per project. The first is the one every existing accessor forwards
    /// to, which is what keeps a single-project run byte-identical to the run
    /// before this existed: slot 0 sits at the origin and nothing about it
    /// moves, so `lint-palette.py`'s pixel comparison still means what it meant.
    public private(set) var rooms: [(project: String, world: RoomWorld)] = []

    /// The room every single-project accessor speaks for.
    public var world: RoomWorld { rooms[0].world }

    /// **How far apart two rooms stand, in room pixels.**
    ///
    /// Not the room's nominal box (`rows * tile` = 288) but **what a room
    /// actually paints**, which is a good deal more: tiles are drawn past the
    /// nominal bounds so that no zoom level ever shows the void at an edge, and
    /// `RoomLayout.drawnRows` is that overscan. A pitch of 288 puts the room
    /// above squarely on top of the room below's back wall, which is measured
    /// rather than guessed: it was tried, rendered, and the wall disappeared.
    ///
    /// So the pitch is measured off **the plan**, which is the part of a room
    /// that is the room: 18 tiles from the walkway's near edge at `y = -6` to
    /// the back band's top at `y = 11`, i.e. 576 px. At that pitch the floor of
    /// the room above begins exactly where the back wall of the room below
    /// ends: no overlap, and no strip of void between them either.
    ///
    /// **Both neighbouring values were rendered before this one was picked.**
    /// The nominal box (288) put the upper room squarely on top of the lower
    /// room's back wall and the wall vanished. The painted height (672, the
    /// overscan `drawnRows`) left a 64 px band of void that is panel height
    /// spent on nothing, which at 1x is a third of a character's worth of
    /// screen per room.
    ///
    /// It is derived from `RoomPlan`'s own span rather than typed, so a plan
    /// that ever changes depth takes the stack with it.
    public var roomPitch: Double {
        let plan = rooms[0].world.store.room.plan
        guard let lowest = plan.spaces.map(\.y).min(),
              let highest = plan.spaces.map({ $0.y + $0.h }).max(),
              highest > lowest
        else { return layout.height + Double(layout.tile) }
        return Double((highest - lowest) * layout.tile)
    }

    private let camera_ = SKCameraNode()
    private let manifest: Manifest
    private let baseLayout: RoomLayout

    /// The scale the director asked for, from population. The viewport can
    /// only ever push this *down* the ladder, never up. [I6]
    private var preferredScale = 3
    private var effectiveScale = 3
    private var viewport = CGSize(width: 960, height: 540)

    public init(
        manifest: Manifest, themeID: String? = nil, layout: RoomLayout = RoomLayout()
    ) {
        let first = RoomWorld(manifest: manifest, themeID: themeID, layout: layout)
        self.manifest = manifest
        self.baseLayout = layout
        super.init(size: CGSize(width: 320, height: 180))
        rooms = [(project: "", world: first)]
        scaleMode = .fill
        // Slightly darker than the room's value floor so the room never blends
        // into the void behind it.
        backgroundColor = RoomWorld.voidColour
        addChild(first.root)
        addChild(camera_)
        camera = camera_
        applyScale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: What the room is, forwarded

    public var layout: RoomLayout { world.layout }
    public var store: TextureStore { world.store }
    public var population: Int { world.population }
    public var charactersOnScreen: [Character] { world.charactersOnScreen }
    public var overflowShown: Int { world.overflowShown }
    public func character(for agent: AgentRef) -> Character? { world.character(for: agent) }

    public var currentScale: Int { effectiveScale }

    /// The room's roster plus the one line only the view can write.
    public var debugRoster: [String] {
        world.debugRoster + [
            "camera x=\(Int(camera_.position.x)) y=\(Int(camera_.position.y))"
            + " scale=\(effectiveScale)"
            + " sceneSize=\(Int(size.width))x\(Int(size.height))",
        ]
    }

    // MARK: The rooms [M9 Phase 4]

    /// **The room for `project`, made if this is the first time it is seen.**
    ///
    /// Slot 0 is claimed by the first project to ask, and it takes over the room
    /// built in `init`, theme and all: building a second and throwing the first
    /// away would redraw the whole room on the first delta of every run.
    ///
    /// Rooms stack **upstage**, one `roomPitch` apart, in first-seen order. That
    /// order is deliberately not "most recently active": a room that reshuffled
    /// itself whenever another project got busy would move every character on
    /// screen for a reason none of them had anything to do with, which is the
    /// lurch `theRoomIsDrawnWideAtEveryPopulation` exists to prevent, one level
    /// up. [I1]
    @discardableResult
    public func room(for project: String, themeID: String?) -> RoomWorld {
        if let existing = rooms.first(where: { $0.project == project }) {
            return existing.world
        }
        // The room `init` built is unclaimed until the first project arrives.
        if rooms.count == 1, rooms[0].project == "" {
            rooms[0].project = project
            return rooms[0].world
        }
        let world = RoomWorld(manifest: manifest, themeID: themeID, layout: baseLayout)
        world.root.position = CGPoint(x: 0, y: CGFloat(Double(rooms.count) * roomPitch))
        rooms.append((project: project, world: world))
        addChild(world.root)
        refreshRoomLabels()
        applyScale()
        return world
    }

    /// **Rooms are labelled only when there is more than one.** [ADR-016]
    ///
    /// A single-project run has no "whose room is this" question to answer, so
    /// it draws no label and its pixels stay exactly what they were. That is
    /// not a nicety: `lint-palette.py`'s scene agreement compares this scene to
    /// an independent transcription pixel for pixel, and a caption it does not
    /// model would fail it, correctly.
    ///
    /// The label is set from the display name the app hands over, which is the
    /// same string the menu bar already shows for that project.
    private func refreshRoomLabels() {
        let many = rooms.count > 1
        for entry in rooms {
            entry.world.setLabel(many ? (labels[entry.project] ?? Self.tail(entry.project)) : nil)
        }
    }

    /// **The last path component, as the fallback when the app has not handed
    /// over a display name yet.**
    ///
    /// A room can be created part-way through a frame, before `RoomHost` has
    /// recomputed the roster's names, and the first draft fell back to the
    /// **whole `cwd`**: the panel showed `/USERS/HE...` truncated to a plate's
    /// width, which is the one thing a label must never be. A full path is
    /// never the right answer at this size, whoever is asking.
    ///
    /// This is not the app's `displayNames`, and deliberately not: that
    /// function disambiguates *across the roster*, taking as many trailing
    /// components as it needs to make every name unique, and that is a question
    /// about the whole set which the scene has no business answering. This is
    /// only a floor: something readable until the real answer arrives, which is
    /// on the next frame.
    nonisolated static func tail(_ project: String) -> String {
        project.split(separator: "/").last.map(String.init) ?? project
    }

    /// Display names, by project. Set by the app; the scene never derives one,
    /// because turning a `cwd` into something short enough to read is a
    /// question about the whole roster and not about any one room.
    public var labels: [String: String] = [:] {
        didSet { refreshRoomLabels() }
    }

    /// Which room a project is drawn in, or `nil` if it has never been seen.
    /// Slot 0 is the bottom of the stack.
    public func slot(of project: String) -> Int? {
        rooms.firstIndex { $0.project == project }
    }

    // MARK: Intents

    /// **`.setScale` is taken out here and everything else goes through.**
    ///
    /// It is the one intent that is about the view rather than about the room,
    /// so the room does not get to see it: `RoomWorld.apply`'s `.setScale` arm
    /// is unreachable by construction rather than by agreement.
    public func apply(_ intents: [SpriteIntent]) {
        apply(intents, to: rooms[0].project)
    }

    /// **The same, addressed to one project's room.** [M9 Phase 4]
    ///
    /// `.setScale` is still taken out here rather than forwarded: the scale is
    /// the camera's and there is one camera however many rooms there are, so
    /// the last room to speak does not get to decide it. Every other intent
    /// goes to the room the project is drawn in.
    public func apply(_ intents: [SpriteIntent], to project: String) {
        let target = rooms.first { $0.project == project }?.world ?? rooms[0].world
        for intent in intents {
            if case let .setScale(scale) = intent {
                preferredScale = scale
            } else {
                target.apply(intent)
            }
        }
        applyScale()
    }

    public func apply(_ intent: SpriteIntent) { apply([intent]) }

    // MARK: Clock

    /// SpriteKit calls this from the view's render loop. The offscreen harness
    /// calls `advance(to:)` directly with a simulated clock: one animation
    /// engine, two drivers, identical output.
    public override func update(_ currentTime: TimeInterval) {
        advance(to: currentTime)
    }

    public func advance(to time: TimeInterval) { world.advance(to: time) }

    // MARK: Camera [I6]

    /// Call on resize, and before the first frame. Dimensions in the same unit
    /// the scene will be presented in.
    public func setViewport(_ size: CGSize) {
        viewport = size
        applyScale()
    }

    /// **How many rooms the viewport can actually hold, at least one.**
    /// [M9 Phase 4]
    ///
    /// A stack taller than the frame is worse than a single room, not better:
    /// the camera centres on the union, so two rooms in a 400 px panel would
    /// show the top of one and the floor of the other and **neither one's
    /// characters**. That is a regression for the exact user the feature is
    /// for, so the room count is bounded by the frame rather than by hope.
    ///
    /// The surplus is **counted, not drawn**, which is the answer this room
    /// already gives for the eighth agent: a picture that states a population
    /// it does not have is the failure, and dropping a project silently is the
    /// same failure one level up. [I1]
    ///
    /// This makes the panel's height a pure taste knob. At 400 px it is one
    /// room, exactly as before this existed; at 800 it is two. Nothing else has
    /// to change to spend it.
    /// **Measured at `1x`, deliberately, and not at the current scale.**
    ///
    /// The scale is chosen *from* what is drawn, so asking "how many rooms fit
    /// at the current scale" is circular: the first draft did exactly that and
    /// an empty room at `3x` reported that a 800 px panel could hold one room,
    /// which is how the circle shows itself.
    ///
    /// `1x` is the right cut anyway. It is the floor of the ladder [I6] and the
    /// only rung the shipped panel uses, so this asks the question the panel is
    /// actually asking: how many rooms does this height buy. A run that zooms
    /// past `1x` (few enough characters that a closer rung fits) then crops the
    /// stack, which is exactly what it already does to a single room and needs
    /// no separate rule.
    var roomsThatFit: Int {
        guard roomPitch > 0 else { return 1 }
        let band = rooms[0].world.contentBand
        let bandHeight = max(1, band.top - band.bottom)
        // The first room costs its band; each further one costs a whole pitch.
        let extra = Int(((Double(viewport.height) - bandHeight) / roomPitch).rounded(.down))
        return max(1, min(rooms.count, 1 + max(0, extra)))
    }

    /// **The viewport height that would show every room this scene holds.**
    /// [ADR-016 §4]
    ///
    /// The inverse of `roomsThatFit`, and the number the panel asks for when it
    /// decides how tall to be. One room asks for exactly what it always asked
    /// for, so a single-project run never resizes anything.
    ///
    /// Capped by the caller, not here: this says what the rooms want and the
    /// panel decides what the display can spare.
    public func viewportHeightToShowEveryRoom() -> Double {
        let band = rooms[0].world.contentBand
        let bandHeight = max(1, band.top - band.bottom)
        return bandHeight + roomPitch * Double(max(0, rooms.count - 1))
    }

    /// Projects that exist but are not on screen because the frame cannot hold
    /// them. Drawn by nothing yet; `RoomHost` reports it.
    public var roomsNotShown: Int { max(0, rooms.count - roomsThatFit) }

    private func applyScale() {
        // **The frame has to hold every room, not the first one.** [M9 Phase 4]
        // With one room this is arithmetically identical to what it was: the
        // union of one span is that span, and slot 0 is at the origin, so a
        // single-project run frames exactly what it framed before.
        // Hide the rooms that do not fit before framing, so the camera frames
        // what is drawn rather than what exists.
        let shown = roomsThatFit
        for (index, entry) in rooms.enumerated() {
            entry.world.root.isHidden = index >= shown
        }
        var span = layout.occupiedSpan(seats: rooms[0].world.charactersBySeat())
        var band = rooms[0].world.contentBand
        for (index, entry) in rooms.enumerated().dropFirst() where index < shown {
            let other = layout.occupiedSpan(seats: entry.world.charactersBySeat())
            span = (minX: min(span.minX, other.minX), maxX: max(span.maxX, other.maxX))
            let offset = Double(index) * roomPitch
            let theirs = entry.world.contentBand
            band = (bottom: min(band.bottom, theirs.bottom + offset),
                    top: max(band.top, theirs.top + offset))
        }
        let contentWidth = max(1, span.maxX - span.minX)
        let contentHeight = max(1, band.top - band.bottom)
        let roomCamera = RoomCamera(manifest: store.manifest)
        let fitting = roomCamera.largestFittingScale(
            viewportWidth: Double(viewport.width),
            viewportHeight: Double(viewport.height),
            contentWidth: contentWidth,
            contentHeight: contentHeight)
        let scale = max(roomCamera.minimumScale, min(preferredScale, fitting))
        effectiveScale = scale

        // `.fill` maps `size` onto the whole viewport. Setting `size` to the
        // viewport divided by an integer therefore magnifies by exactly that
        // integer on both axes: no fractional resampling anywhere. [I6]
        let sceneSize = CGSize(
            width: max(1, Double(viewport.width) / Double(scale)),
            height: max(1, Double(viewport.height) / Double(scale)))
        if size != sceneSize { size = sceneSize }

        let centreX = (span.minX + span.maxX) / 2
        camera_.position = CGPoint(
            x: (centreX).rounded(),
            y: world.cameraY(band: band, sceneHeight: sceneSize.height).rounded())
        // The plate's clamp is measured against the frame, so it has to be
        // re-applied whenever the frame moves. The room owns the plate and the
        // arithmetic; the rectangle is the only part it cannot work out itself.
        let frame = CGRect(
            x: camera_.position.x - sceneSize.width / 2,
            y: camera_.position.y - sceneSize.height / 2,
            width: sceneSize.width, height: sceneSize.height)
        for (index, entry) in rooms.enumerated() {
            // Each room clamps its own plate in its own coordinates, so the
            // frame is shifted down by that room's offset before it is handed
            // over: a room does not know where it stands and must not have to.
            let offset = Double(index) * roomPitch
            let local = frame.offsetBy(dx: 0, dy: CGFloat(-offset))
            entry.world.rememberCameraFrame(local)
            entry.world.positionOverflowPlate(in: local)
        }
    }

    // MARK: The room's internals, forwarded for the tests
    //
    // The suite reaches into the room through the scene because that is what it
    // has always had a handle on. Forwarding rather than re-pointing every test
    // at `scene.world` keeps this refactor to what it claims to be: the room and
    // the camera separating, with nothing else moving.

    var contentBand: (bottom: Double, top: Double) { world.contentBand }
    var decorationTopY: Double { world.decorationTopY }
    var planArtForTesting: [String] { world.planArtForTesting }
    var planNodesForTesting: [SKSpriteNode] { world.planNodesForTesting }
    var propNodesForTesting: [SKSpriteNode] { world.propNodesForTesting }
    var propArtForTesting: [String] { world.propArtForTesting }
    var sceneryNodesForTesting: [SKSpriteNode] { world.sceneryNodesForTesting }
    var seatFurnitureNodesForTesting: [SKSpriteNode] { world.seatFurnitureNodesForTesting }
    var propAnimationsForTesting: [PropAnimation] { world.propAnimationsForTesting }
    var deskObjectNodesForTesting: [AgentRef: SKSpriteNode] { world.deskObjectNodesForTesting }
    var deliveryRowHoldersForTesting: [Int] { world.deliveryRowHoldersForTesting }
    var roomBuildCount: Int { world.roomBuildCount }

    func seatOfForTesting(_ agent: AgentRef) -> Int? { world.seatOfForTesting(agent) }
    func charactersBySeat() -> [Int] { world.charactersBySeat() }
    func cameraY(band: (bottom: Double, top: Double), sceneHeight: Double) -> Double {
        world.cameraY(band: band, sceneHeight: sceneHeight)
    }
    func seatMetrics(desk: Manifest.PropRole? = nil) -> RoomLayout.SeatMetrics {
        world.seatMetrics(desk: desk)
    }
    func podFurniture(seat: Int, metrics: RoomLayout.SeatMetrics) -> [RoomWorld.PodPiece] {
        world.podFurniture(seat: seat, metrics: metrics)
    }
    func seatedHeadClearance(nearEdgeX: Double) -> Int {
        world.seatedHeadClearance(nearEdgeX: nearEdgeX)
    }

    public func furnitureForTesting(seat: Int) -> [DrawnFurniture] {
        world.furnitureForTesting(seat: seat)
    }
    public func deskObjectsForTesting() -> [AgentRef: DrawnFurniture] {
        world.deskObjectsForTesting()
    }
    public func deskScreensForTesting() -> [AgentRef: DeskScreen] {
        world.deskScreensForTesting()
    }
    public func overflowPlateBoxForTesting() -> (x: Double, y: Double,
                                                 width: Double, height: Double)? {
        world.overflowPlateBoxForTesting()
    }

    // MARK: The room's own vocabulary, re-exported
    //
    // These are `RoomWorld`'s and they name the manifest's role keys and the
    // scene's depth constants. They are re-exported rather than moved because
    // roughly ninety call sites across `Sources/` and `Tests/` say
    // `RoomScene.surfaceRole` and there is nothing to be gained by making all
    // of them say something else on the day the room and the camera separated.

    public typealias DrawnFurniture = RoomWorld.DrawnFurniture

    nonisolated public static var surfaceRole: String { RoomWorld.surfaceRole }
    nonisolated public static var seatRole: String { RoomWorld.seatRole }
    nonisolated public static var backSeatRole: String { RoomWorld.backSeatRole }
    nonisolated public static var backdropRole: String { RoomWorld.backdropRole }
    nonisolated public static var accentRole: String { RoomWorld.accentRole }
    nonisolated public static var monitorRole: String { RoomWorld.monitorRole }
    nonisolated public static var deskKitRole: String { RoomWorld.deskKitRole }
    nonisolated public static var voidColour: SKColor { RoomWorld.voidColour }
    nonisolated public static var seatDepthBias: CGFloat { RoomWorld.seatDepthBias }
    nonisolated public static var surfaceInFrontBias: CGFloat { RoomWorld.surfaceInFrontBias }

    nonisolated public static func decorationPlacements(
        layout: RoomLayout
    ) -> [(role: String, point: ScenePoint)] {
        RoomWorld.decorationPlacements(layout: layout)
    }

    nonisolated public static func dressingPlacements(
        store: TextureStore
    ) -> [(prop: Manifest.PropRole, point: ScenePoint)] {
        RoomWorld.dressingPlacements(store: store)
    }

    nonisolated public static func surfaceDepthBias(
        deskHeight: Int, headClearance: Int
    ) -> CGFloat {
        RoomWorld.surfaceDepthBias(deskHeight: deskHeight, headClearance: headClearance)
    }

    nonisolated public static func seatedFrames(
        manifest: Manifest, facing: Facing
    ) -> [Bitmap] {
        RoomWorld.seatedFrames(manifest: manifest, facing: facing)
    }

    nonisolated public static func surfaceNearEdgeX(
        of prop: Manifest.PropRole, layout: RoomLayout
    ) -> Double {
        RoomWorld.surfaceNearEdgeX(of: prop, layout: layout)
    }

    nonisolated public static func deskObjectNearEdgeX(manifest: Manifest) -> Double {
        RoomWorld.deskObjectNearEdgeX(manifest: manifest)
    }
}
