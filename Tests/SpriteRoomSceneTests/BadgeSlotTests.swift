import CoreGraphics
import Foundation
import ImageIO
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **Where the badge slot is drawn.** Not what it means, not when it appears:
/// those are `ToolBadgeTests`, `AttentionBadgeTests`, `SleepBadgeTests` and
/// `ClosingBeatTests`, and none of them moved.
///
/// The slot used to sit **above** the head with its bottom edge one pixel over
/// the hair. It now sits **beside** the head with its *top* edge on that same
/// line, which is 34 px (a whole badge canvas) off the top of everything the
/// camera has to frame. That is the entire change, and the tests below are the
/// three things it could have broken:
///
/// 1. it could cover the head, or the body, or the plate;
/// 2. it could reach into a neighbour's column;
/// 3. it could drop the dormancy tab somewhere the eye is not.
struct BadgeSlotTests {

    /// The one number the camera takes from a character. `RoomScene.contentBand`
    /// asks for it with the **smallest** `head_top_px` in the cast, because the
    /// smallest is the highest head.
    @Test func theSlotTopIsOnePixelAboveTheHighestHeadInTheCast() throws {
        let manifest = try SceneFixtures.manifest()
        let canvasHeight = manifest.characters.canvas.height
        let heads = manifest.characters.orderedVariantIDs
            .compactMap { manifest.characters.variant($0)?.headTopPx }
        let headTop = try #require(heads.min())

        let top = Character.badgeSlotTopAboveFeet(
            canvasHeight: canvasHeight, headTopPx: headTop)
        #expect(top == Double(canvasHeight - headTop + 1))
        #expect(top == 51, "the shipped cast's highest head moved")

        // And what it replaced: the same line plus a badge canvas, because the
        // slot used to hang its *bottom* here. The saving is the canvas.
        let above = top + Double(manifest.badges.canvas.height)
        #expect(above == 85)
        #expect(above - top == Double(manifest.badges.canvas.height))
    }

    /// **The slot covers no pixel of any character, in any state, at any frame,
    /// facing either way, and it is one pixel from doing so.**
    ///
    /// Both halves matter and they pull opposite ways. The first is the
    /// invariant: a badge over a head hides the one thing the room draws that a
    /// person is looking at. The second is the *budget*: horizontal space is
    /// what the seat pitch is made of, so a slot parked comfortably clear of the
    /// body would be spending pitch on air. The near edge is therefore flush
    /// with the body canvas's own edge, and the cast reaches that edge, so the
    /// clearance is exactly zero and the assertion is that zero is enough.
    ///
    /// Measured off the shipped PNGs rather than off the manifest, because the
    /// manifest records one head-top number per variant and this needs the
    /// silhouette of every frame.
    @Test(.enabled(if: SceneArt.isAvailable))
    @MainActor
    func theSlotClearsEveryPixelTheCastCanDrawAndOnlyJust() throws {
        let manifest = try SceneFixtures.manifest()
        let store = TextureStore(manifest: manifest)
        let canvas = manifest.characters.canvas

        var widestRight = 0
        for id in manifest.characters.orderedVariantIDs {
            guard let variant = manifest.characters.variant(id) else { continue }
            for state in BodyState.allCases {
                for facing in [Facing.right, .left] {
                    for path in variant.animation(state)?.frames(facing: facing) ?? [] {
                        let image = try #require(
                            PNGProbe.load(SceneFixtures.repositoryRoot.appending(path: path)))
                        widestRight = max(widestRight, image.rightmostOpaqueColumn ?? 0)
                    }
                }
            }
        }

        // The body node is anchored bottom-centre on a `canvas.width` box, so
        // canvas column `c` lands at `c − width/2` in the character's own
        // coordinates.
        let bodyRightEdge = Double(widestRight + 1) - Double(canvas.width) / 2
        let character = Character(
            variant: try #require(manifest.characters.orderedVariantIDs.first),
            nameplate: NameplateText(lead: "8DE", role: "Explore"), store: store)
        character.apply(badge: BadgeSelection.select(openToolNames: ["Bash"]))

        #expect(character.badgeRect.minX >= bodyRightEdge, Comment(rawValue:
                "the slot starts at \(character.badgeRect.minX) and the cast reaches "
                + "\(bodyRightEdge)"))
        #expect(character.badgeRect.minX - bodyRightEdge <= 1,
                "\(character.badgeRect.minX - bodyRightEdge) px of air is pitch spent on nothing")

        // The plate hangs under the feet and the slot's floor is well above
        // them, so the two cannot meet however tall either grows.
        #expect(character.badgeRect.minY > character.nameplateRect.maxY)
    }

    /// **The slot is on one side and stays there, whichever way the character
    /// faces.**
    ///
    /// A seated character faces left whenever its last lateral move was
    /// leftwards (a reporter seated left of the anchor walks home leftwards and
    /// sits that way), so this is a standing state, not a transient. Mirroring
    /// the slot with the facing was rejected on three counts, and the first is
    /// the one this test pins:
    ///
    /// 1. **the trailing side is where the station's own prop stands.** Measured
    ///    over the six shipped themes, a slot on the character's left would land
    ///    inside a `plant` for 89% of its area on average and 100% of it in four
    ///    of the six; on the right it meets a `desk` for 36%. Halving the
    ///    occlusion is not a preference.
    /// 2. a badge that changes sides when a character turns round is a move in
    ///    the slot caused by nothing the slot is about;
    /// 3. one offset for the whole room means one place for the eye to look.
    @Test(.enabled(if: SceneArt.isAvailable))
    @MainActor
    func theSlotDoesNotMirrorWithTheFacing() throws {
        let manifest = try SceneFixtures.manifest()
        let store = TextureStore(manifest: manifest)
        let character = Character(
            variant: try #require(manifest.characters.orderedVariantIDs.first),
            nameplate: NameplateText(lead: "8DE", role: "Explore"), store: store)
        character.apply(badge: BadgeSelection.select(openToolNames: ["Bash"]))

        character.apply(state: .working, facing: .right)
        let right = character.badgeRect
        character.apply(state: .working, facing: .left)
        #expect(character.facing == .left)
        #expect(character.badgeRect == right)
    }

    /// **Nothing of a neighbour's reaches the slot, and the binding neighbour is
    /// not the one you would guess.**
    ///
    /// Ring parity puts adjacent columns on *different rows*, so the nearest
    /// body is 64 px above or below and can never share a horizontal strip with
    /// the slot. What can is that neighbour's **nameplate**, which hangs under
    /// its feet and therefore comes back down into exactly the band the slot now
    /// occupies. That is the check.
    @Test func theSlotAndTheCountChipStayOutOfTheNeighbouringColumn() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let pitch = Double(layout.seatSpacingTiles * layout.tile)

        // The far edge of everything the slot draws: the bubble, then the `×N`
        // chip that hangs off its bottom-right corner.
        let slotRight = Double(manifest.characters.canvas.width) / 2
            + Double(manifest.badges.canvas.width)
        let chipRight = slotRight - 3 + Double(SceneBitmaps.badgeCount(5).width)

        // The neighbour is one pitch away and its plate is centred on it.
        let neighbourPlateLeft = pitch - Double(SceneBitmaps.maximumNameplateWidth) / 2
        #expect(chipRight <= neighbourPlateLeft, Comment(rawValue:
                "the chip reaches \(chipRight) and the neighbour's plate starts at "
                + "\(neighbourPlateLeft)"))

        // And the neighbour's body, which is the easy one.
        #expect(chipRight <= pitch - Double(manifest.characters.canvas.width) / 2)
    }

    /// **The dormancy tab lands in the corner of the slot nearest the head, and
    /// it is still small.**
    ///
    /// The tab and the bubble are two sizes in one slot, so the slot has to be
    /// anchored somewhere and the corner it is anchored at is the only thing
    /// deciding where a 9×11 picture goes inside a 24×34 box. Top-and-near,
    /// because the head is the landmark: bottom-aligning would drop the tab 23
    /// px onto the character's lap and centring would put 7 px of nothing
    /// between it and the head it is about.
    ///
    /// **The distinction from a tool badge is still extent**, which is what
    /// makes it survive `1x`: a dimmed bubble was tried and lost because alpha
    /// cuts contrast and cannot cut extent. Moving the slot changed neither
    /// number, and this asserts that.
    @Test(.enabled(if: SceneArt.isAvailable))
    @MainActor
    func theDormancyTabSitsInTheSlotsHeadCornerAndStaysSmall() throws {
        let manifest = try SceneFixtures.manifest()
        let store = TextureStore(manifest: manifest)
        let character = Character(
            variant: try #require(manifest.characters.orderedVariantIDs.first),
            nameplate: NameplateText(lead: "8DE", role: "Explore"), store: store)

        character.apply(badge: BadgeSelection.select(openToolNames: ["Bash"]))
        let bubble = character.badgeRect
        // `Int` on both sides: a `CGFloat == Double` inside `#expect` compares
        // unequal even when the bit patterns match, because the macro erases
        // each operand and the erased types differ.
        #expect(Int(bubble.width) == manifest.badges.canvas.width)
        #expect(Int(bubble.height) == manifest.badges.canvas.height)

        // **Dormancy is a bubble, and the corner is what this test is for.**
        // It also asserted the dormancy picture stayed under a quarter of the
        // bubble's area, which pinned the authored 9x11 tab; reverted, because
        // at 1x that tab read as a black text box in a slot where every other
        // badge is pack art. The size claim went with it; the *anchor* claim did
        // not, and it is the one that catches a picture drifting off the head.
        character.apply(badge: BadgeSelection.select(openToolNames: [String](), isDormant: true))
        let sleeping = character.badgeRect
        #expect(sleeping.maxY == bubble.maxY, "the sleep badge fell off the head line")
        #expect(sleeping.minX == bubble.minX, "the sleep badge drifted away from the head")
        #expect(Int(sleeping.width) == manifest.badges.canvas.width,
                "the sleep badge is not drawn on the badge canvas")
        #expect(Int(sleeping.height) == manifest.badges.canvas.height)

        // Back to a bubble, at the bubble's own size and in the bubble's own
        // place: the tab resized the node, and a slot anchored at its top means
        // a size change is also a position change.
        character.apply(badge: BadgeSelection.select(openToolNames: ["Read"]))
        #expect(character.badgeRect == bubble)
    }
}

/// Just enough PNG to ask where the ink stops. The scene draws through
/// SpriteKit, which cannot be read back without a window server, and the
/// question here is about the file on disk rather than about the render.
enum PNGProbe {

    struct Image {
        let width: Int
        let height: Int
        let alpha: [UInt8]

        /// Rightmost column holding any opaque pixel, or `nil` for a blank file.
        var rightmostOpaqueColumn: Int? {
            for column in stride(from: width - 1, through: 0, by: -1) {
                for row in 0..<height where alpha[row * width + column] > 0 { return column }
            }
            return nil
        }
    }

    /// Decodes through `CoreGraphics`, which is present wherever SpriteKit is
    /// and needs no window server.
    static func load(_ url: URL) -> Image? {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) { alpha[index] = pixels[index * 4 + 3] }
        return Image(width: width, height: height, alpha: alpha)
    }
}
