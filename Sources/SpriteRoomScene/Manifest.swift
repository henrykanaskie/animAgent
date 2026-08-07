import Foundation

/// A typed view of `assets/manifest.json`.
///
/// Everything the scene draws is addressed through this type. No filename and
/// no frame index appears anywhere else in `SpriteRoomScene` — final art must
/// drop in as a manifest swap with zero code change.
public struct Manifest: Sendable, Hashable {

    // MARK: Nested values

    public struct Size: Sendable, Hashable {
        public let width: Int
        public let height: Int
    }

    /// Normalised anchor point, in SpriteKit's convention (0,0 = bottom-left).
    public struct Anchor: Sendable, Hashable {
        public let x: Double
        public let y: Double
    }

    public struct Render: Sendable, Hashable {
        public let filtering: String
        public let mipmaps: Bool
        /// Descending. `[3, 2, 1]`. [I6]
        public let integerScales: [Int]
    }

    public struct Credit: Sendable, Hashable {
        public let required: Bool
        public let text: String
        public let url: String
    }

    /// One body state of one character variant.
    public struct StateAnimation: Sendable, Hashable {
        public let loops: Bool
        public let fps: Double
        /// Frame paths per direction. `working` carries `right` and `left`
        /// only — the pack ships no front- or back-facing sitting pose.
        public let frames: [Facing: [String]]

        public func frames(facing: Facing) -> [String]? { frames[facing] }

        /// The directions this state was actually drawn for.
        public var facings: Set<Facing> { Set(frames.keys) }
    }

    public struct CharacterVariant: Sendable, Hashable {
        public let id: String
        /// Distance in pixels from the top of the 32×64 frame to the top of the
        /// head. The badge hangs off this, not off the frame top.
        public let headTopPx: Int
        public let states: [BodyState: StateAnimation]

        public func animation(_ state: BodyState) -> StateAnimation? { states[state] }
    }

    public struct Characters: Sendable, Hashable {
        public let canvas: Size
        public let anchor: Anchor
        public let frameRate: Double
        /// Keyed by variant id (`"06"`, `"07"`, …). Iterate `orderedVariantIDs`
        /// when order matters — dictionary order is not stable.
        public let variants: [String: CharacterVariant]
        public let orderedVariantIDs: [String]

        public func variant(_ id: String) -> CharacterVariant? { variants[id] }
    }

    public struct BadgeArt: Sendable, Hashable {
        public let file: String
        /// `"pack"` or `"placeholder"`. Recorded so the About panel and the
        /// M5 swap can both tell the difference; the scene draws either.
        public let provenance: String
    }

    public struct Badges: Sendable, Hashable {
        public let canvas: Size
        public let anchor: Anchor
        public let map: [ToolBadge: BadgeArt]
        /// Non-tool badge states. `attention` is the only one. [I1]
        public let states: [String: BadgeArt]

        public func art(_ badge: ToolBadge) -> BadgeArt? { map[badge] }
    }

    public struct Room: Sendable, Hashable {
        public let tile: Size
        public let builderTiles: [String]
        public let propCanvas: Size
        public let propFiles: [String]
        /// `false` while the pack names its singles by index only. Until this
        /// is true nothing here can be called a desk, so the scene draws
        /// placeholder furniture instead of guessing. [I1]
        public let propsIdentified: Bool
    }

    // MARK: Stored

    public let schema: Int
    public let sizeSet: String
    public let render: Render
    public let credit: Credit
    public let characters: Characters
    public let badges: Badges
    public let room: Room
    /// Directory that manifest-relative paths resolve against — the repository
    /// root, since paths are recorded as `assets/processed/...`.
    public let root: URL

    public func url(_ manifestPath: String) -> URL {
        root.appending(path: manifestPath)
    }

    // MARK: Loading

    public enum LoadError: Error, CustomStringConvertible {
        case notFound(URL)
        case malformed(String)

        public var description: String {
            switch self {
            case .notFound(let url): return "manifest not found at \(url.path)"
            case .malformed(let what): return "manifest is malformed: \(what)"
            }
        }
    }

    /// Loads `<root>/assets/manifest.json`.
    public static func load(root: URL) throws -> Manifest {
        let url = root.appending(path: "assets").appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.notFound(url)
        }
        return try load(contentsOf: url, root: root)
    }

    public static func load(contentsOf url: URL, root: URL) throws -> Manifest {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw LoadError.notFound(url) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError.malformed("top level is not an object")
        }
        return try Manifest(object: object, root: root)
    }

    /// Walks up from the source file to the repository root, falling back to
    /// the working directory. Host-side convenience for M2's dev harness; the
    /// shipping app will pass an explicit bundle root.
    public static func developmentRoot(file: StaticString = #filePath) -> URL {
        let fromSource = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // SpriteRoomScene
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repository root
        if FileManager.default.fileExists(
            atPath: fromSource.appending(path: "assets/manifest.json").path) {
            return fromSource
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    // MARK: Decoding

    private init(object: [String: Any], root: URL) throws {
        self.root = root
        self.schema = (object["schema"] as? Int) ?? 0
        self.sizeSet = (object["size_set"] as? String) ?? ""

        let renderObject = try Self.object(object, "render")
        let scales = (renderObject["integer_scales"] as? [Int]) ?? []
        guard !scales.isEmpty else { throw LoadError.malformed("render.integer_scales is empty") }
        self.render = Render(
            filtering: (renderObject["filtering"] as? String) ?? "nearest",
            mipmaps: (renderObject["mipmaps"] as? Bool) ?? false,
            integerScales: scales.sorted(by: >))

        let creditObject = (object["credit"] as? [String: Any]) ?? [:]
        self.credit = Credit(
            required: (creditObject["required"] as? Bool) ?? true,
            text: (creditObject["text"] as? String) ?? "",
            url: (creditObject["url"] as? String) ?? "")

        // Characters
        let charactersObject = try Self.object(object, "characters")
        let charactersCanvas = try Self.size(charactersObject, "canvas", in: "characters")
        let charactersAnchor = Self.anchor(charactersObject)
        let frameRate = Double((charactersObject["frame_rate"] as? Int) ?? 8)
        let variantsObject = try Self.object(charactersObject, "variants")
        var variants: [String: CharacterVariant] = [:]
        for (id, raw) in variantsObject {
            guard let variantObject = raw as? [String: Any] else {
                throw LoadError.malformed("characters.variants.\(id) is not an object")
            }
            let statesObject = try Self.object(variantObject, "states")
            var states: [BodyState: StateAnimation] = [:]
            for (stateName, rawState) in statesObject {
                guard let state = BodyState(rawValue: stateName) else { continue }
                guard let stateObject = rawState as? [String: Any],
                      let framesObject = stateObject["frames"] as? [String: Any] else {
                    throw LoadError.malformed("characters.variants.\(id).states.\(stateName)")
                }
                var frames: [Facing: [String]] = [:]
                for (direction, rawPaths) in framesObject {
                    guard let facing = Facing(rawValue: direction),
                          let paths = rawPaths as? [String], !paths.isEmpty else { continue }
                    frames[facing] = paths
                }
                guard !frames.isEmpty else {
                    throw LoadError.malformed(
                        "characters.variants.\(id).states.\(stateName) has no usable frames")
                }
                states[state] = StateAnimation(
                    loops: (stateObject["loop"] as? Bool) ?? true,
                    fps: Double((stateObject["fps"] as? Int) ?? Int(frameRate)),
                    frames: frames)
            }
            variants[id] = CharacterVariant(
                id: id,
                headTopPx: (variantObject["head_top_px"] as? Int) ?? 0,
                states: states)
        }
        guard !variants.isEmpty else { throw LoadError.malformed("characters.variants is empty") }
        self.characters = Characters(
            canvas: charactersCanvas,
            anchor: charactersAnchor,
            frameRate: frameRate,
            variants: variants,
            orderedVariantIDs: variants.keys.sorted())

        // Badges
        let badgesObject = try Self.object(object, "badges")
        let badgeMapObject = try Self.object(badgesObject, "map")
        var badgeMap: [ToolBadge: BadgeArt] = [:]
        for (key, raw) in badgeMapObject {
            guard let badge = ToolBadge(manifestKey: key),
                  let entry = raw as? [String: Any],
                  let file = entry["file"] as? String else { continue }
            badgeMap[badge] = BadgeArt(
                file: file, provenance: (entry["provenance"] as? String) ?? "unknown")
        }
        for badge in ToolBadge.allCases where badgeMap[badge] == nil {
            throw LoadError.malformed("badges.map is missing \(badge.manifestKey)")
        }
        var badgeStates: [String: BadgeArt] = [:]
        for (key, raw) in (badgesObject["states"] as? [String: Any]) ?? [:] {
            guard let entry = raw as? [String: Any], let file = entry["file"] as? String else {
                continue
            }
            badgeStates[key] = BadgeArt(
                file: file, provenance: (entry["provenance"] as? String) ?? "unknown")
        }
        self.badges = Badges(
            canvas: try Self.size(badgesObject, "canvas", in: "badges"),
            anchor: Self.anchor(badgesObject),
            map: badgeMap,
            states: badgeStates)

        // Room
        let roomObject = try Self.object(object, "room")
        let builder = try Self.object(roomObject, "builder")
        let props = (roomObject["props"] as? [String: Any]) ?? [:]
        let propCanvasObject = (props["canvas"] as? [String: Any]) ?? [:]
        self.room = Room(
            tile: try Self.size(roomObject, "tile", in: "room"),
            builderTiles: (builder["tiles"] as? [String]) ?? [],
            propCanvas: Size(
                width: (propCanvasObject["w"] as? Int) ?? 64,
                height: (propCanvasObject["h"] as? Int) ?? 96),
            propFiles: (props["files"] as? [String]) ?? [],
            propsIdentified: (props["identified"] as? Bool) ?? false)
        guard !self.room.builderTiles.isEmpty else {
            throw LoadError.malformed("room.builder.tiles is empty")
        }
    }

    private static func object(_ parent: [String: Any], _ key: String) throws -> [String: Any] {
        guard let value = parent[key] as? [String: Any] else {
            throw LoadError.malformed("`\(key)` is missing or not an object")
        }
        return value
    }

    private static func size(
        _ parent: [String: Any], _ key: String, in context: String
    ) throws -> Size {
        guard let value = parent[key] as? [String: Any],
              let w = value["w"] as? Int, let h = value["h"] as? Int else {
            throw LoadError.malformed("\(context).\(key) is missing w/h")
        }
        return Size(width: w, height: h)
    }

    /// Manifest anchors are recorded in image space (y down); SpriteKit anchors
    /// are y-up. Both files record `[0.5, 0.0]`, which means bottom-centre in
    /// SpriteKit terms already, so this is a straight read with the convention
    /// written down rather than assumed.
    private static func anchor(_ parent: [String: Any]) -> Anchor {
        guard let anchorObject = parent["anchor"] as? [String: Any],
              let normalized = anchorObject["normalized"] as? [Double],
              normalized.count == 2 else {
            return Anchor(x: 0.5, y: 0.0)
        }
        return Anchor(x: normalized[0], y: normalized[1])
    }
}
