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
        /// **Which frame of this row holds the body highest**, measured by
        /// `scripts/build-manifest.py` off the frames themselves. [ADR-008]
        ///
        /// `AmbientMotion`'s phrase table is a schedule over two positions of
        /// one bob — `settled` and `raised` — and `raised` used to be computed
        /// as "the last frame". That is a measurement of the three-frame `sit`
        /// row `(rest, rest, up)` and it is wrong for every other row: the
        /// six-frame `idle` row bobs on frames **2 and 3** and comes back to
        /// rest on 4 and 5, so the last frame is a *settled* one and a phrase
        /// built on it would hold a working character motionless. Once a seat
        /// can face the camera the idle row is what a seated character draws,
        /// so this stopped being hypothetical.
        ///
        /// `nil` for a manifest that predates the measurement, and
        /// `AmbientMotion.Beat.frameIndex` then falls back to the old rule, so
        /// an old manifest draws exactly what it drew before.
        public let raisedFrame: Int?
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
        /// The nameplate border colour, **assigned** in the manifest rather than
        /// sampled from the sprite.
        ///
        /// M2 measured the art's own accents and they do not separate: all six
        /// selected premades' most saturated pixels land inside a 30° arc and
        /// two are hue-identical. `nil` only if the manifest omits it, in which
        /// case `TextureStore` falls back to sampling and the weak channel is
        /// back — so the lint requires the field.
        public let accentHex: Bitmap.RGBA?
        public let states: [BodyState: StateAnimation]

        public func animation(_ state: BodyState) -> StateAnimation? { states[state] }
    }

    /// One costume: an ordered stack of overlay layers drawn **on** a character,
    /// in the generator's own back-to-front order. [ADR-002 §4, the costume
    /// amendment]
    ///
    /// A layer is variant-shaped on purpose — the same `states` map, the same
    /// facings, the same frame counts — because that is literally what the art
    /// is. Modern Interiors' `Character_Generator/Outfits` sheets are the
    /// premade sheet's exact geometry, registered frame for frame on every pose
    /// row including `sit`, so a layer is a second `CharacterVariant` drawn over
    /// the first with no offset to solve. Verified before this type was written:
    /// an outfit composited onto each of the six cast premades' seated frames
    /// lands on the torso, covers the premade's own garment, and leaves the
    /// hair and the skin — which is where M0 put the variant identity — alone.
    ///
    /// **There is no hair layer and there must not be one.** The generator ships
    /// 200 hairstyles and they register just as well; the cast's hair is the one
    /// channel M0 measured as actually separating the six variants, and a
    /// costume that overwrote it would spend a proven identity channel to buy an
    /// unproven one.
    public struct Costume: Sendable, Hashable {
        public let id: String
        /// What the costume *is*, in the manifest's words. Never drawn — it is
        /// what an art report and a contract test name it by.
        public let title: String
        /// **Whether wearing this makes a claim about the work.**
        ///
        /// A lab coat says *this agent tests things*. That is a true sentence
        /// when the user named the agent `test-engineer` and the manifest
        /// translates that name; it is fiction when a hash put an arbitrary
        /// `agent_type` in it. So an asserting costume may be reached only
        /// through `Costumes.roles` — the tier that is keyed on the exact text
        /// the user wrote — and never through the pool. `ThemeSelector` enforces
        /// the reachability; `CostumeContractTests` enforces that the pool
        /// contains no costume declaring this. [I1]
        public let asserts: Bool
        /// Back to front. `layers[0]` draws nearest the body.
        public let layers: [Layer]

        public struct Layer: Sendable, Hashable {
            public let states: [BodyState: StateAnimation]

            public func animation(_ state: BodyState) -> StateAnimation? { states[state] }
        }

        /// Every path this costume needs on disk. The art survey asks this
        /// rather than reaching into `layers`, for the reason
        /// `PropRole.declaredPaths` exists: a walk that collects most of an
        /// asset's frames reports a plausible number and goes green with the
        /// rest missing.
        public var declaredPaths: Set<String> {
            var paths: Set<String> = []
            for layer in layers {
                for (_, animation) in layer.states {
                    for (_, frames) in animation.frames { paths.formUnion(frames) }
                }
            }
            return paths
        }
    }

    /// `characters.costumes` — the wardrobe, and the two tiers that keep it
    /// honest.
    ///
    /// ```
    /// costume(agent) =
    ///     nil                            if agent_id is absent   — the main thread
    ///     nil                            if agent_type is absent or ""
    ///     roles[agent_type]              if the manifest translates that exact name
    ///     rendezvous(agent_type, pool)   otherwise
    ///     nil                            if the pool is empty
    /// ```
    ///
    /// **Tier 1 translates; tier 2 must not claim.** `roles` is a table the
    /// manifest carries, keyed on `agent_type` **exactly as received** — the same
    /// rule `ThemeSelector.theme(for:stored:manifest:)` follows for `cwd`, and
    /// for the same reason: this app does not invent normalisations of the user's
    /// own strings. A `test-engineer` in a lab coat is the room repeating a name
    /// the user chose. A hash that put an unrecognised type in the same coat
    /// would be inventing the claim, which is why the pool is a separate list
    /// and why nothing in it may assert.
    ///
    /// **Empty is a legal state and is the shipped one.** No costume art has been
    /// cut, so `sets` is empty, every lookup is `nil`, and the room draws exactly
    /// what it drew before this type existed.
    public struct Costumes: Sendable, Hashable {
        public let sets: [String: Costume]
        /// Sorted. Dictionary order is not stable and neither a hash pool nor a
        /// report may depend on it.
        public let orderedIDs: [String]
        /// `agent_type` → costume id. Exact match, no case folding, no trimming.
        public let roles: [String: String]
        /// The pool the hash draws from, sorted. Ids naming no costume are
        /// dropped at decode; an asserting costume in here is a manifest defect
        /// and a test says so.
        public let assignableIDs: [String]
        /// **How far above the feet a costume's ink reaches**, over the two
        /// states a seated character draws, every set, every layer, every frame,
        /// every direction. Measured by `scripts/build-manifest.py`; 22 px for
        /// the shipped wardrobe. [ADR-008]
        ///
        /// It is the identity channel's extent, and it is what an away-facing
        /// seat's chair is placed against: a chair back `H` px tall drawn in
        /// front of a character hides **every** costume pixel at any standoff
        /// below `H − this`, which is 24 px for the 46 px chair every theme
        /// binds. A standoff chosen without it erases the costume completely
        /// and nothing fails. See `RoomLayout.awayChairStandoff(chairHeight:
        /// costumeTopAboveFeet:)`.
        ///
        /// `0` for a manifest that predates the measurement or declares no
        /// wardrobe, which makes the standoff the chair's own height plus the
        /// collar allowance — the safe direction, since it shows *more* of the
        /// character rather than less.
        public let inkTopAboveFeet: Int

        public func costume(_ id: String) -> Costume? { sets[id] }

        public var isEmpty: Bool { sets.isEmpty }

        public static let none = Costumes(
            sets: [:], orderedIDs: [], roles: [:], assignableIDs: [], inkTopAboveFeet: 0)
    }

    public struct Characters: Sendable, Hashable {
        public let canvas: Size
        public let anchor: Anchor
        public let frameRate: Double
        /// Keyed by variant id (`"06"`, `"07"`, …). Iterate `orderedVariantIDs`
        /// when order matters — dictionary order is not stable.
        public let variants: [String: CharacterVariant]
        public let orderedVariantIDs: [String]
        /// `characters.poses.working` — badge id → the name of a seated state,
        /// plus a required `default`. [ADR-002 §7]
        ///
        /// **Empty is the shipped state and it is a legal one.** The pack ships
        /// one usable seated pose, so every badge class maps to it, and §5b item
        /// 2 says in as many words that this half is then inert *with no code
        /// path to delete*. `workingPose(forBadgeKey:)` is total either way, so
        /// the day a second sit row is imported the table appears in the
        /// manifest and nothing here changes.
        ///
        /// **A pose named here must be seated, and side-on is not the same
        /// claim.** §5a's sentence is "a *seated* pose in every case"; the
        /// facings clause only says it is drawn `right` and `left`. Four of the
        /// pack's remaining rows — `pick_up`, `lift`, `throw`, `push_cart` —
        /// satisfy the facings clause exactly and are people standing up, so the
        /// two are checked separately:
        /// `ThemeContractTests.everyNamedPoseStateExistsWithExactlyRightAndLeftFrames`
        /// and `…IsSeatedRatherThanMerelySideOn`. The second reads pixels,
        /// because a pose row cannot be trusted by its label — the row called
        /// `sleep` is a head on a pillow. See `03-EVENT-MODEL.md`, "One seated
        /// pose is all the pack has".
        public let workingPoses: [String: String]
        /// `characters.costumes`. **Empty in the shipped manifest**, which makes
        /// every costume lookup `nil` and the character exactly the sprite it
        /// has always been.
        public let costumes: Costumes

        /// The key §7 requires every pose table to carry. It is what
        /// `question_mark` resolves to, and therefore what every unmapped tool
        /// gets — which is what makes a tool name nobody has heard of need no
        /// new art. [§5a]
        public static let defaultPoseKey = "default"

        public func variant(_ id: String) -> CharacterVariant? { variants[id] }

        /// The seated state for a badge class. **Total by construction**, in
        /// three steps, each of which is a real fallback rather than a guard:
        /// the badge's own entry, then the table's required `default`, then
        /// `working` itself for a manifest that declares no table at all.
        ///
        /// A name the table gives that is not one of the six body states
        /// resolves to the same floor. `BodyState` is a closed enum, so a
        /// seventh seated pose needs a case adding beside its manifest entry —
        /// recorded as a gap in §8 item 7 rather than worked around with a
        /// stringly-typed state that nothing could draw.
        public func workingPose(forBadgeKey key: String?) -> BodyState {
            let named = key.flatMap { workingPoses[$0] } ?? workingPoses[Self.defaultPoseKey]
            return named.flatMap(BodyState.init(rawValue:)) ?? .working
        }
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
        /// Non-tool badge states: `attention` and `sleep`. [I1]
        ///
        /// Deliberately separate from `map`: `map` is keyed by `ToolBadge` and
        /// every one of its keys must exist or the manifest is malformed, while
        /// these answer to no tool at all. Both are pack art — `attention` from
        /// M0b, `sleep` from M6b — and both are components of the same UI sheet,
        /// which is why adding the second one needed no new key and no new
        /// anchor.
        public let states: [String: BadgeArt]

        /// The `badges.states` key for the `Notification` badge. Written once,
        /// here, so no other file in the scene spells it.
        public static let attentionKey = "attention"

        /// The `badges.states` key for the dormant badge — a subagent that
        /// finished a turn, kept its seat, and may be revived by a later event.
        ///
        /// Beside `attention` rather than in `map` for the identical reason: it
        /// answers to no tool. It is the *badge* half of dormancy and there is
        /// no body half — the pack's `sleep` body row is a head on a pillow
        /// drawn for a top-down bed and cannot be worn by a character sitting
        /// side-on. [I1]
        public static let sleepKey = "sleep"

        public var attention: BadgeArt? { states[Self.attentionKey] }

        public var sleep: BadgeArt? { states[Self.sleepKey] }

        public func art(_ badge: ToolBadge) -> BadgeArt? { map[badge] }
    }

    /// One single that has actually been identified, and where its art sits
    /// inside the canvas.
    ///
    /// The Modern Office singles are 64×96 canvases with the object dropped in
    /// wherever it sat on the source sheet — they are neither bottom-aligned nor
    /// centred, and two objects' baselines differ by as much as 20 px. So the
    /// scene places a prop by putting `contentBox`'s bottom-centre on a named
    /// point. That is placement by measurement; a fixed offset would be a guess
    /// that happened to work for one file.
    public struct PropRole: Sendable, Hashable {
        public let file: String
        /// Opaque bounding box inside the canvas, y **down** (image space). For
        /// an animated role it is the **union over all frames**, so the scene's
        /// clearance arithmetic covers the whole swing rather than frame 0's.
        public let contentBox: Box
        /// `props.roles.<role>.animation`, when the role carries one.
        ///
        /// **Additive beside `file`, and `file` is always frame 0.** A reader
        /// that knows nothing about this key draws a still prop and is correct
        /// — which is exactly why nothing broke when the key landed, and also
        /// why nothing noticed that the art survey was not counting the other
        /// frames. [ADR-002 §14b]
        public let animation: Animation?
        /// `props.roles.<role>.surface_y` — **how many pixels above the floor
        /// this prop's top surface sits**, when the generator measured one.
        /// Carried by the `desk` role and by nothing else today. [ADR-006 §2b]
        ///
        /// It is not `contentBox.height`, and the difference is the whole reason
        /// the key exists: `content_box` measures a prop's ink footprint, not the
        /// plane you may stand something on, and for a desk with something
        /// already drawn on it the two disagree. `library` binds a school desk
        /// with an open book on top — box top 44, slab 36 — so a reader that used
        /// the box would float every desk-top object 8 px above the wood.
        ///
        /// `nil` for every other role, and for a `desk` in a manifest older than
        /// the measurement. `RoomScene` falls back to the box top in that case,
        /// which is the right answer for five of the seven desks that ship and is
        /// the answer the room drew before this key existed.
        public let surfaceY: Int?

        /// `props.roles.<role>.variants` — **every file this role may be drawn
        /// with, `file` first**. Never empty, and `variants[0] == file` always.
        ///
        /// **Additive beside `file`, exactly as `animation` is**, and the
        /// manifest says so in its own `variants_note`: a reader that has never
        /// heard of this key draws `file` and is correct. That is why a manifest
        /// without it needs no special case here — absence decodes to `[file]`,
        /// which is what every theme but `office` gets and what every caller
        /// that asks for variant 0 gets everywhere.
        ///
        /// **Nothing in a `WorldDelta` may choose an entry.** What indexes it is
        /// the seat, once, at room-build time — a seat is stable for the life of
        /// a scene, so the room is still built once and never rebuilt. A prop
        /// that changed because an agent did something would be the fiction
        /// ADR-002 §6 rule 1 exists to prevent. [I1]
        public let variants: [String]

        public struct Box: Sendable, Hashable {
            public let x: Int, y: Int, width: Int, height: Int

            public init(x: Int, y: Int, width: Int, height: Int) {
                self.x = x
                self.y = y
                self.width = width
                self.height = height
            }
        }

        public init(
            file: String, contentBox: Box, animation: Animation?, surfaceY: Int?,
            variants: [String]? = nil
        ) {
            self.file = file
            self.contentBox = contentBox
            self.animation = animation
            self.surfaceY = surfaceY
            // The one place the "`file` first, always" contract is enforced, so
            // no caller has to check it. A list that does not lead with `file`
            // is a list this reader cannot index safely — variant 0 would draw
            // something other than what a variant-blind reader draws — so it is
            // discarded whole rather than repaired.
            let declared = variants ?? []
            self.variants = declared.first == file && !declared.contains(where: \.isEmpty)
                ? declared : [file]
        }

        /// **This role drawn with one of its `variants`.** Out-of-range and
        /// negative indices wrap, so a caller may hand this a seat number
        /// without knowing how much stock the manifest declared.
        ///
        /// The copy keeps the role's own `content_box` and `surface_y` — a
        /// variant is the same slot in the same theme — and **drops
        /// `animation`**, because `animation.frames[0]` is `file` and a variant
        /// that is not `file` has no frames of its own. A role that both idles
        /// and carries stock would otherwise play frame 0 of the wrong picture.
        /// No shipped role does both; this is what stops the first one that does
        /// from being a defect.
        ///
        /// **The caller is responsible for the box when a variant's art is not
        /// registered with `file`'s.** `RoomScene` measures it — see
        /// `TextureStore.inkBox(path:)` — because the manifest declares one
        /// `content_box` per role and the office `desk_kit` stock is four
        /// objects cut from four different source sheets.
        public func variant(_ index: Int) -> PropRole {
            guard variants.count > 1 else { return self }
            let wrapped = ((index % variants.count) + variants.count) % variants.count
            guard wrapped != 0 else { return self }
            return PropRole(
                file: variants[wrapped], contentBox: contentBox, animation: nil,
                surfaceY: surfaceY)
        }

        /// The same role drawn with `variant`'s file **and that file's own
        /// measured ink box**, which is the pair `RoomScene` places.
        ///
        /// `box` is ignored where the index resolves to variant 0: the manifest
        /// measured `file` itself and a declared box outranks a measured one
        /// wherever there is a declaration to read. So a theme with no stock, or
        /// a seat that lands on entry 0, draws exactly what it drew before this
        /// key existed — including if the measurement is unavailable.
        public func variant(_ index: Int, box: Box?) -> PropRole {
            let picked = variant(index)
            guard picked.file != file, let box else { return picked }
            return PropRole(
                file: picked.file, contentBox: box, animation: picked.animation,
                surfaceY: picked.surfaceY)
        }

        /// A prop that idles on its own loop.
        ///
        /// **It takes no input but time.** [ADR-002 §14b] A clock that swings is
        /// scenery; a clock that swings faster when an agent is busy is scenery
        /// asserting something, and that is the fiction the animated-prop ban
        /// existed to prevent. There is no field here for anything a delta could
        /// supply, and there must not be one.
        public struct Animation: Sendable, Hashable {
            /// Every frame, in order. `frames[0]` is `PropRole.file`.
            public let frames: [String]
            public let fps: Double
            /// Always `true` — §14b says so in as many words, and the manifest
            /// has never carried another value. Decoded rather than assumed
            /// because `PropAnimation` is total over both and a decoded `false`
            /// that was silently looped would be the manifest and the screen
            /// disagreeing.
            public let loops: Bool

            /// Whether there is anything to play. One frame is a still prop and
            /// takes the ordinary path.
            public var isPlayable: Bool { frames.count > 1 && fps > 0 }
        }

        /// **Every path this role needs on disk**, `file` first.
        ///
        /// One place, because there are two of them now and `file` is a subset
        /// of the frames rather than a separate asset. Anything that walks the
        /// manifest asking "what art does this need" has to ask this rather
        /// than read `file` — the art survey read `file` and was silently
        /// blind to frames 1..N, which would have let
        /// `SPRITE_ROOM_REQUIRE_ART=1` pass with an animation half on disk.
        public var declaredPaths: [String] {
            var paths = [file]
            if let animation, !animation.frames.isEmpty {
                paths = animation.frames.contains(file) ? animation.frames : paths + animation.frames
            }
            // Stock is art this room draws, so a declared variant missing from
            // disk has to fail the art gate rather than vanish quietly at a
            // seat. Frame 0 is already here, hence the filter.
            return paths + variants.filter { !paths.contains($0) }
        }

        /// SpriteKit anchor (y-up, fractions of the canvas) that puts the
        /// content box's bottom-centre on the node's position.
        public func anchor(inCanvas canvas: Size) -> Anchor {
            guard canvas.width > 0, canvas.height > 0 else { return Anchor(x: 0.5, y: 0) }
            let bottomRow = contentBox.y + contentBox.height - 1
            return Anchor(
                x: (Double(contentBox.x) + Double(contentBox.width) / 2) / Double(canvas.width),
                y: Double(canvas.height - 1 - bottomRow) / Double(canvas.height))
        }
    }

    /// One piece of scenery: a prop plus the depth band it stands in.
    ///
    /// **The band is the only placement fact the manifest carries**, and that is
    /// deliberate. `docs/PLACEMENT-BANDS.md` is a measured negative result — the
    /// pixels do not say whether a sprite hangs on a wall or stands on a floor,
    /// `painting_framed`, `desk_wood` and `table_console` measure geometrically
    /// identical, and 62% of the catalogue cannot be classified at all. So the
    /// band is hand-authored per prop in `scripts/process-assets.py`, from the
    /// same knowledge `scripts/compose-scene.py`'s per-placement `kind` carries,
    /// and it is the *only* thing that crosses the manifest boundary. Which
    /// column and which y is scene geometry and stays in `RoomLayout`.
    public struct SceneryProp: Sendable, Hashable {
        public let band: RoomLayout.SceneryBand
        public let prop: PropRole
        public init(band: RoomLayout.SceneryBand, prop: PropRole) {
            self.band = band
            self.prop = prop
        }
    }

    /// A desk, a chair, and at most one adjacent floor-standing prop, at one
    /// seat. [ADR-002 §7]
    ///
    /// **The chair role is per *facing*, and this rule used to be global.**
    /// [ADR-008]
    ///
    /// It read "`chair` must be side view with the backrest on the left so a
    /// person on it faces right — the only direction the pack's sit rows were
    /// drawn for", and that was true while every seat in the room was side-on.
    /// A seat now declares which way its occupant faces, and the sentence splits
    /// in two:
    ///
    /// - **`chair`** — still the side view with the backrest on the left, still
    ///   for the sit rows, and still the *only* chair a side-on seat may take.
    /// - **`chair_back`** — the same office chair drawn from behind, for a seat
    ///   whose occupant faces away from the camera. A side chair under a
    ///   back-facing occupant is a chair pointing 90° away from the person in
    ///   it, so this is not a variant of the first, it is the other view of it.
    ///
    /// A seat facing the *camera* takes neither: the body covers the chair
    /// entirely, which is what the pack's own `Office_Design_2.gif` does at
    /// every camera-facing desk. `RoomLayout.SeatFacing.seatRole` is the mapping
    /// and it is the only place it is written down.
    ///
    /// **`desk` and `chair` are the theme's own unless the station overrides
    /// them.** Every station the shipped manifest declares overrides neither, so
    /// what a station changes is what stands *beside* the seat — which is the
    /// only channel the art we own can actually separate. The pack's desks all
    /// desaturate to the same pale slab, and it ships exactly two chairs worth
    /// binding: one side view and one back view, both of them the same chair.
    /// [ADR-002 §14c]
    ///
    /// `asserts` is the same flag `Costume` carries and it means the same thing:
    /// whether this station makes a claim about what kind of worker sits at it.
    /// A station reached from `roles` may; one the hash can reach may not. [I1]
    public struct Station: Sendable, Hashable {
        public let id: String
        /// What a person would call it. Prose, never compared.
        public let title: String
        /// What the art is, and why it was chosen. Prose.
        public let what: String
        /// Whether this station claims something about the agent at it.
        public let asserts: Bool
        public let desk: PropRole
        public let chair: PropRole
        /// Optional floor-standing item adjacent to the seat.
        public let prop: PropRole?

        public init(
            id: String = "", title: String = "", what: String = "",
            asserts: Bool = false, desk: PropRole, chair: PropRole, prop: PropRole? = nil
        ) {
            self.id = id
            self.title = title
            self.what = what
            self.asserts = asserts
            self.desk = desk
            self.chair = chair
            self.prop = prop
        }

        /// Every path this station needs on disk.
        public var declaredPaths: [String] {
            desk.declaredPaths + chair.declaredPaths + (prop?.declaredPaths ?? [])
        }
    }

    public struct Room: Sendable, Hashable {
        public let tile: Size
        public let builderTiles: [String]
        /// `builder.floor` — the tile the floor is drawn from, **declared**
        /// rather than searched for.
        ///
        /// The search is `TextureStore.roomTileChoice()`'s heuristic, and the
        /// art-director measured what it costs: of the Office room's 141 builder
        /// tiles it accepts exactly 2, because it takes only tiles that are
        /// fully opaque *and* a single flat colour. So a room drawn wide is two
        /// flat colour fields and the other 139 tiles are dead weight — which is
        /// most of why a wide room reads as empty floor. A floor that carries a
        /// pattern cannot pass that filter by construction, so no amount of art
        /// would have fixed it.
        ///
        /// `nil` for a manifest that predates the declaration, and the heuristic
        /// is then still the answer. [04-ART-DIRECTION, "Two facts about the
        /// room that this work uncovered"]
        public let declaredFloor: String?
        /// `builder.wall`. Deliberately an `authored` flat in every theme that
        /// declares one: every tile in `Room_Builder_Walls` carries vertical
        /// trim — measured, the left and right edge columns differ on 28–32 of
        /// 32 rows — so tiling one across a 25-tile room seams every 32 px. It
        /// is also the better answer under I7 regardless, since the wall is the
        /// largest continuous area on screen and sits directly behind every
        /// character.
        public let declaredWall: String?
        public let propCanvas: Size
        public let propFiles: [String]
        /// `false` while nothing among the singles has been identified. Until
        /// this is true nothing here can be called a desk, so the scene draws
        /// placeholder furniture instead of guessing. [I1]
        public let propsIdentified: Bool
        /// The singles that *have* been identified, keyed by role
        /// (`"desk"`, `"chair"`, …). Empty is a legal state and means the scene
        /// falls back to placeholders — the room still draws.
        ///
        /// **The role names are placement slots, not object nouns.** A theme
        /// fills `plant` with whatever plays the part of the repeated back-wall
        /// and walkway accent — a console terminal, a bookcase, a stage curtain.
        /// [04-ART-DIRECTION, "The five themes"]
        public let propRoles: [String: PropRole]
        /// **`props.scenery` — the room's dressing, in declaration order.**
        ///
        /// The four `propRoles` above are the slots the room's *arithmetic*
        /// needs: a surface and a seat at every seat, one standing object, one
        /// repeated accent. This is everything else — the printers, cabinets,
        /// bins, coolers and wall boards that make a floor read as a place. Each
        /// entry names the depth band it stands in and nothing else; where
        /// inside that band it lands is `RoomLayout.sceneryAnchors(_:)`'s to
        /// say, so the art is swappable without moving the room. [M8 Phase 2b]
        ///
        /// **It is furniture and it can never be anything else.** It is chosen
        /// by theme, decided at build time, identical for every agent, and
        /// nothing in the delta stream reaches it. [ADR-002 §6 rule 1, I1]
        public let scenery: [SceneryProp]
        /// §7's station bindings, keyed by station id (`"main"`, `"default"`,
        /// and the named ones). Declared once under `room` and inherited by
        /// every theme that does not declare its own. [§14c]
        public let stations: [String: Station]
        /// Tier 1: `agent_type` → station id, keyed on the **exact** string a
        /// session produced. A station reached this way is a translation of a
        /// name we were given, so it is allowed to assert. Entries naming a
        /// station the manifest does not declare are dropped at decode. [§14c]
        public let stationRoles: [String: String]
        /// Tier 2: the pool `rendezvous` draws from for an `agent_type` nobody
        /// anticipated. Sorted, because the pool must not depend on dictionary
        /// order — the tie-break in `rendezvous` is only half of that guarantee.
        ///
        /// **Nothing in it may assert.** Arbitrary user text licenses no claim
        /// about the work, so a hashed station may say only *this is a different
        /// agent from that one*. Enforced by
        /// `StationContractTests.noAssertingStationIsInThePoolTheHashDrawsFrom`.
        /// [I1]
        public let assignableStationIDs: [String]
        /// **`plan` — the authored floor plan this theme's room is drawn on.**
        /// [ADR-007]
        ///
        /// `RoomPlan.open` for a theme that declares none, which is five of the
        /// six and is not a degraded state: a plan needs a builder sheet with
        /// cap, body and several floor tiles in it, and only the Modern Office
        /// sheet has one. A reader that knows nothing about plans draws the open
        /// floor and is correct.
        public let plan: RoomPlan

        public init(
            tile: Size, builderTiles: [String], declaredFloor: String?, declaredWall: String?,
            propCanvas: Size, propFiles: [String], propsIdentified: Bool,
            propRoles: [String: PropRole], stations: [String: Station],
            stationRoles: [String: String] = [:], assignableStationIDs: [String]? = nil,
            scenery: [SceneryProp] = [], plan: RoomPlan = .open
        ) {
            self.plan = plan
            self.scenery = scenery
            self.tile = tile
            self.builderTiles = builderTiles
            self.declaredFloor = declaredFloor
            self.declaredWall = declaredWall
            self.propCanvas = propCanvas
            self.propFiles = propFiles
            self.propsIdentified = propsIdentified
            self.propRoles = propRoles
            self.stations = stations
            self.stationRoles = stationRoles
            // **The numeric convention is the fallback, not the rule.** §7
            // numbered the subagent stations and the pool was "the ids that are
            // digits"; §14c replaced that with a declared list, for the reason
            // costumes already had one — a pool the hash may reach has to be
            // stated, not inferred from a naming habit. A manifest or a test
            // fixture that predates the list still gets the old convention, so
            // the flat shape keeps working exactly as it did.
            self.assignableStationIDs = assignableStationIDs
                ?? stations.keys.filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }.sorted()
        }

        public func prop(_ role: String) -> PropRole? { propRoles[role] }

        /// The art one hand-placed piece draws, from whichever of the two pools
        /// it names. `nil` for a role this theme does not bind or an index past
        /// the end of the scenery list — the same silence an unreadable scenery
        /// entry gets, and `RoomPlan.dressingViolations` is what makes it loud.
        public func piece(_ piece: RoomPlan.Piece) -> PropRole? {
            switch piece {
            case let .role(name): return prop(name)
            case let .scenery(index):
                return scenery.indices.contains(index) ? scenery[index].prop : nil
            }
        }

        /// The scenery declared for one depth band, in declaration order.
        public func scenery(_ band: RoomLayout.SceneryBand) -> [PropRole] {
            scenery.filter { $0.band == band }.map(\.prop)
        }

        public func station(_ id: String) -> Station? { stations[id] }

        /// Sorted station ids. Dictionary order is not stable and neither a test
        /// nor a survey may depend on it.
        public var orderedStationIDs: [String] { stations.keys.sorted() }

        /// The old name for `assignableStationIDs`, kept because §7 and three
        /// tests spell it this way and it still means the same set.
        public var numberedStationIDs: [String] { assignableStationIDs }
    }

    /// One named set of role bindings. [ADR-002 §7, §14a]
    ///
    /// **The same shape as `room`**, which is why this wraps one rather than
    /// restating it: `room` is byte-for-byte the contract the scene already
    /// loads and it *is* the resolved default theme, so a reader learns one
    /// loader and not two. [§14a]
    public struct Theme: Sendable, Hashable {
        /// The manifest key. This, never the title, is what is stored and
        /// compared — a title is prose and may be reworded.
        public let id: String
        /// What the user reads in the menu.
        public let title: String
        /// Whether the **derived default** may draw this theme. Every theme is
        /// choosable; only some are assignable.
        ///
        /// A user who picks a jail has said something about their project; a
        /// hash that picks one has said it *for* them, which is the fiction I1
        /// exists to prevent. Defaults to `true` for a manifest that predates
        /// the flag. [§3e, §14a]
        public let isAssignable: Bool
        public let room: Room

        public var numberedStationIDs: [String] { room.numberedStationIDs }
        public var assignableStationIDs: [String] { room.assignableStationIDs }
        public var stationRoles: [String: String] { room.stationRoles }
        public var orderedStationIDs: [String] { room.orderedStationIDs }

        public func station(_ id: String) -> Station? { room.station(id) }

        /// A theme with nothing in it, for the `SceneDirector` initialiser that
        /// takes variant ids and no manifest. Its station pool is empty, so
        /// every typed subagent lands on `default` — which is what a director
        /// that was never told about a room should say.
        public static let unbound = Theme(
            id: "", title: "", isAssignable: false,
            room: Room(
                tile: Size(width: 0, height: 0), builderTiles: [],
                declaredFloor: nil, declaredWall: nil,
                propCanvas: Size(width: 0, height: 0), propFiles: [],
                propsIdentified: false, propRoles: [:], stations: [:]))
    }

    /// `themes.sets` and `themes.default`.
    ///
    /// **Top-level `themes`, not `room.themes`.** §7 specified the latter and
    /// the manifest shipped the former; §14a resolves it in the shipped shape's
    /// favour, because it leaves `room` untouched.
    public struct Themes: Sendable, Hashable {
        /// `themes.default`. `nil` when the manifest declares no themes at all,
        /// which is not a corner case: it is a checkout that has not run the
        /// import scripts.
        public let defaultID: String?
        public let sets: [String: Theme]
        /// Sorted by id. Dictionary order is not stable and neither a menu nor a
        /// hash pool may depend on it.
        public let orderedIDs: [String]

        public func theme(_ id: String) -> Theme? { sets[id] }

        public func contains(_ id: String) -> Bool { sets[id] != nil }

        public var isEmpty: Bool { sets.isEmpty }

        /// The pool the derived default draws from. [§3e]
        public var assignableIDs: [String] {
            orderedIDs.filter { sets[$0]?.isAssignable == true }
        }

        public static let none = Themes(defaultID: nil, sets: [:], orderedIDs: [])
    }

    // MARK: Stored

    public let schema: Int
    public let sizeSet: String
    public let render: Render
    public let credit: Credit
    public let characters: Characters
    public let badges: Badges
    public let room: Room
    public let themes: Themes
    /// Directory that manifest-relative paths resolve against — the repository
    /// root, since paths are recorded as `assets/processed/...`.
    public let root: URL

    public func url(_ manifestPath: String) -> URL {
        root.appending(path: manifestPath)
    }

    /// The room bindings for a theme id.
    ///
    /// **`nil` means `room`, exactly.** Not "the default theme's set" — those
    /// are the same pixels but not the same files, and `nil` is what every
    /// caller that has not selected a theme passes. So a scene built without a
    /// theme draws precisely what this app drew before themes existed, which is
    /// a property worth having mechanically rather than by inspection.
    ///
    /// An id the manifest does not have falls back the same way. A theme that
    /// was removed, or a manifest older than the stored choice, degrades to the
    /// room rather than to nothing. [§3d]
    public func room(theme id: String?) -> Room {
        guard let id, let theme = themes.theme(id) else { return room }
        return theme.room
    }

    /// The same resolution, as a `Theme` — what
    /// `ThemeSelector.station(agentID:agentType:in:)` takes.
    ///
    /// An unknown or absent id synthesises one around `manifest.room`, so the
    /// station rules are total for a scene that was never given a theme. It is
    /// not put in `themes.sets`: it has no id the user could store or pick.
    public func themeBindings(_ id: String?) -> Theme {
        if let id, let declared = themes.theme(id) { return declared }
        return Theme(id: "", title: "", isAssignable: false, room: room)
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
            let states = try Self.states(
                try Self.object(variantObject, "states"),
                frameRate: frameRate, context: "characters.variants.\(id)")
            variants[id] = CharacterVariant(
                id: id,
                headTopPx: (variantObject["head_top_px"] as? Int) ?? 0,
                accentHex: Self.colour(variantObject["accent_hex"] as? String),
                states: states)
        }
        guard !variants.isEmpty else { throw LoadError.malformed("characters.variants is empty") }
        var workingPoses: [String: String] = [:]
        for (badgeKey, raw) in
            ((charactersObject["poses"] as? [String: Any])?["working"] as? [String: Any]) ?? [:] {
            guard let stateName = raw as? String else { continue }
            workingPoses[badgeKey] = stateName
        }
        self.characters = Characters(
            canvas: charactersCanvas,
            anchor: charactersAnchor,
            frameRate: frameRate,
            variants: variants,
            orderedVariantIDs: variants.keys.sorted(),
            workingPoses: workingPoses,
            costumes: try Self.costumes(
                charactersObject["costumes"] as? [String: Any], frameRate: frameRate))

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
        let roomDecode = try Self.roomBindings(try Self.object(object, "room"), context: "room")
        self.room = roomDecode.room
        guard !self.room.builderTiles.isEmpty else {
            throw LoadError.malformed("room.builder.tiles is empty")
        }

        // Themes. `themes.sets.<id>` has the same shape as `room`, so it goes
        // through the same loader — that is the whole reason §14a chose the
        // shipped key path over §7's. [§14a]
        let themesObject = (object["themes"] as? [String: Any]) ?? [:]
        var sets: [String: Theme] = [:]
        for (id, raw) in (themesObject["sets"] as? [String: Any]) ?? [:] {
            guard let entry = raw as? [String: Any] else {
                throw LoadError.malformed("themes.sets.\(id) is not an object")
            }
            let bindings = try Self.roomBindings(
                entry, context: "themes.sets.\(id)", inheriting: roomDecode.declared).room
            guard !bindings.builderTiles.isEmpty else {
                throw LoadError.malformed("themes.sets.\(id).builder.tiles is empty")
            }
            sets[id] = Theme(
                id: id,
                // The id rather than a prettified one: a theme with no title is
                // still listable, and inventing prose for it here would put a
                // display string in `Sources/`.
                title: (entry["title"] as? String) ?? id,
                isAssignable: (entry["assignable"] as? Bool) ?? true,
                room: bindings)
        }
        // A default naming a set that is not there is not a default. Falling to
        // `nil` puts the room back to `manifest.room`, which is the same room.
        let declaredDefault = themesObject["default"] as? String
        self.themes = Themes(
            defaultID: declaredDefault.flatMap { sets[$0] != nil ? $0 : nil },
            sets: sets,
            orderedIDs: sets.keys.sorted())
    }

    /// Decodes a `states` map — the shape a character variant and a costume
    /// layer share, because the art is the same geometry drawn on two sheets.
    ///
    /// One decoder for both. Two decoders over one shape drift, and this one
    /// drifting would show up as a costume layer that plays at a different
    /// frame rate from the body it is drawn on.
    private static func states(
        _ statesObject: [String: Any], frameRate: Double, context: String
    ) throws -> [BodyState: StateAnimation] {
        var states: [BodyState: StateAnimation] = [:]
        for (stateName, rawState) in statesObject {
            guard let state = BodyState(rawValue: stateName) else { continue }
            guard let stateObject = rawState as? [String: Any],
                  let framesObject = stateObject["frames"] as? [String: Any] else {
                throw LoadError.malformed("\(context).states.\(stateName)")
            }
            var frames: [Facing: [String]] = [:]
            for (direction, rawPaths) in framesObject {
                guard let facing = Facing(rawValue: direction),
                      let paths = rawPaths as? [String], !paths.isEmpty else { continue }
                frames[facing] = paths
            }
            guard !frames.isEmpty else {
                throw LoadError.malformed("\(context).states.\(stateName) has no usable frames")
            }
            states[state] = StateAnimation(
                loops: (stateObject["loop"] as? Bool) ?? true,
                fps: Double((stateObject["fps"] as? Int) ?? Int(frameRate)),
                raisedFrame: stateObject["raised_frame"] as? Int,
                frames: frames)
        }
        return states
    }

    /// Decodes `characters.costumes`.
    ///
    /// **Absent is the shipped state and decodes to `.none`**, so a manifest
    /// that has never heard of costumes produces a wardrobe that dresses nobody
    /// and a room identical to the one before this key existed.
    ///
    /// Two entries are dropped rather than thrown on, and both droppings are the
    /// honest answer rather than leniency:
    ///
    /// - a `roles` entry naming a costume that is not in `sets` — a costume
    ///   removed from the art, or a hand-edited manifest. That `agent_type`
    ///   falls through to the pool, which is what it would have done had the
    ///   entry never been written.
    /// - an `assignable` id naming no costume. The pool is the hash's range and
    ///   an id with nothing behind it would be a character wearing nothing while
    ///   the code believed it was dressed.
    private static func costumes(
        _ object: [String: Any]?, frameRate: Double
    ) throws -> Costumes {
        guard let object else { return .none }
        var sets: [String: Costume] = [:]
        for (id, raw) in (object["sets"] as? [String: Any]) ?? [:] {
            guard let entry = raw as? [String: Any] else {
                throw LoadError.malformed("characters.costumes.sets.\(id) is not an object")
            }
            var layers: [Costume.Layer] = []
            for (index, rawLayer) in ((entry["layers"] as? [[String: Any]]) ?? []).enumerated() {
                let states = try Self.states(
                    (rawLayer["states"] as? [String: Any]) ?? [:],
                    frameRate: frameRate,
                    context: "characters.costumes.sets.\(id).layers[\(index)]")
                guard !states.isEmpty else {
                    throw LoadError.malformed(
                        "characters.costumes.sets.\(id).layers[\(index)] draws no state")
                }
                layers.append(Costume.Layer(states: states))
            }
            guard !layers.isEmpty else {
                throw LoadError.malformed("characters.costumes.sets.\(id) has no layers")
            }
            sets[id] = Costume(
                id: id,
                title: (entry["title"] as? String) ?? id,
                asserts: (entry["asserts"] as? Bool) ?? false,
                layers: layers)
        }
        var roles: [String: String] = [:]
        for (agentType, raw) in (object["roles"] as? [String: Any]) ?? [:] {
            guard let costumeID = raw as? String, sets[costumeID] != nil else { continue }
            roles[agentType] = costumeID
        }
        let assignable = ((object["assignable"] as? [String]) ?? [])
            .filter { sets[$0] != nil }
            .sorted()
        return Costumes(
            sets: sets, orderedIDs: sets.keys.sorted(),
            roles: roles, assignableIDs: assignable,
            inkTopAboveFeet: max(0, (object["ink_top_px"] as? Int) ?? 0))
    }

    /// Decodes one `room`-shaped object: tile, builder, props, stations.
    ///
    /// One function for `room` and for every `themes.sets.<id>`, because they
    /// are one shape. Two decoders over one shape drift.
    private static func roomBindings(
        _ roomObject: [String: Any], context: String, inheriting inherited: StationSpecs? = nil
    ) throws -> (room: Room, declared: StationSpecs) {
        let builder = try Self.object(roomObject, "builder")
        let props = (roomObject["props"] as? [String: Any]) ?? [:]
        let propCanvasObject = (props["canvas"] as? [String: Any]) ?? [:]
        var propRoles: [String: PropRole] = [:]
        for (role, raw) in (props["roles"] as? [String: Any]) ?? [:] {
            guard let box = Self.propRole(raw) else {
                throw LoadError.malformed("\(context).props.roles.\(role)")
            }
            propRoles[role] = box
        }
        // **A scenery entry the room cannot place draws nothing and the rest
        // still draw.** An unknown band, or art whose box will not decode, is a
        // manifest ahead of this build — the vocabulary is closed and its
        // unmatched case is silence, which is the same answer the identity model
        // gives an ambiguous attribution. It is *not* a throw: a room that
        // refuses to load because one printer moved is worse than a room with
        // one fewer printer. [I1]
        var scenery: [SceneryProp] = []
        for raw in (props["scenery"] as? [[String: Any]]) ?? [] {
            guard let name = raw["band"] as? String,
                  let band = RoomLayout.SceneryBand(rawValue: name),
                  let prop = Self.propRole(raw) else { continue }
            scenery.append(SceneryProp(band: band, prop: prop))
        }
        let declared = try Self.stationSpecs(props["stations"], context: context)
        // **Inheritance is all-or-nothing, per theme.** A theme either states
        // its own stations or takes the room's whole block — sets, roles and
        // pool together. Merging the two would let a theme silently keep a role
        // entry pointing at a station it had just replaced. [§14c]
        let effective = declared.isEmpty ? (inherited ?? declared) : declared
        let stations = effective.materialised(with: propRoles)
        return (
            Room(
                tile: try Self.size(roomObject, "tile", in: context),
                builderTiles: (builder["tiles"] as? [String]) ?? [],
                declaredFloor: builder["floor"] as? String,
                declaredWall: builder["wall"] as? String,
                propCanvas: Size(
                    width: (propCanvasObject["w"] as? Int) ?? 64,
                    height: (propCanvasObject["h"] as? Int) ?? 96),
                propFiles: (props["files"] as? [String]) ?? [],
                propsIdentified: (props["identified"] as? Bool) ?? false,
                propRoles: propRoles,
                stations: stations,
                stationRoles: effective.roles.filter { stations[$0.value] != nil },
                assignableStationIDs: effective.declaredAssignable
                    .map { $0.filter { stations[$0] != nil }.sorted() },
                scenery: scenery,
                plan: Self.plan(roomObject["plan"])),
            declared)
    }

    /// Decodes `plan`, or `RoomPlan.open` for anything it cannot read.
    ///
    /// **Never a throw, for the reason the scenery decoder never throws**: a
    /// room that refuses to load because one wall moved is worse than a room
    /// drawn on the open floor the app has always drawn. A space whose surface
    /// is not declared, or whose rect is degenerate, is dropped and the rest
    /// still draw — and `RoomPlanContractTests` is what turns that silence into
    /// a red test rather than a quietly emptier room. [I1]
    private static func plan(_ raw: Any?) -> RoomPlan {
        guard let object = raw as? [String: Any] else { return .open }
        var surfaces: [String: RoomPlan.Surface] = [:]
        for (id, entry) in (object["surfaces"] as? [String: Any]) ?? [:] {
            guard let entry = entry as? [String: Any],
                  let floor = entry["floor"] as? String,
                  let cap = entry["cap"] as? String,
                  let body = entry["body"] as? String,
                  let edge = Self.rgb(entry["line_edge"]),
                  let fill = Self.rgb(entry["line_fill"]) else { continue }
            surfaces[id] = RoomPlan.Surface(
                id: id, floor: floor, cap: cap, body: body, lineEdge: edge, lineFill: fill)
        }
        var spaces: [RoomPlan.Space] = []
        for entry in (object["spaces"] as? [[String: Any]]) ?? [] {
            guard let surface = entry["surface"] as? String, surfaces[surface] != nil,
                  let x = entry["x"] as? Int, let y = entry["y"] as? Int,
                  let w = entry["w"] as? Int, let h = entry["h"] as? Int,
                  w > 0, h > 0 else { continue }
            spaces.append(RoomPlan.Space(
                name: (entry["name"] as? String) ?? surface,
                surface: surface, x: x, y: y, w: w, h: h,
                doorways: (entry["doorways"] as? [Int]) ?? [],
                hasBand: (entry["band"] as? Bool) ?? true))
        }
        var partitions: [RoomPlan.Partition] = []
        for entry in (object["partitions"] as? [[String: Any]]) ?? [] {
            guard let x = entry["x"] as? Int, let y = entry["y"] as? Int,
                  let h = entry["h"] as? Int, h > 0 else { continue }
            partitions.append(RoomPlan.Partition(x: x, y: y, h: h))
        }
        // **A placement the room cannot read draws nothing and the rest still
        // draw**, exactly as an unreadable scenery entry does. `what` is
        // optional and advisory: it is echoed into `RoomPlan.Dressing` so that
        // `dressingViolations` can report a scenery list that moved under a
        // placement, and it is never drawn.
        var dressing: [RoomPlan.Dressing] = []
        for entry in (object["dressing"] as? [[String: Any]]) ?? [] {
            guard let x = entry["x"] as? Int, let y = entry["y"] as? Int else { continue }
            let piece: RoomPlan.Piece
            if let role = entry["role"] as? String, !role.isEmpty {
                piece = .role(role)
            } else if let index = entry["scenery"] as? Int, index >= 0 {
                piece = .scenery(index)
            } else {
                continue
            }
            dressing.append(RoomPlan.Dressing(
                piece: piece, x: x, y: y, what: (entry["what"] as? String) ?? ""))
        }
        guard !spaces.isEmpty else { return .open }
        return RoomPlan(
            spaces: spaces, surfaces: surfaces, partitions: partitions, dressing: dressing)
    }

    private static func rgb(_ raw: Any?) -> Bitmap.RGBA? {
        guard let values = raw as? [Int], values.count >= 3,
              values.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return Bitmap.RGBA(UInt8(values[0]), UInt8(values[1]), UInt8(values[2]))
    }

    /// `props.stations` as written, before a theme's own desk and chair have
    /// been folded in. [ADR-002 §14c]
    ///
    /// It exists because the block is declared once and used six times: the
    /// prop is the same object in every theme, and the desk and chair under it
    /// are whatever that theme puts at a seat. Materialising per theme is what
    /// keeps a station from dragging the Office desk into the library.
    private struct StationSpecs {
        struct Spec {
            let title: String
            let what: String
            let asserts: Bool
            let desk: PropRole?
            let chair: PropRole?
            let prop: PropRole?
        }

        var specs: [String: Spec] = [:]
        var roles: [String: String] = [:]
        /// `nil` when the manifest declared no `assignable` list, which is the
        /// cue for `Room.init` to fall back to the numeric-id convention.
        var declaredAssignable: [String]?

        var isEmpty: Bool { specs.isEmpty }

        /// A station whose desk or chair resolves to nothing is **dropped, not
        /// faked**: the seat then keeps the theme-wide pair, which is the
        /// picture the room drew before stations existed. [I1]
        func materialised(with propRoles: [String: PropRole]) -> [String: Station] {
            var out: [String: Station] = [:]
            for (id, spec) in specs {
                guard let desk = spec.desk ?? propRoles[surfaceRoleKey],
                      let chair = spec.chair ?? propRoles[seatRoleKey] else { continue }
                out[id] = Station(
                    id: id, title: spec.title, what: spec.what, asserts: spec.asserts,
                    desk: desk, chair: chair, prop: spec.prop)
            }
            return out
        }
    }

    /// The two `props.roles` keys a station falls back to. Spelled here rather
    /// than imported from `RoomScene`, because they are manifest keys and the
    /// manifest decoder may not depend on the scene.
    private static let surfaceRoleKey = "desk"
    private static let seatRoleKey = "chair"

    /// Decodes `props.stations` in either shape.
    ///
    /// The tiered shape — `{sets, roles, assignable}` — is what ships, and it is
    /// `characters.costumes`' shape for the reason §14c gives. The flat shape —
    /// a bare map of id → station — is what §7 originally specified and what
    /// hand-built fixtures still write; it carries no tiers, so its pool is the
    /// numeric-id convention and its `roles` table is empty.
    private static func stationSpecs(
        _ raw: Any?, context: String
    ) throws -> StationSpecs {
        guard let object = raw as? [String: Any] else { return StationSpecs() }
        let tiered = object["sets"] as? [String: Any]
        var out = StationSpecs()
        for (id, entry) in tiered ?? object {
            guard let entry = entry as? [String: Any] else {
                throw LoadError.malformed("\(context).props.stations.\(id) is not an object")
            }
            let desk = Self.propRole(entry["desk"])
            let chair = Self.propRole(entry["chair"])
            // The flat shape has no fallback to inherit from, so it must carry
            // both. Throwing here is what caught a malformed fixture before
            // stations shipped and it keeps catching one.
            if tiered == nil, desk == nil || chair == nil {
                throw LoadError.malformed("\(context).props.stations.\(id)")
            }
            out.specs[id] = StationSpecs.Spec(
                title: (entry["title"] as? String) ?? id,
                what: (entry["what"] as? String) ?? "",
                asserts: (entry["asserts"] as? Bool) ?? false,
                desk: desk, chair: chair, prop: Self.propRole(entry["prop"]))
        }
        for (agentType, value) in (object["roles"] as? [String: Any]) ?? [:] {
            guard let stationID = value as? String, out.specs[stationID] != nil else { continue }
            out.roles[agentType] = stationID
        }
        if let assignable = object["assignable"] as? [String] {
            out.declaredAssignable = assignable.filter { out.specs[$0] != nil }.sorted()
        }
        return out
    }

    /// A `{file, content_box}` entry. `nil` for anything that is not one —
    /// including absence, which is how an optional station prop reads.
    private static func propRole(_ raw: Any?) -> PropRole? {
        guard let entry = raw as? [String: Any],
              let file = entry["file"] as? String,
              let box = entry["content_box"] as? [String: Any],
              let x = box["x"] as? Int, let y = box["y"] as? Int,
              let w = box["w"] as? Int, let h = box["h"] as? Int,
              w > 0, h > 0 else { return nil }
        return PropRole(
            file: file,
            contentBox: PropRole.Box(x: x, y: y, width: w, height: h),
            animation: propAnimation(entry["animation"]),
            // Absent in an older manifest and absent on every role but `desk`.
            // Not defaulted to the box height here: the fallback is a *drawing*
            // decision and belongs where the drawing happens, so that a reader
            // of this type can still tell "measured 24" from "nobody measured".
            surfaceY: entry["surface_y"] as? Int,
            // **Never throws, and never for anything.** A list of anything but
            // strings, a list that does not lead with `file`, an empty list, the
            // key absent — every one of them decodes to `[file]`, which is the
            // picture the room drew before the key existed. Losing a seat's
            // stock is a smaller failure than losing the room, and it is the
            // same call `propAnimation` makes for a malformed `animation`. The
            // `file`-first invariant itself is enforced in `PropRole.init`.
            variants: entry["variants"] as? [String])
    }

    /// A `{frames, fps, loop}` entry. `nil` for anything that is not one,
    /// including absence — a role with no `animation` key is a still prop, which
    /// is every role but one.
    ///
    /// A malformed `animation` degrades to `nil` rather than throwing: `file` is
    /// frame 0 and is decoded independently, so the prop still draws. Losing the
    /// swing is a smaller failure than losing the clock.
    private static func propAnimation(_ raw: Any?) -> PropRole.Animation? {
        guard let entry = raw as? [String: Any],
              let frames = entry["frames"] as? [String], !frames.isEmpty else { return nil }
        let fps: Double
        if let value = entry["fps"] as? Double { fps = value }
        else if let value = entry["fps"] as? Int { fps = Double(value) }
        else { return nil }
        return PropRole.Animation(
            frames: frames, fps: fps, loops: (entry["loop"] as? Bool) ?? true)
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

    /// `"#RRGGBB"` → colour. Anything else is `nil` rather than a guessed
    /// value: a mis-parsed accent would silently reinstate the weak channel the
    /// assigned hues exist to replace.
    static func colour(_ text: String?) -> Bitmap.RGBA? {
        guard var hex = text?.trimmingCharacters(in: .whitespaces) else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Bitmap.RGBA(
            UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
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
