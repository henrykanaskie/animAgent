import Foundation
import SpriteKit
import Testing
@testable import SpriteRoomScene

/// **The room's dressing, and the four rules it may never break.** [M8 Phase 2b]
///
/// `scenery` exists because the shipped room bound four roles and left roughly
/// 335 processed singles unused, and the maintainer put it beside
/// `scripts/compose-scene.py`'s composed scenes — 88 props and a floor plan —
/// and asked for the second. The mechanism is one sentence: the manifest says
/// *what* and *which depth band*, `RoomLayout.sceneryAnchors(_:)` says *where*.
///
/// What this suite is for is the other half — that adding twenty props to every
/// theme did not cost the room any of the properties it was already holding.
/// The four that matter, and each is a rule from `docs/06-SET-BUILDING.md` §8
/// restated in this room's own terms:
///
/// | | |
/// |---|---|
/// | R2/R3 | a prop stands on floor nobody walks on — never a seat column, never the delivery row |
/// | R4 | no two props share a floor space |
/// | R7 | nothing is drawn and then buried by what is painted over it |
/// | I1 | scenery is furniture: it is a function of the theme and of nothing else |
///
/// The first is the one with teeth. Every route in this room is either straight
/// up a character's own seat column — `entranceRoute`, `homeRoute`,
/// `upstageExit`, the first two legs of `deliveryRoute` — or lateral on
/// `deliveryRowY`, and a prop on either of those is a prop somebody walks
/// through. That is checked here against `RoomLayout` rather than against a
/// transcription of it.
@MainActor
@Suite struct SceneryContractTests {

    /// Every scenery prop the room places, as `(band, box in scene pixels)`.
    ///
    /// Scene pixels, y-up, from the same two things the scene uses: the anchor
    /// and the measured content box. It is computed rather than read off the
    /// nodes so that the arithmetic under test is the manifest's and the
    /// layout's, not SpriteKit's.
    static func placements(_ room: Manifest.Room, layout: RoomLayout)
    -> [(band: RoomLayout.SceneryBand, x: ClosedRange<Double>, y: ClosedRange<Double>,
         file: String)] {
        var out: [(RoomLayout.SceneryBand, ClosedRange<Double>, ClosedRange<Double>, String)] = []
        for band in RoomLayout.SceneryBand.allCases {
            let props = room.scenery(band)
            guard !props.isEmpty else { continue }
            for (index, point) in layout.sceneryAnchors(band).enumerated() {
                let prop = props[index % props.count]
                let half = Double(prop.contentBox.width) / 2
                out.append((band,
                            (point.x - half)...(point.x + half),
                            point.y...(point.y + Double(prop.contentBox.height)),
                            prop.file))
            }
        }
        return out
    }

    /// The two decoration roles' boxes, same shape. They are the fixed point the
    /// scenery bands were laid out around.
    static func decoration(_ room: Manifest.Room, layout: RoomLayout)
    -> [(x: ClosedRange<Double>, y: ClosedRange<Double>, role: String)] {
        RoomScene.decorationPlacements(layout: layout).compactMap { placement in
            guard let prop = room.prop(placement.role) else { return nil }
            let half = Double(prop.contentBox.width) / 2
            return ((placement.point.x - half)...(placement.point.x + half),
                    placement.point.y...(placement.point.y + Double(prop.contentBox.height)),
                    placement.role)
        }
    }

    static func rooms(_ manifest: Manifest) -> [(String, Manifest.Room)] {
        [("manifest.room", manifest.room)]
            + manifest.themes.orderedIDs.compactMap { id in
                manifest.themes.theme(id).map { (id, $0.room) }
            }
    }

    // MARK: The routes are sacred

    /// **No prop that stands on a floor stands in a seat column.**
    ///
    /// A seat column is a corridor from the delivery row to the wall line: a
    /// character arrives up it, reports down and up it, and leaves up it. The
    /// half-width checked is 16 px, the character canvas, which is wider than
    /// any body's ink — a clearance argued against the canvas cannot be undone
    /// by a variant with broader shoulders.
    ///
    /// The `wall` band is exempt **and states why in the assertion rather than
    /// in a skip**: it hangs two tiles up the wall face, above `wallBaseY`,
    /// which is where a leaver's feet stop and where `upstageExit` ends. Its own
    /// clearance is the test below.
    @Test func noSceneryStandsInASeatColumn() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let columns = (0..<layout.seatCapacity).map { layout.seatPosition($0).x }
        for (name, room) in Self.rooms(manifest) {
            for placement in Self.placements(room, layout: layout) {
                if placement.band == .wall {
                    #expect(placement.y.lowerBound > layout.wallBaseY, Comment(rawValue:
                        "\(name): a `wall` prop is the one thing allowed in a seat"
                        + " column, and only because it hangs above \(layout.wallBaseY)"
                        + " where a leaver's feet stop — this one starts at"
                        + " \(placement.y.lowerBound)"))
                    continue
                }
                for column in columns {
                    let clear = placement.x.upperBound <= column - 16
                        || placement.x.lowerBound >= column + 16
                    #expect(clear, Comment(rawValue:
                        "\(name): \(placement.band.rawValue) prop \(placement.file)"
                        + " spans x \(placement.x) and seat column \(column) runs"
                        + " through it"))
                }
            }
        }
    }

    /// **Nothing is on the delivery row, or on the walkway, or on a seat row.**
    ///
    /// `deliveryRowY` is the one row a character travels *along* and the whole
    /// of its safety is that nothing else is ever on it. The walkway and the two
    /// seat rows are the rest of `standingRows`, and the rule the foreground
    /// plant row was replaced with — nothing decorative nearer the camera than
    /// the seat row — subsumes all four: the nearest band is a full tile upstage
    /// of the furthest-upstage seat.
    @Test func noSceneryIsOnARowACharacterStandsOn() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        for (name, room) in Self.rooms(manifest) {
            for band in RoomLayout.SceneryBand.allCases {
                for point in layout.sceneryAnchors(band) where !room.scenery(band).isEmpty {
                    #expect(point.y > layout.backSeatRowY, Comment(rawValue:
                        "\(name): \(band.rawValue) stands at y=\(point.y), which is"
                        + " level with or nearer the camera than the back seat row"))
                    #expect(!layout.standingRows.contains(point.y), Comment(rawValue:
                        "\(name): \(band.rawValue) stands on \(point.y), a row"
                        + " characters walk on"))
                }
            }
        }
    }

    /// **The width bound is what keeps a column clear, at its own limit.**
    ///
    /// The test above measures the art; this measures the *rule*, by standing a
    /// prop of the maximum admissible width on every anchor and asking the same
    /// question. It is the difference between "the twenty props that ship are
    /// clear" and "the bound cannot be satisfied by a prop that is not", and the
    /// second is what a future art swap actually rests on.
    ///
    /// **The desk and the station-prop lanes are deliberately not in it.** A
    /// station occupies 92 px of its 96 px pitch — desk at `x+12…x+44`, adjacent
    /// prop at `x−48…x−16` — so on a *seat row* there is no room for anything
    /// and scenery never claims any. It is `noSceneryIsOnARowACharacterStandsOn`
    /// that keeps it off those rows, and this that keeps it out of the columns
    /// crossing them.
    @Test func theWidthBoundKeepsEveryColumnClearAtItsOwnLimit() throws {
        let layout = RoomLayout()
        for band in RoomLayout.SceneryBand.allCases where band != .wall {
            let bound = Double(layout.sceneryInkBound(band).width) / 2
            for x in layout.sceneryAnchors(band).map(\.x) {
                for seat in 0..<layout.seatCapacity {
                    let column = layout.seatPosition(seat).x
                    let clear = x + bound <= column - 16 || x - bound >= column + 16
                    #expect(clear, Comment(rawValue:
                        "\(band.rawValue) column \(x) at its full \(bound * 2) px"
                        + " reaches into seat column \(column)"))
                }
            }
        }
    }

    // MARK: Nothing buries anything

    /// **No two props on the same row overlap.** [R4]
    ///
    /// Props on *different* rows may overlap and routinely do — that is what a
    /// 3/4 projection is, and a filing cabinet standing in front of a chart
    /// board is a room rather than a defect. Two props on one row cannot: they
    /// are at the same depth, so which one wins is a tie broken by draw order
    /// and the loser is simply gone. Every scenery prop is compared with every
    /// other and with both decoration roles.
    @Test func noTwoPropsOnOneRowOverlap() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        for (name, room) in Self.rooms(manifest) {
            let all = Self.placements(room, layout: layout)
                .map { (y: $0.y.lowerBound, x: $0.x, what: $0.file) }
                + Self.decoration(room, layout: layout)
                .map { (y: $0.y.lowerBound, x: $0.x, what: $0.role) }
            for i in all.indices {
                for j in all.indices where j > i && all[i].y == all[j].y {
                    let clear = all[i].x.upperBound <= all[j].x.lowerBound
                        || all[j].x.upperBound <= all[i].x.lowerBound
                    #expect(clear, Comment(rawValue:
                        "\(name): \(all[i].what) and \(all[j].what) both stand on"
                        + " y=\(all[i].y) and overlap in x"))
                }
            }
        }
    }

    /// **A wall prop never intersects a backdrop.** [R7]
    ///
    /// The wall band is the far plane, so anything drawn over it is drawn over
    /// it completely. It sits in the seat columns and the backdrops sit half a
    /// pitch away, which separates them in x for every theme — except that three
    /// themes bind a backdrop taller than the two tiles of wall this band hangs
    /// at, and for those the clearance has to be real rather than assumed. It
    /// is: the three are 38, 32 and 30 px wide against a 96 px pitch.
    ///
    /// Asserted as *box intersection* rather than as a width bound, because the
    /// width bound alone does not carry it — a 56 px wall prop beside
    /// `broadcast`'s 80 px softbox clears by 1 px, and it is the actual art that
    /// says whether that case exists.
    @Test func noWallPropIntersectsABackdrop() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        for (name, room) in Self.rooms(manifest) {
            let decoration = Self.decoration(room, layout: layout)
            for wall in Self.placements(room, layout: layout) where wall.band == .wall {
                for other in decoration {
                    let clear = wall.x.upperBound <= other.x.lowerBound
                        || other.x.upperBound <= wall.x.lowerBound
                        || wall.y.upperBound <= other.y.lowerBound
                        || other.y.upperBound <= wall.y.lowerBound
                    #expect(clear, Comment(rawValue:
                        "\(name): wall prop \(wall.file) at x\(wall.x) y\(wall.y)"
                        + " intersects the \(other.role) at x\(other.x) y\(other.y)"))
                }
            }
        }
    }

    /// **A prop never intersects the overflow plate.**
    ///
    /// The plate is the room saying how many agents it has no seat for, and a
    /// caption drawn over furniture is a caption that cannot be read. Its column
    /// is excluded from the `wall_line` band by construction
    /// [`RoomLayout.sceneryAnchors(_:)`]; this is the check on everything else,
    /// including the wall band two tiles above it.
    @Test func noSceneryIntersectsTheOverflowPlate() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let point = layout.overflowPlatePosition
        let half = Double(SceneBitmaps.maximumNameplateWidth) / 2
        let plateX = (point.x - half)...(point.x + half)
        let plateY = point.y...(point.y + Double(SceneBitmaps.maximumNameplateHeight))
        for (name, room) in Self.rooms(manifest) {
            for placement in Self.placements(room, layout: layout) {
                let clear = placement.x.upperBound <= plateX.lowerBound
                    || plateX.upperBound <= placement.x.lowerBound
                    || placement.y.upperBound <= plateY.lowerBound
                    || plateY.upperBound <= placement.y.lowerBound
                #expect(clear, Comment(rawValue:
                    "\(name): \(placement.band.rawValue) prop \(placement.file)"
                    + " stands where the overflow plate hangs"))
            }
        }
    }

    /// **Every declared prop fits the band it declares.**
    ///
    /// The bounds are `RoomLayout.sceneryInkBound(_:)`'s, and they are the two
    /// arguments above stated as sizes: width is what keeps a prop out of a seat
    /// column, height is what stops it burying the prop one row upstage of it.
    /// Asked of the shipped manifest, so a wrong index in
    /// `scripts/process-assets.py` fails the suite rather than the eye — which
    /// is what `docs/06-SET-BUILDING.md` §4 asks for, since a catalogue name is
    /// a family of pieces and the ink is how the piece is chosen.
    @Test func everyDeclaredSceneryPropFitsItsBand() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        for (name, room) in Self.rooms(manifest) {
            for entry in room.scenery {
                let bound = layout.sceneryInkBound(entry.band)
                #expect(entry.prop.contentBox.width <= bound.width, Comment(rawValue:
                    "\(name): \(entry.prop.file) is \(entry.prop.contentBox.width) px"
                    + " wide in the \(entry.band.rawValue) band, over \(bound.width)"))
                #expect(entry.prop.contentBox.height <= bound.height, Comment(rawValue:
                    "\(name): \(entry.prop.file) is \(entry.prop.contentBox.height) px"
                    + " tall in the \(entry.band.rawValue) band, over \(bound.height)"))
            }
        }
    }

    // MARK: It is furniture

    /// **No scenery prop animates.**
    ///
    /// The motion budget is priced on `props.roles` — `scripts/lint-palette.py`
    /// multiplies a role's measured pixels-per-second by the copies the room
    /// draws, and that census counts the four roles and nothing else. A scenery
    /// prop that carried an `animation` would be motion the budget never saw,
    /// which is I7 on the time axis failing silently. One animated prop, in
    /// `board`, is the whole allowance. [ADR-002 §14b]
    @Test func noSceneryPropAnimates() throws {
        let manifest = try SceneFixtures.manifest()
        for (name, room) in Self.rooms(manifest) {
            for entry in room.scenery {
                #expect(entry.prop.animation == nil, Comment(rawValue:
                    "\(name): scenery prop \(entry.prop.file) declares an animation,"
                    + " which the motion budget does not price"))
            }
        }
    }

    /// **Every theme dresses every band**, so the room's geometry does not
    /// change with the theme.
    ///
    /// `ThemeSceneTests.changingTheThemeRedressesTheRoomAndMovesNoCharacter`
    /// asserts that two themes put props at exactly the same points, which is
    /// only true while every theme fills every band. A theme that declared no
    /// `mid_floor` would draw five fewer props than its neighbours and the room
    /// would be a different shape for it — so the requirement is named here,
    /// where the reason is, rather than discovered there.
    @Test func everyThemeDressesEveryBand() throws {
        let manifest = try SceneFixtures.manifest()
        for (name, room) in Self.rooms(manifest) {
            for band in RoomLayout.SceneryBand.allCases {
                #expect(!room.scenery(band).isEmpty, Comment(rawValue:
                    "\(name) declares nothing for the \(band.rawValue) band"))
            }
        }
    }

    /// **The room places every anchor, and it places them once.**
    ///
    /// A theme that owns fewer props than a band has anchors repeats them round
    /// the band — `library` draws two flat wall objects over seven columns —
    /// rather than leaving a gap, which is the pack's own habit and is what
    /// keeps a thin set honest instead of padded with props nobody looked at.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theRoomDrawsOneSceneryNodePerAnchorInEveryTheme() throws {
        let manifest = try SceneFixtures.manifest()
        let expected = RoomLayout.SceneryBand.allCases
            .reduce(0) { $0 + RoomLayout().sceneryAnchors($1).count }
        #expect(expected == 20, "the anchor count moved; the numbers below are stale")
        for theme in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            let scene = RoomScene(manifest: manifest, themeID: theme)
            #expect(scene.sceneryNodesForTesting.count == expected, Comment(rawValue:
                "\(theme ?? "manifest.room") drew"
                + " \(scene.sceneryNodesForTesting.count) scenery nodes, not \(expected)"))
        }
    }

    /// **Scenery is a function of the theme and of nothing else.** [I1, ADR-002
    /// §6 rule 1]
    ///
    /// Two scenes built from one theme draw the same scenery in the same places,
    /// whatever has happened in either of them. The room's own guard —
    /// `roomBuildCount` never leaving 1 across a whole fixture replay — already
    /// says no prop node is ever rebuilt; this says the picture does not depend
    /// on the delta stream in the first place, which is the half a rebuild count
    /// cannot see.
    @Test(.enabled(if: SceneArt.isAvailable))
    func sceneryIsIdenticalAcrossTwoScenesOfOneTheme() throws {
        let manifest = try SceneFixtures.manifest()
        for theme in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            func dressing() -> [String] {
                let scene = RoomScene(manifest: manifest, themeID: theme)
                return scene.sceneryNodesForTesting.map {
                    "\(Int($0.position.x)),\(Int($0.position.y)),\(Int($0.zPosition))"
                }
            }
            #expect(dressing() == dressing(), Comment(rawValue:
                "\(theme ?? "manifest.room") dressed itself differently twice"))
        }
    }

    /// **The camera frames the scenery it draws.**
    ///
    /// `decorationTopY` is what `RoomScene.cameraY` aims below, and the `wall`
    /// band is now the highest thing the room draws in five of six themes. A
    /// band the camera did not know about would be a band the camera crops —
    /// which is the exact defect that accessor was written against, one row
    /// lower down.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theWallBandIsInsideTheFrameTheCameraChooses() throws {
        let manifest = try SceneFixtures.manifest()
        for theme in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            let scene = RoomScene(manifest: manifest, themeID: theme)
            let top = Self.placements(scene.store.room, layout: scene.layout)
                .map(\.y.upperBound).max() ?? 0
            #expect(scene.decorationTopY >= top, Comment(rawValue:
                "\(theme ?? "manifest.room"): scenery reaches \(top) and"
                + " decorationTopY says \(scene.decorationTopY)"))
            let band = scene.contentBand
            let frameTop = scene.cameraY(band: band, sceneHeight: 400) + 200
            #expect(frameTop >= top, Comment(rawValue:
                "\(theme ?? "manifest.room"): the 1x frame stops at \(frameTop)"
                + " and the scenery reaches \(top)"))
        }
    }
}
