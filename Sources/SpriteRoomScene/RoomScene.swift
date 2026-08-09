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
        //   entire right half — and a role chosen on `seat % 2` put all four
        //   backdrops on the left and all three accents on the right. The room
        //   read as two different rooms stitched at the centre line. Sorting the
        //   positions and alternating along **x** gives the same four and three
        //   — so the motion budget is unchanged, which is not an accident but
        //   the constraint this placement was designed against [ADR-002 §14b] —
        //   spread across the whole width.
        // - *One row* is what the maintainer saw as "the wall furniture sits in
        //   one strip". The backdrops now stand **against the wall**, which is
        //   where a backdrop belongs and which is what puts something in the
        //   band of the panel that was flat wall; the accents stand a tile
        //   behind the back seat row. Alternating the two along x makes the
        //   depth zigzag, so the upstage half of the room has a near edge and a
        //   far edge rather than a single line.
        //
        // I7's standing instruction — a background detail competes with the
        // characters at exactly the zoom where they are hardest to read — is
        // still what keeps this thin: two kinds of object, seven of them, both
        // through the same desaturating import pass as the floor, and every one
        // of them upstage of both seat rows.
        let backdropRowY = layout.wallBaseY
        let accentRowY = layout.backSeatRowY + Double(tile)
        let propColumns = (0..<layout.seatCapacity)
            .map { Double(layout.seatColumn($0) * tile + tile / 2) + Double(tile) * 1.5 }
            .filter { $0 < layout.width }
            .sorted()
        for (index, x) in propColumns.enumerated() {
            let isBackdrop = index.isMultiple(of: 2)
            place(
                role: isBackdrop ? Self.backdropRole : Self.accentRole,
                at: ScenePoint(x: x, y: isBackdrop ? backdropRowY : accentRowY))
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
            guard let node = place(
                role: Self.seatRole, at: layout.seatPosition(seat), depthBias: seatDepthBias),
                  let path = store.room.prop(Self.seatRole)?.file else { continue }
            emptySeatFurniture[seat, default: []].append(
                SeatFurniture(node: node, path: path))
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
            if let node = place(
                role: Self.surfaceRole, at: position, depthBias: surfaceDepthBias),
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
            node.zPosition = Character.Layer.rowDepth(position.y) + surfaceDepthBias
            world.addChild(node)
            // The placeholder has no manifest path, and saying so is the point:
            // nothing in the manifest is called a desk here. It is still a piece
            // of this seat's furniture, so a station still hides it.
            emptySeatFurniture[seat, default: []].append(
                SeatFurniture(node: node, path: ""))
        }
    }

    // MARK: Stations [ADR-002 §4, §8 items 4 and 6]

    /// The chair sits a hair behind the body; the desk a half-row in front of
    /// it. Named once because the station path has to reproduce both exactly —
    /// a station whose desk sorted differently from the theme's desk would
    /// change whether the near edge crosses the body, which is the one cue at
    /// 32 px that a character is sitting *at* a desk rather than beside one.
    private let seatDepthBias: CGFloat = -0.25
    private let surfaceDepthBias: CGFloat = 0.5

    /// The theme-wide desk and chair drawn at each seat at build time.
    ///
    /// They are the **empty desk**: an office has them, and drawing furniture
    /// only when somebody arrives would make the room rearrange itself as agents
    /// come and go. When a character with a station sits down, its seat's pair
    /// is hidden and the station's own furniture is drawn in their place; when
    /// it leaves, they come back. The nodes are never destroyed, which is what
    /// keeps `noPropNodeIsEverRebuiltAcrossAnyFixtureReplay` — §6 rule 1 made
    /// mechanical — true through every arrival and departure in every fixture.
    private var emptySeatFurniture: [Int: [SeatFurniture]] = [:]

    /// One piece of furniture at a seat, with the manifest path behind it.
    ///
    /// The path is carried rather than recoverable, because node identity says a
    /// desk was *placed* and says nothing about which picture — and "a desk was
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
    /// six themes, every one placed, every one drawn — and the same picture at
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
        draw(station.chair, at: layout.seatPosition(seat), depthBias: seatDepthBias)
        draw(station.desk, at: layout.deskPosition(seat), depthBias: surfaceDepthBias)
        if let prop = station.prop {
            draw(prop, at: layout.stationPropPosition(seat), depthBias: seatDepthBias)
        }

        stationFurniture[agent] = placed
        stationSeat[agent] = seat
    }

    /// Takes a character's station down and puts the empty desk back.
    ///
    /// Called when the node is actually retired rather than when the exit intent
    /// arrives, so a character walking out is still walking away from its own
    /// desk for the whole of the walk. The seat may already have been reclaimed
    /// by then — a seat is free the instant its occupant starts leaving — so the
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
    /// picture. Two themes place the same number of props at the same points —
    /// that is the layout being theme-independent, which is a required property
    /// — so a test that compares only positions and counts cannot tell a themed
    /// room from a room that ignored the theme id. This is what it compares
    /// instead, and it is the manifest's own string rather than a texture, so
    /// two scenes with two `TextureStore`s can be compared at all.
    var propArtForTesting: [String] { propPaths }

    private var propNodes: [SKSpriteNode] = []
    private var propPaths: [String] = []

    /// The props that idle on their own loop. [ADR-002 §14b]
    ///
    /// One per placed node, so four copies of an animated `board` swing
    /// together — they are handed the same clock, so they are in phase by
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
        guard let prop = store.room.prop(role),
              let node = place(prop: prop, at: point, depthBias: depthBias) else { return nil }
        propNodes.append(node)
        propPaths.append(prop.file)

        // A prop that idles. `prop.file` is frame 0 and is already on the node,
        // so a manifest without this key — or with art that will not load —
        // draws exactly the still prop it always did.
        //
        // **Only room props idle, and stations deliberately do not.** The motion
        // budget is I7 on the time axis and it is a budget on moving pixels per
        // second *summed over every copy the room draws* — which the room knows
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
            // once — there is no code path that could redraw it, which is §6
            // rule 2 enforced by there being nothing to enforce.
            placeStation(station, for: agent, at: seat)
            // **Straight up its own column, from its own ring's delivery row.**
            // See `RoomLayout.entranceRoute(forSeat:)`: the walk-in used to run
            // one seat pitch sideways along the aisle, which is the one row
            // every character steps through, and it started on the *next ring's
            // own station*. A seat vacated and refilled while that neighbour was
            // mid-report put the newcomer on top of it — measured at −25.6 px,
            // an overlap and not a near miss. Entering up the column is the exit
            // reversed, so it is closed by the same construction and needs no
            // argument of its own.
            character.enter(along: layout.entranceRoute(forSeat: seat))

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
                ) { [weak self, weak character] in
                    self?.retire(character)
                    self?.retireStation(for: agent)
                }
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
                ) { [weak self, weak character] in
                    self?.retire(character)
                    self?.retireStation(for: agent)
                }
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
        // **The only place a prop's picture is ever changed after the room is
        // built, and it is handed the clock and nothing else.** [ADR-002 §14b]
        // `apply(_:)` is where every consequence of a delta reaches this scene,
        // and it does not appear in this loop's call graph — a prop cannot learn
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
