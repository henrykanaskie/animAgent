import Foundation
import Testing
@testable import SpriteRoomScene

/// Criterion 5 has two halves. The half a test can carry is that the nameplate
/// has the right pixels in the right places; the half it cannot is whether a
/// human can read it, and that is what the rendered PNGs are for.
struct NameplateTests {

    let font = PixelFont.standard

    @Test func everyGlyphInTheTableIsFiveBySeven() {
        for character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/+…× " {
            let bitmap = font.render(String(character), colour: Bitmap.RGBA(255, 255, 255))
            #expect(bitmap.height == 7)
            #expect(bitmap.width == 5, "\(character)")
        }
    }

    @Test func everyLetterAndDigitHasInk() {
        for character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
            let bitmap = font.render(String(character), colour: Bitmap.RGBA(255, 255, 255))
            #expect(bitmap.opaquePixelCount > 0, "\(character) is blank")
        }
    }

    /// A cast is only separable by nameplate if no two glyphs are the same
    /// shape. Two letters that render identically would silently merge two
    /// agents.
    @Test func noTwoGlyphsRenderIdentically() {
        var seen: [[UInt8]: Swift.Character] = [:]
        for character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
            let bitmap = font.render(String(character), colour: Bitmap.RGBA(255, 255, 255))
            if let clash = seen[bitmap.pixels] {
                Issue.record("\(character) renders identically to \(clash)")
            }
            seen[bitmap.pixels] = character
        }
    }

    @Test func lowercaseAndUppercaseRenderTheSame() {
        let lower = font.render("explore", colour: Bitmap.RGBA(255, 255, 255))
        let upper = font.render("EXPLORE", colour: Bitmap.RGBA(255, 255, 255))
        #expect(lower.pixels == upper.pixels)
    }

    /// A glyph we do not have must not silently shorten the name — that would
    /// turn two different agents into the same plate.
    @Test func anUnknownGlyphBecomesASpaceRatherThanVanishing() {
        #expect(font.normalise("A☃B").count == 3)
        #expect(font.width(of: font.normalise("A☃B")) == font.width(of: "ABC"))
    }

    @Test func longNamesAreTruncatedWithAnEllipsisNotClipped() {
        let fitted = font.fit("security-reviewer", limit: SceneBitmaps.nameplateGlyphLimit)
        #expect(fitted.count == SceneBitmaps.nameplateGlyphLimit)
        #expect(fitted.hasSuffix("…"))
        #expect(fitted.hasPrefix("SECURITY-"))
    }

    /// The line is still short of the longest type, so the truncation has to
    /// stay *visible*. A silently chopped type reads as a different, shorter
    /// type.
    @Test func aTruncatedTypeStillSaysItWasTruncated() {
        #expect(font.fit("general-purpose", limit: SceneBitmaps.nameplateGlyphLimit)
                == "GENERAL-P…")
    }

    /// **The glyph limit is whatever fits a plate the seat pitch can be built
    /// from, and this is that relation rather than the number.**
    ///
    /// The limit went 8 → 10 → 11 while the 96 px pitch was a given and the
    /// plate was fitted to it. It is 10 now because the causality was turned
    /// round: the plate is the widest thing a character owns, so it sets the
    /// pitch, and a pitch is a whole number of 32 px tiles. Everything in
    /// 65…95 px therefore buys exactly what 95 buys, and only ≤ 64 buys
    /// anything at all.
    ///
    /// **Losing two rows did not change this**, which is why the plate did not
    /// widen when it got shorter: the dead band is a property of the tile, not
    /// of how many rows the plate has.
    ///
    /// Asserted as *the plate clears a two-tile pitch* rather than as
    /// `limit == 10`, so that a wider font, a change of tracking or a change of
    /// padding fails here instead of silently spending the tile.
    @Test func theLineIsAsLongAsATwoTilePitchCanCarry() {
        let tile = RoomLayout().tile
        #expect(SceneBitmaps.maximumNameplateWidth <= 2 * tile,
                "the plate is \(SceneBitmaps.maximumNameplateWidth) px and no longer fits two tiles")
        // And it is the *largest* such plate: one more glyph would not fit, so
        // no width is being left on the table for nothing.
        let oneMore = SceneBitmaps.maximumNameplateWidth + font.glyphWidth + font.tracking
        #expect(oneMore > 2 * tile,
                "a glyph is going spare: \(oneMore) px would still fit two tiles")
    }

    /// **Ten glyphs separate the types that exist, and nothing catches the ones
    /// they cannot.**
    ///
    /// Truncation is lossy and no glyph count fixes that: two types sharing a
    /// ten-character prefix truncate alike, and `claude-code-guide` against a
    /// hypothetical `claude-code-runner` is the case. The discriminator row used
    /// to catch exactly that, and the plate is one row now — so this records
    /// that the two are the same plate, which is the second half of what the
    /// row was doing and the second half of what its removal cost.
    @Test func typesSeparateOnTheOneLineAndNothingCatchesTheRest() {
        let limit = SceneBitmaps.nameplateGlyphLimit
        let real = ["claude-code-guide", "security-reviewer", "scene-engineer",
                    "statusline-setup", "general-purpose", "Explore", "Plan"]
        let fitted = real.map { font.fit($0, limit: limit) }
        #expect(Set(fitted).count == real.count, "two types share a line: \(fitted)")

        // And where the line cannot separate them, nothing else on the plate
        // does either. [SceneDirectorTests.sameTypedSubagentsWithNoDispatchNowShareOnePlate]
        let accent = Bitmap.RGBA(77, 195, 255)
        #expect(font.fit("claude-code-guide", limit: limit)
                == font.fit("claude-code-runner", limit: limit))
        #expect(SceneBitmaps.nameplate(
                    NameplateText(lead: "", role: "claude-code-guide"), accent: accent).pixels
                == SceneBitmaps.nameplate(
                    NameplateText(lead: "", role: "claude-code-runner"), accent: accent).pixels)
    }

    /// Integer scaling is pixel doubling, so a 2× line is exactly the 1× line
    /// magnified — no second set of letterforms exists to be drawn wrong. [I6]
    @Test func scalingAGlyphIsExactPixelDoubling() {
        let one = font.render("R", colour: Bitmap.RGBA(255, 255, 255))
        let two = font.render("R", colour: Bitmap.RGBA(255, 255, 255), scale: 2)
        #expect(two.width == one.width * 2)
        #expect(two.height == one.height * 2)
        for y in 0..<two.height {
            for x in 0..<two.width {
                #expect(two.at(x, y) == one.at(x / 2, y / 2), "mismatch at \(x),\(y)")
            }
        }
    }

    @Test func scaledTextIsExactlyTwiceAsWide() {
        #expect(font.width(of: "8DE", scale: 2) == font.width(of: "8DE") * 2)
        #expect(font.height(scale: 2) == font.glyphHeight * 2)
    }

    @Test func shortNamesAreNotTouched() {
        #expect(font.fit("main", limit: 10) == "MAIN")
        #expect(font.fit("Explore", limit: 10) == "EXPLORE")
    }

    /// The plate has to fit inside one seat's spacing, or two neighbours'
    /// nameplates overlap and neither reads — and "fits" is not "touches".
    ///
    /// The maintainer's complaint at the wide default was that two plates
    /// *nearly touch*: the 12-glyph single-line plate was 77 px against a 96 px
    /// pitch, a 19 px gap. This is the number that fixes the headline at eleven
    /// glyphs — twelve would be 77 px again, and the complaint back with it.
    ///
    /// **The two seat rows do not buy any slack here, and it is worth writing
    /// down because they look like they should.** Ring parity puts adjacent
    /// columns on different rows, so no two *seated* plates share a horizontal
    /// strip at all. But a back-row character walking down its own column to the
    /// walkway passes through the front row's line, one pitch from a front-row
    /// seat; and two reporters in adjacent columns stand a pitch apart on the
    /// walkway. Both are same-row pairs at exactly one pitch, so the pitch is
    /// still the bound. See `RoomLayout.isBackRow(seat:)` and
    /// `RoomSceneTests.theRoomHasNoLateralMovementLeftToSeparate`.
    ///
    /// **What this asserts is non-occlusion, not comfort.** It used to demand
    /// 24 px of daylight between two neighbouring plates, which was a crowding
    /// judgement wearing an invariant's clothes — the maintainer's own direction
    /// is that sprites and desks may sit close together as long as they do not
    /// cover anything up. The bound kept is the margin the *other* axis already
    /// has, `tile − plateHeight`, so the room clears by the same amount both
    /// ways; `RoomLayout.minimumSeatSpacingTiles(plateWidth:plateHeight:tile:)`
    /// is that relation, and narrowing the plate is now a way to narrow the room.
    @Test func theWidestPlateLeavesAVisibleGapInsideTheSeatSpacing() {
        let layout = RoomLayout()
        let pitch = layout.seatSpacingTiles * layout.tile
        let widest = SceneBitmaps.maximumNameplateWidth
        let margin = layout.tile - SceneBitmaps.maximumNameplateHeight
        #expect(widest <= pitch)
        #expect(pitch - widest >= margin,
                "only \(pitch - widest) px between neighbours, against \(margin) across the rows")
    }

    /// Two subagents can stop within a second of each other and both step out to
    /// report. They stand on one row — the walkway — a seat pitch apart, so the
    /// pitch is what clears them across. What the **row** pitch has to clear is
    /// the other axis: a walkway character's plate against the seat row above it,
    /// and a front-row character's against the back row's. A tile taller than the
    /// tallest plate is what makes two rows unable to share a horizontal strip.
    @Test func theRowPitchClearsTheTallestPlateSoTwoRowsNeverShareAStrip() {
        let layout = RoomLayout()
        #expect(Double(layout.tile) > Double(SceneBitmaps.maximumNameplateHeight))
        #expect(layout.baselineY - layout.aisleY == Double(layout.tile))
        #expect(layout.backSeatRowY - layout.baselineY >= Double(layout.tile))
    }

    /// **Height was the axis the three-row plate spent, and it is bounded.**
    /// A seated character stands one tile above a character on the walkway. A
    /// plate taller than that tile would put a seated plate and a walkway plate
    /// in the same horizontal strip, at which point `noTwoNameplatesEverIntersect`
    /// would be resting on x-separation alone — which is a seat pitch, and the
    /// pitch is only one plate wide plus a margin.
    @Test func thePlateIsShorterThanTheGapBetweenTheAisleAndTheSeatRow() {
        let layout = RoomLayout()
        let drop = layout.baselineY - layout.aisleY
        #expect(Double(SceneBitmaps.maximumNameplateHeight) < drop)
    }

    /// **The plate is one line on one band, and the band is the whole plate.**
    ///
    /// The maintainer's instruction, asserted as geometry: there is one run of
    /// ink, it is one glyph tall, and every pixel that is not that ink is the
    /// accent. No second row, no dark field under it, and no empty slot left
    /// where a row used to be. [I1 — a viewer cannot be shown a slot and left
    /// to wonder what should have been in it]
    @Test func thePlateIsOneLineOnOneBandAndNothingElse() throws {
        let accent = Bitmap.RGBA(255, 136, 77)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose", task: "READ ALPH…"),
            accent: accent)
        let ink = SceneBitmaps.contrastingInk(on: accent)

        var inkRows: Set<Int> = []
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == ink { inkRows.insert(y) }
        }
        let top = try #require(inkRows.min()), bottom = try #require(inkRows.max())
        #expect(bottom - top + 1 <= font.glyphHeight, "more than one row of ink: \(inkRows)")
        #expect(!plate.pixels.isEmpty)

        // Every non-ink pixel is the accent — the dark plate colour the rows
        // used to sit on is not drawn at all.
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) != ink {
                #expect(plate.at(x, y) == accent, "a non-accent pixel at \(x),\(y)")
            }
        }

        // And the line is the 1× face and nothing else — no stretch, no second
        // letterform set. [I6]
        var inkCount = 0
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == ink { inkCount += 1 }
        }
        #expect(inkCount == font.render("READ ALPH…", colour: ink).opaquePixelCount)
    }

    /// **The plate's exact size, pinned.** 63 × 11 where the three-row plate was
    /// 63 × 29. The height is what the camera's content band and `RoomLayout`'s
    /// row clearance are both derived from, so it is asserted as a number here
    /// and as a relation everywhere else.
    @Test func theWholePlateIsSixtyThreeByEleven() {
        #expect(SceneBitmaps.maximumNameplateWidth == 63)
        #expect(SceneBitmaps.maximumNameplateHeight == 11)
        // A real plate, not just the bound: every plate is one row, so a
        // full-width task is exactly the largest one.
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose", task: "READ ALPH…"),
            accent: Bitmap.RGBA(196, 255, 77))
        #expect(plate.height == SceneBitmaps.maximumNameplateHeight)
        #expect(plate.width == SceneBitmaps.maximumNameplateWidth)
    }

    @Test func thePlateHasABorderInTheAccentHueAndInkInTheMiddle() {
        let accent = Bitmap.RGBA(255, 64, 0)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "Explore"), accent: accent)
        #expect(plate.at(0, 0) == accent)
        #expect(plate.at(plate.width - 1, plate.height - 1) == accent)

        var ink = 0
        let lineInk = SceneBitmaps.contrastingInk(on: accent)
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == lineInk { ink += 1 }
        }
        #expect(ink > 0, "no line on the plate")
    }

    /// The accent is no longer a one-pixel outline. M2 refuted hue *sampled
    /// from the art*; these hues are assigned 60° apart and lint-enforced, so
    /// they are the one identity channel that measurably works — and a band is
    /// catchable from the corner of the eye where an outline is not.
    ///
    /// **It got louder as the plate got smaller**: the band was the top 11 px of
    /// a 29 px plate and is now the whole of an 11 px one, so everything on the
    /// plate that is not a glyph is the character's hue.
    @Test func theAccentCoversASubstantialShareOfThePlate() {
        let accent = Bitmap.RGBA(77, 195, 255)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose"), accent: accent)
        var count = 0
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == accent { count += 1 }
        }
        let share = Double(count) / Double(plate.width * plate.height)
        #expect(share > 0.75, "accent covers only \(share) of the plate")
    }

    /// Six hues 60° apart cannot all be light, so the band's ink is chosen by
    /// contrast rather than fixed. Every accent the manifest can carry must
    /// clear the WCAG large-text threshold against whichever ink it gets.
    @Test func everyAccentGetsALegibleInkOnTheBand() {
        for hex in ["#FF884D", "#C4FF4D", "#4DFF88", "#4DC3FF", "#884DFF", "#FF4DC4"] {
            var value: UInt64 = 0
            Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
            let accent = Bitmap.RGBA(
                UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
            let ink = SceneBitmaps.contrastingInk(on: accent)
            #expect(SceneBitmaps.contrast(accent, ink) >= 3.0,
                    "\(hex) scores \(SceneBitmaps.contrast(accent, ink))")
        }
    }

    /// The whole plate is opaque: a nameplate that lets the room through does
    /// not read at 1x, which is the size it has to read at — and a themed room
    /// with real furniture behind it is coming.
    @Test func thePlateIsFullyOpaqueNotJustFullyCovered() {
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "6E7", role: "Explore"), accent: Bitmap.RGBA(0, 255, 0))
        #expect(plate.opaquePixelCount == plate.width * plate.height)
        for y in 0..<plate.height {
            for x in 0..<plate.width {
                #expect(plate.at(x, y).a == 255, "translucent pixel at \(x),\(y)")
            }
        }
    }

    @Test func differentNamesProduceDifferentPlates() {
        let accent = Bitmap.RGBA(200, 100, 0)
        let a = SceneBitmaps.nameplate(NameplateText(lead: "", role: "EXPLORE"), accent: accent)
        let b = SceneBitmaps.nameplate(NameplateText(lead: "", role: "EXPLORF"), accent: accent)
        #expect(a.pixels != b.pixels)
    }

    /// Identity has a second channel: two agents with the same name but
    /// different variants still differ, because the plate carries the accent.
    /// **It is the only channel left for two agents the text cannot separate**,
    /// and it is assigned per character rather than per type.
    @Test func theAccentSeparatesTwoPlatesWithTheSameName() {
        let a = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "Explore"), accent: Bitmap.RGBA(255, 0, 0))
        let b = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "Explore"), accent: Bitmap.RGBA(0, 0, 255))
        #expect(a.pixels != b.pixels)
    }

    /// **The ladder is a true statement at every rung, and every rung is one
    /// row.** A subagent with a dispatch shows the task; one we never saw a
    /// dispatch for shows its `agent_type`; the main agent shows `MAIN`. Nothing
    /// is synthesised to fill a line and no line is left empty. [I1]
    @Test func everyRungOfTheLadderIsOneRowAndSomethingTheDataSaid() {
        let accent = Bitmap.RGBA(77, 195, 255)
        let ink = SceneBitmaps.contrastingInk(on: accent)
        let rungs = [
            NameplateText(lead: "", role: "general-purpose", task: "READ ALPH…"),
            NameplateText(lead: "", role: "general-purpose"),
            NameplateText(lead: "main"),
        ]
        let expected = ["READ ALPH…", "GENERAL-P…", "MAIN"]
        for (text, line) in zip(rungs, expected) {
            let plate = SceneBitmaps.nameplate(text, accent: accent)
            #expect(plate.height == SceneBitmaps.maximumNameplateHeight, "\(line) is not one row")
            #expect(plate.opaquePixelCount == plate.width * plate.height)
            var count = 0
            for y in 0..<plate.height {
                for x in 0..<plate.width where plate.at(x, y) == ink { count += 1 }
            }
            #expect(count == font.render(line, colour: ink).opaquePixelCount,
                    "the plate does not read \(line)")
        }
    }

    /// An empty `agent_type` — M0c found it arrives — must not draw a blank
    /// plate. With nothing above it on the ladder, `lead` is what is left.
    @Test func anEmptyRoleFallsThroughToTheLead() {
        let accent = Bitmap.RGBA(255, 136, 77)
        #expect(SceneBitmaps.nameplate(NameplateText(lead: "main", role: ""), accent: accent)
                == SceneBitmaps.nameplate(NameplateText(lead: "main"), accent: accent))
    }

    @Test func theBadgeCountPlateRendersTheMultiplier() {
        let plate = SceneBitmaps.badgeCount(5)
        #expect(plate.width > 0 && plate.height > 0)
        var ink = 0
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == SceneBitmaps.nameplateInk {
                ink += 1
            }
        }
        #expect(ink > 0)
        #expect(SceneBitmaps.badgeCount(12).width > SceneBitmaps.badgeCount(2).width)
    }

    /// The desk is a placeholder and has to look like one — but it must still
    /// stay inside the room's value band so it never owns the darkest pixel on
    /// screen. [I7]
    @Test func thePlaceholderDeskStaysInsideTheRoomValueBand() {
        let desk = SceneBitmaps.placeholderDesk()
        #expect(desk.width == 32)
        for y in 0..<desk.height {
            for x in 0..<desk.width {
                let pixel = desk.at(x, y)
                guard pixel.a > 0 else { continue }
                let value = Double(max(pixel.r, max(pixel.g, pixel.b))) / 255
                #expect(value >= 0.45, "desk pixel too dark at \(x),\(y): \(value)")
                let low = Double(min(pixel.r, min(pixel.g, pixel.b))) / 255
                #expect((value - low) / value < 0.25, "desk pixel too saturated")
            }
        }
    }

    // MARK: The task line — the plate's only occupant

    /// **An agent with no task shows its type on the same one row**, and that is
    /// the whole of "shows nothing where the task would be". There is no empty
    /// row and no placeholder — a viewer cannot be shown a slot and left to
    /// wonder what should have been in it. [I1]
    @Test func aPlateWithNoTaskShowsTheTypeOnTheSameOneRow() {
        let accent = Bitmap.RGBA(77, 195, 255)
        let withoutTask = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose"), accent: accent)
        let explicitlyNone = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose", task: nil), accent: accent)
        #expect(withoutTask.pixels == explicitlyNone.pixels)
        #expect(withoutTask.height == 11)
        // And the main agent, which has no task permanently, is the same plate.
        #expect(SceneBitmaps.nameplate(NameplateText(lead: "main"), accent: accent).height == 11)
    }

    /// **The plate does not change shape when a task lands.** `agentTasked`
    /// rides one event behind the `SubagentStart` that seated the character, so
    /// the update happens under the user's eye; with one row it is a
    /// substitution on a line that keeps its height, not a plate that grows.
    ///
    /// The width can change, and only because the *text* did: a ten-glyph task
    /// replacing a seven-glyph type is a wider line. The plate is centred on the
    /// character, so that is symmetric and moves nothing else.
    @Test func gainingATaskReplacesTheLineAndChangesNoRowCount() {
        let accent = Bitmap.RGBA(196, 255, 77)
        let before = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose"), accent: accent)
        let after = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose", task: "READ ALPH…"),
            accent: accent)
        #expect(after.height == before.height, "the plate changed height")
        // Both lines are ten glyphs here, so this pair does not move at all.
        #expect(after.width == before.width)
        #expect(after.pixels != before.pixels, "the line did not change")
    }

    /// **Ten glyphs is the plate's width.** One row, so the line's limit *is*
    /// the plate's width — and the plate's width is the term the seat pitch and
    /// the camera are both derived from.
    @Test func theTaskLineGetsThePlatesWidthAndNotAGlyphMore() {
        let accent = Bitmap.RGBA(255, 64, 0)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose", task: "MMMMMMMMMM"),
            accent: accent)
        #expect(plate.width == SceneBitmaps.maximumNameplateWidth)
        #expect(plate.width == 63)
        // Eleven glyphs would be 69 px, which buys the same three-tile pitch and
        // costs the ≤ 64 px target. See `SceneBitmaps.nameplateGlyphLimit`.
        #expect(font.width(of: String(repeating: "M", count: 11)) + 4 == 69)
    }

    /// **Every plate is the tallest plate, because every plate is one row.**
    /// `maximumNameplateHeight` is what `RoomLayout` separates the seat rows by
    /// and what the camera's content band is measured from, so it has to be the
    /// bound of the plate that can actually happen — and there is now only one
    /// shape a plate can be.
    @Test func theTallestPlateIsTheOnlyShapeAPlateHas() {
        let accent = Bitmap.RGBA(255, 136, 77)
        let tasked = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "MMMMMMMMMM", task: "MMMMMMMMMM"), accent: accent)
        #expect(SceneBitmaps.maximumNameplateHeight == tasked.height)
        #expect(tasked.height == 11)
        #expect(tasked.height < RoomLayout().tile,
                "the plate no longer fits between the aisle and the seat row")
    }

    /// **The ten real `Agent` dispatches in `fixtures/`, every one of them.**
    ///
    /// Not invented strings: these are the exact `tool_input.description` values
    /// the corpus carries, and the expectation is the whole of what the rule
    /// does. A change to the stop-word list or to the clip shows up here as ten
    /// diffs rather than as an argument.
    @Test func everyRealDispatchInTheCorpusShortensToSomethingReadable() {
        let corpus: [(String, String)] = [
            ("Touch file s1", "TOUCH FIL…"),
            ("Touch file s2", "TOUCH FIL…"),
            ("Read one.txt sleep", "READ ONE…"),
            ("Read two.txt sleep", "READ TWO…"),
            ("Read three.txt sleep", "READ THRE…"),
            ("Read four.txt sleep", "READ FOUR…"),
            ("Touch a file via bash", "TOUCH FIL…"),
            ("Read alpha.txt and sleep", "READ ALPH…"),
            ("Read beta/gamma and sleep", "READ BETA…"),
            ("Read delta/epsilon, sleep, reread alpha", "READ DELT…"),
        ]
        for (description, expected) in corpus {
            #expect(SceneDirector.taskLine(description) == expected, "\(description)")
        }
    }

    /// **The maintainer's own two examples.** They are the specification for
    /// this feature in the form it was given, so they are pinned in that form.
    /// `MOVE BADG…` rather than the `move badge` that was asked for is the one
    /// glyph the honesty mark costs — `beside the head` was dropped and the
    /// plate has to say so.
    @Test func theMaintainersExamplesShortenToTheirVerbAndObject() {
        #expect(SceneDirector.taskLine("Move the badge beside the head") == "MOVE BADG…")
        #expect(SceneDirector.taskLine("Rework the report beat") == "REWORK RE…")
    }

    /// **Three genuinely similar dispatches stay three distinct plates.** This
    /// is the case the feature is for: `three-subagents` sends three subagents
    /// to read three different things and sleep, and before this every plate in
    /// that room read `EXPLORE` or `GENERAL-P…`.
    @Test func theThreeSimilarDispatchesDoNotCollapseIntoOneHeadline() {
        let lines = [
            "Read alpha.txt and sleep",
            "Read beta/gamma and sleep",
            "Read delta/epsilon, sleep, reread alpha",
        ].map { SceneDirector.taskLine($0) }
        #expect(Set(lines).count == 3, "the shortening collapsed them: \(lines)")
    }

    /// **`…` means there is more in the description than is drawn, always.**
    ///
    /// The rule is total on purpose: a clip that lands on a word boundary reads
    /// as a finished phrase and is the one case the eye cannot catch. `Touch
    /// file s1` shortening to a bare `TOUCH FILE` would have the room assert
    /// somebody was sent to touch *a* file.
    @Test func aTaskLineEndsInAnEllipsisWheneverAnythingWasDropped() {
        // Dropped by the clip.
        #expect(SceneDirector.taskLine("Touch file s1")?.hasSuffix("…") == true)
        // Dropped as a stop word, with room to spare on the line.
        #expect(SceneDirector.taskLine("Fix the bug") == "FIX BUG…")
        // Nothing dropped at all: no mark.
        #expect(SceneDirector.taskLine("Touch file") == "TOUCH FILE")
        #expect(SceneDirector.taskLine("Sleep") == "SLEEP")
        // Never longer than the line.
        for description in ["Fix the bug", "Touch file", "Move the badge beside the head",
                            "Read delta/epsilon, sleep, reread alpha"] {
            let line = SceneDirector.taskLine(description) ?? ""
            #expect(line.count <= SceneBitmaps.nameplateGlyphLimit, "\(description) → \(line)")
        }
    }

    /// **Nothing is invented when there is nothing to shorten.** A description
    /// with no drawable word gets no task row rather than a placeholder, and a
    /// description that is *all* function words is shown as it is rather than
    /// erased — dropping every word would leave a plate asserting the agent has
    /// a task and refusing to say what. [I1]
    @Test func aTaskLineIsNeverInventedAndNeverBlank() {
        #expect(SceneDirector.taskLine(nil) == nil)
        #expect(SceneDirector.taskLine("") == nil)
        #expect(SceneDirector.taskLine("   ") == nil)
        #expect(SceneDirector.taskLine("☃ ☃") == nil)
        // Nothing was dropped from it, so it carries no mark either.
        #expect(SceneDirector.taskLine("the and of") == "THE AND OF")
    }

    /// The shortening only ever contains characters the description contained,
    /// in the order it contained them — plus the mark. No abbreviation table, no
    /// synonym, no paraphrase. This is the mechanical form of I1 for this line.
    @Test func everyGlyphOfATaskLineCameFromTheDescription() {
        for description in ["Touch file s1", "Read delta/epsilon, sleep, reread alpha",
                            "Move the badge beside the head", "Rework the report beat"] {
            let line = (SceneDirector.taskLine(description) ?? "")
                .replacingOccurrences(of: "…", with: "")
            let source = description.uppercased()
            var cursor = source.startIndex
            for character in line where character != " " {
                guard let found = source[cursor...].firstIndex(of: character) else {
                    Issue.record("\(character) is not in \(description) after \(cursor)")
                    break
                }
                cursor = source.index(after: found)
            }
        }
    }
}
