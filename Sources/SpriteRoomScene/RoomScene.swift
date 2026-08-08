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

    /// The scale the director asked for, from population. The viewport can
    /// only ever push this *down* the ladder, never up. [I6]
    private var preferredScale = 3
    private var effectiveScale = 3
    private var viewport = CGSize(width: 960, height: 540)

    /// - Parameter themeID: which `themes.sets.<id>` dresses the room. `nil`
    ///   draws `manifest.room`, which is the room this app has always drawn and
    ///   which §14a establishes *is* the resolved default theme.
    ///
    /// **No theme name and no filename appears in this file, or anywhere else
    /// in `SpriteRoomScene`.** The id arrives from the app, having come from the
    /// manifest or from the user's stored pick; the bindings behind it are read
    /// through `TextureStore.room`. A test asserts the absence mechanically over
    /// the source, because it is the kind of rule that decays quietly.
    /// [ADR-002 §8 item 5]
    public init(
        manifest: Manifest, themeID: String? = nil, layout: RoomLayout = RoomLayout()
    ) {
        self.layout = layout
        self.store = TextureStore(manifest: manifest, themeID: themeID)
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

    /// The four placement slots a theme fills, and the keys they are looked up
    /// by in `props.roles`.
    ///
    /// **These are slot names, not object nouns, and the distinction is the
    /// whole theme mechanism.** The scene places a work surface at each seat, a
    /// seat, a standing object on the back wall, and a repeated accent along the
    /// back wall and the walkway. They are spelled `desk`, `chair`, `board` and
    /// `plant` because those are the Office room's words and the Office room is
    /// the manifest's default theme — so those words became the interface. A
    /// theme filling `plant` with a stage curtain or a console terminal is the
    /// slot doing its job, not a mislabelling.
    ///
    /// They are constants rather than literals at four call sites so that the
    /// vocabulary is in one place when someone renames it — which
    /// `04-ART-DIRECTION.md` says is the right change and is not this one.
    /// A role name is not a filename and not a theme name: it is the key the
    /// manifest and the scene agree on, exactly as `badges.map`'s keys are.
    nonisolated static let surfaceRole = "desk"
    nonisolated static let seatRole = "chair"
    nonisolated static let backdropRole = "board"
    nonisolated static let accentRole = "plant"

    /// How many times the room has been built. **One, for the life of a scene.**
    ///
    /// §6 rule 1 is that the room does not change with activity, at all, and
    /// this is that rule made mechanical rather than argued: a test replays
    /// every fixture and asserts this never leaves 1, and that no prop node was
    /// replaced by another with the same picture. A theme change is a new scene
    /// — §6 rule 4 — so it does not increment this one, it starts another.
    public private(set) var roomBuildCount = 0

    private func buildRoom() {
        roomBuildCount += 1
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
            let role = seat.isMultiple(of: 2) ? Self.backdropRole : Self.accentRole
            let x = Double(layout.seatColumn(seat) * tile + tile / 2) + Double(tile) * 1.5
            guard x < layout.width else { continue }
            place(role: role, at: ScenePoint(x: x, y: backRowY))
        }

        // **There is no foreground row, and the rule that replaced it is
        // stronger than the one it replaced.**
        //
        // M5 put a row of plants in front of the walkway and kept them honest
        // geometrically: strictly below the content band, so they fell out of
        // frame at the tightest fitting scale and appeared only as the camera
        // pulled back. That answered I7's "remove the detail that competes with
        // the characters" without anyone having to exercise taste — at `3x`,
        // where characters are biggest and the frame is tightest, the decoration
        // was not on screen at all.
        //
        // **The wide camera retired that protection.** `1x` is the only scale a
        // normal room uses now, so "out of frame at the tightest scale" stopped
        // meaning anything: the row was permanently on screen, seven identical
        // plants across the bottom of every glance, and a permanently-visible
        // repeated tile is a bigger I7 risk than an occasionally-visible one.
        //
        // The replacement is a rule about *depth* rather than about zoom, which
        // is why it survives a change of camera policy:
        //
        //   **Nothing decorative is drawn nearer the camera than the seat row.**
        //
        // Everything in front of the desks is now choreography — the aisle and
        // the delivery rows, where arrivals, departures and reports happen — so
        // the foreground is not empty floor any more and does not need filling.
        // Nothing the room draws can ever be between the viewer and a character,
        // at any scale and any population. `theRoomDrawsNoDecorationInFrontOfThe
        // Characters` asserts it over every theme.

        // A chair at every seat, under whoever is sitting there. The side-view
        // chair the pack ships has its backrest on the left, so a person on it
        // faces right — which is the way every seated character faces, because
        // the pack drew no front- or back-facing sit. Drawn a hair behind the
        // body so the character is on the chair rather than in front of it.
        for seat in 0..<layout.seatCapacity {
            place(role: Self.seatRole, at: layout.seatPosition(seat), depthBias: -0.25)
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
            if place(role: Self.surfaceRole, at: position, depthBias: 0.5) { continue }
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
        guard let prop = store.room.prop(role),
              let texture = store.texture(path: prop.file) else { return false }
        let canvas = store.room.propCanvas
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

        case let .deliverReport(agent, anchorSeat):
            guard let character = characters[agent], let seat = seatOf[agent],
                  // Nobody walks over to themselves. The anchor resolves to the
                  // reporter's own seat only for the main agent, which has no
                  // `SubagentStop` and so never reports — this is the guard that
                  // says so rather than a comment claiming it. [I1]
                  seat != anchorSeat else { break }
            // Step out of the seat into the aisle, straight down the reporter's
            // **own column** onto its **own ring's delivery row**, along that row
            // to the anchor, hand over, and back the same way.
            //
            // **The transit used to be the room's one unguarded window.** A
            // reporter walking the aisle passed every station between its desk
            // and its anchor's, and a station is 96 px from the next while the
            // widest plate is 65 — so it was within a plate width of *some*
            // station for most of the walk, and if that station's occupant
            // stepped into the aisle the two plates touched. Widening the seat
            // pitch does not close that: two characters walking one line in
            // opposite directions cross at zero separation whatever the pitch
            // is, and six agents at five tiles do not fit the panel anyway [S4].
            //
            // Giving each ring its own row closes it structurally instead. See
            // `RoomLayout.deliveryRowY(ring:)` for the three-line proof and
            // `theAisleIsGuaranteedClearAtTheStationsAndNotBetweenThem` for the
            // arithmetic that holds it.
            let side = layout.deliverySide(anchorSeat: anchorSeat, reporterSeat: seat)
            character.reportAndReturn(
                out: layout.deliveryRoute(anchorSeat: anchorSeat, reporterSeat: seat),
                facing: layout.deliveryFacing(side: side),
                home: layout.homeRoute(forSeat: seat),
                onFinished: {})

        case let .exitCharacter(agent, style):
            guard let character = characters.removeValue(forKey: agent) else { break }
            let seat = seatOf.removeValue(forKey: agent)
            // **Every exit is a walk up the character's own column and out
            // through the back of the room.** See
            // `RoomLayout.upstageExit(forSeat:)` for why: a lateral corridor
            // that reaches the frame edge passes through every column outside
            // it, and a column is where every other character steps between the
            // desk row, the aisle and its delivery row. The whole cast can leave
            // in one frame — `SessionEnd` does exactly that — and seven leavers
            // going straight back stay a seat pitch apart the entire way, which
            // is a stronger statement than the convoy argument this replaces
            // and needs no argument about relative speeds at all.
            let exit = seat.map(layout.upstageExit(forSeat:))
                ?? layout.upstageExit(fromX: Double(character.position.x))
            switch style {
            case let .report(anchorSeat) where seat != nil && seat != anchorSeat:
                let reporterSeat = seat!
                let side = layout.deliverySide(
                    anchorSeat: anchorSeat, reporterSeat: reporterSeat)
                character.reportAndDepart(
                    out: layout.deliveryRoute(
                        anchorSeat: anchorSeat, reporterSeat: reporterSeat),
                    facing: layout.deliveryFacing(side: side),
                    home: layout.homeRoute(forSeat: reporterSeat),
                    thenExitAt: exit
                ) { [weak self, weak character] in self?.retire(character) }
            case .report, .walkOff:
                // No seat, or a self-report: nothing to walk to, so it just
                // leaves. A character caught **on a delivery row** — mid-report
                // when the session ended — comes back up its own column first,
                // because the only clear way off a delivery row is the column it
                // came down; cutting the corner would drag its plate diagonally
                // across every row in between.
                character.departOffScreen(
                    via: seat.map {
                        layout.homeRoute(
                            forSeat: $0, fromY: Double(character.position.y))
                    } ?? [],
                    to: exit
                ) { [weak self, weak character] in self?.retire(character) }
            }

        case let .setScale(scale):
            preferredScale = scale
        }
    }

    /// **There is nothing left to claim.** Where a reporter stands is a pure
    /// function of its own seat — its ring picks the row, its half of the room
    /// picks the side — so two reporters cannot be sent to the same spot and
    /// there is no reservation to leak, no order to get wrong, and no state that
    /// has to survive a re-entrant second report.
    ///
    /// The bookkeeping this replaces held a set of sideways slots claimed
    /// lowest-free. That was not seat-ordered, so the farther of two same-side
    /// reporters could take the nearer slot and then walk home through the
    /// nearer one's station — a real collision, and the kind that only shows up
    /// when two subagents stop within a second of each other.
    private func retire(_ character: Character?) {
        guard let character else { return }
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
        return layout.contentBand(
            badgeTopAboveFeet: badgeTop, plateDropBelowFeet: seatedPlateDrop)
    }

    /// How far the tallest plate hangs below a character's feet. One number, one
    /// place: the band's floor and the camera's bias are both measured from it.
    private var seatedPlateDrop: Double { Double(SceneBitmaps.maximumNameplateHeight + 2) }

    /// Where to point the camera vertically.
    ///
    /// The band has to *fit*, but centring it wastes the difference on the
    /// floor: the band's bottom is reserved for a character on the outermost
    /// delivery row, and most of the time nobody is on any of them, so the
    /// foreground is a flat field of floor while the wall above is cropped. So
    /// the camera prefers to centre the **seat row's** own content and is then
    /// clamped by however much slack the scale actually left — which is zero at
    /// the tightest fitting scale, so the preference never costs a clipped
    /// nameplate. Nothing about this depends on who is on screen, so the camera
    /// does not jump when someone steps out of a chair.
    ///
    /// **The preference is measured from the seated plate, not inferred from the
    /// band.** It used to reconstruct the seated plate's bottom by subtracting
    /// the band's own depth from the seat row, which is the same number only
    /// while the band's bottom is exactly one plate below the aisle. The delivery
    /// rows made that false, and the bias silently weakened by the depth of the
    /// walkway — the frame drifted down over three tiles of empty floor with no
    /// test able to see it, because the arithmetic still agreed with itself.
    func cameraY(band: (bottom: Double, top: Double), sceneHeight: Double) -> Double {
        let half = sceneHeight / 2
        let seatedPlateBottom = layout.baselineY - seatedPlateDrop
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
