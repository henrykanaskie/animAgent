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

    /// The one room this scene draws today. Phase 4 makes this a collection;
    /// nothing outside this file should assume it stays singular, which is why
    /// every accessor below goes through it rather than around it.
    public let world: RoomWorld

    private let camera_ = SKCameraNode()

    /// The scale the director asked for, from population. The viewport can
    /// only ever push this *down* the ladder, never up. [I6]
    private var preferredScale = 3
    private var effectiveScale = 3
    private var viewport = CGSize(width: 960, height: 540)

    public init(
        manifest: Manifest, themeID: String? = nil, layout: RoomLayout = RoomLayout()
    ) {
        self.world = RoomWorld(manifest: manifest, themeID: themeID, layout: layout)
        super.init(size: CGSize(width: 320, height: 180))
        scaleMode = .fill
        // Slightly darker than the room's value floor so the room never blends
        // into the void behind it.
        backgroundColor = RoomWorld.voidColour
        addChild(world.root)
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

    // MARK: Intents

    /// **`.setScale` is taken out here and everything else goes through.**
    ///
    /// It is the one intent that is about the view rather than about the room,
    /// so the room does not get to see it: `RoomWorld.apply`'s `.setScale` arm
    /// is unreachable by construction rather than by agreement.
    public func apply(_ intents: [SpriteIntent]) {
        for intent in intents {
            if case let .setScale(scale) = intent {
                preferredScale = scale
            } else {
                world.apply(intent)
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

    private func applyScale() {
        let seats = world.charactersBySeat()
        let span = layout.occupiedSpan(seats: seats)
        let contentWidth = max(1, span.maxX - span.minX)
        let band = world.contentBand
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
        world.rememberCameraFrame(frame)
        world.positionOverflowPlate(in: frame)
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
