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
        let fitted = font.fit("security-reviewer", limit: SceneBitmaps.nameplateRoleGlyphLimit)
        #expect(fitted.count == SceneBitmaps.nameplateRoleGlyphLimit)
        #expect(fitted.hasSuffix("…"))
        #expect(fitted.hasPrefix("SECURITY-"))
    }

    /// The role line is short, so the truncation has to stay *visible*. A
    /// silently chopped type reads as a different, shorter type.
    @Test func aTruncatedTypeStillSaysItWasTruncated() {
        #expect(font.fit("general-purpose", limit: SceneBitmaps.nameplateRoleGlyphLimit)
                == "GENERAL-P…")
        // The type gets more glyphs than the single-line plate gave it (8 of
        // 12), not fewer, because it no longer shares the row.
        #expect(SceneBitmaps.nameplateRoleGlyphLimit > 8)
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
    /// pitch, a 19 px gap. The two-row plate is narrower because the type no
    /// longer shares its row with the discriminator, so this asserts a real gap
    /// rather than mere non-overlap.
    @Test func theWidestPlateLeavesAVisibleGapInsideTheSeatSpacing() {
        let layout = RoomLayout()
        let pitch = layout.seatSpacingTiles * layout.tile
        let widest = SceneBitmaps.maximumNameplateWidth
        #expect(widest <= pitch)
        #expect(pitch - widest >= 24, "only \(pitch - widest) px between neighbours")
    }

    /// Two subagents can stop within a second of each other and both walk to the
    /// anchor. They no longer share a line — each delivers on the row that
    /// belongs to its own ring — so what has to clear the plate is the **row
    /// pitch**, and it has to clear it in the other axis: a tile taller than the
    /// tallest plate is what makes two rows unable to share a horizontal strip.
    @Test func theRowPitchClearsTheTallestPlateSoTwoRowsNeverShareAStrip() {
        let layout = RoomLayout()
        #expect(Double(layout.tile) > Double(SceneBitmaps.maximumNameplateHeight))
        #expect(layout.deliveryRowY(ring: 1) - layout.deliveryRowY(ring: 2)
                == Double(layout.tile))
    }

    /// **Height is the axis the two-row plate spends, and it is bounded.**
    /// A seated character stands one tile above an aisle character. A plate
    /// taller than that tile would put a seated plate and an aisle plate in the
    /// same horizontal strip, at which point `noTwoNameplatesEverIntersect`
    /// would be resting on x-separation alone — and during the report beat the
    /// reporter stands 48 px from the anchor, less than two half-plates.
    @Test func thePlateIsShorterThanTheGapBetweenTheAisleAndTheSeatRow() {
        let layout = RoomLayout()
        let drop = layout.baselineY - layout.aisleY
        #expect(Double(SceneBitmaps.maximumNameplateHeight) < drop)
    }

    /// The lead line is drawn large; that is the whole point of the split.
    @Test func theLeadLineIsDrawnLargerThanTheRoleLine() {
        #expect(SceneBitmaps.nameplateLeadScale >= 2)
        let plate = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose"),
            accent: Bitmap.RGBA(255, 136, 77))
        // A 2× lead is 14 rows of a 26-row plate; the role is 7.
        #expect(plate.height >= font.glyphHeight * 3)
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

    /// **An `agent_id` with nothing usable in it gets no headline, not a made-up
    /// one.** The type is not promoted to the 2× row: five doubled glyphs would
    /// cut `general-purpose` to `GENE…` and lose more than the layout buys, and
    /// a synthesised lead would be a label the data never carried. [I1]
    @Test func aPlateWithNoLeadDrawsTheTypeAloneRatherThanInventingOne() {
        let accent = Bitmap.RGBA(77, 195, 255)
        let plain = SceneBitmaps.nameplate(
            NameplateText(lead: "", role: "general-purpose"), accent: accent)
        let led = SceneBitmaps.nameplate(
            NameplateText(lead: "8DE", role: "general-purpose"), accent: accent)
        #expect(plain.height < led.height, "the empty lead still reserved a band")
        #expect(plain.width == led.width, "the role line still sets the width")
        #expect(plain.opaquePixelCount == plain.width * plain.height)
        var ink = 0
        for y in 0..<plain.height {
            for x in 0..<plain.width where plain.at(x, y) == SceneBitmaps.nameplateInk {
                ink += 1
            }
        }
        #expect(ink > 0, "the type vanished with the lead")
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
}
