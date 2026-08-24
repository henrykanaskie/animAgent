import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **The dormancy signal, both halves.** [ADR-006 §12]
///
/// A dormant character used to be told apart by a badge and nothing else. It now
/// has a dark desk screen and a dimmed body, and this file measures both: the
/// inks and the separations on the art side, the keying and the intent
/// discipline on the director side, and (the two that matter) that the dim
/// cannot weaken I7's contrast floor and that neither channel animates.
///
/// The colour arithmetic is deliberately ungated: it is over bitmaps this
/// repository draws itself, which is the layer `scripts/lint-palette.py` cannot
/// see, because that lint reads `assets/manifest.json` and these pixels have no
/// manifest entry. The measurements that need the *cast* are gated, and say so.
struct DeskScreenArtTests {

    /// The room's band, from `04-ART-DIRECTION.md`. Same three numbers
    /// `DeskWorkArtTests` uses; repeated rather than shared so that a change to
    /// one file cannot silently move the other's floor.
    static let valueFloor = 0.55
    static let valueCeiling = 0.92
    static let saturationCeiling = 0.25

    static func value(_ colour: Bitmap.RGBA) -> Double {
        Double(max(colour.r, max(colour.g, colour.b))) / 255
    }

    static func saturation(_ colour: Bitmap.RGBA) -> Double {
        let high = value(colour)
        guard high > 0 else { return 0 }
        let low = Double(min(colour.r, min(colour.g, colour.b))) / 255
        return (high - low) / high
    }

    /// Every kind's bitmap in a given state, whichever file owns it.
    static func bitmap(_ kind: WorkKind, _ screen: DeskScreen) -> Bitmap {
        DeskWorkArt.bitmap(kind, screen: screen) ?? DeskMonitorArt.bitmap(screen: screen)
    }

    // MARK: The ink

    /// **The off ink is inside the room's band, and it is the darkest 8-bit
    /// neutral that is.**
    ///
    /// The band's floor is what stops the room owning the darkest pixel on
    /// screen, and a dark screen is the one place a desk object is allowed to go
    /// looking for it. `140/255` is 0.549 and is outside; `141/255` is 0.553 and
    /// is not. This asserts both, so a later "make it darker" is a decision that
    /// fails a test rather than one that slips through.
    @Test func theOffInkIsTheDarkestNeutralTheRoomBandAdmits() {
        let off = DeskMonitorArt.screenOff
        #expect(Self.value(off) >= Self.valueFloor,
                "the off ink is value \(Self.value(off)), under the room's floor")
        #expect(Self.value(off) <= Self.valueCeiling)
        #expect(Self.saturation(off) == 0, "an off screen emits nothing, so it has no hue")
        // One 8-bit step darker is outside the band, which is what makes this
        // the darkest admissible neutral rather than a round number.
        let darker = Bitmap.RGBA(off.r - 1, off.g - 1, off.b - 1)
        #expect(Self.value(darker) < Self.valueFloor)
        #expect(off.r == off.g && off.g == off.b, "the off ink is neutral grey")
    }

    /// **Separable by value, which is the channel that survives 1x.**
    ///
    /// The lit ink is 0.871 and the off ink is 0.553: a step of 0.318, larger
    /// than the room's whole measured spread from its darkest ink to its mean
    /// (0.659 → 0.785 = 0.126) and larger than the lit screen's own step away
    /// from the casing it sits in (0.871 − 0.667 = 0.204). Both comparisons are
    /// made here rather than asserted as a bare threshold, because a bare
    /// threshold is a number somebody tuned.
    @Test func theLitAndDarkScreensAreSeparableByValueAtOnex() {
        let lit = Self.value(DeskMonitorArt.screen)
        let off = Self.value(DeskMonitorArt.screenOff)
        let casing = Self.value(DeskMonitorArt.outline)
        let separation = lit - off

        #expect(separation > 0.3, "lit and dark differ by only \(separation)")
        #expect(separation > lit - casing,
                "the screen turning off is a smaller change than it turning on")
        #expect(separation > 0.785 - 0.659,
                "the change is smaller than the room's own darkest-to-mean spread")
        // And the dark screen is *darker than the casing around it*, so the
        // object reads as a recess rather than dissolving into one flat slab.
        #expect(off < casing, "the off screen is not darker than the box it sits in")
    }

    /// **The room still does not own the darkest pixel on screen.** [I7]
    ///
    /// The off ink is 0.553 against the cast's darkest at 0.314, and against
    /// the *dimmed* cast, which is what a dark screen is usually standing beside.
    /// `HeldObjectArt.outline` is the cast's darkest value by construction (its
    /// own doc comment records that it was chosen to sit on the cast floor), so
    /// this measures against a colour rather than against a remembered number.
    @Test func theOffScreenIsNowhereNearTheDarkestPixelOnScreen() {
        let off = Self.value(DeskMonitorArt.screenOff)
        let castFloor = Self.value(HeldObjectArt.outline)
        let dimmedCastFloor = Self.value(CharacterDim.dimmed(HeldObjectArt.outline))
        #expect(castFloor <= 0.32, "the assumed cast floor moved")
        #expect(off > castFloor + 0.2)
        #expect(off > dimmedCastFloor + 0.2)
    }

    // MARK: The bitmaps

    /// Every pixel of every kind, in **both** states, is inside the room's band
    /// and under its saturation ceiling. `DeskWorkArtTests` asserts this for the
    /// lit state; a second state is a second chance to leave the band.
    @Test func everyPixelOfADarkObjectStaysInsideTheRoomsBand() {
        for kind in WorkKind.allCases {
            let bitmap = Self.bitmap(kind, .dark)
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                    let pixel = bitmap.at(x, y)
                    #expect(Self.value(pixel) >= Self.valueFloor
                            && Self.value(pixel) <= Self.valueCeiling,
                            "\(kind.rawValue) dark at (\(x), \(y)) has value \(Self.value(pixel))")
                    #expect(Self.saturation(pixel) <= Self.saturationCeiling,
                            "\(kind.rawValue) dark at (\(x), \(y)) is too saturated")
                }
            }
        }
    }

    /// **The two kinds with screens change and the two paper kinds do not.**
    ///
    /// Turning paper off is fiction, so `research` and `coordinating` return
    /// bit-identical bitmaps in either state, checked here rather than left to
    /// a reader to infer from `WorkKind.hasScreen`, and stated as *identical
    /// pixels* rather than *no crash*.
    @Test func onlyTheTwoKindsWithScreensRedraw() {
        for kind in WorkKind.allCases {
            let lit = Self.bitmap(kind, .lit)
            let dark = Self.bitmap(kind, .dark)
            let changed = (0..<lit.height).reduce(0) { total, y in
                total + (0..<lit.width).filter { lit.at($0, y) != dark.at($0, y) }.count
            }
            if kind.hasScreen {
                #expect(changed > 0, "\(kind.rawValue) has a screen and did not go dark")
            } else {
                #expect(changed == 0,
                        "\(kind.rawValue) is paper and \(changed) pixels of it changed, [I1]")
            }
        }
        #expect(WorkKind.allCases.filter(\.hasScreen).count == 2)
        #expect(Set(WorkKind.allCases.filter(\.hasScreen)) == [.authoring, .running])
    }

    /// **The silhouette does not move.** A screen going dark is a colour change,
    /// and the outline is the object's identity [ADR-006 §1a], so every pixel
    /// that had ink still has ink, and no pixel gained any. Without this, a
    /// later edit could make a dark object a different *shape* and break the
    /// four-way silhouette separation `DeskWorkArtTests` protects.
    @Test func theSilhouetteIsIdenticalInBothStates() {
        for kind in WorkKind.allCases {
            let lit = Self.bitmap(kind, .lit)
            let dark = Self.bitmap(kind, .dark)
            #expect(lit.width == dark.width && lit.height == dark.height)
            for y in 0..<lit.height {
                for x in 0..<lit.width {
                    #expect(lit.at(x, y).a == dark.at(x, y).a,
                            "\(kind.rawValue) changed shape at (\(x), \(y))")
                }
            }
        }
    }

    /// **The laptop's keyboard stays lit and the monitor's status dots do not.**
    ///
    /// Both files spell their `b` glyph with `DeskMonitorArt.statusDot`, and it
    /// means different things in each: two icon dots *on the glass* for the
    /// monitor, and the keyboard *under the hinge* for the laptop. A keyboard
    /// does not go dark when a display does. This measures the distinction on
    /// the pixels rather than trusting the two doc comments to stay in step.
    @Test func aDarkScreenTakesTheGlassAndNotTheHardware() {
        let laptopDark = Self.bitmap(.authoring, .dark)
        #expect(laptopDark.contains(DeskMonitorArt.statusDot),
                "the laptop's keyboard row went dark with its screen")
        #expect(laptopDark.contains(DeskMonitorArt.screenOff))
        #expect(!laptopDark.contains(DeskWorkArt.face), "the laptop screen is still lit")

        let monitorDark = Self.bitmap(.running, .dark)
        #expect(!monitorDark.contains(DeskMonitorArt.statusDot),
                "a dark monitor kept its status lights on")
        #expect(!monitorDark.contains(DeskMonitorArt.screen))
        #expect(monitorDark.contains(DeskMonitorArt.outline), "the casing went dark too")
    }

    /// The texture cache key carries the state, or the first picture drawn would
    /// be handed to every later caller and the screen would look stuck. Also
    /// that the two keys are stable strings rather than anything derived from a
    /// pointer.
    @Test func theTextureKeyDistinguishesTheTwoStates() {
        for kind in WorkKind.allCases {
            #expect(kind.textureKey(screen: .lit) != kind.textureKey(screen: .dark))
            #expect(kind.textureKey(screen: .lit) == kind.textureKey(screen: .lit))
        }
        #expect(Set(WorkKind.allCases.flatMap {
            [$0.textureKey(screen: .lit), $0.textureKey(screen: .dark)]
        }).count == WorkKind.allCases.count * 2)
    }
}

private extension Bitmap {
    /// Whether any opaque pixel of this bitmap is exactly `colour`.
    func contains(_ colour: Bitmap.RGBA) -> Bool {
        for y in 0..<height {
            for x in 0..<width where at(x, y).a > 0 && at(x, y) == colour { return true }
        }
        return false
    }
}

/// The screen's keying: what turns it off, what must not, and how often it is
/// allowed to say so.
struct DeskScreenDirectorTests {

    static let cast = ["06", "07", "09", "10", "17", "19"]

    static func ref(_ agent: AgentID) -> AgentRef {
        AgentRef(project: "/p", session: "s", agent: agent)
    }

    static func call(_ id: String, _ tool: String) -> OpenCall {
        let start = Date(timeIntervalSince1970: 0)
        return OpenCall(
            toolUseID: id, toolName: tool, startedAt: start,
            deadline: start.addingTimeInterval(60))
    }

    static func screens(_ intents: [SpriteIntent]) -> [DeskScreen] {
        intents.compactMap {
            if case let .setDeskScreen(_, screen) = $0 { return screen } else { return nil }
        }
    }

    static func seated(_ director: inout SceneDirector, _ agent: AgentRef, type: String?)
    -> [SpriteIntent] {
        director.apply(
            [.agentAppeared(agent: agent, agentType: type, lifecycle: .active)],
            at: Date(timeIntervalSince1970: 0))
    }

    /// **A character walks in with its screen on, and is not told so.** The
    /// memory is seeded at spawn exactly as `emittedGated`'s is, so the commonest
    /// character in the corpus (one that never goes dormant) never receives
    /// this intent at all.
    @Test func aSpawningCharactersScreenIsLitAndUnstated() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.mainThread)
        let intents = Self.seated(&director, agent, type: nil)
        #expect(Self.screens(intents).isEmpty)
        #expect(director.deskScreen(agent) == .lit)
    }

    /// **`SubagentStop` darkens the screen and a revival relights it**, the
    /// subagent half of the turn boundary, which is the half that never sees a
    /// `turnChanged` delta at all.
    @Test func aSubagentsTurnBoundaryTurnsTheScreenOff() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.subagent("a1"))
        _ = Self.seated(&director, agent, type: "Explore")

        let asleep = director.apply([.dormancyChanged(agent: agent, isDormant: true)])
        #expect(Self.screens(asleep) == [.dark])
        #expect(director.deskScreen(agent) == .dark)

        let awake = director.apply([.dormancyChanged(agent: agent, isDormant: false)])
        #expect(Self.screens(awake) == [.lit])
        #expect(director.deskScreen(agent) == .lit)
    }

    /// **`Stop` darkens the main agent's**, which is the other half and the only
    /// half `turnChanged` covers.
    @Test func theMainThreadsTurnBoundaryTurnsTheScreenOff() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.mainThread)
        _ = Self.seated(&director, agent, type: nil)

        #expect(Self.screens(director.apply([.turnChanged(agent: agent, hasTurn: false)])) == [.dark])
        #expect(Self.screens(director.apply([.turnChanged(agent: agent, hasTurn: true)])) == [.lit])
    }

    /// **The finding the brief asked to be checked rather than assumed.**
    ///
    /// `turnChanged(hasTurn: false)` is **not** guaranteed to have fired for an
    /// agent that `dormancyChanged(isDormant: true)` reports; it never fires
    /// for a subagent at all, because `Stop` carries no `agent_id` and
    /// `SubagentStop` always does. What closes a subagent's turn is the dormancy
    /// arm's own `isInTurn = !isDormant`, and this constructs the one ordering
    /// that leaves the two disagreeing: a `callOpened` after a dormancy, with no
    /// revival between them. The live model cannot produce it:
    /// `WorldModel.ensureAgent` revives before `PreToolUse` opens anything, but
    /// `Presentation` is a value with two fields and this is what it does when
    /// they conflict.
    ///
    /// Dark is the right answer, and it is `BadgeSelection.isSleeping`'s own
    /// ruling on the identical co-occurrence: the calls would be stale and the
    /// turn boundary would not be.
    @Test func aDormantAgentsScreenIsDarkEvenWithACallLeftOpen() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.subagent("a1"))
        _ = Self.seated(&director, agent, type: "Explore")
        _ = director.apply([.dormancyChanged(agent: agent, isDormant: true)])
        #expect(director.deskScreen(agent) == .dark)

        let reopened = director.apply([.callOpened(agent: agent, call: Self.call("t1", "Bash"))])
        #expect(Self.screens(reopened).isEmpty, "a stale call relit a dormant agent's screen")
        #expect(director.deskScreen(agent) == .dark)
        // And the body agrees with it: the badge slot shows sleep over the tool
        // for the same reason.
        #expect(director.badge(agent).isSleeping)
    }

    /// **The screen is keyed to the turn and not to the calls inside it.** Twenty
    /// calls open and close inside one turn and the screen is never mentioned,
    /// which is the whole reason this is not `setBadge` with extra steps. At a
    /// 23 ms median call it would otherwise be the strobe ADR-006 §10 refused.
    @Test func callsInsideATurnNeverTouchTheScreen() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.mainThread)
        _ = Self.seated(&director, agent, type: nil)
        var emitted: [DeskScreen] = []
        for index in 0..<20 {
            emitted += Self.screens(director.apply([
                .callOpened(agent: agent, call: Self.call("t\(index)", "Bash"))]))
            emitted += Self.screens(director.apply([
                .callClosed(agent: agent, toolUseID: "t\(index)", toolName: "Bash",
                            outcome: .succeeded)]))
        }
        #expect(emitted.isEmpty, "the screen changed \(emitted.count) times inside one turn")
        #expect(director.deskScreen(agent) == .lit)
    }

    /// A repeated `SubagentStop` restates nothing, the same discipline
    /// `setDeskObject` and `setNameplate` keep.
    @Test func aRepeatedTurnBoundaryEmitsNoSecondIntent() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.subagent("a1"))
        _ = Self.seated(&director, agent, type: "Explore")
        #expect(Self.screens(director.apply([
            .dormancyChanged(agent: agent, isDormant: true)])) == [.dark])
        #expect(Self.screens(director.apply([
            .dormancyChanged(agent: agent, isDormant: true)])).isEmpty)
    }

    /// **A permission gate does not turn the screen off.** A blocked agent is at
    /// its workstation with a turn in progress, that is exactly what ADR-005 §7
    /// says, and it is why the gate takes the motion and nothing else. A dark
    /// screen there would assert that the agent had finished, when what it is
    /// doing is waiting for the human.
    @Test func aPermissionGateLeavesTheScreenOn() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.mainThread)
        _ = Self.seated(&director, agent, type: nil)
        _ = director.apply([.callOpened(agent: agent, call: Self.call("t1", "Bash"))])
        let gated = director.apply([.gateChanged(agent: agent, isGated: true)])
        #expect(Self.screens(gated).isEmpty)
        #expect(director.deskScreen(agent) == .lit)
        let attentive = director.apply([
            .attentionChanged(agent: agent, attention: .permissionPrompt)])
        #expect(Self.screens(attentive).isEmpty)
        #expect(director.deskScreen(agent) == .lit)
    }

    /// The screen goes with the character: a departed agent leaves no memory
    /// behind for a reused seat to inherit. [I4]
    @Test func departureForgetsTheScreen() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.subagent("a1"))
        _ = Self.seated(&director, agent, type: "Explore")
        _ = director.apply([.dormancyChanged(agent: agent, isDormant: true)])
        _ = director.apply([.agentDeparted(agent: agent)])
        #expect(director.deskScreen(agent) == .dark, "an unknown agent is not running anything")

        let back = Self.seated(&director, agent, type: "Explore")
        #expect(Self.screens(back).isEmpty, "the seed came back stale")
        #expect(director.deskScreen(agent) == .lit)
    }

    /// **Over the whole corpus**, so the change count is a measurement rather
    /// than a claim: every screen change lands on a turn boundary, and the total
    /// is the number of boundaries the corpus contains rather than the number of
    /// calls it contains.
    @Test func theCorpusChangesTheScreenOnceEveryTurnBoundaryAndNeverMore() async throws {
        var director = SceneDirector(variantIDs: Self.cast)
        var screenChanges = 0
        var callOpens = 0
        var boundaries = 0

        for (at, deltas) in try await SceneFixtures.timedBatchedDeltas("four-subagents") {
            for delta in deltas {
                switch delta {
                case .callOpened: callOpens += 1
                case .dormancyChanged, .turnChanged: boundaries += 1
                default: break
                }
            }
            screenChanges += Self.screens(director.apply(deltas, at: at)).count
        }

        // Printed, in the shape `DeskObjectCorpusTests` prints its own table, so
        // a run reports the numbers rather than only agreeing with them.
        print("""
            desk screen over four-subagents: \(screenChanges) changes, \
            \(boundaries) turn-boundary deltas, \(callOpens) calls opened
            """)
        #expect(callOpens > 0)
        #expect(screenChanges > 0, "no screen ever changed, so this measured nothing")
        #expect(screenChanges <= boundaries,
                "the screen changed more often than the turn did")
        #expect(screenChanges < callOpens,
                "the screen is tracking calls rather than turns")
    }
}

/// The character dim: the two numbers, the direction of the effect, and the two
/// things it must not touch.
struct CharacterDimTests {

    static func value(_ colour: Bitmap.RGBA) -> Double {
        Double(max(colour.r, max(colour.g, colour.b))) / 255
    }

    static func saturation(_ colour: Bitmap.RGBA) -> Double {
        let high = value(colour)
        guard high > 0 else { return 0 }
        let low = Double(min(colour.r, min(colour.g, colour.b))) / 255
        return (high - low) / high
    }

    /// I7's third check, from `scripts/lint-palette.py`.
    static let minimumValueContrast = 0.40

    /// **The floor one named theme is held to instead**, mirroring
    /// `scripts/lint-palette.py`'s `THEME_MIN_VALUE_CONTRAST`. [ADR-011]
    ///
    /// `office` draws its props, floor and wall on the pack's own values rather
    /// than the standard `[0.55, 0.92]` band, which puts its mean at 0.685 and
    /// its contrast against the cast's darkest ink at 0.372. The number it is
    /// measured against is not a concession to that: it is
    /// `output/01-engineering-office.png`, the composite the maintainer built
    /// off the untouched pack and asked this room to reproduce, which measures
    /// **0.353** on this same test. A room that reads worse than the picture it
    /// is copying still fails here.
    ///
    /// **This is the second copy of a fact and the duplication is deliberate**,
    /// because the lint reads PNGs off disk and this reads the manifest through
    /// the typed loader: two paths to the same claim. It is also the copy that
    /// drifted: it sat at 0.40 while the lint moved, and the suite went red at
    /// exactly the right moment, which is the argument for keeping both.
    static func minimumValueContrast(forTheme id: String) -> Double {
        id == "office" ? 0.35 : minimumValueContrast
    }
    /// Its first two, which are what the dim's factor was derived from.
    static let characterMinimumSaturation = 0.55
    static let roomMaximumSaturation = 0.25

    // MARK: The arithmetic, with no art on disk

    /// **The blend cannot raise a character's darkest value, at any factor.**
    ///
    /// This is the safety argument for the whole channel and it is structural
    /// rather than empirical: blending is a per-channel lerp, and the tint's own
    /// value equals the cast's darkest pixel, so no dimmed pixel can be brighter
    /// than the darkest lit one already is. Swept over the whole factor range
    /// and over the tint itself, so the property is checked rather than the one
    /// shipped number.
    @Test func theDimCannotWeakenI7sContrastFloorAtAnyFactor() {
        let castFloor = HeldObjectArt.outline
        #expect(Self.value(castFloor) <= 0.315, "the assumed cast floor moved")
        for step in 0...20 {
            let factor = Double(step) / 20
            let dimmed = CharacterDim.dimmed(castFloor, factor: factor)
            #expect(Self.value(dimmed) <= Self.value(castFloor) + 1.0 / 255,
                    "factor \(factor) raised the cast's darkest value")
        }
        // And the tint is the reason: its value *is* the cast floor.
        #expect(abs(Self.value(CharacterDim.tint) - Self.value(castFloor)) < 1.0 / 255)
    }

    /// **Alpha was measured out, not judged out**, and this is the arithmetic
    /// that did it. Compositing a character of value `v` at alpha `α` over a
    /// background of value `b` gives `vα + b(1−α)`, so reducing alpha over a
    /// pale room *raises* the darkest character pixel and *cuts* the contrast;
    /// the opposite of the intuition that a see-through character recedes
    /// safely. Against the binding theme, every alpha under ~0.94 fails I7.
    @Test func reducedAlphaWouldHaveBrokenTheContrastFloorAtAnyVisibleStrength() {
        let castFloor = Self.value(HeldObjectArt.outline)   // 0.314
        let themeMean = 0.738                               // mission_control, the lowest
        func contrast(alpha: Double, over background: Double) -> Double {
            themeMean - (castFloor * alpha + background * (1 - alpha))
        }
        // The direction, first: less alpha is less contrast, not more.
        #expect(contrast(alpha: 0.5, over: themeMean) < contrast(alpha: 1.0, over: themeMean))
        // A visible dim (call it 60%) is nowhere near the floor.
        #expect(contrast(alpha: 0.6, over: themeMean) < Self.minimumValueContrast)
        #expect(contrast(alpha: 0.6, over: 0.604) < Self.minimumValueContrast)
        // And the largest reduction I7 permits is a few per cent, over either
        // background: not a signal, a rounding error.
        var admissible = 0.0
        for step in 0...100 where contrast(alpha: Double(step) / 100, over: themeMean)
            >= Self.minimumValueContrast {
            admissible = min(admissible == 0 ? 1 : admissible, Double(step) / 100)
        }
        #expect(admissible > 0.9,
                "alpha \(admissible) still clears the floor, so the tint was not forced")
        // The tint, by contrast, clears it at full strength.
        #expect(themeMean - Self.value(CharacterDim.dimmed(HeldObjectArt.outline))
                >= Self.minimumValueContrast)
    }

    /// Alpha is carried through the blend untouched, which is the silhouette
    /// staying exactly where it was. A dim that ate an edge pixel would move
    /// M0's silhouette findings, the badge slot's clearances and the seated
    /// head's occlusion arithmetic all at once.
    @Test func theDimIsAColourChangeAndNeverAnOutlineChange() {
        for alpha in [UInt8(0), 1, 128, 254, 255] {
            let colour = Bitmap.RGBA(200, 40, 90, alpha)
            #expect(CharacterDim.dimmed(colour).a == alpha)
        }
    }

    // MARK: The cast, measured

    /// **The factor's derivation, re-measured over the shipped art.**
    ///
    /// A dormant character sits in the gap between the two saturation thresholds
    /// the palette lint already enforces: under `CHAR_MIN_SAT` (0.55), so it no
    /// longer carries the saturation I7 reserves for the working cast, and over
    /// `ROOM_MAX_SAT` (0.25), so it has not become scenery. The lower bound
    /// holds at any factor (the tint's own saturation is 0.275) and the upper
    /// bound is what picked 0.65: at 0.60 the cast still peaks at 0.585.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theDimmedCastSitsBetweenTheTwoSaturationThresholds() throws {
        let colours = try Self.castColours()
        #expect(colours.count > 50, "only \(colours.count) cast colours were read")

        func peakSaturation(factor: Double) -> Double {
            colours.map { Self.saturation(CharacterDim.dimmed($0, factor: factor)) }.max() ?? 0
        }

        let lit = peakSaturation(factor: 0)
        let dimmed = peakSaturation(factor: CharacterDim.factor)
        print("cast peak saturation: lit \(lit), dimmed \(dimmed)")
        #expect(lit >= Self.characterMinimumSaturation, "the lit cast stopped clearing I7")
        #expect(dimmed < Self.characterMinimumSaturation,
                "at factor \(CharacterDim.factor) the cast still peaks at \(dimmed)")
        #expect(dimmed > Self.roomMaximumSaturation,
                "a dimmed character has become scenery")
        // The factor is near the boundary rather than comfortably past it,
        // which is what "smallest twentieth that clears it" means.
        #expect(peakSaturation(factor: CharacterDim.factor - 0.05)
                >= Self.characterMinimumSaturation,
                "a smaller factor would have done, so this one is not derived")
        // The lower bound needs no factor at all.
        #expect(peakSaturation(factor: 1) > Self.roomMaximumSaturation)
    }

    /// **The direction of the effect on I7's tightest number, over real
    /// pixels.**
    ///
    /// The theme means are re-measured here rather than quoted, because the
    /// binding number is `theme mean − darkest character pixel` and both halves
    /// have to come from the same art the scene draws. The contrast must not
    /// fall, in any theme, for any variant.
    @Test(.enabled(if: SceneArt.isAvailable))
    func dimmingACharacterRaisesItsValueContrastRatherThanCuttingIt() throws {
        let manifest = try SceneFixtures.manifest()
        var lowestThemeMean = (id: "", mean: 1.0)
        for id in manifest.themes.orderedIDs {
            guard let theme = manifest.themes.theme(id) else { continue }
            var paths: Set<String> = []
            paths.formUnion(theme.room.builderTiles)
            paths.formUnion(theme.room.propFiles)
            for (_, role) in theme.room.propRoles { paths.formUnion(role.declaredPaths) }
            var total = 0.0
            var count = 0
            for path in paths {
                let bitmap = try PixelImage.bitmap(contentsOf: manifest.url(path))
                for y in 0..<bitmap.height {
                    for x in 0..<bitmap.width where bitmap.at(x, y).a >= 128 {
                        total += Self.value(bitmap.at(x, y))
                        count += 1
                    }
                }
            }
            guard count > 0 else { continue }
            let mean = total / Double(count)
            if mean < lowestThemeMean.mean { lowestThemeMean = (id, mean) }
        }
        #expect(!lowestThemeMean.id.isEmpty, "no theme was measured")

        let colours = try Self.castColours()
        let litDarkest = colours.map(Self.value).min() ?? 0
        let dimmedDarkest = colours
            .map { Self.value(CharacterDim.dimmed($0)) }.min() ?? 0
        let litContrast = lowestThemeMean.mean - litDarkest
        let dimmedContrast = lowestThemeMean.mean - dimmedDarkest
        print("""
            lowest theme mean \(lowestThemeMean.mean) (\(lowestThemeMean.id)); \
            cast darkest lit \(litDarkest) → contrast \(litContrast); \
            dimmed \(dimmedDarkest) → contrast \(dimmedContrast)
            """)

        // Measured against the floor *that theme* is held to, because the
        // binding theme is the one with the lowest mean and since ADR-011 that
        // is `office`, which is on its own floor. Naming the theme in the
        // message matters: a future theme that darkens past `office` becomes
        // the binding one and is held to 0.40, and the failure has to say so
        // rather than reading as office drifting.
        let floorForTheme = Self.minimumValueContrast(forTheme: lowestThemeMean.id)
        #expect(litContrast >= floorForTheme,
                "the lit cast stopped clearing I7 over '\(lowestThemeMean.id)': \(litContrast) against a floor of \(floorForTheme)")
        #expect(dimmedContrast >= floorForTheme,
                "the dim broke I7's contrast floor over '\(lowestThemeMean.id)': \(dimmedContrast) against a floor of \(floorForTheme)")
        #expect(dimmedContrast >= litContrast,
                "the dim cut the contrast rather than raising it")
    }

    /// Every distinct opaque colour in the shipped cast, read once and reused.
    static func castColours() throws -> [Bitmap.RGBA] {
        let manifest = try SceneFixtures.manifest()
        var colours: Set<Bitmap.RGBA> = []
        for id in manifest.characters.orderedVariantIDs {
            guard let variant = manifest.characters.variant(id) else { continue }
            for (_, animation) in variant.states {
                for (_, paths) in animation.frames {
                    for path in paths {
                        let bitmap = try PixelImage.bitmap(contentsOf: manifest.url(path))
                        for y in 0..<bitmap.height {
                            for x in 0..<bitmap.width where bitmap.at(x, y).a >= 128 {
                                colours.insert(bitmap.at(x, y))
                            }
                        }
                    }
                }
            }
        }
        return Array(colours)
    }
}

/// The dim where it is actually applied: on the nodes.
@MainActor
struct CharacterDimSceneTests {

    static func character(_ manifest: Manifest) throws -> Character {
        let store = TextureStore(manifest: manifest)
        let variant = try #require(manifest.characters.orderedVariantIDs.first)
        return Character(
            variant: variant, nameplate: NameplateText(lead: "8DE", role: "Explore"), store: store)
    }

    /// **The body dims, the identity does not.** `Character.Layer`'s own comment
    /// is the argument: M0 measured that this cast is not separable by
    /// silhouette, so the nameplate *is* the identity and the badge *is* the
    /// tool. Degrading either would mean a viewer can no longer tell *which*
    /// agent went dormant, which is less information than before rather than
    /// more.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aDormantCharacterDimsItsBodyAndNotItsNameplateOrBadge() throws {
        let character = try Self.character(try SceneFixtures.manifest())
        #expect(character.bodyColorBlendFactorForTesting == 0)

        character.apply(badge: BadgeSelection.select(openToolNames: [String](), isDormant: true))
        #expect(character.isDimmedForTesting)
        #expect(abs(character.bodyColorBlendFactorForTesting - CGFloat(CharacterDim.factor)) < 0.001)
        #expect(character.identityColorBlendFactorsForTesting.allSatisfy { $0 == 0 },
                "the dim reached the nameplate or the badge")
        #expect(character.isBadgeVisible, "the dormancy tab went with the dim")
        #expect(character.isNameplateVisible)

        character.apply(badge: .none)
        #expect(!character.isDimmedForTesting)
        #expect(character.bodyColorBlendFactorForTesting == 0)
    }

    /// **An instant step, never a fade.** [I2] A crossfade is motion and a
    /// dormant character holds no open call, so the dim must be one still state
    /// to another. Advanced through a second of frames at 60 fps with the blend
    /// factor read on every one: a fade would show a ramp and an `SKAction`
    /// would show anything at all.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theDimDoesNotAnimate() throws {
        let character = try Self.character(try SceneFixtures.manifest())
        character.advance(to: 0)
        character.apply(badge: BadgeSelection.select(openToolNames: [String](), isDormant: true))

        var factors: Set<CGFloat> = []
        for frame in 0...60 {
            character.advance(to: Double(frame) / 60)
            factors.insert(character.bodyColorBlendFactorForTesting)
        }
        #expect(factors.count == 1, "the dim took \(factors.count) values over a second")
        #expect(!character.hasActions(), "the dim ran an SKAction")
    }

    /// **Dormancy dims the body whether or not the badge slot is showing the
    /// tab.** The dim is keyed to the *fact* (`isDormant`) and the slot has a
    /// precedence order (`isSleeping` is `isDormant && !isAttention`), so an
    /// attention prompt over a finished agent takes the badge and leaves the
    /// body dimmed, which is the truthful picture of both facts at once.
    @Test(.enabled(if: SceneArt.isAvailable))
    func attentionTakesTheBadgeSlotAndLeavesTheDimAlone() throws {
        let character = try Self.character(try SceneFixtures.manifest())
        let selection = BadgeSelection.select(
            openToolNames: [String](), attention: .permissionPrompt, isDormant: true)
        #expect(!selection.isSleeping)
        character.apply(badge: selection)
        #expect(character.isDimmedForTesting)
        #expect(character.bodyColorBlendFactorForTesting > 0)
    }
}

/// The screen where it is actually drawn: on the node.
@MainActor
struct DeskScreenSceneTests {

    static let agent = AgentRef(project: "/p", session: "s", agent: .subagent("a1"))

    static func scene(_ manifest: Manifest) -> RoomScene {
        let scene = RoomScene(manifest: manifest)
        scene.apply([.spawnCharacter(
            agent: agent, variant: manifest.characters.orderedVariantIDs[0],
            nameplate: NameplateText(lead: "", role: "Explore"), seat: 1,
            station: "", costume: nil)])
        return scene
    }

    /// **The node is reused, and the texture is the dark one.** ADR-002 §6 rule
    /// 1's discipline: a screen change swaps a texture on a node that is already
    /// in the tree. The texture is compared against the one the store hands out
    /// for the dark key, so this checks *which* picture is up rather than that
    /// one is.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aScreenChangeSwapsTheTextureAndNeverTheNode() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = Self.scene(manifest)
        // The scene's own store, not a second one: `texture(bitmap:key:)` caches
        // per store, so a fresh store would hand back an equal texture that is
        // not the same object and the identity comparison would mean nothing.
        let store = scene.store

        scene.apply([.setDeskObject(agent: Self.agent, kind: .running)])
        let node = try #require(scene.deskObjectNodesForTesting[Self.agent])
        let lit = try #require(store.texture(
            bitmap: DeskMonitorArt.bitmap(screen: .lit),
            key: WorkKind.running.textureKey(screen: .lit)))
        #expect(node.texture === lit)
        #expect(scene.deskScreensForTesting()[Self.agent] == nil, "the default is not the seed")

        scene.apply([.setDeskScreen(agent: Self.agent, screen: .dark)])
        #expect(scene.deskObjectNodesForTesting[Self.agent] === node, "the node was rebuilt")
        let dark = try #require(store.texture(
            bitmap: DeskMonitorArt.bitmap(screen: .dark),
            key: WorkKind.running.textureKey(screen: .dark)))
        #expect(node.texture === dark)
        #expect(node.texture !== lit)
        #expect(!node.isHidden, "a dark screen is not an absent object")

        scene.apply([.setDeskScreen(agent: Self.agent, screen: .lit)])
        #expect(node.texture === lit)
        #expect(scene.deskObjectNodesForTesting[Self.agent] === node)
    }

    /// **A screen change on a bare desk draws nothing and is not lost.** The two
    /// facts arrive on separate intents in either order, so the flag has to
    /// survive the frames in which there is nothing to apply it to.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aScreenChangeBeforeAnyObjectIsRememberedRatherThanDropped() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = Self.scene(manifest)
        let store = scene.store

        scene.apply([.setDeskScreen(agent: Self.agent, screen: .dark)])
        let node = try #require(scene.deskObjectNodesForTesting[Self.agent])
        #expect(node.isHidden, "a screen change furnished a bare desk")
        #expect(scene.deskScreensForTesting()[Self.agent] == .dark)

        scene.apply([.setDeskObject(agent: Self.agent, kind: .authoring)])
        let laptop = try #require(DeskWorkArt.bitmap(.authoring, screen: .dark))
        let dark = try #require(store.texture(
            bitmap: laptop, key: WorkKind.authoring.textureKey(screen: .dark)))
        #expect(node.texture === dark, "the object arrived lit on a dark desk")
        #expect(!node.isHidden)
    }

    /// A paper kind draws the same pixels either way, so a dormant researcher's
    /// desk is untouched and only the character recedes. [I1]
    @Test(.enabled(if: SceneArt.isAvailable))
    func aPaperDeskIsUnchangedByTheScreenGoingDark() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = Self.scene(manifest)

        scene.apply([.setDeskObject(agent: Self.agent, kind: .research)])
        let node = try #require(scene.deskObjectNodesForTesting[Self.agent])
        let size = node.size
        scene.apply([.setDeskScreen(agent: Self.agent, screen: .dark)])
        #expect(node.size == size)
        #expect(scene.deskObjectNodesForTesting[Self.agent] === node)
        // The pixels are identical; only the cache key differs.
        let lit = DeskWorkArt.bitmap(.research, screen: .lit)
        let dark = DeskWorkArt.bitmap(.research, screen: .dark)
        #expect(lit?.pixels == dark?.pixels)
    }
}
