import Foundation
import Testing
@testable import SpriteRoomScene

/// The manifest is the contract. If these break, either the art moved or the
/// scene started assuming something the manifest does not promise.
///
/// `assets/manifest.json` is tracked, so most of these run anywhere. The three
/// that go on to open the files the manifest names are gated on `SceneArt` —
/// see `SceneFixtures.swift` for why the art may legitimately be absent.
struct ManifestTests {

    @Test func theManifestLoadsAndDeclaresTheIntegerLadder() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(manifest.render.filtering == "nearest")
        #expect(manifest.render.mipmaps == false)
        #expect(manifest.render.integerScales == [3, 2, 1])
    }

    @Test func charactersAreThirtyTwoBySixtyFourNotSquare() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(manifest.characters.canvas.width == 32)
        #expect(manifest.characters.canvas.height == 64)
        #expect(manifest.characters.anchor.x == 0.5)
        #expect(manifest.characters.anchor.y == 0.0)
    }

    /// Six body states, not seven. `read` is gone because no `read a book`
    /// animation exists, and `attention` is badge-only by design. [I1]
    @Test func everyVariantShipsExactlyTheSixBodyStates() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(!manifest.characters.orderedVariantIDs.isEmpty)
        for id in manifest.characters.orderedVariantIDs {
            let variant = try #require(manifest.characters.variant(id))
            #expect(Set(variant.states.keys) == Set(BodyState.allCases), "variant \(id)")
        }
    }

    /// The pack has no front- or back-facing sitting pose at any size. A scene
    /// that asks for one is asking for art nobody drew.
    @Test func workingIsSideViewOnlyAndEverythingElseIsFourWay() throws {
        let manifest = try SceneFixtures.manifest()
        for id in manifest.characters.orderedVariantIDs {
            let variant = try #require(manifest.characters.variant(id))
            let working = try #require(variant.animation(.working))
            #expect(working.facings == [.right, .left], "variant \(id) working")
            for state in BodyState.allCases where state != .working {
                let animation = try #require(variant.animation(state))
                #expect(animation.facings == Set(Facing.allCases), "variant \(id) \(state)")
            }
        }
    }

    @Test func deliverIsTheOnlyOneShot() throws {
        let manifest = try SceneFixtures.manifest()
        for id in manifest.characters.orderedVariantIDs {
            let variant = try #require(manifest.characters.variant(id))
            for state in BodyState.allCases {
                let animation = try #require(variant.animation(state))
                #expect(animation.loops == (state != .deliver), "variant \(id) \(state)")
            }
        }
    }

    @Test(.enabled(if: SceneArt.isAvailable))
    func everyDeclaredFrameIsActuallyOnDisk() throws {
        let manifest = try SceneFixtures.manifest()
        var checked = 0
        for id in manifest.characters.orderedVariantIDs {
            let variant = try #require(manifest.characters.variant(id))
            for (_, animation) in variant.states {
                for (_, paths) in animation.frames {
                    for path in paths {
                        #expect(
                            FileManager.default.fileExists(atPath: manifest.url(path).path),
                            "missing \(path)")
                        checked += 1
                    }
                }
            }
        }
        #expect(checked > 0)
    }

    @Test(.enabled(if: SceneArt.isAvailable))
    func everyBadgeInTheTableHasArtAndAFileOnDisk() throws {
        let manifest = try SceneFixtures.manifest()
        for badge in ToolBadge.allCases {
            let art = try #require(manifest.badges.art(badge), "no art for \(badge)")
            #expect(
                FileManager.default.fileExists(atPath: manifest.url(art.file).path),
                "missing \(art.file)")
        }
    }

    /// Six of the seven badges are placeholders and one is real. The scene does
    /// not care which — it reads the manifest either way — but the manifest
    /// must keep saying which, so the M5 swap stays reviewable.
    @Test func badgeProvenanceIsRecorded() throws {
        let manifest = try SceneFixtures.manifest()
        for badge in ToolBadge.allCases {
            let art = try #require(manifest.badges.art(badge))
            #expect(["pack", "placeholder"].contains(art.provenance), "\(badge)")
        }
        #expect(manifest.badges.art(.questionMark)?.provenance == "pack")
    }

    @Test func attentionIsABadgeStateAndNotABodyState() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(manifest.badges.states["attention"] != nil)
        #expect(BodyState(rawValue: "attention") == nil)
        #expect(BodyState(rawValue: "read") == nil)
    }

    @Test func theRoomDeclaresTilesAndItsIdentifiedProps() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(manifest.room.tile.width == 32)
        #expect(manifest.room.tile.height == 32)
        #expect(!manifest.room.builderTiles.isEmpty)
        // `identified` and the role map say the same thing, and must not be
        // able to disagree: a true flag with no roles would let the scene look
        // for a desk that is not there.
        #expect(manifest.room.propsIdentified == !manifest.room.propRoles.isEmpty)
        #expect(manifest.room.prop("desk") != nil, "M5 identified a desk")
    }

    /// A role's content box has to be inside the canvas and non-empty, or the
    /// anchor derived from it points somewhere the art is not.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyPropRoleHasAMeasuredBoxInsideItsCanvas() throws {
        let manifest = try SceneFixtures.manifest()
        let canvas = manifest.room.propCanvas
        for (role, prop) in manifest.room.propRoles {
            let box = prop.contentBox
            #expect(box.width > 0 && box.height > 0, "\(role) has an empty box")
            #expect(box.x >= 0 && box.y >= 0, "\(role) box starts outside the canvas")
            #expect(box.x + box.width <= canvas.width, "\(role) box overflows in x")
            #expect(box.y + box.height <= canvas.height, "\(role) box overflows in y")
            let anchor = prop.anchor(inCanvas: canvas)
            #expect(anchor.x >= 0 && anchor.x <= 1)
            #expect(anchor.y >= 0 && anchor.y <= 1)
            #expect(FileManager.default.fileExists(atPath: manifest.url(prop.file).path),
                    "\(role) points at a file that is not there")
        }
    }

    /// The desk's baseline is at row 87 of its canvas and the plant's at row 75,
    /// in canvases of identical size. A prop placed by a fixed offset would be
    /// right for one and 12 px into the floor for the other — which is why the
    /// manifest carries the box and the scene anchors off it.
    @Test func propsAreNotBottomAlignedInTheirCanvasAndSoNeedTheirBox() throws {
        let manifest = try SceneFixtures.manifest()
        let boxes = manifest.room.propRoles.values.map { $0.contentBox.y + $0.contentBox.height }
        #expect(Set(boxes).count > 1, "if every prop shared a baseline, the box would be dead weight")
    }

    @Test func everyVariantCarriesAnAssignedAccent() throws {
        let manifest = try SceneFixtures.manifest()
        for id in manifest.characters.orderedVariantIDs {
            #expect(manifest.characters.variant(id)?.accentHex != nil,
                    "variant \(id) has no accent_hex; sampling the art does not separate")
        }
    }

    @Test func anAccentHexIsParsedAndAnythingElseIsNil() {
        #expect(Manifest.colour("#FF884D") == Bitmap.RGBA(255, 136, 77))
        #expect(Manifest.colour("FF884D") == Bitmap.RGBA(255, 136, 77))
        #expect(Manifest.colour("#FFF") == nil)
        #expect(Manifest.colour("not a colour") == nil)
        #expect(Manifest.colour(nil) == nil)
    }

    @Test func theCreditLineIsPresentAndRequired() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(manifest.credit.required)
        #expect(manifest.credit.text.contains("limezu.itch.io"))
    }

    @Test func aMissingManifestIsAnErrorNotACrash() {
        #expect(throws: (any Error).self) {
            try Manifest.load(root: URL(fileURLWithPath: "/nowhere/at/all"))
        }
    }
}
