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

    @Test func shortNamesAreNotTouched() {
        #expect(font.fit("main", limit: 10) == "MAIN")
        #expect(font.fit("Explore", limit: 10) == "EXPLORE")
    }

    /// The plate has to fit inside one seat's spacing, or two neighbours'
    /// nameplates overlap and neither reads.
    @Test func theWidestPlateFitsInsideTheSeatSpacing() {
        let layout = RoomLayout()
        let widest = SceneBitmaps.nameplate(
            String(repeating: "W", count: SceneBitmaps.nameplateGlyphLimit),
            accent: Bitmap.RGBA(255, 0, 0))
        #expect(widest.width <= layout.seatSpacingTiles * layout.tile)
    }

    /// Two subagents can stop within a second of each other and both walk to
    /// the delivery row, so the slot pitch has to clear the widest plate — and
    /// the plate got wider at M5 to carry the discriminator.
    @Test func theWidestPlateAlsoFitsInsideTheDeliverySlotPitch() {
        let widest = SceneBitmaps.nameplate(
            String(repeating: "W", count: SceneBitmaps.nameplateGlyphLimit),
            accent: Bitmap.RGBA(255, 0, 0))
        #expect(Double(widest.width) <= RoomLayout.deliverySlotPitch)
    }

    /// The budget is spent as 8 glyphs of type + separator + 3 of discriminator.
    /// If those stop adding up to the limit, one of the three is being silently
    /// clipped.
    @Test func theGlyphBudgetAddsUp() {
        #expect(SceneDirector.nameplateTypeGlyphs
                + 1
                + SceneDirector.nameplateDiscriminatorGlyphs
                == SceneBitmaps.nameplateGlyphLimit)
    }

    @Test func thePlateHasABorderInTheAccentHueAndInkInTheMiddle() {
        let accent = Bitmap.RGBA(255, 64, 0)
        let plate = SceneBitmaps.nameplate("MAIN", accent: accent)
        #expect(plate.at(0, 0) == accent)
        #expect(plate.at(plate.width - 1, plate.height - 1) == accent)

        var ink = 0
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == SceneBitmaps.nameplateInk {
                ink += 1
            }
        }
        #expect(ink > 0, "no text on the plate")
    }

    /// The whole plate is opaque: a nameplate that lets the floor through does
    /// not read at 1x, which is the size it has to read at.
    @Test func thePlateIsFullyCovered() {
        let plate = SceneBitmaps.nameplate("EXPLORE", accent: Bitmap.RGBA(0, 255, 0))
        #expect(plate.opaquePixelCount == plate.width * plate.height)
    }

    @Test func differentNamesProduceDifferentPlates() {
        let accent = Bitmap.RGBA(200, 100, 0)
        let a = SceneBitmaps.nameplate("EXPLORE", accent: accent)
        let b = SceneBitmaps.nameplate("EXPLORF", accent: accent)
        #expect(a.pixels != b.pixels)
    }

    /// Identity has a second channel: two agents with the same name but
    /// different variants still differ, because the border carries the accent.
    @Test func theAccentSeparatesTwoPlatesWithTheSameName() {
        let a = SceneBitmaps.nameplate("EXPLORE", accent: Bitmap.RGBA(255, 0, 0))
        let b = SceneBitmaps.nameplate("EXPLORE", accent: Bitmap.RGBA(0, 0, 255))
        #expect(a.pixels != b.pixels)
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
