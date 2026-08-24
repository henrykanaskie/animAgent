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
    /// direction, pinned by `ManifestTests` and restated here so the phrase
    /// arithmetic below is read against the real number.
    static let seatedFrameCount = 3

    /// **Six phrases, six distinct loops.** A shared phrase would be two kinds
    /// of work moving identically while the room asserts they differ, which is
    /// the failure this whole file exists to prevent, and it is the one the
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

    /// **The 3x2 grid, pinned.** A two-position bob has exactly two parameters (
    /// period and duty) so the six classes occupy the six cells of {fast, slow}
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
    /// to an icon: the argument `HeldObject.init(badge:)` already makes for the
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
                for: badge, state: .working, openCalls: 1,
                frameCount: Self.seatedFrameCount) == [0, 1, 2])
        }
    }

    /// **Only a `working` body plays a phrase.** [I2] There is nothing to claim
    /// about how a character walks, spawns, departs or hands a report over, so
    /// every one of those plays its animation exactly as authored.
    ///
    /// `idle` is excluded here and pinned by `anIdleBodyHoldsOneFrame` instead:
    /// it plays no phrase either, but it no longer plays the shipped loop.
    ///
    /// The open call is what makes this test about the *state*: since ADR-005 a
    /// character can be seated with none, and a phrase is refused for that
    /// reason instead of this one.
    @Test func noStateButWorkingPlaysAPhrase() {
        for state in BodyState.allCases where state != .working && state != .idle {
            for badge in ToolBadge.allCases {
                let sequence = AmbientMotion.sequence(
                    for: badge, state: state, openCalls: 1, frameCount: 6)
                #expect(sequence == Array(0..<6),
                        "\(state.rawValue) under \(badge.rawValue) is not the shipped loop")
            }
        }
    }

    /// **A character with no open call holds one frame, whatever its badge says.**
    ///
    /// This is the busy/idle signal at `1x`, and it only works if it is exact:
    /// *any* residual idle motion competes with a working body that can never
    /// move more than 2 px, so the assertion is `[0]` rather than "less than".
    ///
    /// The badge loop matters because the two channels are deliberately allowed
    /// to disagree: an `ADR-003` closing beat is a tool glyph over a body that
    /// is not working, and a dormant character wears a tab over one. Neither may
    /// put the body back in motion, because the body is the channel I2 makes
    /// truthful for every frame.
    ///
    /// The open-call loop is ADR-005's addition: a standing character with an
    /// open call is unreachable in the live stream (a `PreToolUse` opens the
    /// turn that seats it) but this function is total and a state nothing can
    /// produce is still a state something may ask for.
    @Test func anIdleBodyHoldsOneFrame() {
        for frameCount in 1...10 {
            for badge in ToolBadge.allCases.map({ Optional($0) }) + [nil] {
                for openCalls in [0, 1, 3] {
                    #expect(AmbientMotion.sequence(
                        for: badge, state: .idle, openCalls: openCalls,
                        frameCount: frameCount) == [0],
                            "idle under \(badge?.rawValue ?? "no badge") moved")
                }
            }
        }
    }

    /// **And so does a seated body with no open call.** [ADR-005 §3]
    ///
    /// This is the same claim on the other posture, and it is the load-bearing
    /// half of ADR-005: the posture moved off the open-call set and the *motion*
    /// did not, so the dead air between two calls of one turn is now drawn
    /// seated instead of standing and moves 0 px/s either way. If this fails,
    /// the room has an ambient loop running with nothing open, which is the one
    /// thing I2 exists to forbid, and it would be running under a character
    /// that the badge layer correctly shows as doing nothing.
    ///
    /// The badge loop is what makes it exact. A closing beat leaves a `magnifier`
    /// on screen with an empty set for 500 ms, and a phrase keyed off that glyph
    /// would be a body asserting a read that has finished.
    @Test func aSeatedBodyWithNoOpenCallHoldsOneFrame() {
        for frameCount in 1...10 {
            for badge in ToolBadge.allCases.map({ Optional($0) }) + [nil] {
                #expect(AmbientMotion.sequence(
                    for: badge, state: .working, openCalls: 0, frameCount: frameCount) == [0],
                        "a seated character with no call moved under \(badge?.rawValue ?? "none")")
            }
        }
        // The frame it holds is `settled`, which is where every phrase starts
        // and ends, so a call opening or closing moves the body no pixels at
        // all until the phrase itself does.
        #expect(AmbientMotion.seatedStillSequence
                == [AmbientMotion.Beat.settled.frameIndex(inFrameCount: 3)])
        for badge in ToolBadge.allCases where AmbientMotion.phrase(for: badge) != nil {
            #expect(AmbientMotion.phrase(for: badge)?.first == .settled,
                    "\(badge.rawValue) does not start where a still body already is")
        }
    }

    /// **And so does a body stopped at a permission gate, whatever it holds
    /// open.** [ADR-005 §7]
    ///
    /// The third and last thing that stops the body, and the only one of the
    /// three that takes away motion this room was previously drawing. The badge
    /// loop is the point: a gated `Bash` is `terminal`, the busiest schedule in
    /// the table, and it played it. The open-call loop is the other half: a
    /// gated agent is holding those calls, which is exactly why the open-call
    /// set could not answer this question by itself.
    @Test func aBodyStoppedAtAPermissionGateHoldsOneFrame() {
        for frameCount in 1...10 {
            for badge in ToolBadge.allCases.map({ Optional($0) }) + [nil] {
                for openCalls in [0, 1, 5] {
                    #expect(AmbientMotion.sequence(
                        for: badge, state: .working, openCalls: openCalls, isGated: true,
                        frameCount: frameCount) == [0],
                            "a gated character moved under \(badge?.rawValue ?? "no badge")")
                }
            }
        }
        // It holds `settled`, the same frame the two other still cases hold, so
        // a gate opening or closing moves the body no pixels at all until the
        // phrase itself does.
        #expect(AmbientMotion.gatedStillSequence == AmbientMotion.seatedStillSequence)
        #expect(AmbientMotion.gatedStillSequence
                == [AmbientMotion.Beat.settled.frameIndex(inFrameCount: 3)])

        // And the same inputs without the gate do move, for every mapped class,
        // so the rule above is the gate's doing and not a phrase table that
        // resolved to one frame.
        for badge in ToolBadge.allCases where AmbientMotion.phrase(for: badge) != nil {
            #expect(AmbientMotion.sequence(
                for: badge, state: .working, openCalls: 1, isGated: false,
                frameCount: 3).count > 1, "\(badge.rawValue) does not move ungated either")
        }
    }

    /// **A gate never freezes a told event.** `walk`, `spawn`, `depart` and
    /// `deliver` each *are* an event being told, so they play as authored: a
    /// character that stopped mid-stride because a dialog opened would slide
    /// across the floor. Reachable in one batch: `SubagentStop` clears the gate
    /// and starts the report walk together.
    @Test func aGateFreezesNoStateThatIsAnEventBeingTold() {
        for state in BodyState.allCases where state != .idle && state != .working {
            #expect(AmbientMotion.sequence(
                for: .terminal, state: state, openCalls: 1, isGated: true,
                frameCount: 6).count == 6,
                    "\(state.rawValue) froze at a permission gate")
        }
        // And a standing character is already one held frame, so the gate adds
        // nothing there and takes nothing away.
        #expect(AmbientMotion.sequence(
            for: .terminal, state: .idle, openCalls: 1, isGated: true, frameCount: 6) == [0])
    }

    /// The states that are a *told event* keep every frame the artist drew. The
    /// idle loop was the one animation in the room with no event behind it, and
    /// it is the only one that went. Nothing here is a preference: a walk that
    /// froze would be a character sliding across the floor.
    @Test func everyStateWithAnEventBehindItStillAnimates() {
        for state in BodyState.allCases where state != .idle {
            #expect(AmbientMotion.sequence(
                for: nil, state: state, openCalls: 1, frameCount: 6).count == 6,
                    "\(state.rawValue) lost its frames")
        }
        // `walk`, `spawn`, `depart` and `deliver` each *are* an event being
        // told, so they keep every frame whether or not a call is open: a
        // character that stopped mid-stride because its `Read` returned would
        // slide across the floor. Only the two resting postures answer to the
        // open-call set. [ADR-005 §3]
        for state in BodyState.allCases where state != .idle && state != .working {
            #expect(AmbientMotion.sequence(
                for: nil, state: state, openCalls: 0, frameCount: 6).count == 6,
                    "\(state.rawValue) froze when the open-call set emptied")
        }
    }

    /// **Total for any frame count**, which is the property that keeps a tool
    /// name appearing tomorrow from needing new art: the same argument
    /// `03-EVENT-MODEL.md` makes for the pose table, applied to the schedule
    /// over it. A phrase that indexed past the end of a shorter seated loop
    /// would crash the room on a manifest change rather than degrade.
    @Test func everyPhraseIndexesInsideAnySeatedLoop() {
        for frameCount in 1...8 {
            for badge in ToolBadge.allCases {
                let sequence = AmbientMotion.sequence(
                    for: badge, state: .working, openCalls: 1, frameCount: frameCount)
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

    /// **The seated loop holds two positions, not three, and its feet never
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
                // them is an eye blink (0 px on variant 10, 32 at the most)
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
    /// Every pair, not one pair, and over a whole second, long enough for the
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
            // And each of them genuinely moves: a phrase that resolved to one
            // frame would pass the inequality above against a different constant
            // while drawing a character frozen at its desk.
            #expect(Set(played[lhs] ?? []).count > 1, "\(lhs) never changes frame")
        }
    }

    /// **I3: an agent's state is a set, and the body plays the set's
    /// lowest-ordinal class, the same one its badge shows.**
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
    /// restarted by an event arriving: it is what keeps a burst of short calls
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

    /// **I2 on the motion layer, on a real character: a body with no open call
    /// plays no phrase, in either posture, and neither does one inside
    /// `ADR-003`'s closing beat.**
    ///
    /// The beat is a glyph over a body that asserts no ongoing work (the
    /// condition `ADR-003` §6 says voids it if an implementer drops it, as
    /// restated by ADR-005 §5) so a lingering `terminal` must not reach this
    /// channel. It could not before because the body was `idle` for every frame
    /// of a beat; it cannot now because the sequence is a function of the
    /// open-call count, which is `0` for every frame of a beat. **That is the
    /// substitution ADR-005 makes, checked here in the frames the node plays
    /// rather than in the policy that chose them.**
    @Test(.enabled(if: SceneArt.isAvailable))
    func aBodyWithNoOpenCallPlaysNoPhraseEvenUnderALingeringGlyph() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)

        character.apply(state: .idle, facing: .right, startingAt: 0)
        #expect(character.frameSequenceForTesting == [0], "the standing body moved")

        // The beat's shape as the room now draws it: the open set emptied, so
        // `BadgeSelection.select` reaches `closingBeat` and the slot still shows
        // `terminal`, over a body that is **seated** and has stopped moving,
        // because the turn did not end when the call did.
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.apply(badge: BadgeSelection.select(openToolNames: [], closingBeat: .terminal))
        #expect(character.badgeSelection.badge == .terminal, "the beat is not set up")
        #expect(character.state == .working, "the beat's body is the seated one")
        #expect(character.frameSequenceForTesting == [0],
                "a closing beat put the seated body back in motion")
        #expect(character.heldObjectForTesting == nil, "a closing beat filled the hands")

        // And the same body with a call open does move, so the assertions above
        // are about the empty set rather than about a character that could not
        // animate at all.
        character.apply(badge: BadgeSelection.select(openToolNames: ["Bash"]))
        #expect(character.frameSequenceForTesting.count > 1,
                "the seated body cannot move at all, so this test proves nothing")
    }

    /// **A call parked at a permission gate stops, and the attention bubble is
    /// not what stops it.** [ADR-005 §7]
    ///
    /// This test used to be named `aGatedCallKeepsItsGaitAndLosesOnlyItsHands`
    /// and asserted the opposite of its first half. The argument it carried (
    /// I2 keys the body on the open-call set, a gated agent is still holding
    /// those calls, so it is still working) is *true about the set* and was
    /// wrong about the room: a call parked at a dialog is not running, which is
    /// ADR-003 §1's own sentence for refusing to draw `terminal` over it, and
    /// the body was drawing the fastest phrase in the table over the one agent
    /// in the room that could not proceed.
    ///
    /// **The three characters here are the whole of the distinction**, and the
    /// middle one is why the gate needed a delta of its own:
    ///
    /// - **ungated, `Bash` open**: moves, and holds a console;
    /// - **the bubble alone**: moves. A `Notification` can name an agent with
    ///   no gate at all (`idle_prompt`, and a `permission_prompt` that no mark
    ///   could attribute), so the bubble is not evidence of a block. It empties
    ///   the hands, because that is a claim about the badge slot;
    /// - **gated**: still, whatever the slot shows. The bubble arrives 6.0 s
    ///   after the gate opens, so for those six seconds this is the only signal
    ///   there is.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aGatedCallStopsMovingAndTheBubbleIsNotWhatStopsIt() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let ungated = Self.character(store)
        Self.working(ungated, tools: ["Bash"])

        let bubbleOnly = Self.character(store)
        bubbleOnly.advance(to: 0)
        bubbleOnly.apply(state: .working, facing: .right, startingAt: 0)
        bubbleOnly.apply(badge: BadgeSelection.select(
            openToolNames: ["Bash"], attention: .permissionPrompt))

        let gated = Self.character(store)
        gated.advance(to: 0)
        gated.apply(state: .working, facing: .right, startingAt: 0)
        gated.apply(badge: BadgeSelection.select(openToolNames: ["Bash"]))
        gated.setGated(true)

        #expect(ungated.frameSequenceForTesting.count > 1, "the ungated body does not move")
        #expect(bubbleOnly.frameSequenceForTesting == ungated.frameSequenceForTesting,
                "the attention bubble alone changed how the body moves")
        #expect(gated.frameSequenceForTesting == [0],
                "a character stopped at a permission gate is still playing a phrase")

        // The hands are the badge layer's business and are unmoved by this: the
        // gate empties nothing the bubble did not already empty, and it empties
        // nothing on a character whose slot still shows its tool.
        #expect(ungated.heldObjectForTesting == .console)
        #expect(bubbleOnly.heldObjectForTesting == nil, "the bubble left something in the hands")
        #expect(gated.heldObjectForTesting == .console)

        // Answering the dialog puts the body straight back into its own class's
        // phrase: no new badge, no new state, nothing else to re-send.
        gated.setGated(false)
        #expect(gated.frameSequenceForTesting == ungated.frameSequenceForTesting,
                "the body did not resume when the gate cleared")
    }
}
