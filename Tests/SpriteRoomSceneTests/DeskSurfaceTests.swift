import Foundation
import Testing
@testable import SpriteRoomScene

/// ADR-006 §2b/§2c, step 1 only: the desk-surface anchor.
///
/// This step draws nothing — no object stands on a desk yet, and none is
/// placed by this file. What exists after it is a manifest measurement
/// (`room.props.roles.desk.surface_y` and each theme's own) and a pure
/// `RoomLayout` accessor a later step will use to place something there. These
/// tests check exactly that pair: the measurement is right, and the arithmetic
/// that turns it into a scene point is right — nothing about what gets drawn.
struct DeskSurfaceTests {

    enum FixtureError: Error { case notADictionary(String) }

    /// The raw manifest, read as JSON rather than through `Manifest`.
    ///
    /// `surface_y` is a new key this task adds; `Manifest.swift` does not
    /// decode it (that is a later step's job, once something actually reads
    /// it to draw). Reading the bytes directly is the same choice
    /// `ManifestTests.authoredBadgesSayTheyAreAuthoredAndWhy` already makes for
    /// a provenance/measurement key nothing in `Sources/` consumes yet.
    static func rawManifest() throws -> [String: Any] {
        let url = SceneFixtures.repositoryRoot
            .appending(path: "assets").appending(path: "manifest.json")
        let raw = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        guard let dict = raw as? [String: Any] else { throw FixtureError.notADictionary("manifest root") }
        return dict
    }

    /// `desk`'s role entry under `room.props.roles`, or under one theme's own
    /// `props.roles` when `theme` is given.
    static func deskRole(_ root: [String: Any], theme: String? = nil) -> [String: Any]? {
        let container: [String: Any]?
        if let theme {
            let sets = (root["themes"] as? [String: Any])?["sets"] as? [String: Any]
            container = sets?[theme] as? [String: Any]
        } else {
            container = root["room"] as? [String: Any]
        }
        let roles = (container?["props"] as? [String: Any])?["roles"] as? [String: Any]
        return roles?["desk"] as? [String: Any]
    }

    /// `surface_y` for the room default and every theme, keyed by name
    /// (`"room"` for the default). One entry per desk role the manifest binds.
    static func deskSurfaceHeights(_ root: [String: Any]) -> [String: Int] {
        var out: [String: Int] = [:]
        if let height = deskRole(root)?["surface_y"] as? Int {
            out["room"] = height
        }
        let themes = (root["themes"] as? [String: Any])?["sets"] as? [String: Any] ?? [:]
        for name in themes.keys {
            if let height = deskRole(root, theme: name)?["surface_y"] as? Int {
                out[name] = height
            }
        }
        return out
    }

    // MARK: The manifest measurement

    /// Every theme's desk has a surface — the room default plus all six
    /// themes, seven entries total, matching ADR-006 §2b's table.
    @Test func everyThemesDeskHasASurface() throws {
        let root = try Self.rawManifest()
        let heights = Self.deskSurfaceHeights(root)
        #expect(heights.count == 7,
                "expected 7 desk surfaces (room default + 6 themes), got \(heights.keys.sorted())")
        for (name, height) in heights {
            #expect(height > 0, "\(name)'s desk surface is not above the floor")
        }
    }

    /// ADR-006 §2b's own table, reproduced independently for this task and
    /// checked against the shipped manifest rather than trusted from the doc.
    @Test func theMeasuredHeightsMatchADR006sTable() throws {
        let root = try Self.rawManifest()
        let heights = Self.deskSurfaceHeights(root)
        let expected: [String: Int] = [
            "room": 24, "briefing": 24, "broadcast": 24, "office": 24, "stage": 24,
            "library": 36, "mission_control": 36,
        ]
        #expect(heights == expected)
    }

    /// The case the rule exists to discriminate: `library` binds *"wooden
    /// school desk with an open book on the top"*, whose `content_box` top is
    /// 8 px above the slab underneath (44 px tall, not 36). The rule has to
    /// find the slab, not the box's own top row.
    @Test func libraryFindsTheSlabUnderTheBookNotTheBoxTop() throws {
        let root = try Self.rawManifest()
        let desk = try #require(Self.deskRole(root, theme: "library"))
        let box = try #require(desk["content_box"] as? [String: Any])
        let boxHeight = try #require(box["h"] as? Int)
        let surface = try #require(desk["surface_y"] as? Int)
        #expect(boxHeight == 44, "library's desk content_box height moved; ADR-006 §2b needs re-deriving")
        #expect(surface == 36, "library's surface should be the slab under the book, not the box top")
        #expect(surface != boxHeight,
                "if these ever match, the desk stopped drawing a book on it and the special case is gone")
    }

    /// A surface is inside its own content box: strictly above the floor
    /// (`content_box`'s own bottom row) and never above the box's own top row.
    /// `surface_y` is a height above the floor, so this is `0 < surface_y <=
    /// content_box.h` for every desk role the manifest declares.
    @Test func everySurfaceIsInsideItsOwnContentBox() throws {
        let root = try Self.rawManifest()
        var checked = 0

        func check(_ label: String, _ desk: [String: Any]?) throws {
            let comment = Comment(rawValue: label)
            let desk = try #require(desk, comment)
            let box = try #require(desk["content_box"] as? [String: Any], comment)
            let boxHeight = try #require(box["h"] as? Int, comment)
            let surface = try #require(desk["surface_y"] as? Int, comment)
            #expect(surface > 0, "\(label): surface at or below the floor")
            #expect(surface <= boxHeight, "\(label): surface above the box's own top row")
            checked += 1
        }

        try check("room", Self.deskRole(root))
        let themes = try #require((root["themes"] as? [String: Any])?["sets"] as? [String: Any])
        for name in themes.keys {
            try check(name, Self.deskRole(root, theme: name))
        }
        #expect(checked == 7)
    }

    // MARK: RoomLayout.deskSurfacePosition — pure arithmetic, needs no manifest

    /// Same seat, same height, called twice: the same point. `RoomLayout` has
    /// no state and no clock, so nothing here can drift between calls.
    @Test func deskSurfacePositionIsDeterministic() {
        let layout = RoomLayout()
        let first = layout.deskSurfacePosition(seat: 3, surfaceHeightAboveFloor: 24)
        let second = layout.deskSurfacePosition(seat: 3, surfaceHeightAboveFloor: 24)
        #expect(first == second)
    }

    /// The surface sits directly above the desk's own bottom-centre anchor —
    /// same `x`, `y` raised by exactly the given height — for every seat the
    /// room has.
    @Test func deskSurfaceSitsDirectlyAboveTheDesksOwnAnchor() {
        let layout = RoomLayout()
        for seat in 0..<layout.seatCapacity {
            let anchor = layout.deskPosition(seat)
            let surface = layout.deskSurfacePosition(seat: seat, surfaceHeightAboveFloor: 24)
            #expect(surface.x == anchor.x, "seat \(seat)")
            #expect(surface.y == anchor.y + 24, "seat \(seat)")
        }
    }

    /// `library`'s taller surface (36) stands further above the floor than a
    /// bare desk's (24), by exactly the difference — the height parameter is
    /// not silently clamped or ignored.
    @Test func aTallerSurfaceHeightStandsFurtherAboveTheFloor() {
        let layout = RoomLayout()
        let bare = layout.deskSurfacePosition(seat: 0, surfaceHeightAboveFloor: 24)
        let library = layout.deskSurfacePosition(seat: 0, surfaceHeightAboveFloor: 36)
        #expect(library.y > bare.y)
        #expect(library.y - bare.y == 12)
    }

    /// Every seat's desk surface, at the room's own measured heights, lands on
    /// the row `RoomLayout` says the seat's desk occupies — never below the
    /// desk's bottom-centre anchor, which is where the ADR's placement rule
    /// (§2c, a later step) starts reasoning from.
    @Test func deskSurfaceIsNeverBelowTheDesksOwnAnchor() throws {
        let root = try Self.rawManifest()
        let heights = Self.deskSurfaceHeights(root)
        let layout = RoomLayout()
        for (_, height) in heights {
            let anchor = layout.deskPosition(0)
            let surface = layout.deskSurfacePosition(seat: 0, surfaceHeightAboveFloor: Double(height))
            #expect(surface.y >= anchor.y)
        }
    }
}
