import Foundation
import Testing
@testable import SpriteRoomScene

/// The manifest is the contract. If these break, either the art moved or the
/// scene started assuming something the manifest does not promise.
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

    @Test func everyDeclaredFrameIsActuallyOnDisk() throws {
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

    @Test func everyBadgeInTheTableHasArtAndAFileOnDisk() throws {
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

    @Test func theRoomDeclaresTilesAndUnidentifiedProps() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(manifest.room.tile.width == 32)
        #expect(manifest.room.tile.height == 32)
        #expect(!manifest.room.builderTiles.isEmpty)
        // While this is false the scene may not call any single a desk.
        #expect(manifest.room.propsIdentified == false)
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
