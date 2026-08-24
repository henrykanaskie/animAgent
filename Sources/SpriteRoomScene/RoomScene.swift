import Foundation
import SpriteKit
import SpriteRoomCore

/// The room. Applies `SpriteIntent`s to nodes and nothing else: every policy
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
    /// The last body state `setBody` handed each character: the director's own
    /// word on what the data says it is doing.
    ///
    /// Only the report beat reads it, and only to hand the body back at the end
    /// of the beat facing the desk again. It is remembered rather than asked of
    /// the character because `Character.restingState` is deliberately private:
    /// the body is set from one place and this is that place's memory of it, not
    /// a second opinion.
    private var restingBody: [AgentRef: BodyState] = [:]

    /// **Who is walking along the delivery row.** The one piece of scheduling in
    /// this scene, and it schedules nothing: it decides which of two truthful
    /// report beats a reporter plays, never whether or when one plays at all.
    /// See `RoomLayout.deliveryPosition(anchorSeat:reporterSeat:)` and
    /// `DeliveryFloor`.
    private var deliveryFloor: DeliveryFloor
    /// Who holds each live claim, so it can be given back the moment that
    /// character stops walking or leaves. Keyed by the claim's own id.
    ///
    /// The *character* rather than the agent, because a leaver is taken out of
    /// `characters` at the top of its exit and is still walking the row for
    /// several seconds after that: a report and a `SessionEnd` in one frame is
    /// exactly the case `.report` exists for.
    private var deliveryClaimant: [Int: (character: Character, seat: Int)] = [:]
    /// One id per beat, never reused. See `DeliveryFloor` for why the seat is
    /// not the key.
    private var nextDeliveryBeatID = 0

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
        let store = TextureStore(manifest: manifest, themeID: themeID)
        self.store = store
        // **The plan is the theme's, so it is resolved here and nowhere else.**
        // A caller hands in the route geometry: the seat pitch, the capacity,
        // the tile, and the manifest hands in what that geometry is drawn on.
        // Doing it in this order is what keeps a theme id out of every call site
        // and out of `RoomLayout`, which has no access to a manifest and never
        // reads a PNG. [ADR-007 §3, ADR-002 §8 item 5]
        self.layout = layout.adopting(plan: store.room.plan)
        // The clearance is the plate's, measured, not a constant: see
        // `RoomLayout.deliveryClearance(plateWidth:plateHeight:tile:)`.
        self.deliveryFloor = DeliveryFloor(
            clearance: RoomLayout.deliveryClearance(
                plateWidth: SceneBitmaps.maximumNameplateWidth,
                plateHeight: SceneBitmaps.maximumNameplateHeight,
                tile: layout.tile))
        super.init(size: CGSize(width: 320, height: 180))
        scaleMode = .fill
        // Slightly darker than the room's value floor so the room never blends
        // into the void behind it.
        backgroundColor = Self.voidColour
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
    /// an exit walk. Tests that check the *picture* need the leavers too,
    /// the report walk is exactly when two characters share the frame.
    public var charactersOnScreen: [Character] { animated }

    /// Which seat a live character holds, for tests that have to ask the scene
    /// where it put somebody rather than re-deriving it from the director.
    func seatOfForTesting(_ agent: AgentRef) -> Int? { seatOf[agent] }

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
    /// the manifest's default theme, so those words became the interface. A
    /// theme filling `plant` with a stage curtain or a console terminal is the
    /// slot doing its job, not a mislabelling.
    ///
    /// They are constants rather than literals at four call sites so that the
    /// vocabulary is in one place when someone renames it, which
    /// `04-ART-DIRECTION.md` says is the right change and is not this one.
    /// A role name is not a filename and not a theme name: it is the key the
    /// manifest and the scene agree on, exactly as `badges.map`'s keys are.
    nonisolated static let surfaceRole = "desk"
    /// The side-view chair. **A seat's chair is now the facing's, not this
    /// constant's**: `RoomLayout.SeatFacing.seatRole` answers it, and this is
    /// what that returns for a side-on seat. Kept as the name of the slot for
    /// the same reason the other three are constants. [ADR-008]
    nonisolated static let seatRole = "chair"
    /// The back view of the same chair. **No seat draws it**: see
    /// `RoomLayout.SeatFacing.seatRole`, which measures why, and the name is
    /// kept because `seatMetrics` still reads the role's own `content_box`: the
    /// height that does not fit is what the refusal is derived from, so it has to
    /// come from the manifest rather than from a number written down here.
    nonisolated static let backSeatRole = "chair_back"
    nonisolated static let backdropRole = "board"
    nonisolated static let accentRole = "plant"

    /// **The screen rig on an away-facing pod's desktop.** [ADR-009]
    ///
    /// Optional in a way the four above are not: a theme that binds no `monitor`
    /// has no pod, and its seats are drawn exactly as they were before this role
    /// existed. Five of the six shipped themes are in that case.
    nonisolated static let monitorRole = "monitor"
    /// **The orientation-neutral object on a camera-facing pod's desktop**: a
    /// paper stack, which reads the same from either side where a screen does
    /// not. Theme furniture: it says nothing about any agent [I1], and it is not
    /// ADR-006's work-kind slot, which a camera-facing seat still does not carry.
    nonisolated static let deskKitRole = "desk_kit"

    /// **The measured art the seat furniture is placed against.** [ADR-008]
    ///
    /// `RoomLayout` reads no manifest and opens no PNG, so a turned seat's three
    /// numbers are gathered here and handed to it: the desk's ink height decides
    /// how far downstage a camera-facing desk stands, the back chair's decides
    /// how far downstage an away-facing chair stands, and the wardrobe's ink top
    /// is the floor under the second of those.
    ///
    /// Per **desk** rather than per theme, because a station may bind its own
    /// desk and an object standing on that desk has to be placed at *its*
    /// surface: the same reason `stationDesks` exists.
    func seatMetrics(desk: Manifest.PropRole? = nil) -> RoomLayout.SeatMetrics {
        let desk = desk ?? store.room.prop(Self.surfaceRole)
        let monitor = store.room.prop(Self.monitorRole)
        return RoomLayout.SeatMetrics(
            deskInkHeight: Double(
                desk?.contentBox.height ?? SceneBitmaps.placeholderDesk().height),
            chairInkHeight: Double(
                store.room.prop(Self.backSeatRole)?.contentBox.height ?? 0),
            costumeTopAboveFeet: Double(store.manifest.characters.costumes.inkTopAboveFeet),
            deskInkWidth: Double(
                desk?.contentBox.width ?? SceneBitmaps.placeholderDesk().width),
            monitorInkWidth: Double(monitor?.contentBox.width ?? 0),
            monitorInkHeight: Double(monitor?.contentBox.height ?? 0))
    }

    /// **Where the two decoration bands stand**, as `(role, bottom-centre)`, in
    /// the order `buildRoom` places them.
    ///
    /// A pure function of the layout, and the only copy of this arithmetic: the
    /// overflow plate's clearance is asserted against *these* points rather than
    /// against a transcription of them, and a transcription checked against a
    /// transcription is not a check: `scripts/preview-theme.py` learned that at
    /// M6e over a foreground row that no longer existed.
    nonisolated static func decorationPlacements(layout: RoomLayout)
    -> [(role: String, point: ScenePoint)] {
        let backdropRowY = layout.wallBaseY
        let accentRowY = layout.backSeatRowY + Double(layout.tile)
        return layout.decorationColumns.map { column in
            (column.isBackdrop ? backdropRole : accentRole,
             ScenePoint(x: column.x, y: column.isBackdrop ? backdropRowY : accentRowY))
        }
    }

    /// **The plan's hand-placed dressing, resolved against the theme's own
    /// scenery list**, in declaration order, which is draw order.
    ///
    /// One function so that the three readers agree by construction rather than
    /// by transcription: `buildRoom` draws it, `decorationTopY` measures it for
    /// the camera, and the contract test checks it. A placement whose index is
    /// past the end of the list resolves to nothing and is skipped here; it is
    /// `RoomPlan.dressingViolations` that turns that silence into a red test,
    /// exactly as `routeViolations` does for a space with no surface.
    nonisolated static func dressingPlacements(store: TextureStore)
    -> [(prop: Manifest.PropRole, point: ScenePoint)] {
        store.room.plan.dressing.compactMap { item in
            guard let prop = store.room.piece(item.piece) else { return nil }
            return (prop, ScenePoint(x: Double(item.x), y: Double(item.y)))
        }
    }

    /// How many times the room has been built. **One, for the life of a scene.**
    ///
    /// §6 rule 1 is that the room does not change with activity, at all, and
    /// this is that rule made mechanical rather than argued: a test replays
    /// every fixture and asserts this never leaves 1, and that no prop node was
    /// replaced by another with the same picture. A theme change is a new scene
    /// (§6 rule 4) so it does not increment this one, it starts another.
    public private(set) var roomBuildCount = 0

    private func buildRoom() {
        roomBuildCount += 1
        let tiles = store.roomTileChoice()
        let tile = layout.tile
        let floorTexture = store.texture(path: tiles.floor)
        let wallTexture = store.texture(path: tiles.wall)

        if layout.plan.isEmpty {
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
        } else {
            buildPlan(layout.plan)
        }

        // Furniture upstage of the seats. Deterministic positions, one per seat
        // pitch, so the room does not rearrange itself as agents come and go.
        //
        // **Two bands, and the roles alternate along x rather than by seat
        // index.** Both of those are corrections to one strip of decoration that
        // sat on one row at `baselineY + 1` tile, and both were visible in the
        // shipped panel:
        //
        // - *By seat index* meant by **side**. Seats fill outward in pairs, so
        //   even seats are the entire left half of the room and odd seats the
        //   entire right half, and a role chosen on `seat % 2` put all four
        //   backdrops on the left and all three accents on the right. The room
        //   read as two different rooms stitched at the centre line. Sorting the
        //   positions and alternating along **x** gives the same four and three
        //, so the motion budget is unchanged, which is not an accident but
        //   the constraint this placement was designed against [ADR-002 §14b],
        //   spread across the whole width.
        // - *One row* is what the maintainer saw as "the wall furniture sits in
        //   one strip". The backdrops now stand **against the wall**, which is
        //   where a backdrop belongs and which is what puts something in the
        //   band of the panel that was flat wall; the accents stand a tile
        //   behind the back seat row. Alternating the two along x makes the
        //   depth zigzag, so the upstage half of the room has a near edge and a
        //   far edge rather than a single line.
        //
        // I7's standing instruction: a background detail competes with the
        // characters at exactly the zoom where they are hardest to read: is
        // still what keeps this thin: two kinds of object, seven of them, both
        // through the same desaturating import pass as the floor, and every one
        // of them upstage of both seat rows.
        // **A hand-placed room places its backdrops and accents too.** They are
        // the oldest lattice in the file: a board on the wall line at every
        // even column, a plant a tile behind the back row at every odd one, and
        // leaving them running under an authored composition would keep two of
        // the four stripes the composition exists to break.
        if store.room.plan.dressing.isEmpty {
            for placement in Self.decorationPlacements(layout: layout) {
                place(role: placement.role, at: placement.point)
            }
        }

        // **The scenery: everything the four roles above are not.** [M8 Phase 2b]
        //
        // The maintainer looked at the shipped room and asked for the density of
        // `scripts/compose-scene.py`'s composed scenes: 88 props against this
        // room's four bound roles and roughly 335 processed singles going
        // unused. This is that, and the whole of the mechanism is: the manifest
        // says *what* and *which depth band*, `RoomLayout.sceneryAnchors(_:)`
        // says *where*, and the two never negotiate. Swapping the art is a
        // manifest change with no code in it, which is the standing rule for
        // every asset in this project.
        //
        // **Three things about it are not composition, and each has a test.**
        //
        // - It is drawn once, here, in `buildRoom`, from the theme alone. There
        //   is no path from a `WorldDelta` to any of it and there must not be:
        //   a prop that changed because an agent did something is the fiction
        //   ADR-002 §6 rule 1 exists to prevent. It goes in `propNodes` with the
        //   rest of the furniture, so the "zero prop-node rebuilds across a
        //   whole fixture replay" assertion already covers it.
        // - Nothing stands in a seat column. Every route in this room is either
        //   straight up a character's own column or lateral on `deliveryRowY`,
        //   so the columns and that one row are the two things a prop may never
        //   touch. `sceneryColumns` is the gaps between them, and the `wall`
        //   band is the one exception: it hangs two tiles up the wall face,
        //   above the line where a leaver's feet stop.
        // - Nothing is nearer the camera than the seat row, which is the rule
        //   that replaced M5's foreground row and is stated again below.
        //
        // Entries are assigned to anchors in declaration order and repeat to
        // fill the band, so a theme that owns three good props gets a full band
        // of them rather than four bare anchors. That is the pack's own habit,
        // `Office_Design_2` repeats one plant in three corners, and it is what
        // keeps a thin theme honest instead of padded with props nobody looked
        // at.
        // **A plan may place its own dressing by hand, and then the bands do not
        // run at all.**
        //
        // The bands put every prop on one of four depths and one of eight
        // columns, and the maintainer's word for the result was that the
        // furniture "sits in one strip": four strips, in fact, which is what a
        // lattice looks like once it is filled. `compose-scene.py`'s engineering
        // office is the same floor with 45 objects on it and no two of them
        // sharing a row: things cluster, stack a lane three deep, and leave the
        // next lane empty. That is authored composition, and it cannot be
        // derived from a band name, so a plan that wants it states every point.
        //
        // It is all-or-nothing per theme rather than additive. A hand-placed
        // room with the bands still running underneath is a room with 20 props
        // on a lattice *and* 45 off it, and the lattice would still read.
        // **`place(roomProp:)`, not `place(prop:)`**: the first is the room's
        // own placement primitive and it does three things this loop was doing
        // two of: the node lists, and **starting the prop's idle animation**.
        // Going through the raw primitive meant a hand-placed theme could not
        // have an animated prop at all, silently: the manifest would still stamp
        // the role `animation` and nothing would ever play it. It surfaced as
        // `library` losing its pendulum clock the moment that theme was composed
        // by hand, which is a room quietly getting stiller because of where its
        // furniture is listed.
        for placement in Self.dressingPlacements(store: store) {
            guard let node = place(roomProp: placement.prop, at: placement.point)
            else { continue }
            sceneryNodes.append(node)
        }
        if store.room.plan.dressing.isEmpty {
            for band in RoomLayout.SceneryBand.allCases {
                let props = store.room.scenery(band)
                guard !props.isEmpty else { continue }
                for (index, point) in layout.sceneryAnchors(band).enumerated() {
                    let prop = props[index % props.count]
                    guard let node = place(prop: prop, at: point, depthBias: 0) else { continue }
                    propNodes.append(node)
                    propPaths.append(prop.file)
                    sceneryNodes.append(node)
                }
            }
        }

        // **There is no foreground row, and the rule that replaced it is
        // stronger than the one it replaced.**
        //
        // M5 put a row of plants in front of the walkway and kept them honest
        // geometrically: strictly below the content band, so they fell out of
        // frame at the tightest fitting scale and appeared only as the camera
        // pulled back. That answered I7's "remove the detail that competes with
        // the characters" without anyone having to exercise taste: at `3x`,
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
        // Everything in front of the desks is now choreography: the aisle and
        // the delivery rows, where arrivals, departures and reports happen, so
        // the foreground is not empty floor any more and does not need filling.
        // Nothing the room draws can ever be between the viewer and a character,
        // at any scale and any population. `theRoomDrawsNoDecorationInFrontOfThe
        // Characters` asserts it over every theme.

        // **A chair at every seat that has one, in the view its facing needs.**
        // [ADR-008]
        //
        // A side-on seat takes the side-view chair, whose backrest is on the
        // left, so a person on it faces right, which is the way a side-on
        // seated character faces, because the pack drew no front- or back-facing
        // sit. It is drawn a hair behind the body so the character is on the
        // chair rather than in front of it.
        //
        // An away-facing seat takes the **back view** of the same chair, a whole
        // standoff downstage of the body rather than under it, because that is
        // what makes an `idle_up` figure read as sitting in it. It needs no
        // depth bias: it is genuinely nearer the camera than its occupant, so
        // `rowDepth` puts it in front with nothing to tune.
        //
        // A camera-facing seat takes **none**. The body covers a chair entirely
        // at that angle, which is why the pack's own `Office_Design_2.gif` draws
        // no chair at any camera-facing desk in its own room.
        let metrics = seatMetrics()
        for seat in 0..<layout.seatCapacity {
            guard let role = layout.seatFacing(seat).seatRole,
                  let point = layout.chairPosition(seat, metrics: metrics) else { continue }
            let bias = layout.seatFacing(seat) == .sideOn ? Self.seatDepthBias : 0
            guard let node = place(role: role, at: point, depthBias: bias),
                  let path = store.room.prop(role)?.file else { continue }
            emptySeatFurniture[seat, default: []].append(
                SeatFurniture(node: node, path: path))
        }

        // A desk at every seat, occupied or not: an office has empty desks,
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
        // walking past is always in front of the desks, which is why the
        // walkway exists.
        // **The desk's depth is measured, not fixed.** See `surfaceDepthBias`:
        // a desk taller than the shortest head goes behind the body instead of
        // in front of it, because two shipped themes bind one that would
        // otherwise cover every face in the room.
        //
        // **All of the paragraph above is the side-on case.** At a turned seat
        // the desk is not on the character's row at all: it stands downstage of
        // a camera-facing occupant and upstage of an away-facing one, so
        // `rowDepth` alone sorts it correctly and the bias is zero. The tie
        // these constants break exists only where a desk and its occupant share
        // a row. [ADR-008]
        for seat in 0..<layout.seatCapacity {
            let position = layout.deskPosition(seat, metrics: metrics)
            let surfaceBias = layout.seatFacing(seat) == .sideOn
                ? surfaceDepthBias(for: store.room.prop(Self.surfaceRole)) : 0
            if let node = place(
                role: Self.surfaceRole, at: position, depthBias: surfaceBias),
               let path = store.room.prop(Self.surfaceRole)?.file {
                emptySeatFurniture[seat, default: []].append(
                    SeatFurniture(node: node, path: path))
                continue
            }
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
            // The placeholder is 26 px tall, so it is always the in-front case
            // where the tie has to be broken at all.
            node.zPosition = Character.Layer.rowDepth(position.y)
                + (layout.seatFacing(seat) == .sideOn ? Self.surfaceInFrontBias : 0)
            world.addChild(node)
            // The placeholder has no manifest path, and saying so is the point:
            // nothing in the manifest is called a desk here. It is still a piece
            // of this seat's furniture, so a station still hides it.
            emptySeatFurniture[seat, default: []].append(
                SeatFurniture(node: node, path: ""))
        }

        // **The kit on the desktop, which is what makes a slab read as a
        // workstation rather than a bench.** [ADR-009]
        //
        // A screen rig at every away-facing seat and a paper stack at every
        // camera-facing one: the split `scripts/compose-scene.py`'s `desk_pod`
        // makes, for that file's reason: there is no rear view of a monitor
        // anywhere in the 12,279-prop catalogue, so a screen facing the camera is
        // being looked at from below by the person sitting behind it.
        //
        // Both are **theme furniture**. They are drawn at every seat whether
        // anyone is sitting there or not, they never change, and no path from a
        // `WorldDelta` reaches either [I1, ADR-002 §6 rule 1]. What says *what
        // the work is* is still ADR-006's object, and it stands in the pod's
        // other slot.
        for seat in 0..<layout.seatCapacity {
            for piece in podFurniture(seat: seat, metrics: metrics) {
                guard let node = place(
                    roomProp: piece.prop, at: piece.point,
                    depthBias: piece.depthBias) else { continue }
                emptySeatFurniture[seat, default: []].append(
                    SeatFurniture(node: node, path: piece.prop.file))
            }
        }
    }

    /// **One piece of a pod's desktop**: which role it came from, the resolved
    /// prop, which carries both the file this seat draws and the ink box it is
    /// placed against, and where it stands.
    struct PodPiece {
        let role: String
        let prop: Manifest.PropRole
        let point: ScenePoint
        let depthBias: CGFloat
    }

    /// **Everything standing on one seat's desktop that is furniture.** Empty for
    /// a theme that is not a pod and for a seat whose facing carries nothing.
    /// [ADR-009]
    ///
    /// One list, read by `buildRoom` for the empty desk and by `placeStation` for
    /// an occupied one, so the two cannot draw different desktops: the same
    /// reason `decorationPlacements` is a function rather than two loops.
    ///
    /// ## Which picture, and what may choose it
    ///
    /// A role may declare `variants`, and **the seat is the whole of the key**:
    /// entry `(slot.rawValue + seat) % count`. Not the agent, not the tool, not
    /// the open-call count, not anything hashed out of a payload. A seat is fixed
    /// for the life of a scene, so this is evaluated at room-build time and never
    /// again: the room is still built once, still never rebuilt, and a prop that
    /// changed because an agent did something would be exactly the fiction
    /// ADR-002 §6 rule 1 and I1 forbid. The rotation is by slot as well as by
    /// seat because a camera-facing pod carries **all four** objects at once;
    /// what the seat changes is which object stands where, not how many there
    /// are.
    ///
    /// ## Why the prop is resolved here rather than by name at the call site
    ///
    /// `content_box` is declared per role, and the office `desk_kit` stock is
    /// four singles cut from four source sheets at four unrelated offsets in the
    /// 64×96 canvas. So a variant carries its own **measured** box: see
    /// `TextureStore.inkBox(path:)`, and that box decides the lift, which is
    /// what makes "it cannot cover a face" true of each object at its own ink
    /// height rather than of the one object that used to stand here.
    ///
    /// ## The bias
    ///
    /// **`lift + deskObjectInFrontStep × (depth rank + 1)`, and the lift has to
    /// be in it.** `place` sorts on the point it is given, and a prop lifted onto
    /// a desktop is `lift` px *above* the desk's floor point, which sorts it
    /// `lift` px **behind** the desk, so the desk paints over everything below
    /// its own back edge and what survives is a screen apparently hovering with
    /// no base. That is `compose-scene.py`'s `on_desk` docstring, which records
    /// the symptom being on screen for two renders before anyone read it
    /// correctly. Adding the lift back puts the prop on its desk's own row and
    /// the step puts it one notch in front: the same construction the ADR-006
    /// object already uses.
    ///
    /// The **rank** is what the second row needs: adding the lift back collapses
    /// every desktop object onto one z, so a front-row object drawn over the
    /// back-row one it overlaps would be relying on child order. One extra step
    /// per rank is 0.25, four orders of magnitude below the gap to any other
    /// layer.
    func podFurniture(seat: Int, metrics: RoomLayout.SeatMetrics) -> [PodPiece] {
        var pieces: [PodPiece] = []
        if let rig = store.room.prop(Self.monitorRole) {
            // The rig's lift is the pod's own: a screen is *meant* to clear the
            // desk's back edge, by `monitorScreenClearance`, and it stands at a
            // facing with no face in front of it to cover.
            let lift = layout.deskTopLift(
                surfaceHeightAboveFloor: metrics.deskInkHeight, metrics: metrics)
            // **Both slots**, because the `monitor` role carries its own desk
            // surface and one of them covers half a slab: see
            // `RoomLayout.monitorPosition(_:slot:metrics:)` for the picture that
            // produced and for what ADR-006 keeps. The two never overlap: 32 px of
            // ink each on a 64 px slab, so the tie their equal bias leaves is
            // between disjoint rectangles.
            for slot in RoomLayout.PodRigSlot.allCases {
                guard let point = layout.monitorPosition(
                    seat, slot: slot, metrics: metrics) else { continue }
                // **A different picture in each slot, keyed by slot and seat**,
                // the same construction the kit uses, and `desk_pod`'s own
                // `LIT_RIGS[(3v)%4]` beside `LIT_RIGS[(3v+1)%4]`. Two identical
                // rigs side by side read as one sprite tiled, which is the thing
                // a variant list exists to avoid.
                pieces.append(PodPiece(
                    role: Self.monitorRole, prop: variantProp(rig, seat + slot.rawValue),
                    point: point,
                    depthBias: CGFloat(lift) + Self.deskObjectInFrontStep))
            }
        }
        if let kit = store.room.prop(Self.deskKitRole) {
            for slot in RoomLayout.PodKitSlot.drawOrder {
                let prop = variantProp(kit, slot.rawValue + seat)
                let height = Double(prop.contentBox.height)
                guard let lift = layout.deskKitLift(
                        inkHeight: height, slot: slot, metrics: metrics),
                      let point = layout.deskKitPosition(
                        seat, slot: slot, inkHeight: height, metrics: metrics)
                else { continue }
                pieces.append(PodPiece(
                    role: Self.deskKitRole, prop: prop, point: point,
                    depthBias: CGFloat(lift)
                        + Self.deskObjectInFrontStep * CGFloat(slot.depthRank + 1)))
            }
        }
        return pieces
    }

    /// A role drawn with entry `index` of its `variants`, carrying that file's
    /// own ink box where the art can be measured and the role's declared box
    /// where it cannot. Entry 0 is the role itself, declared box included.
    private func variantProp(_ prop: Manifest.PropRole, _ index: Int) -> Manifest.PropRole {
        let picked = prop.variant(index)
        guard picked.file != prop.file else { return prop }
        return prop.variant(index, box: store.inkBox(path: picked.file))
    }

    // MARK: The floor plan [ADR-007]

    /// **Outside the room.** The scene's background and, under a plan, the field
    /// past its edge: one constant, so the two can never disagree and a plan's
    /// edge is always an edge against the same tone.
    nonisolated static let voidColour = SKColor(red: 0.14, green: 0.13, blue: 0.17, alpha: 1)

    /// Every node the plan painted, in draw order. Read-only, and it exists for
    /// the same reason `propArtForTesting` does: node identity says a tile was
    /// *placed* and says nothing about which picture, and the failure this has
    /// to catch: a plan that decoded to nothing and fell back to one flat floor
    ///: produces a perfectly correct set of nodes.
    private var planNodes: [(node: SKSpriteNode, what: String)] = []

    var planArtForTesting: [String] { planNodes.map(\.what) }
    var planNodesForTesting: [SKSpriteNode] { planNodes.map(\.node) }

    /// **Draws the plan: floors, wall bands, doorways, jambs, partitions.**
    ///
    /// The order is `scripts/compose-scene.py`'s `draw_plan`, step for step, and
    /// the order is the whole of the correctness:
    ///
    /// 1. **Floors first, over each space's whole rect**: including the two
    ///    rows its wall band will cover. So a doorway, which is simply a column
    ///    the band skips, already has floor under it and needs nothing drawn in
    ///    it. An earlier version of the reference script patched the gap with the
    ///    floor of the space *beyond*, which stacked two materials and left a
    ///    seam across every doorway that read as a step.
    /// 2. **The band, per column, cap over body**, skipping doorway columns.
    ///    Two tiles, because that is what the pack draws: 12 px of floor-plan
    ///    line and 20 px of face in the cap, 30 px more face and a 2 px baseboard
    ///    in the body. Everything above the topmost band is left unpainted, and
    ///    what shows there is the scene's background: the *outside* of the plan,
    ///    which is what makes the room read as a building seen from above rather
    ///    than as a stage with an infinite backcloth. That single change gives
    ///    the room a top edge, which it has never had.
    /// 3. **The contact shadow the band casts on its own floor.** The pack's
    ///    artists paint it in; without it the band floats.
    /// 4. **Jambs**, because a doorway cut through a 64 px band leaves two raw
    ///    edges.
    /// 5. **Partitions**, last, so a vertical line closes over the bands it
    ///    meets without any junction piece having to exist.
    private func buildPlan(_ plan: RoomPlan) {
        let tile = layout.tile

        // **The outside, drawn rather than left to whatever is behind the
        // scene.** A plan has an edge: that is most of what makes it a plan,
        // and the pixels past that edge have to be a deliberate colour rather
        // than the compositor's default, which is transparent black offscreen
        // and the desktop behind a non-opaque panel. It is the scene's own
        // background tone, so a room with no plan and a room with one meet the
        // void at exactly the same colour.
        let surround = SKSpriteNode(color: Self.voidColour, size: CGSize(
            width: Double(layout.drawnColumns.count * tile),
            height: Double(layout.drawnRows.count * tile)))
        surround.anchorPoint = CGPoint(x: 0, y: 0)
        surround.position = CGPoint(
            x: layout.drawnColumns.lowerBound * tile, y: layout.drawnRows.lowerBound * tile)
        surround.zPosition = -40
        world.addChild(surround)
        planNodes.append((surround, "outside"))

        for space in plan.spaces {
            guard let surface = plan.surface(space.surface),
                  let floor = store.texture(path: surface.floor) else { continue }
            for row in space.y..<(space.y + space.h) {
                for column in space.columns {
                    addPlanTile(floor, column: column, row: row, z: -30, what: surface.floor)
                }
            }
        }

        for space in plan.spaces {
            guard let rows = space.bandRows, let surface = plan.surface(space.surface),
                  let cap = store.texture(path: surface.cap),
                  let body = store.texture(path: surface.body) else { continue }
            for column in space.columns where !space.isDoorway(column: column) {
                addPlanTile(body, column: column, row: rows.body, z: -20, what: surface.body)
                addPlanTile(cap, column: column, row: rows.cap, z: -20, what: surface.cap)
                addShadow(underColumn: column, atY: Double(rows.body * tile))
            }
            for column in space.doorways where space.columns.contains(column) {
                for edge in [column, column + 1] {
                    addJamb(
                        atX: Double(edge * tile), fromY: Double(rows.body * tile),
                        height: Double(RoomPlan.wallRowsFromTop * tile), colour: surface.lineEdge)
                }
            }
        }

        for partition in plan.partitions {
            guard let surface = plan.spaces
                .first(where: { $0.columns.contains(partition.x) })
                .flatMap({ plan.surface($0.surface) })
                ?? plan.surfaces.values.sorted(by: { $0.id < $1.id }).first else { continue }
            let bitmap = SceneBitmaps.planLine(
                height: partition.h * tile, edge: surface.lineEdge, fill: surface.lineFill)
            guard let texture = store.texture(
                bitmap: bitmap, key: "plan:partition:\(partition.h):\(surface.id)") else { continue }
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.size = CGSize(width: bitmap.width, height: bitmap.height)
            node.position = CGPoint(x: partition.x * tile, y: partition.y * tile)
            node.zPosition = -18
            world.addChild(node)
            planNodes.append((node, "partition@\(partition.x)"))
        }
    }

    private func addPlanTile(
        _ texture: SKTexture, column: Int, row: Int, z: CGFloat, what: String
    ) {
        let tile = layout.tile
        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = CGPoint(x: 0, y: 0)
        node.size = CGSize(width: tile, height: tile)
        node.position = CGPoint(x: column * tile, y: row * tile)
        node.zPosition = z
        world.addChild(node)
        planNodes.append((node, what))
    }

    private func addShadow(underColumn column: Int, atY y: Double) {
        let bitmap = SceneBitmaps.wallContactShadow(width: layout.tile)
        guard let texture = store.texture(bitmap: bitmap, key: "plan:shadow") else { return }
        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = CGPoint(x: 0, y: 1)
        node.size = CGSize(width: bitmap.width, height: bitmap.height)
        node.position = CGPoint(x: Double(column * layout.tile), y: y)
        node.zPosition = -19
        world.addChild(node)
        planNodes.append((node, "shadow"))
    }

    private func addJamb(atX x: Double, fromY y: Double, height: Double, colour: Bitmap.RGBA) {
        let bitmap = SceneBitmaps.planJamb(height: Int(height), colour: colour)
        guard let texture = store.texture(
            bitmap: bitmap, key: "plan:jamb:\(Int(height)):\(colour)") else { return }
        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.size = CGSize(width: bitmap.width, height: bitmap.height)
        node.position = CGPoint(x: x, y: y)
        node.zPosition = -19
        world.addChild(node)
        planNodes.append((node, "jamb"))
    }

    // MARK: Stations [ADR-002 §4, §8 items 4 and 6]

    /// The chair sits a hair behind the body; the desk a half-row in front of
    /// it. Named once because the station path has to reproduce both exactly,
    /// a station whose desk sorted differently from the theme's desk would
    /// change whether the near edge crosses the body, which is the one cue at
    /// 32 px that a character is sitting *at* a desk rather than beside one.
    nonisolated static let seatDepthBias: CGFloat = -0.25

    /// A desk short enough to sit at is drawn **in front of** the body: at 32 px
    /// the only cue that a character is sitting *at* a desk rather than beside
    /// one is whether the desk's near edge crosses it.
    nonisolated static let surfaceInFrontBias: CGFloat = 0.5

    /// A desk taller than the head line is drawn **behind** it instead: behind
    /// the chair, too, so the three still sort in one consistent order.
    ///
    /// **This is the occlusion defect's fix and it is not a preference.** The
    /// argument for putting the desk in front assumes a desk shorter than the
    /// person at it. `library` bound a **56×70** desk-with-an-open-book and
    /// `mission_control` a **44×36**, both chosen for `props.roles` before
    /// stations existed and both drawn at *every* seat by `buildRoom` whether
    /// anyone is sitting there or not. At 70 px the near-edge cue is not
    /// weakened, it is moot: the desk covers the whole body including the face,
    /// and a room whose characters have no faces cannot be read at all. Losing a
    /// depth cue costs less than losing the character.
    ///
    /// **The paragraph above was corrected once and is now corrected again, and
    /// the second correction is the interesting one.** `1c0eeb3` re-cut both
    /// desks (`library` to **32×44** and `mission_control` to **40×36**) and
    /// the note that stood here concluded that no desk any shipped theme binds
    /// took this branch, so the rule was a standing guard rather than a live one.
    /// That conclusion was arithmetically correct *about the rule as written* and
    /// wrong about the room: the maintainer's `mission_control` desk was drawn in
    /// front of the body with its top edge at eye level, across the nose, the
    /// mouth and the jaw, which is the defect the paragraph above says this
    /// constant exists to prevent. The branch is **live**: `library` and
    /// `mission_control` both take it now, and what changed is not the art but
    /// the number the rule compares against. See `seatedHeadClearance(nearEdgeX:)`.
    nonisolated static let surfaceBehindBias: CGFloat = -0.5

    /// Which of the two a desk of this height gets. `headClearance` is how tall a
    /// surface standing at this desk's own near edge may be before it covers a
    /// head pixel: `seatedHeadClearance(nearEdgeX:)`, which measures it.
    ///
    /// **This function never changed and never had to.** What was passed to it
    /// did: for six milestones `headClearance` was `canvas.height − head_top_px`,
    /// which is how far above its feet the head *starts*. That is the head's top,
    /// so it is the height at which a surface covers the head **completely**, and
    /// passing it here read the guard's own sentence backwards.
    nonisolated static func surfaceDepthBias(deskHeight: Int, headClearance: Int) -> CGFloat {
        deskHeight <= headClearance ? surfaceInFrontBias : surfaceBehindBias
    }

    /// **How tall a surface may stand at a seat before it covers a face, as a
    /// function of how far to the character's right its near edge falls.**
    ///
    /// Two things about this are corrections rather than refinements, and both
    /// were rendered before they were written down.
    ///
    /// **It is the head's bottom, not its top.** `head_top_px` is the only head
    /// datum the manifest carries and it is the *crown*: 44 px above the feet on
    /// the shortest of the cast. The chin is at **16–18 px**. A 44 px desk drawn
    /// in front does not "just reach" the head, it hides all of it.
    ///
    /// **And height alone does not decide it.** A desk is centred seven eighths
    /// of a tile to the character's right, so a 32 px desk's near edge falls at
    /// `+12` from the seat and a 40 px desk's at `+8`. The seated silhouette is
    /// widest at the hair, rows that reach `+13` to `+15`, and narrowest at the
    /// chin, which reaches only `+9`. So the answer is genuinely two-dimensional:
    /// at `+12` a surface may stand **26 px** without touching a head, and at
    /// `+8` only **16**. A single number for the whole cast would have to be 16,
    /// which puts every desk in every theme behind the body and spends the
    /// near-edge cue in four themes that never had the defect.
    ///
    /// Measured off the sit frames themselves, because nothing in the manifest
    /// says where a head ends. `nil` (no cast, or art that will not load) is
    /// answered `0`, which sends every surface behind: a clearance we cannot
    /// measure is not a clearance we may assume.
    func seatedHeadClearance(nearEdgeX: Double) -> Int {
        guard let head = seatedHeadMeasurement else { return 0 }
        return head.clearance(nearEdgeX: nearEdgeX)
    }

    /// Measured once per scene, off the art the scene is about to draw.
    private lazy var seatedHeadMeasurement: SeatedHead? = SeatedHead(
        frames: Self.seatedFrames(
            manifest: store.manifest, facing: RoomLayout.SeatFacing.sideOn.bodyFacing))

    /// Every seated frame of every variant, as pixels.
    ///
    /// The **whole cast**, because a clearance that only holds for the short half
    /// of it is not a clearance, and every **frame**, because the sit loop moves:
    /// the third frame's head sits 2 px lower than the first's, and a rule
    /// measured on frame 0 alone would be wrong for a third of every second.
    ///
    /// **One facing, and it is the side-on seat's own.** The two sit facings are
    /// pixel-exact mirrors, so measuring both would put the hair's widest rows at
    /// *both* edges of the canvas and hand every desk in the room the clearance
    /// of a character sitting the wrong way round, which cost `office` its
    /// near-edge cue the first time this was written.
    ///
    /// It asked `RoomLayout.seatedFacing` while that was one constant for the
    /// whole room. A seat declares its own facing now [ADR-008], and this
    /// measurement is about the sit row and about nothing else: the whole
    /// near-edge cue is the side-on arrangement's, so it names
    /// `SeatFacing.sideOn` rather than asking a seat that may have turned.
    nonisolated static func seatedFrames(manifest: Manifest, facing: Facing) -> [Bitmap] {
        var frames: [Bitmap] = []
        for id in manifest.characters.orderedVariantIDs {
            guard let variant = manifest.characters.variant(id),
                  let animation = variant.animation(.working),
                  let paths = animation.frames(facing: facing) else { continue }
            for path in paths {
                guard let bitmap = try? PixelImage.bitmap(contentsOf: manifest.url(path))
                else { continue }
                frames.append(bitmap)
            }
        }
        return frames
    }

    /// The bias for one desk, measured off its own content box **and off where
    /// the layout puts it**. The second half is what the height-only version
    /// missed: the same 36 px desk clears every head at `+12` and covers six of
    /// them at `+8`, and nothing about the desk's own box says which it is.
    private func surfaceDepthBias(for prop: Manifest.PropRole?) -> CGFloat {
        guard let prop else { return Self.surfaceInFrontBias }
        return Self.surfaceDepthBias(
            deskHeight: prop.contentBox.height,
            headClearance: seatedHeadClearance(nearEdgeX: Self.surfaceNearEdgeX(
                of: prop, layout: layout)))
    }

    /// How far to the character's right a desk's near edge falls, in seat-relative
    /// scene pixels. The desk is centred on `deskPosition` and anchored on its own
    /// content box, so this is the layout's offset less half the box.
    nonisolated static func surfaceNearEdgeX(
        of prop: Manifest.PropRole, layout: RoomLayout
    ) -> Double {
        layout.sideOnDeskOffsetX - Double(prop.contentBox.width) / 2
    }

    /// The theme-wide desk and chair drawn at each seat at build time.
    ///
    /// They are the **empty desk**: an office has them, and drawing furniture
    /// only when somebody arrives would make the room rearrange itself as agents
    /// come and go. When a character with a station sits down, its seat's pair
    /// is hidden and the station's own furniture is drawn in their place; when
    /// it leaves, they come back. The nodes are never destroyed, which is what
    /// keeps `noPropNodeIsEverRebuiltAcrossAnyFixtureReplay`: §6 rule 1 made
    /// mechanical: true through every arrival and departure in every fixture.
    private var emptySeatFurniture: [Int: [SeatFurniture]] = [:]

    /// One piece of furniture at a seat, with the manifest path behind it.
    ///
    /// The path is carried rather than recoverable, because node identity says a
    /// desk was *placed* and says nothing about which picture, and "a desk was
    /// placed" was true for three months while every desk in the room was the
    /// same one.
    private struct SeatFurniture {
        let node: SKSpriteNode
        let path: String
    }

    /// The furniture drawn for one seated character's station, and the seat it
    /// stands at. Keyed by agent because a seat can be vacated and refilled
    /// while the leaver is still walking out.
    private var stationFurniture: [AgentRef: [SeatFurniture]] = [:]
    private var stationSeat: [AgentRef: Int] = [:]

    /// One sprite the room has drawn at a seat, flattened to values a test can
    /// rasterise without SpriteKit.
    ///
    /// This exists because the assertion that matters is about *pixels*, and the
    /// failure it has to catch produced perfectly correct nodes: six stations in
    /// six themes, every one placed, every one drawn, and the same picture at
    /// every seat, because the picture came from `props.roles` and the station
    /// id reached nothing. Positions and counts cannot see that. A path and a
    /// placement can.
    public struct DrawnFurniture: Sendable, Hashable {
        public let path: String
        public let x: Double, y: Double
        public let anchorX: Double, anchorY: Double
        public let width: Double, height: Double
        public let z: Double
    }

    /// Everything currently visible at one seat, in draw order.
    ///
    /// Hidden nodes are omitted: the theme-wide pair is hidden, not destroyed,
    /// while a station stands on its seat, so "what is on screen" and "what
    /// nodes exist" are different questions and this answers the first.
    public func furnitureForTesting(seat: Int) -> [DrawnFurniture] {
        var pieces = emptySeatFurniture[seat] ?? []
        for (agent, furniture) in stationFurniture where stationSeat[agent] == seat {
            pieces += furniture
        }
        return pieces
            .filter { !$0.node.isHidden }
            .map {
                DrawnFurniture(
                    path: $0.path,
                    x: Double($0.node.position.x), y: Double($0.node.position.y),
                    anchorX: Double($0.node.anchorPoint.x),
                    anchorY: Double($0.node.anchorPoint.y),
                    width: Double($0.node.size.width), height: Double($0.node.size.height),
                    z: Double($0.node.zPosition))
            }
            .sorted { $0.z < $1.z }
    }

    /// Draws one character's station at its seat: the station's own desk and
    /// chair in place of the theme-wide pair, plus at most one adjacent
    /// floor-standing prop. [ADR-002 §7]
    ///
    /// **The theme's `props.roles` stay the fallback**, and they are the whole
    /// answer for a seat whose station names nothing: a theme that declares no
    /// stations, a station id the theme does not bind, or a manifest that
    /// predates stations entirely all leave the build-time pair exactly where it
    /// was and draw nothing here. That is what makes this change degrade to the
    /// picture the app drew yesterday rather than to an empty room.
    ///
    /// **Placement is the seat's own, not the station's.** The chair goes on
    /// `seatPosition`, the desk on `deskPosition`, both at the same depth biases
    /// the build-time pair uses, and each is anchored on its own measured
    /// content box. A station cannot move a seat, so the layout stays
    /// theme-independent and every plate-clearance argument in `RoomLayout`
    /// survives untouched.
    private func placeStation(_ id: String, for agent: AgentRef, at seat: Int) {
        guard let station = store.room.station(id) else { return }
        for piece in emptySeatFurniture[seat] ?? [] { piece.node.isHidden = true }

        var placed: [SeatFurniture] = []
        func draw(_ role: Manifest.PropRole, at point: ScenePoint, depthBias: CGFloat) {
            guard let node = place(prop: role, at: point, depthBias: depthBias) else { return }
            placed.append(SeatFurniture(node: node, path: role.file))
        }
        // **The chair is the seat's, not the station's, wherever the seat has
        // turned.** [ADR-008] A station's chair falls back to the theme's `chair`
        // role: every station in the shipped manifest declares none, and the
        // manifest's own note says why: there is one side-view chair in either
        // pack, so a station cannot be themed art anyway. A side view under a
        // back-facing occupant is a chair pointing 90° away from the person in
        // it, so an away-facing seat takes `chair_back` and a camera-facing seat
        // takes nothing, exactly as `buildRoom` places them.
        let facing = layout.seatFacing(seat)
        let metrics = seatMetrics(desk: station.desk)
        if let point = layout.chairPosition(seat, metrics: metrics) {
            let chair = facing == .sideOn
                ? station.chair
                : (layout.seatFacing(seat).seatRole.flatMap { store.room.prop($0) })
            if let chair {
                draw(chair, at: point, depthBias: facing == .sideOn ? Self.seatDepthBias : 0)
            }
        }
        draw(station.desk, at: layout.deskPosition(seat, metrics: metrics),
             depthBias: facing == .sideOn ? surfaceDepthBias(for: station.desk) : 0)
        // The desktop kit is the **theme's**, not the station's, exactly as the
        // turned seat's chair is: a station changes what stands beside the seat
        // and never what the theme's furniture looks like [ADR-002 §14c]. It is
        // redrawn here rather than left showing because `placeStation` hides the
        // whole of `emptySeatFurniture`, the kit included. [ADR-009]
        for piece in podFurniture(seat: seat, metrics: metrics) {
            draw(piece.prop, at: piece.point, depthBias: piece.depthBias)
        }
        if let prop = station.prop {
            draw(prop, at: layout.stationPropPosition(seat), depthBias: Self.seatDepthBias)
        }

        stationFurniture[agent] = placed
        stationSeat[agent] = seat
        stationDesks[agent] = station.desk
    }

    // MARK: The desk-top object [ADR-006]

    /// One node per seated character, standing on its own desk. Empty until a
    /// character is spawned and never rebuilt while it is on screen.
    ///
    /// **Outside `propNodes`, exactly as a station's furniture is**, and for the
    /// same reason: `propNodes` is the *room's* furniture, the set §6 rule 1
    /// promises is never rebuilt across a whole fixture replay, and how many
    /// copies of it exist is decided at build time. This is per-character
    /// furniture (it exists because an agent does) so it is created and retired
    /// with the character, alongside `stationFurniture`. What rule 1's spirit
    /// asks of it is checked by its own test
    /// (`DeskObjectSceneTests.noDeskObjectNodeIsEverRebuiltAcrossAnyFixtureReplay`):
    /// a kind that changes swaps a texture and never a node.
    private var deskObjectNodes: [AgentRef: SKSpriteNode] = [:]

    /// The desk-top objects currently on screen, flattened the same way
    /// `furnitureForTesting(seat:)` flattens a station's. Hidden nodes: a
    /// character whose desk is still bare: are omitted, so this answers "what is
    /// on the desks" rather than "what nodes exist".
    public func deskObjectsForTesting() -> [AgentRef: DrawnFurniture] {
        var out: [AgentRef: DrawnFurniture] = [:]
        for (agent, node) in deskObjectNodes where !node.isHidden {
            out[agent] = DrawnFurniture(
                path: deskObjectPaths[agent] ?? "",
                x: Double(node.position.x), y: Double(node.position.y),
                anchorX: Double(node.anchorPoint.x), anchorY: Double(node.anchorPoint.y),
                width: Double(node.size.width), height: Double(node.size.height),
                z: Double(node.zPosition))
        }
        return out
    }

    /// The manifest path behind each drawn desk object. **Uniformly `""` since
    /// all four kinds became authored**: it was `""` for `running` alone while
    /// the other three were pack bindings. Kept because the role arm of
    /// `deskObjectArt` still fills it if a kind ever names a role again. Node
    /// identity says an object was placed; it says nothing about which picture.
    private var deskObjectPaths: [AgentRef: String] = [:]

    /// **What kind each character's desk object is drawing**, so that a screen
    /// change can redraw it without the director restating the kind.
    ///
    /// The two facts arrive on separate intents and in either order: a kind is
    /// adopted when the votes say so and the screen changes at a turn boundary,
    /// so each has to be able to land without the other being present. `nil`
    /// here is the bare desk, and a screen change on a bare desk is a stored
    /// flag and no drawing at all.
    private var deskObjectKinds: [AgentRef: WorkKind] = [:]

    /// **Whether each character's desk screen is on.** [ADR-006 §12]
    ///
    /// Defaults to `.lit` for a character the director has not spoken about,
    /// which is what a character walking in is: it exists because an event
    /// arrived, and an event arriving means it is in a turn. `SceneDirector`
    /// seeds its own memory with the same value for the same reason, so the two
    /// agree without either asking the other.
    private var deskScreens: [AgentRef: DeskScreen] = [:]

    var deskObjectNodesForTesting: [AgentRef: SKSpriteNode] { deskObjectNodes }

    /// The screen state each desk is drawn in, for tests that check the picture
    /// rather than the policy.
    public func deskScreensForTesting() -> [AgentRef: DeskScreen] { deskScreens }

    /// **How far to the character's right a desk-top object's near edge stands**,
    /// in seat-relative scene pixels. [ADR-006 §2c]
    ///
    /// Half the character canvas, which is the first column strictly outside a
    /// seated character's own sprite, and `SeatedHead.clearance(nearEdgeX:)` is
    /// unbounded from exactly there, measured against every seated frame the pack
    /// ships. So an object standing at this edge **cannot cover a head pixel at
    /// any height whatsoever**, which is why nothing in this file compares an
    /// object's height against anything.
    ///
    /// Derived from the manifest rather than written down as 16, so a cast on a
    /// different canvas moves it without anyone remembering to.
    nonisolated static func deskObjectNearEdgeX(manifest: Manifest) -> Double {
        Double(manifest.characters.canvas.width) / 2
    }

    /// **One depth step in front of the desk it stands on**, whichever way that
    /// desk sorted.
    ///
    /// A quarter row rather than a half, so it lands strictly between the desk
    /// and the next depth band either way: a desk drawn in front of the body
    /// (`surfaceInFrontBias`) keeps its object in front of it, and one drawn
    /// behind (`surfaceBehindBias`, which `library` and `mission_control` both
    /// take) keeps its object in front of *it* and still behind the body. Nothing
    /// about the body matters visually here: the object is outside the
    /// character's own canvas by construction, but the two have to sort the same
    /// way every frame rather than by dictionary order.
    nonisolated static let deskObjectInFrontStep: CGFloat = 0.25

    /// Creates a character's desk-object node, hidden and bare.
    ///
    /// Called from the spawn arm beside `placeStation`, so every seated character
    /// has exactly one and it exists before any `setDeskObject` can arrive. It
    /// carries no texture until a kind is adopted: a character whose work the
    /// room cannot name keeps the plain desk the room has always drawn, and that
    /// is the commonest case rather than an error path. [I1]
    private func placeDeskObjectNode(for agent: AgentRef) {
        guard deskObjectNodes[agent] == nil else { return }
        let node = SKSpriteNode()
        node.isHidden = true
        world.addChild(node)
        deskObjectNodes[agent] = node
    }

    /// Puts a kind on a character's desk, or leaves the desk bare when its art
    /// will not load.
    ///
    /// **The node is reused and never rebuilt.** A kind that changes swaps the
    /// texture, the anchor, the size and the position on the node that is already
    /// there; nothing is added to the tree and nothing is removed from it. That
    /// is ADR-002 §6 rule 1's discipline applied to a slot rule 1 does not cover,
    /// and `noDeskObjectNodeIsEverRebuiltAcrossAnyFixtureReplay` is where it is
    /// checked mechanically.
    private func showDeskObject(_ kind: WorkKind, for agent: AgentRef) {
        // Recorded before the guard, so a screen change arriving later still
        // knows what to redraw even in the (unreachable today) case where the
        // art failed to load and the desk stayed bare.
        deskObjectKinds[agent] = kind
        let slot = deskObjectNodes[agent]
        guard let node = slot, let seat = seatOf[agent],
              layout.isSeatable(seat),
              // **A camera-facing seat's desk carries nothing**, and it is the
              // only slot in the room that answers a real fact with silence.
              // [ADR-008 §5, `RoomLayout.SeatFacing.showsDeskTopObject`] The
              // desk is between the occupant and the viewer, so an object on it
              // faces upstage, and there is no rear view of a screen anywhere
              // in 12,279 catalogue props, so a lit monitor there draws somebody
              // staring at the back of their own screen. The desk is also 32 px
              // wide with the body occupying all of it, so no column on it is
              // clear of the face. Two independent reasons, and I1's answer when
              // you cannot say something truthfully is to say nothing.
              layout.seatFacing(seat).showsDeskTopObject,
              let art = deskObjectArt(kind, screen: deskScreens[agent] ?? .lit) else {
            slot?.isHidden = true
            return
        }
        // The desk this seat actually draws, which is a station's own when it has
        // one and the theme's `desk` role otherwise. Stations fall back to that
        // role when they declare no desk, and none in the shipped manifest does,
        // so this resolves to the same object either way today: asked properly
        // anyway, because a station that ever binds its own desk would otherwise
        // put every object on it at the wrong height.
        let desk = stationDesks[agent] ?? store.room.prop(Self.surfaceRole)
        // `surface_y` is the measured plane; the box top is the fallback for a
        // manifest that predates the measurement, and the placeholder's own
        // height for a manifest with no desk role at all. [ADR-006 §2b]
        let surfaceHeight = desk.map { Double($0.surfaceY ?? $0.contentBox.height) }
            ?? Double(SceneBitmaps.placeholderDesk().height)
        let metrics = seatMetrics(desk: desk)
        let facing = layout.seatFacing(seat)
        let deskPoint = layout.deskPosition(seat, metrics: metrics)
        let surface = layout.deskSurfacePosition(
            seat: seat, surfaceHeightAboveFloor: surfaceHeight, metrics: metrics)
        // **Where on the desk it stands is one rule, and an away-facing seat
        // keeps it.** One character half-canvas to the right of the seat, which
        // is the first column strictly outside the sprite, so the object cannot
        // cover a head pixel at any height [ADR-006 §2c]. That holds unchanged
        // at an away-facing seat because the desk moved in *depth* and not in x
        //: see `RoomLayout.deskPosition(_:metrics:)` for why it was kept there.
        // A camera-facing seat never reaches this line.
        let nearEdge = layout.seatPosition(seat).x
            + Self.deskObjectNearEdgeX(manifest: store.manifest)
        // **On a pod it stands in the right-hand rig slot instead**: on that
        // rig's own desktop, one depth step in front of it. [ADR-009] Both slots
        // carry a rig as theme furniture, because the `monitor` role is a whole
        // workstation and one of them covers half the slab
        // [`RoomLayout.monitorPosition(_:slot:metrics:)`], so the desktop says
        // *this is a workstation* whoever is sitting at it and this object says
        // *this is the work* on top of it.
        //
        // **The near-edge rule is not weakened, it is inapplicable here.** ADR-006
        // §2c pushes the object clear of the body so it cannot cover a head pixel
        // at any height. Only a camera-facing seat can be covered that way, and a
        // camera-facing seat draws no object at all: at an away-facing seat the
        // desk and everything on it is genuinely *upstage* of the occupant, so
        // `rowDepth` draws the body over the object and the risk the rule exists
        // to close cannot occur at any x. What the slot costs instead is a few
        // columns of the object hidden behind the body, and the body's ink is
        // narrower than its canvas.
        let objectX = metrics.isDeskPod
            ? deskPoint.x + layout.podSlotOffsetX(metrics: metrics)
            : nearEdge + art.contentWidth / 2

        node.texture = art.texture
        node.anchorPoint = art.anchor
        node.size = art.size
        node.position = CGPoint(x: objectX, y: surface.y)
        // **In front of the rig it shares a slot with, and the rig's own lift has
        // to be in the bias to get there.** `podFurniture` gives each rig
        // `lift + deskObjectInFrontStep`, for the reason that function's own
        // comment records: a prop standing `lift` px above its desk's floor point
        // sorts `lift` px *behind* the desk unless the lift is added back. This
        // takes the same lift and one more step, so it lands one notch in front of
        // the rig and stays behind everything the rig was already behind.
        node.zPosition = Character.Layer.rowDepth(deskPoint.y)
            + (facing == .sideOn ? surfaceDepthBias(for: desk) : 0)
            + (metrics.isDeskPod
               ? CGFloat(layout.deskTopLift(surfaceHeightAboveFloor: surfaceHeight,
                                            metrics: metrics))
                 + Self.deskObjectInFrontStep * 2
               : Self.deskObjectInFrontStep)
        node.isHidden = false
        deskObjectPaths[agent] = art.path
    }

    /// **The desk `placeStation` actually drew for each character**, kept so that
    /// the object standing on it is placed at *that* desk's surface rather than
    /// at the theme desk's.
    ///
    /// `nil` for a character whose station named nothing, which keeps the
    /// theme-wide pair, and the fallback in `showDeskObject` asks the theme for
    /// the same role that pair was drawn from.
    private var stationDesks: [AgentRef: Manifest.PropRole] = [:]

    /// One kind's art, resolved through the manifest wherever the manifest has
    /// it.
    ///
    /// **All four are authored, and the role arm below is currently
    /// unreachable.** `WorkKind.propRole` returns `nil` for every kind, so every
    /// call takes the `guard` branch and draws `DeskWorkArt` or, for `running`,
    /// `DeskMonitorArt`: the way the badges, the nameplate and the held objects
    /// are drawn.
    ///
    /// It was three-from-the-pack and one authored until the three pack singles
    /// were rendered at the panel's true size and found unreadable there: all
    /// isometric, and a diagonal wedge loses its diagonal before anything else.
    /// `DeskWorkArt` carries that measurement.
    ///
    /// **The role lookup is kept deliberately.** It is the seam that lets final
    /// art arrive as a manifest swap with no code change, it prefers the theme's
    /// own binding over the root `room`'s, and reinstating one kind's role is all
    /// it takes to use it. `WorkKind.propRole` records that only the authored arm
    /// is covered by a test.
    private func deskObjectArt(_ kind: WorkKind, screen: DeskScreen)
    -> (texture: SKTexture, anchor: CGPoint, size: CGSize, contentWidth: Double, path: String)? {
        guard let role = kind.propRole else {
            // `running` is the monitor next door; the other three are
            // `DeskWorkArt`. Both are authored and both are their own content
            // box, so the arithmetic below is the same for either.
            //
            // **The screen state reaches the art here and only here.** Two of
            // the four kinds redraw for it and two return the same pixels
            // (`WorkKind.hasScreen`), so a paper desk is bit-identical in both
            // states rather than special-cased anywhere above this line.
            let bitmap = DeskWorkArt.bitmap(kind, screen: screen)
                ?? DeskMonitorArt.bitmap(screen: screen)
            guard let texture = store.texture(
                bitmap: bitmap, key: kind.textureKey(screen: screen)) else {
                return nil
            }
            // The authored bitmap *is* its own content box: ink reaches every
            // edge, so the canvas needs no anchor arithmetic.
            return (texture, CGPoint(x: 0.5, y: 0),
                    CGSize(width: bitmap.width, height: bitmap.height),
                    Double(bitmap.width), "")
        }
        let themed = store.room.prop(role).map { ($0, store.room.propCanvas) }
        let rooted = store.manifest.room.prop(role).map { ($0, store.manifest.room.propCanvas) }
        guard let (prop, canvas) = themed ?? rooted,
              let texture = store.texture(path: prop.file) else { return nil }
        let anchor = prop.anchor(inCanvas: canvas)
        return (texture, CGPoint(x: anchor.x, y: anchor.y),
                CGSize(width: canvas.width, height: canvas.height),
                Double(prop.contentBox.width), prop.file)
    }

    /// Takes a character's desk object down with the character.
    private func retireDeskObject(for agent: AgentRef) {
        deskObjectNodes.removeValue(forKey: agent)?.removeFromParent()
        deskObjectPaths.removeValue(forKey: agent)
        deskObjectKinds.removeValue(forKey: agent)
        deskScreens.removeValue(forKey: agent)
        stationDesks.removeValue(forKey: agent)
    }

    /// Takes a character's station down and puts the empty desk back.
    ///
    /// Called when the node is actually retired rather than when the exit intent
    /// arrives, so a character walking out is still walking away from its own
    /// desk for the whole of the walk. The seat may already have been reclaimed
    /// by then (a seat is free the instant its occupant starts leaving) so the
    /// empty pair is only restored if nobody else has since drawn a station on
    /// it.
    private func retireStation(for agent: AgentRef) {
        for piece in stationFurniture.removeValue(forKey: agent) ?? [] {
            piece.node.removeFromParent()
        }
        guard let seat = stationSeat.removeValue(forKey: agent) else { return }
        guard !stationSeat.values.contains(seat) else { return }
        for piece in emptySeatFurniture[seat] ?? [] { piece.node.isHidden = false }
    }

    /// Every furniture node drawn from an identified manifest role. Read-only;
    /// nothing in the scene depends on it, and it exists so a test can check
    /// what was placed rather than trusting that something was.
    var propNodesForTesting: [SKSpriteNode] { propNodes }

    /// The manifest path behind each of those nodes, in the same order.
    ///
    /// Node identity says a prop was *placed*; it says nothing about which
    /// picture. Two themes place the same number of props at the same points,
    /// that is the layout being theme-independent, which is a required property
    ///, so a test that compares only positions and counts cannot tell a themed
    /// room from a room that ignored the theme id. This is what it compares
    /// instead, and it is the manifest's own string rather than a texture, so
    /// two scenes with two `TextureStore`s can be compared at all.
    var propArtForTesting: [String] { propPaths }

    private var propNodes: [SKSpriteNode] = []
    private var propPaths: [String] = []
    /// The scenery subset of `propNodes`, so a test can tell the room's dressing
    /// from the four bound roles without re-deriving which is which from
    /// positions. [M8 Phase 2b]
    private var sceneryNodes: [SKSpriteNode] = []

    var sceneryNodesForTesting: [SKSpriteNode] { sceneryNodes }

    /// **The seat furniture subset of `propNodes`**: every desk and every chair
    /// the room draws at a seat, occupied or not. [ADR-008]
    ///
    /// It exists for the same reason `sceneryNodesForTesting` does, and it
    /// became necessary for a reason worth writing down: the two decoration
    /// tests used to separate seat furniture from decoration **by position**,
    /// filtering out anything standing on a seat row. That was exact while every
    /// desk and chair shared its occupant's row, and ADR-008 moves them off it,
    /// a camera-facing desk stands downstage of the seat and an away-facing
    /// chair further downstage still. Identity is what the exclusion always
    /// meant; the position filter was a proxy that happened to be equivalent,
    /// and `decorationIsSpreadAcrossTheRoomAndStandsAtTwoDepths`'s own comment
    /// already says why identity is the right key.
    var seatFurnitureNodesForTesting: [SKSpriteNode] {
        emptySeatFurniture.values.flatMap { $0 }.map(\.node)
            + stationFurniture.values.flatMap { $0 }.map(\.node)
    }

    /// The props that idle on their own loop. [ADR-002 §14b]
    ///
    /// One per placed node, so four copies of an animated `board` swing
    /// together: they are handed the same clock, so they are in phase by
    /// construction rather than by a shared index anybody has to maintain.
    ///
    /// **Nothing outside `advance(to:)` may touch this.** See `PropAnimation`
    /// for the whole of why, and for what enforces it.
    private var propAnimations: [PropAnimation] = []

    var propAnimationsForTesting: [PropAnimation] { propAnimations }

    /// Draws the theme's prop for one role. `nil`, having drawn nothing, when
    /// the manifest has no such role.
    ///
    /// This is the **room's** furniture: it is registered in `propNodes` and
    /// therefore covered by §6 rule 1's "zero prop-node rebuilds across an
    /// entire fixture replay", and it is the only path that starts a prop
    /// animation.
    @discardableResult
    private func place(role: String, at point: ScenePoint, depthBias: CGFloat = 0)
    -> SKSpriteNode? {
        guard let prop = store.room.prop(role) else { return nil }
        return place(roomProp: prop, at: point, depthBias: depthBias)
    }

    /// The same, for a prop the caller has already resolved: a role drawn with
    /// one of its `variants`, which is a picture the role name alone no longer
    /// identifies. Everything else is identical, the registration in `propNodes`
    /// included, because a variant is the room's own furniture exactly as entry 0
    /// is.
    @discardableResult
    private func place(roomProp prop: Manifest.PropRole, at point: ScenePoint,
                       depthBias: CGFloat = 0) -> SKSpriteNode? {
        guard let node = place(prop: prop, at: point, depthBias: depthBias) else { return nil }
        propNodes.append(node)
        propPaths.append(prop.file)

        // A prop that idles. `prop.file` is frame 0 and is already on the node,
        // so a manifest without this key, or with art that will not load,
        // draws exactly the still prop it always did.
        //
        // **Only room props idle, and stations deliberately do not.** The motion
        // budget is I7 on the time axis and it is a budget on moving pixels per
        // second *summed over every copy the room draws*, which the room knows
        // at build time and cannot know for a station, because how many copies
        // of a station exist is how many agents of that type turned up. A budget
        // that cannot be computed is not a budget. [ADR-002 §14b]
        if let animation = prop.animation, animation.isPlayable {
            let textures = animation.frames.compactMap { store.texture(path: $0) }
            if textures.count == animation.frames.count,
               let player = PropAnimation(
                node: node, frames: textures, fps: animation.fps, loops: animation.loops) {
                propAnimations.append(player)
            }
        }
        return node
    }

    /// Draws one identified prop with its **content box's** bottom-centre on
    /// `point`. `nil`, having drawn nothing, when its art will not load.
    ///
    /// The anchor comes from the measured box rather than from the canvas,
    /// because the Modern Office singles are 64×96 canvases with the object
    /// dropped in wherever it sat on the source sheet: the desk's baseline is at
    /// row 87 and the plant's at row 75, in canvases of identical size. Any
    /// fixed offset would be right for one file and wrong for the next.
    ///
    /// One primitive for the room's props and for a station's, so a station desk
    /// is anchored, sized and depth-sorted by exactly the arithmetic the theme's
    /// desk is. Two placement paths over one kind of object drift, and the drift
    /// here would be a desk sitting a few pixels into the floor for one agent
    /// and not another.
    private func place(prop: Manifest.PropRole, at point: ScenePoint, depthBias: CGFloat)
    -> SKSpriteNode? {
        guard let texture = store.texture(path: prop.file) else { return nil }
        let canvas = store.room.propCanvas
        let anchor = prop.anchor(inCanvas: canvas)
        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = CGPoint(x: anchor.x, y: anchor.y)
        node.size = CGSize(width: canvas.width, height: canvas.height)
        node.position = CGPoint(x: point.x, y: point.y)
        node.zPosition = Character.Layer.rowDepth(point.y) + depthBias
        world.addChild(node)
        return node
    }

    // MARK: Intents

    public func apply(_ intents: [SpriteIntent]) {
        for intent in intents { apply(intent) }
        applyScale()
    }

    public func apply(_ intent: SpriteIntent) {
        switch intent {
        case let .spawnCharacter(agent, variant, nameplate, seat, station, costume):
            guard characters[agent] == nil else { break }
            let character = Character(
                variant: variant, nameplate: nameplate, store: store, costume: costume)
            world.addChild(character)
            characters[agent] = character
            animated.append(character)
            seatOf[agent] = seat
            // **The station reaches the room here and only here.** It was
            // resolved at spawn, it rode in on the spawn intent, and it is drawn
            // once: there is no code path that could redraw it, which is §6
            // rule 2 enforced by there being nothing to enforce.
            placeStation(station, for: agent, at: seat)
            // **Beside the station and after it**, because the object stands on
            // the desk the station just drew and is depth-sorted against it. It
            // goes up hidden and bare: a character whose work the room cannot
            // name keeps the plain desk. [ADR-006 §3]
            placeDeskObjectNode(for: agent)
            // **A turned seat's posture channel is silent, so its dim carries
            // the turn.** [ADR-008 §6] Told once, here, from the seat's own
            // facing: a side-on seat is told nothing changed and keeps the
            // picture this app has always drawn.
            character.setDimsOutOfTurn(!layout.seatFacing(seat).showsPosture)
            character.setInTurn((deskScreens[agent] ?? .lit) == .lit)
            // **Straight up its own column, from the walkway.**
            // See `RoomLayout.entranceRoute(forSeat:)`: the walk-in used to run
            // one seat pitch sideways along the aisle, which is the one row
            // every character steps through, and it started on the *next ring's
            // own station*. A seat vacated and refilled while that neighbour was
            // mid-report put the newcomer on top of it: measured at −25.6 px,
            // an overlap and not a near miss. Entering up the column is the exit
            // reversed, so it is closed by the same construction and needs no
            // argument of its own.
            character.enter(along: layout.entranceRoute(forSeat: seat))

        case let .setNameplate(agent, nameplate):
            // A plate that learned something after its character was drawn,
            // almost always the task, which arrives one event behind the
            // `SubagentStart`. Redrawing the texture is the whole of it: the
            // node is anchored at its top edge, so a plate that gained a row
            // grows downward and nothing on screen moves.
            characters[agent]?.setNameplate(nameplate)

        case let .setBody(agent, state, facing):
            restingBody[agent] = state
            characters[agent]?.setResting(state, facing: facing)

        case let .setBadge(agent, selection):
            characters[agent]?.apply(badge: selection)

        case let .setDeskObject(agent, kind):
            // **Furniture, not a character channel.** It has no body state, no
            // pose and no ambient loop, and it moves 0 px/s in every frame of its
            // life, which is why ADR-006 needs no carve-out from I2 and proposes
            // none. Nothing about the character it belongs to changes here.
            showDeskObject(kind, for: agent)

        case let .setDeskScreen(agent, screen):
            // **Furniture again, and the same argument.** A screen going dark
            // is one texture swapped for another on a node that is already in
            // the tree: no pose, no loop, no interpolation, 0 px/s in every
            // frame of its life. ADR-006 §12 is where that is argued against I2
            // rather than asserted here.
            //
            // Stored whether or not anything is drawn: a bare desk has no
            // object to relight, and the flag is what makes the object correct
            // the moment one is adopted.
            deskScreens[agent] = screen
            if let kind = deskObjectKinds[agent] { showDeskObject(kind, for: agent) }
            // **And the same fact reaches the body at a turned seat.** The
            // screen intent *is* `isInTurn && !isDormant` [ADR-006 §12], which
            // is exactly what the dim is about, so no new intent and no second
            // channel is needed to carry it. A side-on character ignores it,
            // its posture already says this, and `Character.setInTurn` is
            // idempotent, so a repeat draws nothing. [ADR-008 §6]
            characters[agent]?.setInTurn(screen == .lit)

        case let .setGated(agent, isGated):
            // The motion channel's third input, and the only one that takes
            // motion away. Nothing else in the scene reads it: the posture and
            // the slot are unchanged for a blocked agent. [ADR-005 §7]
            characters[agent]?.setGated(isGated)

        case let .deliverReport(agent, anchorSeat):
            guard let character = characters[agent], let seat = seatOf[agent],
                  // Nobody walks over to themselves. The anchor resolves to the
                  // reporter's own seat only for the main agent, which has no
                  // `SubagentStop` and so never reports: this is the guard that
                  // says so rather than a comment claiming it. [I1]
                  seat != anchorSeat else { break }
            // Stand up, step down the reporter's **own column** to the delivery
            // row, walk along it to a delivery gap short of the anchor, turn,
            // hand over, and walk the same route back into the chair.
            //
            // **The transit used to be the room's one unguarded window**, and
            // then its most expensive fixture. A reporter walking the *aisle* to
            // its anchor passed every station in between, and a station is a
            // pitch from the next while the widest plate is 63, so it was
            // within a plate width of *some* station for most of the walk. M6f
            // deleted the leg rather than pay the three rows that fixed it, and
            // the maintainer saw what that left: an envelope handed to nobody.
            //
            // What holds it now is one row nothing else in the room can be on,
            // and a claim on a stretch of that row that no second reporter may
            // overlap. A reporter refused the row plays the in-place beat: the
            // one M6f left behind, rather than waiting for anything.
            // `RoomLayout.deliveryPosition(anchorSeat:reporterSeat:)` carries the
            // proof, `theRoomsOneLateralCorridorMeetsNoOtherRoute` the arithmetic.
            let side = layout.deliverySide(anchorSeat: anchorSeat, reporterSeat: seat)
            let route = claimDeliveryRow(for: character, seat: seat, anchorSeat: anchorSeat)
            character.reportAndReturn(
                out: route.out,
                facing: layout.deliveryFacing(side: side),
                home: layout.homeRoute(forSeat: seat, fromY: route.deliversAtY),
                // **Sit back down facing the desk.** The beat turns the
                // character towards its anchor, and the walk home is now purely
                // vertical, so nothing turns it back: `Character` ends a script
                // on `currentFacing.seated`, and a reporter to the left of its
                // anchor would take its chair with its back to its own desk.
                // The old lateral leg home did this by accident, for whichever
                // half of the cast happened to walk the right way. Re-asserting
                // the director's own last word is the deliberate version, and it
                // is the director's word rather than a constant so that this
                // cannot disagree with `setBody`.
                onFinished: { [weak self, weak character] in
                    guard let self, let character else { return }
                    character.setResting(
                        self.restingBody[agent] ?? .idle,
                        facing: self.layout.seatedFacing(seat))
                })

        case let .exitCharacter(agent, style):
            guard let character = characters.removeValue(forKey: agent) else { break }
            let seat = seatOf.removeValue(forKey: agent)
            restingBody.removeValue(forKey: agent)
            // **Every exit is a walk up the character's own column and out
            // through the back of the room.** See
            // `RoomLayout.upstageExit(forSeat:)` for why: a lateral corridor
            // that reaches the frame edge passes through every column outside
            // it, and a column is where every other character steps between the
            // desk row, the aisle and its delivery row. The whole cast can leave
            // in one frame (`SessionEnd` does exactly that) and seven leavers
            // going straight back stay a seat pitch apart the entire way, which
            // is a stronger statement than the convoy argument this replaces
            // and needs no argument about relative speeds at all.
            //
            // **How far back is the seat's own furniture's answer**, which is
            // why the metrics are gathered here and why they are the *station's*
            // where the character had one: an away-facing seat stands its desk
            // 8 px behind its occupant, and an exit that ignored it walked the
            // leaver up through its own workstation.
            // [`RoomLayout.upstageClearance(forSeat:metrics:)`]
            let exitMetrics = seatMetrics(desk: stationDesks[agent])
            let exit = seat.map { layout.upstageExit(forSeat: $0, metrics: exitMetrics) }
                ?? layout.upstageExit(
                    fromX: Double(character.position.x), metrics: exitMetrics)
            switch style {
            case let .report(anchorSeat) where seat != nil && seat != anchorSeat:
                let reporterSeat = seat!
                let side = layout.deliverySide(
                    anchorSeat: anchorSeat, reporterSeat: reporterSeat)
                // Same claim, same two beats: a leaver that reported in the same
                // frame earns the walk on the same terms as one that stays, and
                // is refused it on the same terms. `retire` gives the stretch
                // back at the end.
                let route = claimDeliveryRow(
                    for: character, seat: reporterSeat, anchorSeat: anchorSeat)
                character.reportAndDepart(
                    out: route.out,
                    facing: layout.deliveryFacing(side: side),
                    home: layout.homeRoute(forSeat: reporterSeat, fromY: route.deliversAtY),
                    thenExitAt: exit
                ) { [weak self, weak character] in
                    self?.retire(character)
                    self?.retireStation(for: agent)
                    self?.retireDeskObject(for: agent)
                }
            case .report, .walkOff:
                // No seat, or a self-report: nothing to walk to, so it just
                // leaves. A character caught **on the walkway**: mid-report
                // when the session ended: comes back up to its chair first, so
                // its exit is the one continuous ascent of its own column that
                // every other exit is. A leaver already *in* its chair gets no
                // leg at all: `homeRoute` reads `fromY` for exactly that, and
                // the 0.2 s a zero-length walk costs is 14 px of the gap a
                // refill climbing the same column is relying on.
                character.departOffScreen(
                    via: seat.map {
                        layout.homeRoute(
                            forSeat: $0, fromY: Double(character.position.y))
                    } ?? [],
                    to: exit
                ) { [weak self, weak character] in
                    self?.retire(character)
                    self?.retireStation(for: agent)
                    self?.retireDeskObject(for: agent)
                }
            }

        case let .setScale(scale):
            preferredScale = scale

        case let .setOverflow(count):
            setOverflow(count)
        }
    }

    // MARK: The overflow plate

    /// The plate that says how many agents the room has no seat for, or `nil`
    /// while it has never had to say anything.
    ///
    /// **Not a prop.** It is deliberately outside `propNodes`, so §6 rule 1's
    /// "zero prop-node rebuilds across an entire fixture replay" still means
    /// what it says: the room's furniture never changes, and this is not
    /// furniture: it is the room's caption on its own population, and it
    /// changes exactly when that population crosses the seat count.
    private var overflowNode: SKSpriteNode?
    private var overflowCount = 0

    /// How many agents the room is currently saying it cannot seat. Read-only.
    public var overflowShown: Int { overflowCount }

    /// The plate's box in scene coordinates, or `nil` when nothing is drawn.
    /// Read by tests: "is the caption on screen" is the only property that
    /// matters about it and it cannot be asked of a node's existence.
    public func overflowPlateBoxForTesting() -> (x: Double, y: Double,
                                                 width: Double, height: Double)? {
        guard let node = overflowNode, !node.isHidden else { return nil }
        return (Double(node.position.x - node.size.width / 2),
                Double(node.position.y),
                Double(node.size.width), Double(node.size.height))
    }

    private func setOverflow(_ count: Int) {
        let wanted = max(0, count)
        guard wanted != overflowCount else { return }
        overflowCount = wanted
        guard wanted > 0 else {
            overflowNode?.isHidden = true
            return
        }
        let bitmap = SceneBitmaps.overflowPlate(wanted)
        guard let texture = store.texture(bitmap: bitmap, key: "overflow:\(wanted)") else {
            overflowNode?.isHidden = true
            return
        }
        let node: SKSpriteNode
        if let existing = overflowNode {
            node = existing
        } else {
            node = SKSpriteNode()
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            // The nameplate band. It is lettering about the cast, so it belongs
            // where the cast's own lettering is: above every body and every
            // prop, which is what makes it legible against whatever a theme
            // stands behind it.
            node.zPosition = Character.Layer.nameplate
            world.addChild(node)
            overflowNode = node
        }
        node.texture = texture
        node.size = CGSize(width: bitmap.width, height: bitmap.height)
        node.isHidden = false
        positionOverflowPlate()
    }

    /// Puts the plate on its point, clamped into the camera's frame.
    ///
    /// The point (`RoomLayout.overflowPlatePosition`) is clear of every
    /// theme's props and inside the 720×400 panel by construction, so on the
    /// panel this app actually ships the clamp does nothing. It is here because
    /// a caption that is off screen is the same silence it exists to break, and
    /// `--render` and `--window` take a size from the command line.
    private func positionOverflowPlate() {
        guard let node = overflowNode, !node.isHidden else { return }
        let point = layout.overflowPlatePosition
        let half = CGPoint(x: size.width / 2, y: size.height / 2)
        let minX = camera_.position.x - half.x, maxX = camera_.position.x + half.x
        let minY = camera_.position.y - half.y, maxY = camera_.position.y + half.y
        let width = node.size.width, height = node.size.height
        let x = width >= maxX - minX
            ? camera_.position.x
            : min(max(CGFloat(point.x), minX + width / 2), maxX - width / 2)
        let y = height >= maxY - minY
            ? camera_.position.y - height / 2
            : min(max(CGFloat(point.y), minY), maxY - height)
        node.position = CGPoint(x: x.rounded(), y: y.rounded())
    }

    // MARK: The delivery row

    /// **Ask for the walk; take the in-place beat if the row is not free.**
    ///
    /// Returns the route the character should walk out along and the y it will
    /// be standing on when it delivers, which is what `homeRoute` needs to know
    /// whether the way back has a lateral leg in it.
    ///
    /// The claim is on `RoomLayout.deliveryCorridor(anchorSeat:reporterSeat:)`,
    /// every x the beat occupies, out and back, so a granted claim is a
    /// statement about where this character is at every instant it is on the
    /// row. Nothing here can make a report wait: the else-branch is a beat, not
    /// a retry. [I4]
    private func claimDeliveryRow(for character: Character, seat: Int, anchorSeat: Int)
    -> (out: [ScenePoint], deliversAtY: Double) {
        let corridor = layout.deliveryCorridor(anchorSeat: anchorSeat, reporterSeat: seat)
        let out = layout.deliveryRoute(anchorSeat: anchorSeat, reporterSeat: seat)
        // Twice the beat it is timing. The deadline is the reaper of last resort
        //: the normal release is the beat finishing, and the frame loop drops a
        // claim whose character has stopped walking, so it can afford to be
        // generous, and being generous is what stops it firing on a slow frame
        // and handing a live corridor to a second reporter.
        let budget = 2 * (beatSeconds(out: out, seat: seat) + deliverBeatSeconds)
        // A second report for one character replaces its own beat rather than
        // competing with it: `Character.run` restarts the script from wherever
        // it is standing, so the old corridor is not being walked any more.
        releaseDeliveryRow(heldBy: character)
        let id = nextDeliveryBeatID
        nextDeliveryBeatID += 1
        guard deliveryFloor.claim(id: id, corridor: corridor, budget: budget) else {
            return (layout.inPlaceDeliveryRoute(reporterSeat: seat), layout.aisleY)
        }
        deliveryClaimant[id] = (character, seat)
        return (out, layout.deliveryRowY)
    }

    private func releaseDeliveryRow(heldBy character: Character) {
        for (id, held) in deliveryClaimant where held.character === character {
            deliveryFloor.release(id: id)
            deliveryClaimant[id] = nil
        }
    }

    /// How long the whole round trip takes at the walk speed, from the seat out
    /// and back again. `Character.duration` is the same arithmetic the script
    /// itself runs on, including its 0.2 s floor per leg, so this is the beat's
    /// real length rather than an estimate of it.
    private func beatSeconds(out: [ScenePoint], seat: Int) -> TimeInterval {
        var total: TimeInterval = 0
        var from = layout.seatPosition(seat)
        for point in out {
            total += Character.duration(from: from, to: point)
            from = point
        }
        for point in layout.homeRoute(forSeat: seat, fromY: from.y) {
            total += Character.duration(from: from, to: point)
            from = point
        }
        return total
    }

    /// The longest `deliver` any variant in the manifest plays, in seconds. Read
    /// off the manifest rather than written down, so a re-cut animation moves the
    /// deadline with it.
    private var deliverBeatSeconds: TimeInterval {
        var longest: TimeInterval = 0
        for variant in store.manifest.characters.variants.values {
            guard let animation = variant.animation(.deliver) else { continue }
            let frames = animation.frames.values.map(\.count).max() ?? 0
            longest = max(longest, Double(frames) / max(1, animation.fps))
        }
        return longest
    }

    /// Gives back every stretch of the delivery row whose character has stopped
    /// walking (the condition itself rather than a proxy for it) and then
    /// anything held past its budget.
    ///
    /// A character that has finished its script is standing still, and a claim
    /// held by a character standing still is a claim on floor nobody is using. A
    /// character that was retired mid-frame is off the scene graph and has no
    /// script either. Both are the same test.
    private func sweepDeliveryFloor(at time: TimeInterval) {
        for (id, held) in deliveryClaimant where !held.character.isScripted {
            deliveryFloor.release(id: id)
            deliveryClaimant[id] = nil
        }
        for id in deliveryFloor.reap(at: time) { deliveryClaimant[id] = nil }
    }

    /// The seats of the characters currently holding a stretch of the delivery
    /// row. Read-only, for the tests that check the claim is given back,
    /// nothing in the scene reads it and no picture depends on it.
    var deliveryRowHoldersForTesting: [Int] {
        deliveryFloor.occupiedIDs.compactMap { deliveryClaimant[$0]?.seat }.sorted()
    }

    private func retire(_ character: Character?) {
        guard let character else { return }
        animated.removeAll { $0 === character }
        character.removeFromParent()
    }

    // MARK: Clock

    /// SpriteKit calls this from the view's render loop. The offscreen harness
    /// calls `advance(to:)` directly with a simulated clock: one animation
    /// engine, two drivers, identical output.
    public override func update(_ currentTime: TimeInterval) {
        advance(to: currentTime)
    }

    public func advance(to time: TimeInterval) {
        for character in animated { character.advance(to: time) }
        // After the characters, so a beat that ended this frame gives its stretch
        // of the delivery row back this frame rather than next one.
        sweepDeliveryFloor(at: time)
        // **The only place a prop's picture is ever changed after the room is
        // built, and it is handed the clock and nothing else.** [ADR-002 §14b]
        // `apply(_:)` is where every consequence of a delta reaches this scene,
        // and it does not appear in this loop's call graph: a prop cannot learn
        // that an agent is busy, because there is no path by which it could.
        for prop in propAnimations { prop.advance(to: time) }
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
        // **Asked of `Character`, not recomputed here.** It used to be
        // `canvasHeight − headTop + 1` *plus the badge canvas*, which was the
        // slot's arithmetic copied into the camera: true only while the slot
        // hung above the head. The slot is beside the head now and its top edge
        // is where its bottom edge was, so the copy would have gone on reserving
        // 34 px of empty air over every character and the band would never have
        // fallen. The minimum `head_top_px` over the cast is the highest head and
        // therefore the highest slot.
        let badgeTop = Character.badgeSlotTopAboveFeet(
            canvasHeight: manifest.characters.canvas.height, headTopPx: headTop)
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

    /// **The highest pixel the room's own dressing reaches**, measured off the
    /// manifest's content boxes rather than assumed: every decoration point plus
    /// the height of the prop that stands on it.
    ///
    /// It is theme-dependent by construction and the spread is large: the
    /// `office` chart board tops out at 270 and `broadcast`'s softbox at 304,
    /// which is exactly why it is measured here instead of written down. The
    /// floor is `wallBaseY`, so a manifest that binds no backdrop at all still
    /// gets the wall line rather than a nonsense number.
    var decorationTopY: Double {
        // **Under a plan the room has a top edge, and it is the thing to keep in
        // frame.** Without one the wall runs to the top of the overscan and
        // there is nothing up there to aim at, which is why this used to start
        // at the wall line. A plan's topmost band carries the 12 px floor-plan
        // line that says where the building stops, and a frame that crops it
        // turns the plan back into a backcloth. [ADR-007 §5]
        var top = layout.plan.topRow()
            .map { Double(($0 + 1) * layout.tile) } ?? layout.wallBaseY
        // **Guarded on the same condition `buildRoom` guards it on**, because
        // the camera may only measure what the room actually draws. A
        // hand-placed room draws no decoration lattice, and a camera that
        // measured one would be aiming at props that are not there.
        //
        // It costs nothing *today*: the shipped composition stands its boards
        // on `wallBaseY`, which is exactly where the lattice stood them, so the
        // maximum is identical either way. It would start lying the moment a
        // composition moved a board off that line, which is precisely the kind
        // of defect that survives because it is invisible in the still that
        // introduced it.
        if store.room.plan.dressing.isEmpty {
            for placement in Self.decorationPlacements(layout: layout) {
                guard let prop = store.room.prop(placement.role) else { continue }
                top = max(top, placement.point.y + Double(prop.contentBox.height))
            }
        }
        // **The scenery counts, and the `wall` band is usually what decides it.**
        // A picture two tiles up the wall face is the highest thing the room
        // draws in five of six themes, and a camera that measured only the
        // backdrops would aim below it and crop it, which is the exact defect
        // this accessor was written against, one band further up. It costs a
        // little of the dead floor under the room and nothing else: the aim is
        // clamped by the slack the scale left, and at `2x` and `3x` that clamp
        // binds first, so the close views are unmoved.
        for placement in Self.dressingPlacements(store: store) {
            top = max(top, placement.point.y + Double(placement.prop.contentBox.height))
        }
        if store.room.plan.dressing.isEmpty {
            for band in RoomLayout.SceneryBand.allCases {
                let props = store.room.scenery(band)
                guard !props.isEmpty else { continue }
                for (index, point) in layout.sceneryAnchors(band).enumerated() {
                    top = max(top, point.y + Double(props[index % props.count].contentBox.height))
                }
            }
        }
        return top
    }

    /// Where to point the camera vertically.
    ///
    /// The band has to *fit*, and once it does the only question left is where
    /// to spend what the scale did not use. It is spent by **centring the strip
    /// the room actually draws**: from the lowest pixel any character can put on
    /// screen (`band.bottom`, the underside of a walkway character's plate) to
    /// the top of the tallest backdrop standing on the wall line,
    /// `decorationTopY`. The result is then clamped by the slack the scale
    /// really left, which is zero at the tightest fitting scale, so the aim can
    /// never cost a cropped nameplate or a cropped badge. Nothing about it
    /// depends on who is on screen, so the camera does not jump when somebody
    /// steps out of a chair.
    ///
    /// **The top term is new and it is the whole of this fix.** The aim used to
    /// be the midpoint of the seated plate and `band.top`: the top of the
    /// *badge slot*, which is not the top of anything the room draws: `office`'s
    /// chart board stands 91 px above it and `broadcast`'s softbox 125 px. So
    /// the camera aimed at a line with nothing on it, and every pixel of surplus
    /// it declined to spend upward went underneath the room instead. On the
    /// shipped 720×400 panel at `1x` that was **131 px of bare floor below the
    /// lowest nameplate (a third of the frame**) of which 90 px was not even
    /// floor the room owns, but `drawnRows` overscan: tiles painted solely so
    /// that no void shows. A frame whose bottom quarter is overscan is the tell
    /// that its aim point is wrong.
    ///
    /// It also decided how much wall you saw **by accident of theme**, since the
    /// aim was a constant and the backdrops are not: the same frame that left
    /// `office`'s 46 px board 36 px of headroom left `broadcast`'s 80 px softbox
    /// **2 px**, and `library`'s 72 px board 10. Measuring the thing the camera
    /// is trying to clear is what makes that uniform.
    ///
    /// **It is a no-op wherever the band is what binds, so `2x` is
    /// pixel-identical either way.** A `2x` view of this panel has 100 px of
    /// half-height against a band whose top is 178 px above its bottom, so
    /// `highest` lands below any aim this expression can produce and the clamp
    /// decides alone. The frame moves only at `1x`, which is the only place the
    /// slack being redistributed exists. That is what makes "the room must not
    /// look emptier at `2x`" true by construction rather than by measurement,
    /// and `theCloseViewIsUnmovedByWhereTheCameraPrefersToAim` pins it.
    ///
    /// The old aim's own history is worth keeping, because it is the same
    /// mistake one step earlier: it once reconstructed the seated plate's bottom
    /// by subtracting the band's depth from the seat row, which is the same
    /// number only while the band's bottom is exactly one plate below the
    /// walkway. The delivery rows made that false and the frame drifted down
    /// over three tiles of empty floor with no test able to see it, because the
    /// arithmetic still agreed with itself. Both times the repair was to measure
    /// the thing rather than to infer it from a neighbour.
    ///
    /// **What this does not fix, stated rather than implied.** At `1x` the panel
    /// is taller than the room: 400 px against a drawn picture that is 269 px
    /// deep in `office` and 303 in `broadcast`. Aiming redistributes that
    /// surplus; it cannot remove it, and the residual is ~66 px of wall above
    /// the boards and ~97 px of floor below the seated plates. Only a shorter
    /// panel or a taller room removes it, and `notes.md` records why neither was
    /// done here: chiefly that the panel's floor is twice the content band, so
    /// the whole 44 px it could give back buys 22 px of foreground.
    func cameraY(band: (bottom: Double, top: Double), sceneHeight: Double) -> Double {
        let half = sceneHeight / 2
        let preferred = (band.bottom + max(band.top, decorationTopY)) / 2
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
        // integer on both axes: no fractional resampling anywhere. [I6]
        let sceneSize = CGSize(
            width: max(1, Double(viewport.width) / Double(scale)),
            height: max(1, Double(viewport.height) / Double(scale)))
        if size != sceneSize { size = sceneSize }

        let centreX = (span.minX + span.maxX) / 2
        camera_.position = CGPoint(
            x: (centreX).rounded(),
            y: cameraY(band: band, sceneHeight: sceneSize.height).rounded())
        // The plate's clamp is measured against the frame, so it has to be
        // re-applied whenever the frame moves.
        positionOverflowPlate()
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

/// **Where the seated cast's head is, measured off the sit frames.**
///
/// Nothing in `assets/manifest.json` answers this. `head_top_px` is the crown
/// and there is no matching datum for the chin, so the number that decides
/// whether a desk covers a face had to be either invented or measured, and this
/// measures it. The sit frames are on disk, the scene already opens them to make
/// textures, and reading their alpha is the same kind of act as reading a prop's
/// `content_box`: a placement decided by the art rather than by a constant.
///
/// **It answers a profile, not a number.** A surface standing at a seat covers
/// everything from the floor up to its own height, but only from its near edge
/// rightward, and a seated head is not a rectangle. The hair is the widest part
/// of the sprite and reaches `+13` to `+15` from the seat; the chin is the
/// narrowest and reaches `+9`. So "how tall may a surface be" has a different
/// answer at every x, and collapsing it to one number costs four themes their
/// near-edge cue for a defect only two of them had.
public struct SeatedHead: Sendable, Hashable {

    public let canvasWidth: Int
    public let canvasHeight: Int
    /// How many frames went into it. Pinned by a test, because a measurement
    /// taken over zero frames is indistinguishable in its output from a
    /// measurement taken over the cast.
    public let framesMeasured: Int
    /// How many head pixels were found, for the same reason.
    public let headPixelCount: Int

    /// `suffixClearance[c]`: the tallest a surface whose near edge falls at or
    /// left of canvas column `c` may be without covering a head pixel. Suffix-
    /// minimised, so it is monotone: standing further right can only ever be
    /// safer.
    private let suffixClearance: [Int]

    /// `nil` when there is nothing to measure: an empty cast, or art that will
    /// not load. The caller answers that with the conservative branch rather than
    /// with a guess.
    public init?(frames: [Bitmap]) {
        guard let first = frames.first, first.width > 0, first.height > 0 else { return nil }
        let width = first.width, height = first.height
        var perColumn = [Int](repeating: Int.max, count: width)
        var pixels = 0
        var measured = 0
        for frame in frames where frame.width == width && frame.height == height {
            guard let neck = Self.neckRow(of: frame) else { continue }
            measured += 1
            for y in 0..<min(neck, height) {
                for x in 0..<width where frame.at(x, y).a > 0 {
                    pixels += 1
                    // The pixel's own bottom edge, in scene pixels above the feet:
                    // a surface exactly this tall touches it without covering it.
                    perColumn[x] = min(perColumn[x], height - 1 - y)
                }
            }
        }
        guard measured > 0, pixels > 0 else { return nil }
        var suffix = perColumn
        for index in stride(from: width - 2, through: 0, by: -1) {
            suffix[index] = min(suffix[index], suffix[index + 1])
        }
        self.canvasWidth = width
        self.canvasHeight = height
        self.framesMeasured = measured
        self.headPixelCount = pixels
        self.suffixClearance = suffix
    }

    /// How tall a surface whose near edge falls `nearEdgeX` scene pixels to the
    /// right of the seat may stand before it covers a head pixel.
    ///
    /// The column is taken with `floor`, so a near edge landing inside a column
    /// counts as covering the whole of it. Partial coverage of a face pixel is
    /// coverage.
    public func clearance(nearEdgeX: Double) -> Int {
        let column = Int((nearEdgeX + Double(canvasWidth) / 2).rounded(.down))
        if column < 0 { return suffixClearance[0] }
        if column >= canvasWidth { return canvasHeight }
        return suffixClearance[column] == Int.max ? canvasHeight : suffixClearance[column]
    }

    /// **The first row of the sprite that is not head**, from the silhouette
    /// alone.
    ///
    /// A seated character in this art is a head over a torso, and between them
    /// the outline pinches: the widest rows are the hair, and the narrowest rows
    /// below the hair are the neck and shoulders. So the neck is the first row of
    /// the narrowest run below the widest row, and everything above it is head.
    ///
    /// Measured on the shipped cast this lands at rows **46, 48, 46, 46, 46, 48**
    /// for variants 06, 07, 09, 10, 17 and 19: chin height 16–18 px above the
    /// feet. Two independent checks agree with it: drawn over the sprites the
    /// line sits on the jaw, and every one of the twelve shipped costumes: an
    /// outfit, which clothes a torso and not a head: begins at row 46, 47 or 48.
    ///
    /// `nil` for a blank frame. A frame whose widest row is its last is answered
    /// with "all head", which is the conservative reading of art this cannot
    /// interpret.
    public static func neckRow(of frame: Bitmap) -> Int? {
        var counts = [Int](repeating: 0, count: frame.height)
        for y in 0..<frame.height {
            var run = 0
            for x in 0..<frame.width where frame.at(x, y).a > 0 { run += 1 }
            counts[y] = run
        }
        let inked = counts.indices.filter { counts[$0] > 0 }
        guard let lastInk = inked.last, let widest = counts.max(), widest > 0 else { return nil }
        guard let lastWidest = counts.indices.last(where: { counts[$0] == widest })
        else { return nil }
        guard lastWidest < lastInk else { return lastInk + 1 }
        var row = lastWidest
        while row + 1 <= lastInk, counts[row + 1] <= counts[row] { row += 1 }
        let narrowest = counts[row]
        while row - 1 > lastWidest, counts[row - 1] == narrowest { row -= 1 }
        return row
    }
}
