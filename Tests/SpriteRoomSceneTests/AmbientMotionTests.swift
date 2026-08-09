import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// The motion channel: what the seated art can hold, what a phrase may claim,
/// and whether two agents running different tool classes actually move
/// differently.
///
/// **The claim these tests exist to stop being made on trust** is "each agent
/// has its own animation now". Three things have to be true for that and each is
/// checked separately, because each fails differently:
///
/// 1. the art really does hold two positions, so a phrase is a schedule over
///    frames that exist rather than an invention (`AmbientMotionArtTests`);
/// 2. no two classes are handed the same loop while the room claims they differ,
///    and an unmapped tool is handed no claim at all (`AmbientMotionPolicyTests`);
/// 3. it reaches a real `Character`, only while it is `working`, and it does not
///    flicker when an agent holds two calls of different classes
///    (`AmbientMotionSceneTests`).
struct AmbientMotionPolicyTests {

    /// The frame count of the shipped seated loop. Row 4, three frames per
    /// direction — pinned by `ManifestTests` and restated here so the phrase
    /// arithmetic below is read against the real number.
    static let seatedFrameCount = 3

    /// **Six phrases, six distinct loops.** A shared phrase would be two kinds
    /// of work moving identically while the room asserts they differ, which is
    /// the failure this whole file exists to prevent — and it is the one the
    /// task that produced this layer named explicitly.
    ///
    /// Compared **up to rotation**, because a loop is a cycle: `S R` and `R S`
    /// are the same animation seen from a different starting phase, and two
    /// characters starting their calls at different instants would be playing
    /// exactly that. Comparing the arrays alone would call them different.
    @Test func noTwoBadgeClassesArePlayedTheSameWay() {
        func rotations(_ phrase: [AmbientMotion.Beat]) -> Set<[AmbientMotion.Beat]> {
            Set((0..<phrase.count).map { Array(phrase[$0...] + phrase[..<$0]) })
        }

        var seen: [ToolBadge: [AmbientMotion.Beat]] = [:]
        for badge in ToolBadge.allCases where badge != .questionMark {
            let phrase = AmbientMotion.phrase(for: badge)
            #expect(phrase != nil, "\(badge.rawValue) has no phrase")
            guard let phrase else { continue }
            #expect(!phrase.isEmpty, "\(badge.rawValue)'s phrase is empty")
            for (other, existing) in seen {
                #expect(!rotations(existing).contains(phrase),
                        "\(badge.rawValue) and \(other.rawValue) play the same loop")
            }
            seen[badge] = phrase
        }
        #expect(seen.count == ToolBadge.allCases.count - 1)
    }

    /// **The 3x2 grid, pinned.** A two-position bob has exactly two parameters —
    /// period and duty — so the six classes occupy the six cells of {fast, slow}
    /// x {25%, 50%, 75%} and no two share one. This is the assertion that keeps
    /// a later edit from nudging two phrases into the same corner of the space
    /// while `noTwoBadgeClassesArePlayedTheSameWay` still passes on a one-step
    /// difference nobody could see.
    @Test func thePhrasesOccupySixDistinctCellsOfPeriodAndDuty() {
        struct Cell: Hashable { let steps: Int; let raised: Int }
        var cells: [Cell: ToolBadge] = [:]
        for badge in ToolBadge.allCases where badge != .questionMark {
            guard let phrase = AmbientMotion.phrase(for: badge) else { continue }
            let cell = Cell(steps: phrase.count, raised: phrase.filter { $0 == .raised }.count)
            #expect(cells[cell] == nil,
                    "\(badge.rawValue) shares a period and duty with \(cells[cell]?.rawValue ?? "")")
            cells[cell] = badge
            // Every phrase holds both positions. One that held only `settled`
            // would be a character that never moves while the room says it is
            // working, and one that held only `raised` would be a character
            // frozen in the other pose. [I2]
            #expect(cell.raised > 0 && cell.raised < phrase.count,
                    "\(badge.rawValue) never changes position")
        }
        #expect(cells.count == 6)

        // The bars are on the manifest's own 8 fps grid and nothing here
        // introduces a rate. 2 steps = 250 ms, 4 = 500 ms, 8 = 1000 ms.
        #expect(Set(cells.keys.map(\.steps)) == [2, 4, 8])
    }

    /// **An unmapped tool moves the way a character has always moved.** [I1]
    ///
    /// `questionMark` is the glyph that asserts only "we do not recognise this",
    /// and the same discipline applies with more force to a whole animation than
    /// to an icon — the argument `HeldObject.init(badge:)` already makes for the
    /// hands. `Monitor` is deliberately and permanently in this bucket.
    @Test func anUnmappedToolIsGivenNoMotionToClaimWith() {
        #expect(AmbientMotion.phrase(for: .questionMark) == nil)
        #expect(AmbientMotion.phrase(for: nil) == nil)

        for tool in ["Monitor", "SomeToolInventedTomorrow", ""] {
            let badge = ToolBadge.badge(forTool: tool)
            #expect(badge == .questionMark)
            #expect(AmbientMotion.phrase(for: badge) == nil, "\(tool) was given a motion")
            // And what it plays is the shipped loop in order, which is what this
            // app drew before the motion channel existed.
            #expect(AmbientMotion.sequence(
                for: badge, state: .working, frameCount: Self.seatedFrameCount) == [0, 1, 2])
        }
    }

    /// **Only a `working` body plays a phrase.** [I2] There is nothing to claim
    /// about how a character walks, idles, spawns, departs or hands a report
    /// over, so every one of those plays its animation exactly as authored —
    /// which also means an `ADR-003` closing beat, whose body is `idle` for
    /// every frame by definition, cannot reach this channel.
    @Test func noStateButWorkingPlaysAPhrase() {
        for state in BodyState.allCases where state != .working {
            for badge in ToolBadge.allCases {
                let sequence = AmbientMotion.sequence(for: badge, state: state, frameCount: 6)
                #expect(sequence == Array(0..<6),
                        "\(state.rawValue) under \(badge.rawValue) is not the shipped loop")
            }
        }
    }

    /// **Total for any frame count**, which is the property that keeps a tool
    /// name appearing tomorrow from needing new art — the same argument
    /// `03-EVENT-MODEL.md` makes for the pose table, applied to the schedule
    /// over it. A phrase that indexed past the end of a shorter seated loop
    /// would crash the room on a manifest change rather than degrade.
    @Test func everyPhraseIndexesInsideAnySeatedLoop() {
        for frameCount in 1...8 {
            for badge in ToolBadge.allCases {
                let sequence = AmbientMotion.sequence(
                    for: badge, state: .working, frameCount: frameCount)
                #expect(!sequence.isEmpty)
                for index in sequence {
                    #expect(index >= 0 && index < frameCount,
                            "\(badge.rawValue) indexes \(index) of \(frameCount)")
                }
            }
            // A one-frame loop cannot bob, and asking it to must produce a
            // still character rather than an out-of-range read.
            #expect(AmbientMotion.Beat.raised.frameIndex(inFrameCount: 1) == 0)
        }
    }
}

/// The measurement the whole design stands on, re-derived from the shipped PNGs
/// rather than quoted from the comment that records it.
///
/// If this fails, `AmbientMotion`'s premise is wrong: there would be more (or
/// fewer) than two seated positions, and the phrase vocabulary would be built on
/// a reading of the art that the art does not support.
struct AmbientMotionArtTests {

    /// **The seated loop holds two positions, not three — and its feet never
    /// touch the floor row.**
    ///
    /// Both halves matter and they are different claims. *Two positions* is why
    /// a phrase is written in `settled` and `raised` and nothing else. *Feet off
    /// the floor* is what makes it a sit rather than a stand: a character is
    /// bottom-aligned in its 32x64 canvas, so the last pixel row is the floor,
    /// and of the pack's 20 pose rows only the two sit rows never reach it.
    /// [04-ART-DIRECTION, M6g]
    @Test(.enabled(if: SceneArt.isAvailable))
    func theSeatedLoopHoldsExactlyTwoPositions() throws {
        let manifest = try SceneFixtures.manifest()
        var checked = 0

        for variant in manifest.characters.orderedVariantIDs {
            for facing in [Facing.right, Facing.left] {
                let paths = try #require(
                    manifest.characters.variant(variant)?
                        .animation(.working)?.frames(facing: facing))
                #expect(paths.count == 3, "\(variant) \(facing): the seated loop is not 3 frames")
                guard paths.count == 3 else { continue }

                let bitmaps = try paths.map { try PixelImage.bitmap(contentsOf: manifest.url($0)) }
                func differing(_ lhs: Bitmap, _ rhs: Bitmap) -> Int {
                    var total = 0
                    for y in 0..<lhs.height {
                        for x in 0..<lhs.width where lhs.at(x, y) != rhs.at(x, y) { total += 1 }
                    }
                    return total
                }
                func top(_ bitmap: Bitmap) -> Int {
                    for y in 0..<bitmap.height {
                        for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 { return y }
                    }
                    return bitmap.height
                }
                func touchesFloorRow(_ bitmap: Bitmap) -> Bool {
                    (0..<bitmap.width).contains { bitmap.at($0, bitmap.height - 1).a > 0 }
                }

                // Frames 0 and 1 are the same position. The difference between
                // them is an eye blink — 0 px on variant 10, 32 at the most —
                // against a body of about a thousand.
                let blink = differing(bitmaps[0], bitmaps[1])
                #expect(blink <= 40, Comment(rawValue:
                    "\(variant) \(facing): frames 0 and 1 differ by \(blink), so the seated"
                    + " loop holds more than two positions and AmbientMotion's premise is wrong"))
                #expect(top(bitmaps[0]) == top(bitmaps[1]),
                        "\(variant) \(facing): frames 0 and 1 sit at different heights")

                // Frame 2 is the other position: the whole upper body, 2 px up.
                let bob = differing(bitmaps[0], bitmaps[2])
                #expect(bob >= 300, Comment(rawValue:
                    "\(variant) \(facing): frames 0 and 2 differ by only \(bob) px, so there"
                    + " is no second position to schedule"))
                #expect(top(bitmaps[2]) == top(bitmaps[0]) - 2,
                        "\(variant) \(facing): the raised frame is not 2 px up")

                // And it is a sit.
                for (index, bitmap) in bitmaps.enumerated() {
                    #expect(!touchesFloorRow(bitmap),
                            "\(variant) \(facing) frame \(index) stands on the floor row")
                }
                checked += 1
            }
        }

        #expect(checked == 12, "the cast or the seated facings changed: \(checked)")
    }
}

/// The rule on a real character.
@MainActor
struct AmbientMotionSceneTests {

    static func character(_ store: TextureStore, variant: String = "06") -> Character {
        Character(variant: variant, nameplate: NameplateText(lead: "MAIN"), store: store)
    }

    /// The frame indices a character draws over `steps` frames of the 8 fps
    /// grid, starting from the instant it entered its state.
    static func played(_ character: Character, steps: Int) -> [Int] {
        var indices: [Int] = []
        for step in 0..<steps {
            character.advance(to: Double(step) / 8 + 1.0 / 16)
            indices.append(character.frameIndexForTesting ?? -1)
        }
        return indices
    }

    static func working(_ character: Character, tools: [String], at start: TimeInterval = 0) {
        character.advance(to: start)
        character.apply(state: .working, facing: .right, startingAt: start)
        character.apply(badge: BadgeSelection.select(openToolNames: tools))
    }

    /// **The maintainer's question, mechanised: with the badges covered, do two
    /// agents running different tool classes move differently?**
    ///
    /// Every pair, not one pair, and over a whole second — long enough for the
    /// slowest phrase to complete a bar. A pair that agreed would be the room
    /// claiming a difference it does not draw.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyPairOfToolClassesMovesDifferently() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let sample = ["Edit", "Read", "Bash", "WebFetch", "Agent", "mcp__x__y"]

        var played: [String: [Int]] = [:]
        for tool in sample {
            let character = Self.character(store)
            Self.working(character, tools: [tool])
            played[tool] = Self.played(character, steps: 8)
        }

        for (index, lhs) in sample.enumerated() {
            for rhs in sample[(index + 1)...] {
                #expect(played[lhs] != played[rhs],
                        "\(lhs) and \(rhs) draw the same frames: \(played[lhs] ?? [])")
            }
            // And each of them genuinely moves — a phrase that resolved to one
            // frame would pass the inequality above against a different constant
            // while drawing a character frozen at its desk.
            #expect(Set(played[lhs] ?? []).count > 1, "\(lhs) never changes frame")
        }
    }

    /// **I3: an agent's state is a set, and the body plays the set's
    /// lowest-ordinal class — the same one its badge shows.**
    ///
    /// Two properties, and the second is the one that matters. The choice is
    /// *the badge's* choice, so nothing new decides it; and because
    /// `BadgeSelection.select` is order-independent, opening the two calls in
    /// either order plays the same phrase. A most-recent-wins rule would have
    /// the body change gait every time a parallel call opened or closed, which
    /// is the flicker the badge ordinal exists to prevent, arriving one layer
    /// down.
    @Test(.enabled(if: SceneArt.isAvailable))
    func anAgentHoldingTwoClassesPlaysTheLowerOrdinalWhicheverOrderTheyOpenedIn() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())

        // `magnifier` (ordinal 1) beats `terminal` (ordinal 2).
        let forwards = Self.character(store)
        Self.working(forwards, tools: ["Read", "Bash"])
        let backwards = Self.character(store)
        Self.working(backwards, tools: ["Bash", "Read"])
        let magnifierAlone = Self.character(store)
        Self.working(magnifierAlone, tools: ["Read"])
        let terminalAlone = Self.character(store)
        Self.working(terminalAlone, tools: ["Bash"])

        let both = Self.played(forwards, steps: 8)
        #expect(both == Self.played(backwards, steps: 8), "the order of the set changed the gait")
        #expect(both == Self.played(magnifierAlone, steps: 8),
                "two open classes did not play the lowest ordinal")
        #expect(both != Self.played(terminalAlone, steps: 8))

        // Closing the magnifier call hands the body to `terminal`, once, on the
        // change of the set and not on any frame in between.
        forwards.apply(badge: BadgeSelection.select(openToolNames: ["Bash"]))
        #expect(forwards.frameSequenceForTesting
                == terminalAlone.frameSequenceForTesting)
    }

    /// **A phrase swap does not restart the loop.**
    ///
    /// This class's standing contract is that a looping animation is never
    /// restarted by an event arriving — it is what keeps a burst of short calls
    /// from stuttering. A badge change is an event arriving. Every phrase is on
    /// the same 125 ms grid, so the swap lands on a step boundary and the body
    /// continues into the new schedule from wherever it was.
    @Test(.enabled(if: SceneArt.isAvailable))
    func changingClassMidCallDoesNotRestartTheAnimationClock() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        Self.working(character, tools: ["Read"])

        character.advance(to: 3.0)
        let sequenceBefore = character.frameSequenceForTesting
        character.apply(badge: BadgeSelection.select(openToolNames: ["Bash"]))
        #expect(character.frameSequenceForTesting != sequenceBefore, "the gait did not change")

        // Frozen from the *original* start, not from the swap: at t = 3.0 s the
        // step is 24, and `terminal`'s two-step phrase puts an even step on
        // `settled`. A restart would put step 0 there too, so the discriminating
        // instant is a quarter-step later on an odd step.
        character.advance(to: 3.125)
        #expect(character.frameIndexForTesting == 2,
                "the phrase restarted from its own beginning instead of continuing")
    }

    /// **I2 on the motion layer: a character with no open call does not play a
    /// phrase, and neither does one inside `ADR-003`'s closing beat.**
    ///
    /// The beat is a glyph over an *idle* body — the condition `ADR-003` §6 says
    /// voids it if an implementer drops it — so a lingering `terminal` must not
    /// reach this channel. It cannot, structurally: the sequence is a function
    /// of the body state, and the body is `idle` for every frame of a beat.
    @Test(.enabled(if: SceneArt.isAvailable))
    func anIdleBodyPlaysTheShippedLoopEvenUnderALingeringGlyph() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)

        character.apply(state: .idle, facing: .right, startingAt: 0)
        let idleSequence = character.frameSequenceForTesting
        #expect(idleSequence == Array(0..<idleSequence.count))

        // The beat's shape: the open set emptied, so `BadgeSelection.select`
        // reaches `closingBeat` and the slot still shows `terminal` — over a
        // body the director has already put back to `idle`.
        character.apply(badge: BadgeSelection.select(openToolNames: [], closingBeat: .terminal))
        #expect(character.badgeSelection.badge == .terminal, "the beat is not set up")
        #expect(character.frameSequenceForTesting == idleSequence,
                "a closing beat changed how the body moves")
        #expect(character.heldObjectForTesting == nil, "a closing beat filled the hands")
    }

    /// **A call parked at a permission gate keeps its work phrase**, and that is
    /// the one place this layer deliberately parts company with the hands.
    ///
    /// The hands go empty because an object is a second, larger assertion on top
    /// of a glyph the badge layer is correctly refusing to draw. The body is not
    /// that layer: I2 keys it on the open-call set alone, the character really
    /// is still holding those calls, and `SceneDirector.body(for:badge:)` already
    /// reads the tool class straight through an attention override for exactly
    /// this reason. A phrase that fell back to neutral under `attention` would
    /// put the body and the working-pose lookup on two different keys.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aGatedCallKeepsItsGaitAndLosesOnlyItsHands() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let ungated = Self.character(store)
        Self.working(ungated, tools: ["Bash"])

        let gated = Self.character(store)
        gated.advance(to: 0)
        gated.apply(state: .working, facing: .right, startingAt: 0)
        gated.apply(badge: BadgeSelection.select(
            openToolNames: ["Bash"], attention: .permissionPrompt))

        #expect(gated.frameSequenceForTesting == ungated.frameSequenceForTesting,
                "the gate changed how the body moves")
        #expect(gated.heldObjectForTesting == nil, "the gate left something in the hands")
        #expect(ungated.heldObjectForTesting == .console)
    }
}
