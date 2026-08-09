import CoreGraphics
import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// The held-object layer: what the rule allows, what the art is, and where it
/// lands on the body.
///
/// **The claim these tests exist to stop being made on trust** is "characters
/// hold things now". Three separate things have to be true for that, and each
/// one has failed in this project's history in a different way:
///
/// 1. the rule only puts something in the hands when the data says so [I1, I2];
/// 2. the art is real, distinct, and inside I7's band;
/// 3. it is placed on the hands the artist drew, at whole pixels, at every
///    scale on the ladder [I6].
///
/// The third is the one that cannot be asserted from a table, so
/// `theSeatedHandBoxIsWhereTheArtSaysItIs` re-derives the anchor from the
/// shipped PNGs instead of quoting the comment that placed it. It is gated on
/// the art being on disk; the rest are not, because they are about policy and
/// about bitmaps this repository draws itself.
struct HeldObjectPolicyTests {

    /// **The question-mark rule, on the character layer.** An unmapped tool gets
    /// no glyph because guessing one would be a claim the data did not make;
    /// it gets no *object* for the same reason and with more force, because an
    /// object is a bigger assertion than an icon. [I1]
    @Test func anUnmappedToolPutsNothingInTheHands() {
        #expect(HeldObject(badge: .questionMark) == nil)
        // And the tools that reach it really do reach it, so this is not a
        // statement about an unreachable case.
        for tool in ["Monitor", "SomeToolInventedTomorrow", ""] {
            #expect(ToolBadge.badge(forTool: tool) == .questionMark)
            #expect(HeldObject(badge: ToolBadge.badge(forTool: tool)) == nil)
        }
    }

    /// Every *other* badge class has exactly one object, and no two classes
    /// share one. A shared object would make two different kinds of work look
    /// identical in the hands, which is the failure the badge ordinal rule
    /// exists to prevent one layer up.
    @Test func everyMappedBadgeClassHasItsOwnObject() {
        var seen: [HeldObject: ToolBadge] = [:]
        for badge in ToolBadge.allCases where badge != .questionMark {
            let object = HeldObject(badge: badge)
            #expect(object != nil, "\(badge.rawValue) has no held object")
            if let object {
                #expect(seen[object] == nil,
                        "\(badge.rawValue) shares an object with \(seen[object]!.rawValue)")
                seen[object] = badge
            }
        }
        #expect(seen.count == ToolBadge.allCases.count - 1)
        #expect(Set(HeldObject.allCases) == Set(seen.keys),
                "an object exists that no badge class can produce")
    }
}

/// The art itself. Pure bitmap arithmetic, so none of this needs the pack on
/// disk — and it needs checking *here* rather than in `scripts/lint-palette.py`,
/// because that lint reads `assets/manifest.json` and this layer is drawn by the
/// scene, exactly like the nameplate and the `×N`. A layer no lint can see is a
/// layer whose I7 numbers are whatever somebody last typed.
struct HeldObjectArtTests {

    /// The cast's darkest pixel, measured at M0 over every selected premade and
    /// quoted in `docs/04-ART-DIRECTION.md` in four separate places. I7's one
    /// non-negotiable axis is that nothing outside the characters owns the
    /// darkest pixel on screen; a held object is drawn *on* a character, so the
    /// bar it has to clear is not the room's, it is this.
    static let castDarkestValue = 0.314

    static func value(_ colour: Bitmap.RGBA) -> Double {
        Double(max(colour.r, max(colour.g, colour.b))) / 255
    }

    static func saturation(_ colour: Bitmap.RGBA) -> Double {
        let high = value(colour)
        guard high > 0 else { return 0 }
        let low = Double(min(colour.r, min(colour.g, colour.b))) / 255
        return (high - low) / high
    }

    /// **No held object is ever the darkest thing on screen.** It bottoms out at
    /// the pack's own outline ink, which is the cast's floor to three decimals,
    /// because it *is* the cast's ink — every one of the eleven files in
    /// `Character_Generator/{Books,Smartphones}` is built on `(58, 58, 80)`.
    ///
    /// The tolerance is one 255th, which is a rounding step and not a margin: a
    /// colour a whole eighth of a percent darker than the cast fails here.
    @Test func noHeldObjectOwnsTheDarkestPixelOnScreen() {
        for object in HeldObject.allCases {
            let bitmap = HeldObjectArt.bitmap(object)
            var darkest = 1.0
            var brightest = 0.0
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                    darkest = min(darkest, Self.value(bitmap.at(x, y)))
                    brightest = max(brightest, Self.value(bitmap.at(x, y)))
                }
            }
            #expect(darkest >= Self.castDarkestValue - 1.0 / 255,
                    "\(object.rawValue) reaches \(darkest), under the cast's floor")
            // And it has to be a *thing*, not a dark smudge: something in it has
            // to be bright enough to separate from a torso.
            #expect(brightest > 0.6,
                    "\(object.rawValue) peaks at \(brightest); nothing in it will read")
        }
    }

    /// Every colour in every object comes from the palette the pack uses for the
    /// only held objects it draws. Pinned as a set rather than described, so
    /// adding a seventh object cannot quietly introduce a hue nobody measured.
    @Test func theArtUsesThePacksOwnHeldObjectPalette() {
        let allowed: Set<[UInt8]> = [
            HeldObjectArt.outline, HeldObjectArt.shade, HeldObjectArt.soft,
            HeldObjectArt.paper, HeldObjectArt.paperShade,
            HeldObjectArt.blue, HeldObjectArt.blueDark, HeldObjectArt.gold,
            HeldObjectArt.board, HeldObjectArt.screen, HeldObjectArt.casing,
            HeldObjectArt.orange, HeldObjectArt.orangeDark,
        ].reduce(into: Set<[UInt8]>()) { $0.insert([$1.r, $1.g, $1.b]) }

        for object in HeldObject.allCases {
            let bitmap = HeldObjectArt.bitmap(object)
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                    let pixel = bitmap.at(x, y)
                    #expect(allowed.contains([pixel.r, pixel.g, pixel.b]),
                            "\(object.rawValue) uses an off-palette colour at (\(x), \(y))")
                }
            }
        }
        // The outline is the pack's darkest ink to the byte.
        #expect(HeldObjectArt.outline == Bitmap.RGBA(58, 58, 80))
        #expect(abs(Self.value(HeldObjectArt.outline) - Self.castDarkestValue) < 1.0 / 255)
    }

    /// **The pack's grid.** The 32x art is a 2x scale-up of a 16-px design —
    /// every feature in a seated frame is a 2x2 block — so a glyph drawn at
    /// 1 px line weight beside it reads as a different hand immediately. This
    /// asserts the doubling actually happened rather than trusting that the
    /// design tables were transcribed onto it.
    @Test func everyFeatureIsATwoByTwoBlockOnThePacksDesignGrid() {
        for object in HeldObject.allCases {
            let bitmap = HeldObjectArt.bitmap(object)
            #expect(bitmap.width == HeldObjectArt.canvasWidth)
            #expect(bitmap.height == HeldObjectArt.canvasHeight)
            #expect(bitmap.width.isMultiple(of: 2) && bitmap.height.isMultiple(of: 2))
            for y in stride(from: 0, to: bitmap.height, by: 2) {
                for x in stride(from: 0, to: bitmap.width, by: 2) {
                    let corner = bitmap.at(x, y)
                    #expect(bitmap.at(x + 1, y) == corner)
                    #expect(bitmap.at(x, y + 1) == corner)
                    #expect(bitmap.at(x + 1, y + 1) == corner)
                }
            }
        }
    }

    /// No two objects draw the same pixels. Six that differ only in the comment
    /// above them would be the badge row's M5b problem again: a channel that was
    /// built and cannot carry anything.
    @Test func noTwoObjectsAreTheSamePicture() {
        var seen: [Bitmap: HeldObject] = [:]
        for object in HeldObject.allCases {
            let bitmap = HeldObjectArt.bitmap(object)
            #expect(bitmap.opaquePixelCount > 40,
                    "\(object.rawValue) is nearly empty — \(bitmap.opaquePixelCount) px")
            if let clash = seen[bitmap] {
                Issue.record("\(object.rawValue) is pixel-identical to \(clash.rawValue)")
            }
            seen[bitmap] = object
        }
        #expect(seen.count == HeldObject.allCases.count)
    }

    /// **The measurement the whole layer stands on, re-derived from the shipped
    /// frames.**
    ///
    /// `04-ART-DIRECTION.md` refuses an arbitrary prop on this art because the
    /// download carries no per-frame hand anchor, and it is right that it does
    /// not. What makes this layer legal is narrower and is checked here: on the
    /// **one** pose the room draws, the hands do not move, so there is one
    /// anchor and it can be measured.
    ///
    /// **What is invariant, stated as the measurement found it rather than as I
    /// first wrote it down.** Over 36 frames — six variants, three `sit` frames,
    /// both facings — the skin below the shoulder line always occupies **columns
    /// 14...17** and always **ends on row 55**. What varies is the *top*: on some
    /// variants a forearm is visible above the hand and the run starts at row 48
    /// or 50 rather than 52. The first version of this test asserted one box for
    /// all 36 and failed on three of them, which is the test doing its job — the
    /// anchor is the hand, not the arm, so it is taken from the four rows every
    /// frame agrees on, `52...55`, and the arm is allowed to be there.
    ///
    /// If a future manifest recuts the seated row and this fails, the anchor is
    /// wrong and the object is floating. That is exactly the failure this test
    /// exists to make loud, and it is why it re-measures rather than pinning
    /// `Character.seatedHandCentre` against itself.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theSeatedHandBoxIsWhereTheArtSaysItIs() throws {
        let manifest = try SceneFixtures.manifest()
        // The four columns and the bottom row, over every frame checked.
        var columnsAndFloor: Set<[Int]> = []
        var tops: Set<Int> = []
        var frames = 0

        for variant in manifest.characters.orderedVariantIDs {
            for facing in [Facing.right, Facing.left] {
                let paths = try #require(
                    manifest.characters.variant(variant)?
                        .animation(.working)?.frames(facing: facing))
                for path in paths {
                    frames += 1
                    let bitmap = try PixelImage.bitmap(contentsOf: manifest.url(path))
                    // The variant's own skin, taken from the lower half of the
                    // face. Sampled from the *chin* band rather than the cheek
                    // because the seated loop lifts the whole upper body by 2 px
                    // on frame 2, and a window high enough to catch the cheek on
                    // frames 0 and 1 catches hair on frame 2.
                    let faceX = facing == .right ? 18..<28 : 4..<14
                    var tally: [Bitmap.RGBA: Int] = [:]
                    for y in 38..<46 {
                        for x in faceX where bitmap.at(x, y).a > 0 {
                            tally[bitmap.at(x, y), default: 0] += 1
                        }
                    }
                    // Ties broken by brightness, and that is not a detail:
                    // `Dictionary` has no stable order, so `max(by:)` on the
                    // count alone picks a different colour from run to run when
                    // two tie — which made this test fail on one frame in three
                    // runs out of four and pass in the fourth. Skin is the
                    // brightest large field on a face, so the tie-break is also
                    // the right answer rather than merely a deterministic one.
                    let skin = try #require(tally.max(by: { lhs, rhs in
                        lhs.value == rhs.value
                            ? Self.value(lhs.key) < Self.value(rhs.key)
                            : lhs.value < rhs.value
                    })?.key)

                    // The same colour again, below the shoulder line: the hands.
                    var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
                    for y in 47..<bitmap.height {
                        for x in 0..<bitmap.width where bitmap.at(x, y) == skin {
                            minX = min(minX, x); maxX = max(maxX, x)
                            minY = min(minY, y); maxY = max(maxY, y)
                        }
                    }
                    #expect(minX != Int.max,
                            "\(variant) \(facing) \(path): no hand found below the shoulders")
                    guard minX != Int.max else { continue }
                    columnsAndFloor.insert([minX, maxX, maxY])
                    tops.insert(minY)

                    // Every one of the four columns carries skin somewhere in
                    // rows 52...55, which is what makes those four rows *the
                    // hand* rather than the lowest thing the run happened to
                    // reach on one variant.
                    for x in 14...17 {
                        let touched = (52...55).contains { bitmap.at(x, $0) == skin }
                        #expect(touched, "\(variant) \(facing) \(path): column \(x) is not a hand")
                    }
                }
            }
        }

        #expect(frames == 36, "the cast or the seated frame count changed: \(frames)")
        #expect(columnsAndFloor == [[14, 17, 55]],
                "the seated hands moved between variants, frames or facings: \(columnsAndFloor)")
        #expect(tops.allSatisfy { $0 >= 48 && $0 <= 52 },
                "skin appears higher up the torso than a forearm explains: \(tops)")

        // And the constant the scene places against is the agreed box's centre,
        // in the node's own y-up coordinates. Derived here rather than quoted,
        // so the two cannot drift apart.
        let canvasHeight = manifest.characters.canvas.height
        let centreX = Double(14 + 17 + 1) / 2 - Double(manifest.characters.canvas.width) / 2
        let centreY = Double(canvasHeight - 55 - 1 + canvasHeight - 52) / 2
        #expect(Character.seatedHandCentre.x == CGFloat(centreX))
        #expect(Character.seatedHandCentre.y == CGFloat(centreY))
    }
}

/// The rule on a real character, and the geometry on screen.
@MainActor
struct HeldObjectSceneTests {

    static func character(_ store: TextureStore, variant: String = "06") -> Character {
        Character(variant: variant, nameplate: NameplateText(lead: "MAIN"), store: store)
    }

    static func working(_ tools: [String]) -> BadgeSelection {
        BadgeSelection.select(openToolNames: tools)
    }

    /// **I2 on the body layer.** A character with no open call idles, and idle
    /// hands are empty. This is the invariant the layer is most likely to be
    /// asked to break, because a room full of people holding things looks busier
    /// than a room full of people not.
    @Test(.enabled(if: SceneArt.isAvailable))
    func idleHandsAreEmpty() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)

        character.apply(state: .working, facing: .right, startingAt: 0)
        character.apply(badge: Self.working(["Bash"]))
        #expect(character.heldObjectForTesting == .console, "nothing was ever held")

        character.apply(badge: .none)
        character.apply(state: .idle, facing: .right, startingAt: 0)
        #expect(character.heldObjectForTesting == nil)

        // And every other body state the room plays, with a badge still set —
        // walking to hand a report over is not working, so the hands are empty
        // for the whole beat.
        for state in BodyState.allCases where state != .working {
            character.apply(state: state, facing: .right, startingAt: 0)
            character.apply(badge: Self.working(["Bash"]))
            guard character.state == state else { continue }
            #expect(character.heldObjectForTesting == nil,
                    "\(state.rawValue) put something in the hands")
        }
    }

    /// **ADR-003's closing beat reaches the badge slot and never the hands.**
    ///
    /// The beat is defined as a glyph over an *idle* body — §6 condition 1, the
    /// one the ADR says voids it if an implementer drops it. The hands are a
    /// body-layer claim, so they follow the body and go empty at the close. This
    /// falls out of the `working` guard rather than being a case handled beside
    /// it, which is the same structural argument `SceneDirector.body(for:badge:)`
    /// makes about the working-pose lookup.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aClosingBeatLeavesTheHandsEmpty() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.apply(badge: Self.working(["Read"]))
        #expect(character.heldObjectForTesting == .book)

        // What a beat looks like from this class: the open set emptied, so the
        // body went idle, and the badge kept the glyph for D.
        character.apply(state: .idle, facing: .right, startingAt: 0)
        character.apply(badge: BadgeSelection.select(
            openToolNames: [String](), closingBeat: .magnifier))
        #expect(character.isBadgeVisible, "the beat is supposed to keep the glyph")
        #expect(character.heldObjectForTesting == nil, "the beat put an object in idle hands")
    }

    /// **Attention and dormancy empty the hands as well as the tool slot.**
    ///
    /// A call parked at a permission gate is not running — `ADR-003 §1` and the
    /// `isAttention` note both turn on that — so the room must not assert the
    /// work with a second, larger channel while the badge is correctly refusing
    /// to. The body still animates, because I2 keys it on the open set alone and
    /// that is not this layer's to change.
    @Test(.enabled(if: SceneArt.isAvailable))
    func attentionAndDormancyEmptyTheHands() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)

        character.apply(badge: BadgeSelection.select(
            openToolNames: ["Bash"], attention: .permissionPrompt))
        #expect(character.heldObjectForTesting == nil)

        character.apply(badge: BadgeSelection.select(
            openToolNames: ["Bash"], isDormant: true))
        #expect(character.heldObjectForTesting == nil)

        // Clearing it hands the object back with no further body change.
        character.apply(badge: Self.working(["Bash"]))
        #expect(character.heldObjectForTesting == .console)
    }

    /// The lowest-ordinal rule decides the object, because it decides the badge
    /// and the object is read off the badge. Two calls in either order put the
    /// same thing in the hands. [I3]
    @Test(.enabled(if: SceneArt.isAvailable))
    func severalOpenCallsPutOneObjectInTheHandsAndTheOrderDoesNotMatter() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)

        character.apply(badge: Self.working(["Bash", "Read", "WebFetch"]))
        #expect(character.heldObjectForTesting == .book, "magnifier is the lowest ordinal here")
        character.apply(badge: Self.working(["WebFetch", "Read", "Bash"]))
        #expect(character.heldObjectForTesting == .book)
    }

    /// **The object lands on the hands, and it is on whole pixels at 1x, 2x and
    /// 3x.** [I6]
    ///
    /// The rectangle has to overlap the measured hand box — an object beside the
    /// hands is the "it looks detached" failure — and its edges have to be whole
    /// numbers, because a half pixel multiplied by an integer scale is still a
    /// half pixel and shimmers at exactly the zooms I6 protects.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theObjectIsOnTheHandsAndOnWholePixelsAtEveryScale() throws {
        let manifest = try SceneFixtures.manifest()
        let store = TextureStore(manifest: manifest)
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.apply(badge: Self.working(["Read"]))
        #expect(character.heldObjectForTesting != nil)

        // The hand box in the node's own coordinates: canvas x 14...18 against a
        // bottom-centre anchor, canvas y 52...56 counted down, so y-up 8...12.
        let hands = CGRect(x: -2, y: 8, width: 4, height: 4)
        let rect = character.heldRect
        #expect(rect.intersects(hands), "the object is not on the hands: \(rect)")
        // And it does not merely clip a corner — the hands are inside it, which
        // is what "held" means.
        #expect(rect.contains(CGPoint(x: hands.midX, y: hands.midY)),
                "the hand centre is outside the object: \(rect)")

        for scale in [1, 2, 3] {
            for edge in [rect.minX, rect.maxX, rect.minY, rect.maxY] {
                let scaled = edge * CGFloat(scale)
                #expect(scaled == scaled.rounded(),
                        "edge \(edge) lands at \(scaled) at \(scale)x — half a pixel")
            }
        }
    }

    /// Facing left mirrors the object to the other side of the body, and does it
    /// with one sign on both the position and the scale so the two cannot
    /// disagree. The seated pose is drawn `right` in every shipped theme, so
    /// this is the branch no room exercises and the one a themed layout would
    /// find first.
    @Test(.enabled(if: SceneArt.isAvailable))
    func facingLeftMirrorsTheObjectRatherThanLeavingItBehind() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.apply(badge: Self.working(["Read"]))
        let right = character.heldRect

        character.apply(state: .working, facing: .left, startingAt: 0)
        let left = character.heldRect
        #expect(character.facing == .left)
        #expect(left.midX == -right.midX, "the object did not follow the character round")
        #expect(left.midY == right.midY)
        #expect(left.width == right.width && left.height == right.height)
    }

    /// The object is over the body and over any costume, and far under the badge
    /// and the nameplate — so nothing a character holds can cover an identity,
    /// which is the rule `Character.Layer` exists to enforce.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theObjectDrawsOverTheBodyAndUnderEveryIdentityLayer() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.apply(badge: Self.working(["Read"]))
        #expect(character.heldDepth > character.bodyDepth)
        #expect(character.heldDepth > character.zPosition + Character.Layer.costume)
        #expect(character.heldDepth < character.badgeDepth)
        #expect(character.heldDepth < character.nameplateDepth)
    }
}
