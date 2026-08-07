import Foundation
import SpriteKit
import SpriteRoomCore

/// The room. Applies `SpriteIntent`s to nodes and nothing else — every policy
/// decision was already made by `SceneDirector`, and nothing here ever calls
/// back upstream.
@MainActor
public final class RoomScene: SKScene {

    public let layout: RoomLayout
    public let store: TextureStore
    private let camera_ = SKCameraNode()
    private let world = SKNode()

    private var characters: [AgentRef: Character] = [:]
    /// Every character node currently in the scene, including ones part-way
    /// through their exit walk. The clock has to reach those too or a departing
    /// character freezes mid-stride.
    private var animated: [Character] = []
    /// Seat per live character. Kept here rather than recovered from position,
    /// so the camera frames a character's seat from the moment it starts
    /// walking in rather than snapping open when it arrives.
    private var seatOf: [AgentRef: Int] = [:]
    /// Delivery slots currently occupied by a report in flight. Claimed on the
    /// way in, released when the reporter is retired.
    private var reportingSlots: Set<Int> = []
    private var slotOf: [ObjectIdentifier: Int] = [:]

    /// The scale the director asked for, from population. The viewport can
    /// only ever push this *down* the ladder, never up. [I6]
    private var preferredScale = 3
    private var effectiveScale = 3
    private var viewport = CGSize(width: 960, height: 540)

    public init(manifest: Manifest, layout: RoomLayout = RoomLayout()) {
        self.layout = layout
        self.store = TextureStore(manifest: manifest)
        super.init(size: CGSize(width: 320, height: 180))
        scaleMode = .fill
        // Slightly darker than the room's value floor so the room never blends
        // into the void behind it.
        backgroundColor = SKColor(red: 0.14, green: 0.13, blue: 0.17, alpha: 1)
        addChild(world)
        addChild(camera_)
        camera = camera_
        buildRoom()
        applyScale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public var population: Int { characters.count }
    public var currentScale: Int { effectiveScale }

    public func character(for agent: AgentRef) -> Character? { characters[agent] }

    /// Every character node currently drawn, including ones part-way through
    /// an exit walk. Tests that check the *picture* need the leavers too —
    /// the report walk is exactly when two characters share the frame.
    public var charactersOnScreen: [Character] { animated }

    /// Diagnostics for the render harness. Read-only; nothing depends on it.
    public var debugRoster: [String] {
        characters.map { agent, character in
            "\(agent) at x=\(Int(character.position.x)) state=\(character.state.map(\.rawValue) ?? "-") badge=\(character.badgeSelection.badge?.rawValue ?? "-")"
        }.sorted() + ["camera x=\(Int(camera_.position.x)) y=\(Int(camera_.position.y)) scale=\(effectiveScale) sceneSize=\(Int(size.width))x\(Int(size.height))"]
    }

    // MARK: Room construction

    private func buildRoom() {
        let tiles = store.roomTileChoice()
        let tile = layout.tile
        let floorTexture = store.texture(path: tiles.floor)
        let wallTexture = store.texture(path: tiles.wall)

        for row in layout.drawnRows {
            for column in layout.drawnColumns {
                let isWall = row >= layout.floorRows
                let texture = isWall ? wallTexture : floorTexture
                guard let texture else { continue }
                let node = SKSpriteNode(texture: texture)
                node.anchorPoint = CGPoint(x: 0, y: 0)
                node.size = CGSize(width: tile, height: tile)
                node.position = CGPoint(x: column * tile, y: row * tile)
                node.zPosition = isWall ? -20 : -30
                world.addChild(node)
            }
        }

        // A desk at every seat, occupied or not — an office has empty desks,
        // and drawing them only when someone arrives would make the room
        // rearrange itself as agents come and go.
        //
        // **Depth: the desk occludes the seated body, deliberately.** Desks and
        // seated characters stand on the same row, so row sorting alone leaves
        // the tie to chance; the desk takes the row's depth plus a half so the
        // tie resolves the same way every time. It resolves *towards the desk*
        // because at 32px the only cue that a character is sitting *at* a desk
        // rather than beside one is whether the desk's near edge crosses the
        // body. The overlap is the eight pixels where the desk's near leg meets
        // the character's right side; the nameplate and badge are in an overlay
        // band far above this, so nothing a desk does can hide either.
        //
        // Aisle characters sit a whole row nearer the camera, so a character
        // walking past is always in front of the desks — which is why the
        // walkway exists.
        let deskBitmap = SceneBitmaps.placeholderDesk()
        if let deskTexture = store.texture(bitmap: deskBitmap, key: "desk:placeholder") {
            for seat in 0..<layout.seatCapacity {
                let node = SKSpriteNode(texture: deskTexture)
                node.anchorPoint = CGPoint(x: 0, y: 0)
                node.size = CGSize(width: deskBitmap.width, height: deskBitmap.height)
                let position = layout.deskPosition(seat)
                node.position = CGPoint(x: position.x, y: position.y)
                node.zPosition = Character.Layer.rowDepth(position.y) + 0.5
                world.addChild(node)
            }
        }
    }

    // MARK: Intents

    public func apply(_ intents: [SpriteIntent]) {
        for intent in intents { apply(intent) }
        applyScale()
    }

    public func apply(_ intent: SpriteIntent) {
        switch intent {
        case let .spawnCharacter(agent, variant, nameplate, seat):
            guard characters[agent] == nil else { break }
            let character = Character(variant: variant, nameplate: nameplate, store: store)
            world.addChild(character)
            characters[agent] = character
            animated.append(character)
            seatOf[agent] = seat
            character.enter(
                from: layout.edgePosition(forSeat: seat),
                approach: layout.seatApproach(seat),
                seat: layout.seatPosition(seat))

        case let .setBody(agent, state, facing):
            characters[agent]?.setResting(state, facing: facing)

        case let .setBadge(agent, selection):
            characters[agent]?.apply(badge: selection)

        case let .exitCharacter(agent, style):
            guard let character = characters.removeValue(forKey: agent) else { break }
            seatOf.removeValue(forKey: agent)
            let approach = ScenePoint(x: Double(character.position.x), y: layout.aisleY)
            switch style {
            case .report:
                // Step into the aisle, walk to the main agent's anchor, hand
                // over, then leave. The anchor is seat 0 because the
                // parent→child link is not available to the scene — an
                // unlinked subagent anchors to the main agent rather than
                // guessing a parent. [I1]
                var slot = 0
                while reportingSlots.contains(slot) { slot += 1 }
                reportingSlots.insert(slot)
                slotOf[ObjectIdentifier(character)] = slot
                let delivery = layout.deliveryPosition(slot: slot)
                character.reportAndDepart(
                    via: approach,
                    to: delivery,
                    facing: layout.deliveryFacing,
                    thenExitAt: layout.nearestEdge(toX: delivery.x)
                ) { [weak self, weak character] in self?.retire(character) }
            case .walkOff:
                character.departOffScreen(
                    via: approach,
                    to: layout.nearestEdge(toX: Double(character.position.x))
                ) { [weak self, weak character] in self?.retire(character) }
            }

        case let .setScale(scale):
            preferredScale = scale
        }
    }

    private func retire(_ character: Character?) {
        guard let character else { return }
        if let slot = slotOf.removeValue(forKey: ObjectIdentifier(character)) {
            reportingSlots.remove(slot)
        }
        animated.removeAll { $0 === character }
        character.removeFromParent()
    }

    // MARK: Clock

    /// SpriteKit calls this from the view's render loop. The offscreen harness
    /// calls `advance(to:)` directly with a simulated clock — one animation
    /// engine, two drivers, identical output.
    public override func update(_ currentTime: TimeInterval) {
        advance(to: currentTime)
    }

    public func advance(to time: TimeInterval) {
        for character in animated { character.advance(to: time) }
    }

    // MARK: Camera [I6]

    /// Call on resize, and before the first frame. Dimensions in the same unit
    /// the scene will be presented in.
    public func setViewport(_ size: CGSize) {
        viewport = size
        applyScale()
    }

    private func applyScale() {
        let seats = charactersBySeat()
        let span = layout.occupiedSpan(seats: seats)
        let contentWidth = max(1, span.maxX - span.minX)
        let roomCamera = RoomCamera(manifest: store.manifest)
        let fitting = roomCamera.largestFittingScale(
            viewportWidth: Double(viewport.width),
            viewportHeight: Double(viewport.height),
            contentWidth: contentWidth,
            contentHeight: layout.height)
        let scale = max(roomCamera.minimumScale, min(preferredScale, fitting))
        effectiveScale = scale

        // `.fill` maps `size` onto the whole viewport. Setting `size` to the
        // viewport divided by an integer therefore magnifies by exactly that
        // integer on both axes — no fractional resampling anywhere. [I6]
        let sceneSize = CGSize(
            width: max(1, Double(viewport.width) / Double(scale)),
            height: max(1, Double(viewport.height) / Double(scale)))
        if size != sceneSize { size = sceneSize }

        let centreX = (span.minX + span.maxX) / 2
        camera_.position = CGPoint(
            x: (centreX).rounded(),
            y: (layout.height / 2).rounded())
    }

    /// Seat 0 is always in the frame even when empty: the main agent's anchor
    /// is where reports are delivered, so a report from an off-screen subagent
    /// is still visible.
    private func charactersBySeat() -> [Int] {
        var seats = Array(seatOf.values)
        if !seats.contains(0) { seats.append(0) }
        return seats
    }
}
