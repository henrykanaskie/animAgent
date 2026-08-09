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
        let fitted = font.fit("security-reviewer", limit: SceneBitmaps.nameplateTypeGlyphLimit)
        #expect(fitted.count == SceneBitmaps.nameplateTypeGlyphLimit)
        #expect(fitted.hasSuffix("…"))
        #expect(fitted.hasPrefix("SECURITY-"))
    }

    /// The headline is still short of the longest type, so the truncation has to
    /// stay *visible*. A silently chopped type reads as a different, shorter
    /// type.
    @Test func aTruncatedTypeStillSaysItWasTruncated() {
        #expect(font.fit("general-purpose", limit: SceneBitmaps.nameplateTypeGlyphLimit)
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
    /// Asserted as *the plate clears a two-tile pitch* rather than as
    /// `limit == 10`, so that a wider font, a change of tracking or a change of
    /// padding fails here instead of silently spending the tile.
    @Test func theHeadlineIsAsLongAsATwoTilePitchCanCarry() {
        let tile = RoomLayout().tile
        #expect(SceneBitmaps.maximumNameplateWidth <= 2 * tile,
                "the plate is \(SceneBitmaps.maximumNameplateWidth) px and no longer fits two tiles")
        // And it is the *largest* such plate: one more glyph would not fit, so
        // no width is being left on the table for nothing.
        let oneMore = SceneBitmaps.maximumNameplateWidth + font.glyphWidth + font.tracking
        #expect(oneMore > 2 * tile,
                "a glyph is going spare: \(oneMore) px would still fit two tiles")
    }

    /// **Ten glyphs separate the types that exist, and the tag catches the
    /// ones it cannot.**
    ///
    /// Truncation is lossy and no glyph count fixes that: two types sharing a
    /// ten-character prefix truncate alike, and `claude-code-guide` against a
    /// hypothetical `claude-code-runner` is the case. That is the *second* half
    /// of what the discriminator is for and the reason it survives this change
    /// rather than being dropped — it separates two agents of one type, and it
    /// separates two agents whose types the plate could not tell apart either.
    @Test func typesSeparateOnTheHeadlineAndTheTagCatchesTheRest() {
        let limit = SceneBitmaps.nameplateTypeGlyphLimit
        let real = ["claude-code-guide", "security-reviewer", "scene-engineer",
                    "statusline-setup", "general-purpose", "Explore", "Plan"]
        let fitted = real.map { font.fit($0, limit: limit) }
        #expect(Set(fitted).count == real.count, "two types share a headline: \(fitted)")

        // And where a headline genuinely cannot separate them, the plate still
        // does.
        let accent = Bitmap.RGBA(77, 195, 255)
        #expect(font.fit("claude-code-guide", limit: limit)
                == font.fit("claude-code-runner", limit: limit))
        #expect(SceneBitmaps.nameplate(
                    NameplateText(lead: "8DE", role: "claude-code-guide"), accent: accent).pixels
                != SceneBitmaps.nameplate(
                    NameplateText(lead: "6E7", role: "claude-code-runner"), accent: accent).pixels)
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

    /// **Height is the axis the two-row plate spends, and it is bounded.**
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

    /// **The type is on the accent band and the discriminator is not.**
    ///
    /// This is the whole of the hierarchy, and it is position rather than size
    /// because size is not available — see `SceneBitmaps.nameplate` for why the
    /// type cannot be magnified in either axis. So it is asserted where it
    /// lives: every pixel of the type is inside the band, every pixel of the
    /// discriminator is below it, and the band is the saturated field.
    @Test func theTypeIsOnTheAccentBandAndTheDiscriminatorIsBelowIt() throws {
        let accent = Bitmap.RGBA(255, 136, 77)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose"), accent: accent)
        let headlineInk = SceneBitmaps.contrastingInk(on: accent)
        #expect(headlineInk != SceneBitmaps.nameplateInk, "the two rows share an ink")

        var headlineRows: Set<Int> = [], tagRows: Set<Int> = []
        for y in 0..<plate.height {
            for x in 0..<plate.width {
                if plate.at(x, y) == headlineInk { headlineRows.insert(y) }
                if plate.at(x, y) == SceneBitmaps.nameplateInk { tagRows.insert(y) }
            }
        }
        let headlineBottom = try #require(headlineRows.max())
        let tagTop = try #require(tagRows.min())
        #expect(headlineBottom < tagTop, "the type is not above the discriminator")

        // Everything on the type's rows is the accent field; nothing on the
        // discriminator's is. Column 1, not 0: column 0 is the border, which is
        // the accent hue on every row and would prove nothing.
        for y in headlineRows { #expect(plate.at(1, y) == accent, "row \(y) is off the band") }
        for y in tagRows {
            #expect(plate.at(plate.width / 2, y) != accent, "row \(y) is on the band")
        }

        // The type is the 1× face and nothing else — no stretch, no second
        // letterform set. [I6]
        var headlineInkCount = 0
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == headlineInk { headlineInkCount += 1 }
        }
        let flat = font.render(
            font.fit("general-purpose", limit: SceneBitmaps.nameplateTypeGlyphLimit),
            colour: headlineInk)
        #expect(headlineInkCount == flat.opaquePixelCount)
    }

    /// **The discriminator survives, small.** Dropping it would put two
    /// `general-purpose` subagents back on one plate, which is the M4 failure
    /// this project already fixed once; what was wrong was its *size*, not its
    /// presence.
    @Test func theDiscriminatorIsStillOnThePlateAndStillSeparatesTwins() {
        let accent = Bitmap.RGBA(196, 255, 77)
        let first = SceneBitmaps.nameplate(
            NameplateText(lead: "A69", role: "general-purpose"), accent: accent)
        let second = SceneBitmaps.nameplate(
            NameplateText(lead: "1B1", role: "general-purpose"), accent: accent)
        #expect(first.width == second.width && first.height == second.height)
        #expect(first.pixels != second.pixels, "two same-typed agents share a plate")
    }

    @Test func thePlateHasABorderInTheAccentHueAndInkInTheMiddle() {
        let accent = Bitmap.RGBA(255, 64, 0)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "Explore"), accent: accent)
        #expect(plate.at(0, 0) == accent)
        #expect(plate.at(plate.width - 1, plate.height - 1) == accent)

        var ink = 0
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == SceneBitmaps.nameplateInk {
                ink += 1
            }
        }
        #expect(ink > 0, "no type line on the plate")
    }

    /// The accent is no longer a one-pixel outline. M2 refuted hue *sampled
    /// from the art*; these hues are assigned 60° apart and lint-enforced, so
    /// they are the one identity channel that measurably works — and a band is
    /// catchable from the corner of the eye where an outline is not.
    @Test func theAccentCoversASubstantialShareOfThePlate() {
        let accent = Bitmap.RGBA(77, 195, 255)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose"), accent: accent)
        var count = 0
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == accent { count += 1 }
        }
        let share = Double(count) / Double(plate.width * plate.height)
        #expect(share > 0.35, "accent covers only \(share) of the plate")
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
    /// different variants still differ, because the band carries the accent.
    @Test func theAccentSeparatesTwoPlatesWithTheSameName() {
        let a = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "Explore"), accent: Bitmap.RGBA(255, 0, 0))
        let b = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "Explore"), accent: Bitmap.RGBA(0, 0, 255))
        #expect(a.pixels != b.pixels)
    }

    /// **An `agent_id` with nothing usable in it gets no tag, not a made-up
    /// one.** The type is already the headline, so the plate simply loses its
    /// second row; synthesising a discriminator would be a label the data never
    /// carried. [I1]
    @Test func aPlateWithNoDiscriminatorDrawsTheTypeAloneRatherThanInventingOne() {
        let accent = Bitmap.RGBA(77, 195, 255)
        let plain = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose"), accent: accent)
        let tagged = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose"), accent: accent)
        #expect(plain.height < tagged.height, "the empty discriminator still drew a row")
        #expect(plain.width == tagged.width, "the type still sets the width")
        #expect(plain.opaquePixelCount == plain.width * plain.height)
        var ink = 0
        let headlineInk = SceneBitmaps.contrastingInk(on: accent)
        for y in 0..<plain.height {
            for x in 0..<plain.width where plain.at(x, y) == headlineInk { ink += 1 }
        }
        #expect(ink > 0, "the type vanished with the discriminator")
    }

    /// The main agent has no `agent_id` and therefore no `agent_type` either —
    /// absence of `agent_id` *is* the main agent. Its one name goes on the band,
    /// where every other character's identity goes, rather than being demoted to
    /// the small row by a rule that was written for the other case.
    /// [CLAUDE.md, Identity model]
    @Test func theMainAgentsNameIsTheHeadline() {
        let accent = Bitmap.RGBA(255, 136, 77)
        let plate = SceneBitmaps.nameplate(NameplateText(lead: "main"), accent: accent)
        let ink = SceneBitmaps.contrastingInk(on: accent)
        var band = 0
        for y in 0..<(plate.height / 2) {
            for x in 0..<plate.width where plate.at(x, y) == ink { band += 1 }
        }
        #expect(band > 0, "MAIN is not on the band")
        #expect(plate.height == SceneBitmaps.nameplate(
                    NameplateText(lead: "", role: "MAIN"), accent: accent).height,
                "the main plate is not the one-row plate every typeless agent gets")
    }

    /// An empty `agent_type` — M0c found it arrives — must not draw a blank row.
    @Test func anEmptyRoleDrawsNoSecondRow() {
        let accent = Bitmap.RGBA(255, 136, 77)
        #expect(SceneBitmaps.nameplate(NameplateText(lead: "8DE", role: ""), accent: accent)
                == SceneBitmaps.nameplate(NameplateText(lead: "8DE"), accent: accent))
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

    // MARK: The task line — the band's new occupant

    /// **The three rows, in order, asserted where they live.**
    ///
    /// The hierarchy is carried by position and field rather than by size — see
    /// `SceneBitmaps.nameplate` for why no magnification is available to any of
    /// them — so this is the only place it can be checked: every pixel of the
    /// task is inside the accent band, and every pixel of the type and of the
    /// discriminator is below it, in that order.
    @Test func theTaskIsOnTheAccentBandAndTheTypeAndTagAreBelowIt() throws {
        let accent = Bitmap.RGBA(255, 136, 77)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose", task: "MOVE BADG…"),
            accent: accent)
        let bandInk = SceneBitmaps.contrastingInk(on: accent)
        #expect(bandInk != SceneBitmaps.nameplateInk, "the band and the rows share an ink")

        var bandRows: Set<Int> = [], plateRows: Set<Int> = []
        for y in 0..<plate.height {
            for x in 0..<plate.width {
                if plate.at(x, y) == bandInk { bandRows.insert(y) }
                if plate.at(x, y) == SceneBitmaps.nameplateInk { plateRows.insert(y) }
            }
        }
        let bandBottom = try #require(bandRows.max())
        #expect(try #require(plateRows.min()) > bandBottom, "the task is not above the type")
        for y in bandRows { #expect(plate.at(1, y) == accent, "row \(y) is off the band") }
        for y in plateRows {
            #expect(plate.at(plate.width / 2, y) != accent, "row \(y) is on the band")
        }

        // The type is above the discriminator, and both are on the dark plate.
        // Their two runs of rows are separated by the row of air `platePadY`
        // puts above each, so counting the gaps is what says there are two rows
        // rather than one tall one.
        let sorted = plateRows.sorted()
        let breaks = zip(sorted, sorted.dropFirst()).filter { $1 - $0 > 1 }.count
        #expect(breaks == 1, "the type and the discriminator are not two rows: \(sorted)")

        // And the type really is the type: same ink count as the fitted line
        // drawn flat, so nothing was stretched or substituted. [I6]
        var typeInk = 0
        for y in sorted where y <= (sorted.first! + font.glyphHeight) {
            for x in 0..<plate.width where plate.at(x, y) == SceneBitmaps.nameplateInk {
                typeInk += 1
            }
        }
        #expect(typeInk == font.render(
            font.fit("general-purpose", limit: SceneBitmaps.nameplateTypeGlyphLimit),
            colour: SceneBitmaps.nameplateInk).opaquePixelCount)
    }

    /// **An agent with no task gets exactly the plate it had before this
    /// change**, and that is the whole of "shows nothing where the task would
    /// be". There is no empty row, no placeholder and no third band — a viewer
    /// cannot be shown a slot and left to wonder what should have been in it.
    /// [I1]
    @Test func aPlateWithNoTaskIsByteIdenticalToTheTwoRowPlate() {
        let accent = Bitmap.RGBA(77, 195, 255)
        let withoutTask = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose"), accent: accent)
        let explicitlyNone = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose", task: nil), accent: accent)
        #expect(withoutTask.pixels == explicitlyNone.pixels)
        // Two rows: band plus one. 11 + 10.
        #expect(withoutTask.height == 21)
        // And the main agent, which has no task permanently, is untouched too.
        #expect(SceneBitmaps.nameplate(NameplateText(lead: "main"), accent: accent).height == 11)
    }

    /// **The plate gains a row without moving one.** `agentTasked` lands after
    /// the character is already seated, so the update has to be invisible except
    /// for what it adds: the band keeps its height and its position, and the
    /// plate node is anchored at its top edge, so everything new is underneath.
    ///
    /// What this cannot assert is that the band's *text* is unchanged — it is
    /// not, and deliberately: the type gives the band up to the task. That is
    /// one substitution on one row, once per agent, a frame or so after it sits
    /// down.
    @Test func gainingATaskGrowsThePlateDownwardsAndMovesNoRowAboveIt() {
        let accent = Bitmap.RGBA(196, 255, 77)
        let before = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose"), accent: accent)
        let after = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose", task: "READ ALPH…"),
            accent: accent)
        #expect(after.width == before.width, "the plate widened")
        #expect(after.height == before.height + font.glyphHeight + 1)

        // The accent band is the same field in the same place: same height, and
        // every pixel of its interior still the accent.
        func bandHeight(_ bitmap: Bitmap) -> Int {
            var rows = 0
            while rows < bitmap.height, bitmap.at(1, rows) == accent { rows += 1 }
            return rows
        }
        #expect(bandHeight(after) == bandHeight(before))
    }

    /// **Ten glyphs is the plate's width, not the task's allowance.** The band
    /// and the type row are both full-width, so a task limit above the type
    /// limit would widen the plate for one line — and the plate's width is the
    /// term the seat pitch and the camera are both derived from.
    @Test func theTaskLineGetsThePlatesWidthAndNotAGlyphMore() {
        #expect(SceneBitmaps.nameplateTaskGlyphLimit == SceneBitmaps.nameplateTypeGlyphLimit)
        let accent = Bitmap.RGBA(255, 64, 0)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose", task: "MMMMMMMMMM"),
            accent: accent)
        #expect(plate.width == SceneBitmaps.maximumNameplateWidth)
        #expect(plate.width == 63)
    }

    /// **The tallest plate is the three-row one, and it still clears a tile.**
    /// `maximumNameplateHeight` is what `RoomLayout` separates the seat rows by
    /// and what the camera's content band is measured from, so it has to be the
    /// bound of the plate that can actually happen — not of the two-row plate
    /// this used to be.
    @Test func theTallestPlateIsTheOneWithATaskOnIt() {
        let accent = Bitmap.RGBA(255, 136, 77)
        let three = SceneBitmaps.nameplate(
            NameplateText(lead: "MMMMM", role: "MMMMMMMMMM", task: "MMMMMMMMMM"),
            accent: accent)
        #expect(SceneBitmaps.maximumNameplateHeight == three.height)
        #expect(three.height == 29)
        #expect(three.height < RoomLayout().tile,
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
            #expect(line.count <= SceneBitmaps.nameplateTaskGlyphLimit, "\(description) → \(line)")
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
