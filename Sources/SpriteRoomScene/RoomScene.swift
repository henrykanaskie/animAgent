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
            "\(agent) at x=\(Int(character.position.x)) state=\(character.state.map(\.rawValue) ?? "-") badge=\(character.badgeSelection.attention.map { "attention(\($0))" } ?? character.badgeSelection.badge?.rawValue ?? "-")"
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

        // Furniture, behind the desk row and against the wall. Deterministic
        // positions, one per seat pitch, so the room does not rearrange itself
        // as agents come and go — and far enough back that at `3x`, which
        // frames a single seat, none of it is in shot.
        //
        // This is the composition fix, and it is deliberately thin. I7's
        // standing instruction is that a background detail competes with the
        // characters at exactly the zoom where they are hardest to read, so
        // there are two kinds of object, they alternate, and both went through
        // the same desaturating import pass as the floor.
        let backRowY = layout.baselineY + Double(tile)
        for seat in 0..<layout.seatCapacity {
            let role = seat.isMultiple(of: 2) ? "board" : "plant"
            let x = Double(layout.seatColumn(seat) * tile + tile / 2) + Double(tile) * 1.5
            guard x < layout.width else { continue }
            place(role: role, at: ScenePoint(x: x, y: backRowY))
        }

        // A row of plants in front of the walkway, **strictly below the content
        // band**.
        //
        // The rule is the interesting part, not the plants. Decoration placed
        // outside the band is invisible at the tightest fitting scale and comes
        // into frame only as the camera pulls back — so it can never compete
        // with a character at the zoom where characters are hardest to read,
        // which is exactly what I7's "remove the background detail" warning is
        // about, and it fills the foreground at `1x`, where there is otherwise a
        // flat field of floor under everyone's nameplate.
        if let plant = store.manifest.room.prop("plant") {
            let y = contentBand.bottom - Double(plant.contentBox.height) - 4
            for seat in 0..<layout.seatCapacity {
                // Lined up under the back row, so the spacing reads as
                // deliberate rather than scattered.
                let x = layout.seatPosition(seat).x + Double(tile) * 1.5
                guard x < layout.width else { continue }
                place(role: "plant", at: ScenePoint(x: x, y: y))
            }
        }

        // A chair at every seat, under whoever is sitting there. The side-view
        // chair the pack ships has its backrest on the left, so a person on it
        // faces right — which is the way every seated character faces, because
        // the pack drew no front- or back-facing sit. Drawn a hair behind the
        // body so the character is on the chair rather than in front of it.
        for seat in 0..<layout.seatCapacity {
            place(role: "chair", at: layout.seatPosition(seat), depthBias: -0.25)
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
        for seat in 0..<layout.seatCapacity {
            let position = layout.deskPosition(seat)
            if place(role: "desk", at: position, depthBias: 0.5) { continue }
            // Nothing in the manifest is called a desk. Draw an obvious
            // placeholder rather than picking a single that looks desk-shaped.
            // [I1]
            let bitmap = SceneBitmaps.placeholderDesk()
            guard let texture = store.texture(bitmap: bitmap, key: "desk:placeholder") else {
                continue
            }
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.size = CGSize(width: bitmap.width, height: bitmap.height)
            node.position = CGPoint(x: position.x, y: position.y)
            node.zPosition = Character.Layer.rowDepth(position.y) + 0.5
            world.addChild(node)
        }
    }

    /// Every furniture node drawn from an identified manifest role. Read-only;
    /// nothing in the scene depends on it, and it exists so a test can check
    /// what was placed rather than trusting that something was.
    var propNodesForTesting: [SKSpriteNode] { propNodes }

    private var propNodes: [SKSpriteNode] = []

    /// Draws one identified prop with its **content box's** bottom-centre on
    /// `point`. Returns false, having drawn nothing, when the manifest has no
    /// such role.
    ///
    /// The anchor comes from the measured box rather than from the canvas,
    /// because the Modern Office singles are 64×96 canvases with the object
    /// dropped in wherever it sat on the source sheet: the desk's baseline is at
    /// row 87 and the plant's at row 75, in canvases of identical size. Any
    /// fixed offset would be right for one file and wrong for the next.
    @discardableResult
    private func place(role: String, at point: ScenePoint, depthBias: CGFloat = 0) -> Bool {
        guard let prop = store.manifest.room.prop(role),
              let texture = store.texture(path: prop.file) else { return false }
        let canvas = store.manifest.room.propCanvas
        let anchor = prop.anchor(inCanvas: canvas)
        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = CGPoint(x: anchor.x, y: anchor.y)
        node.size = CGSize(width: canvas.width, height: canvas.height)
        node.position = CGPoint(x: point.x, y: point.y)
        node.zPosition = Character.Layer.rowDepth(point.y) + depthBias
        world.addChild(node)
        propNodes.append(node)
        return true
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
            case let .report(anchorSeat):
                // Step into the aisle, walk to the anchor, hand over, then
                // leave. The anchor is the parent's seat when
                // `tool_response.agentId` linked them, and seat 0 — the main
                // agent — when it did not. Slots stay globally unique so two
                // reporters in flight never share a delivery spot. [I1]
                var slot = 0
                while reportingSlots.contains(slot) { slot += 1 }
                reportingSlots.insert(slot)
                slotOf[ObjectIdentifier(character)] = slot
                let delivery = layout.deliveryPosition(anchorSeat: anchorSeat, slot: slot)
                character.reportAndDepart(
                    via: approach,
                    to: delivery,
                    facing: layout.deliveryFacing(anchorSeat: anchorSeat),
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

    /// The strip the camera frames, derived from the manifest rather than
    /// written down: the top is the highest pixel a seated character can put on
    /// screen (its badge), the bottom is the lowest (an aisle character's
    /// nameplate). Everything outside it is room, and room is what the wall and
    /// the floor are for.
    var contentBand: (bottom: Double, top: Double) {
        let manifest = store.manifest
        let headTop = manifest.characters.variants.values.map(\.headTopPx).min() ?? 0
        // Character.init parks the badge at `canvasHeight - headTop + 1` above
        // the feet, anchored at its own bottom.
        let badgeTop = Double(manifest.characters.canvas.height - headTop + 1)
            + Double(manifest.badges.canvas.height)
        // The tallest plate the font and the glyph limits can produce, hung
        // 2 px under the feet. Asked of `SceneBitmaps` rather than recomputed
        // here: this used to be `glyphHeight + 6 + 2`, a copy of the plate's
        // own arithmetic that would have silently cropped the moment the plate
        // grew a second row.
        let plateDrop = Double(SceneBitmaps.maximumNameplateHeight + 2)
        return layout.contentBand(
            badgeTopAboveFeet: badgeTop, plateDropBelowFeet: plateDrop)
    }

    /// Where to point the camera vertically.
    ///
    /// The band has to *fit*, but centring it wastes the difference on the
    /// floor: the band's bottom is reserved for a character standing in the
    /// aisle, and most of the time nobody is, so the foreground is a flat field
    /// of floor while the wall above is cropped. So the camera prefers to centre
    /// the **seat row's** own content and is then clamped by however much slack
    /// the scale actually left — which is zero at the tightest fitting scale, so
    /// the preference never costs a clipped nameplate. Nothing about this
    /// depends on who is on screen, so the camera does not jump when someone
    /// steps into the aisle.
    func cameraY(band: (bottom: Double, top: Double), sceneHeight: Double) -> Double {
        let half = sceneHeight / 2
        // The same plate drop, applied at the seat row instead of the aisle.
        let seatedPlateBottom = layout.baselineY - (layout.aisleY - band.bottom)
        let preferred = (seatedPlateBottom + band.top) / 2
        let lowest = band.top - half        // any lower and the badge is cropped
        let highest = band.bottom + half    // any higher and the plate is cropped
        guard lowest <= highest else { return (band.bottom + band.top) / 2 }
        return min(max(preferred, lowest), highest)
    }

    private func applyScale() {
        let seats = charactersBySeat()
        let span = layout.occupiedSpan(seats: seats)
        let contentWidth = max(1, span.maxX - span.minX)
        let band = contentBand
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
        // integer on both axes — no fractional resampling anywhere. [I6]
        let sceneSize = CGSize(
            width: max(1, Double(viewport.width) / Double(scale)),
            height: max(1, Double(viewport.height) / Double(scale)))
        if size != sceneSize { size = sceneSize }

        let centreX = (span.minX + span.maxX) / 2
        camera_.position = CGPoint(
            x: (centreX).rounded(),
            y: cameraY(band: band, sceneHeight: sceneSize.height).rounded())
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
