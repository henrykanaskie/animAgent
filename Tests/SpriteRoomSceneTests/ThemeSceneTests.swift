import Foundation
import SpriteKit
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// `docs/ADR-002-themed-rooms.md` §8 items 5–7, and the volatility rules §6
/// states them to protect.
///
/// Mixed suite, like `RoomSceneTests`: the rules about *what the director
/// decides* derive from the tracked manifest and run on any checkout; the rules
/// about *what is on screen* need pixels and carry the art gate.
@MainActor
struct ThemeSceneTests {

    /// The main agent plus `count - 1` subagents, in seat order.
    static func cast(_ count: Int) -> [AgentRef] {
        (0..<count).map { index in
            AgentRef(
                project: "/p", session: "s",
                agent: index == 0 ? .mainThread : .subagent(String(format: "a%016x", index)))
        }
    }

    // MARK: §8 item 6 — the station is stored, and never rewritten

    /// The station lands in the presentation record beside `variant`, `seat` and
    /// the nameplate, and it is decided from `agent_id` and `agent_type` alone.
    @Test func theDirectorStoresAStationForEveryCharacter() throws {
        let manifest = try SceneFixtures.manifest()
        var director = SceneDirector(manifest: manifest)
        let cast = Self.cast(3)

        _ = director.apply([
            .agentAppeared(agent: cast[0], agentType: nil, lifecycle: .active),
            .agentAppeared(agent: cast[1], agentType: "Explore", lifecycle: .spawning),
            .agentAppeared(agent: cast[2], agentType: "", lifecycle: .spawning),
        ])

        #expect(director.station(cast[0]) == ThemeSelector.mainStationID)
        #expect(director.station(cast[2]) == ThemeSelector.defaultStationID)
        #expect(director.station(cast[1]) != nil)
    }

    /// **§6 rule 2, mechanically.** `agentAppeared` can arrive again for a
    /// character already on screen, carrying an `agent_type` we did not have the
    /// first time — and it updates the nameplate's copy of it. The station must
    /// not follow, because rewriting a character's furniture under the user's
    /// eye changes its identity at exactly the moment the room got busy and they
    /// are looking at it.
    ///
    /// The check is worth having even while every subagent lands on `default`:
    /// this is the assertion that stays true when the numbered stations arrive,
    /// and it would be the one nobody thought to add then.
    @Test func theStationIsNeverRewrittenAfterSpawn() throws {
        let manifest = try SceneFixtures.manifest()
        var director = SceneDirector(manifest: manifest)
        let theme = ThemeFixtures.stationed(count: 6)
        var stationed = SceneDirector(
            layout: RoomLayout(), variantIDs: manifest.characters.orderedVariantIDs,
            theme: theme)
        let agent = Self.cast(2)[1]

        for candidate in [director, stationed].indices {
            var subject = candidate == 0 ? director : stationed
            _ = subject.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .spawning)])
            let atSpawn = subject.station(agent)
            #expect(atSpawn == ThemeSelector.defaultStationID)

            // Every later shape of the same fact, including the one that really
            // happens: a type arriving after the character is on screen.
            _ = subject.apply([
                .agentAppeared(agent: agent, agentType: "security-reviewer", lifecycle: .active),
            ])
            _ = subject.apply([
                .agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active),
                .callOpened(agent: agent, call: OpenCall(
                    toolUseID: ToolUseID("t1"), toolName: "Read", startedAt: Date(),
                    deadline: Date().addingTimeInterval(60))),
            ])
            #expect(subject.station(agent) == atSpawn,
                    "the station moved when `agent_type` arrived")
            if candidate == 0 { director = subject } else { stationed = subject }
        }
    }

    /// A typed subagent in a theme that *does* declare numbered stations lands
    /// on one, and two agents of the same type land on the same one. The shipped
    /// manifest declares none, so this drives the fixture theme — see
    /// `ThemeFixtures.stationed`.
    @Test func typedSubagentsOfOneKindShareAStation() throws {
        let manifest = try SceneFixtures.manifest()
        var director = SceneDirector(
            layout: RoomLayout(), variantIDs: manifest.characters.orderedVariantIDs,
            theme: ThemeFixtures.stationed(count: 6))
        let cast = Self.cast(4)

        _ = director.apply([
            .agentAppeared(agent: cast[1], agentType: "general-purpose", lifecycle: .spawning),
            .agentAppeared(agent: cast[2], agentType: "general-purpose", lifecycle: .spawning),
            .agentAppeared(agent: cast[3], agentType: "Explore", lifecycle: .spawning),
        ])
        #expect(director.station(cast[1]) == director.station(cast[2]))
        #expect(director.station(cast[1]) != ThemeSelector.defaultStationID)
        #expect(director.station(cast[1]) != ThemeSelector.mainStationID)
    }

    // MARK: §8 item 7 / §6 rule 5 — pose changes ≤ badge changes

    /// **The same assertion the badge has, on the body.** [§6 rule 5, §12 item 4]
    ///
    /// M4 established the badge-change count must equal the open-call-change
    /// count and caught a real spurious change with it. The pose gets the
    /// identical shape of assertion, and it gets it **at real time** — a fixed
    /// 1/60 step rather than a step per batch — because compressing the event
    /// stream against a slower clock manufactures coincidences a real replay
    /// could not produce.
    ///
    /// The bound holds *structurally*, and that is the point of writing it here:
    /// the pose is a pure function of the badge class, read at the instant the
    /// director already computes the badge, so it cannot change more often than
    /// its input does.
    ///
    /// **ADR-003 put a dwell in the badge slot and §6 rule 3 still holds**, for
    /// the reason it was written rather than by luck. Rule 3 refused a dwell
    /// that makes the *body* assert a tool class the badge above it says has
    /// ended; ADR-003's beat only ever runs while the open set is empty, so the
    /// body is `idle` for every frame of it and the pose lookup — which
    /// `SceneDirector.body(for:badge:)` reaches only from `working` — is not
    /// entered at all. A lingering `magnifier` cannot move the pose because the
    /// pose follows the body, not the badge. [ADR-003 §2]
    ///
    /// Idle is not a pose. A character leaving its seat has not changed which
    /// seated pose it uses, so `.idle` does not count and does not reset the
    /// memory — otherwise this would measure the open-call set twice and forbid
    /// the one thing §6 rule 5 permits.
    @Test func poseChangesNeverOutnumberBadgeChangesAtRealTime() async throws {
        let manifest = try SceneFixtures.manifest()
        var director = SceneDirector(manifest: manifest)

        var poseChanges: [AgentRef: Int] = [:]
        var badgeChanges: [AgentRef: Int] = [:]
        var lastPose: [AgentRef: BodyState] = [:]
        var frames = 0

        let entries = try HookLog.load(contentsOf: SceneFixtures.url("three-subagents"))
        let origin = try #require(entries.first?.receivedAt)
        let end = try #require(entries.last?.receivedAt)
        let model = WorldModel()
        var index = entries.startIndex
        var time = 0.0
        let step = 1.0 / 60.0

        while time <= end.timeIntervalSince(origin) + 10 {
            var pending: [WorldDelta] = []
            let cutoff = origin.addingTimeInterval(time)
            while index < entries.endIndex, entries[index].receivedAt <= cutoff {
                if let event = entries[index].event {
                    pending += await model.ingest(event, at: entries[index].receivedAt)
                }
                index += 1
            }
            // Unguarded since ADR-003: the director is a function of deltas and
            // time, and the frames a beat ends on are the ones carrying nothing.
            for intent in director.apply(pending, at: cutoff) {
                switch intent {
                case let .setBody(agent, state, _):
                    guard state != .idle else { continue }
                    if lastPose[agent] != state {
                        lastPose[agent] = state
                        poseChanges[agent, default: 0] += 1
                    }
                case let .setBadge(agent, _):
                    badgeChanges[agent, default: 0] += 1
                default:
                    break
                }
            }
            frames += 1
            time += step
        }

        #expect(frames > 2000, "the whole fixture was not stepped at 1/60")
        #expect(!badgeChanges.isEmpty, "nothing happened in the replay")
        for (agent, poses) in poseChanges {
            let badges = badgeChanges[agent] ?? 0
            #expect(poses <= badges,
                    "\(agent) changed pose \(poses) times against \(badges) badge changes")
        }
    }

    /// The table is empty in the shipped manifest, so every badge class resolves
    /// to the one seated pose the pack ships. **That is the correct answer, not a
    /// missing feature** — §5b item 2 says in as many words that a single usable
    /// sit row makes this half inert with no code path to delete.
    ///
    /// What is asserted is that the *lookup* is live: it is total over every
    /// badge class, and it reads the manifest rather than returning a constant
    /// the compiler folded away.
    @Test func theWorkingPoseIsLookedUpForEveryBadgeClass() throws {
        let manifest = try SceneFixtures.manifest()
        for badge in ToolBadge.allCases {
            #expect(manifest.characters.workingPose(forBadgeKey: badge.manifestKey) == .working)
        }
        #expect(manifest.characters.workingPose(forBadgeKey: nil) == .working)

        // A manifest that *does* carry a table is read. The pose is keyed on the
        // badge class and falls to `default` for a class the table omits, which
        // is what makes a tool name nobody has heard of need no new art.
        var director = SceneDirector(
            layout: RoomLayout(), variantIDs: ["06"],
            workingPoses: ["terminal": BodyState.idle.rawValue,
                           Manifest.Characters.defaultPoseKey: BodyState.deliver.rawValue])
        let agent = Self.cast(1)[0]
        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])
        _ = director.apply([.callOpened(agent: agent, call: OpenCall(
            toolUseID: ToolUseID("t1"), toolName: "Bash", startedAt: Date(),
            deadline: Date().addingTimeInterval(60)))])
        #expect(director.bodyState(agent) == .idle, "the terminal entry was not read")

        _ = director.apply([.callOpened(agent: agent, call: OpenCall(
            toolUseID: ToolUseID("t2"), toolName: "Read", startedAt: Date(),
            deadline: Date().addingTimeInterval(60)))])
        // `magnifier` outranks `terminal` and the table does not name it, so the
        // required `default` answers.
        #expect(director.bodyState(agent) == .deliver, "the default entry was not read")
    }

    // MARK: §6 rule 1 — the room does not change with activity, at all

    /// **Zero prop-node rebuilds across every fixture replay.** [§8 tests, last
    /// bullet but one]
    ///
    /// The strongest form of §6 rule 1, and mechanical rather than argued: no
    /// fixture contains a project switch or a user pick, so nothing in any of
    /// them may touch the room. Node *identity* is compared rather than a count,
    /// because a rebuild that replaced every prop with an identical one would
    /// pass a count and still be the thing this forbids.
    @Test(.enabled(if: SceneArt.isAvailable))
    func noPropNodeIsEverRebuiltAcrossAnyFixtureReplay() async throws {
        let manifest = try SceneFixtures.manifest()
        let fixtures = try FileManager.default
            .contentsOfDirectory(atPath: SceneFixtures.repositoryRoot.appending(path: "fixtures").path)
            .filter { $0.hasSuffix(".jsonl") }
            .map { String($0.dropLast(6)) }
            .sorted()
        #expect(fixtures.count > 10, "the fixture sweep found almost nothing")

        for name in fixtures {
            let scene = RoomScene(manifest: manifest)
            scene.setViewport(CGSize(width: 720, height: 400))
            var director = SceneDirector(manifest: manifest)
            let before = Set(scene.propNodesForTesting.map(ObjectIdentifier.init))
            #expect(!before.isEmpty, "\(name): the room drew no props to begin with")

            var time = 0.0
            for batch in try await SceneFixtures.batchedDeltas(name) {
                scene.apply(director.apply(batch))
                time += 1.0 / 60.0
                scene.advance(to: time)
            }

            let after = Set(scene.propNodesForTesting.map(ObjectIdentifier.init))
            #expect(after == before, "\(name): the prop nodes were rebuilt")
            #expect(scene.roomBuildCount == 1, "\(name): the room was built more than once")
        }
    }

    // MARK: §8 item 5 — the theme dresses the room and nothing else

    /// **A theme change rebuilds the prop nodes; it does not touch characters'
    /// seats, plates, variants or badges.** [§8 item 5]
    ///
    /// Two scenes rather than one mutated in place, because that is how a theme
    /// actually changes: §6 rule 4 says a theme change is a rebuild, not a
    /// transition — no cross-fade, no prop animating in, the room is simply the
    /// other room. What has to hold is that the same deltas put the same
    /// characters in the same places in both.
    ///
    /// **"Redresses" is asserted, not assumed.** This test used to check only
    /// that the characters were identical and that the *count* of props matched
    /// — which a `RoomScene` that ignored `themeID` altogether would pass, since
    /// it would draw the same room every time. The count check is right and
    /// stays. What was missing is the other half: the props' *art* must differ,
    /// or the theme did nothing. Both halves are needed, and neither implies the
    /// other.
    ///
    /// ## Amended at M8: the positions no longer have to match across *every*
    /// theme, and that is ADR-007's whole cost stated as a test
    ///
    /// It used to assert `other.props == first.props` over all six themes, on
    /// ADR-002 §2c's grounds that room geometry is theme-independent and changes
    /// **never**. ADR-007 overturns that row for the four **scenery** bands and
    /// for them only: a theme with a floor plan has a wall you can see the face
    /// of, a strip of floor behind it and doorways cut through it, and a band
    /// that stood where it stood on an open floor would hang its pictures on
    /// nothing and put a vending machine through a wall.
    ///
    /// So the assertion is split, and the split is the point:
    ///
    /// - **The route geometry is still theme-independent, and now that is
    ///   checked directly rather than as a side effect.** Every seat's chair and
    ///   desk stands on exactly the same point in all six themes. That is the
    ///   half of "geometry" that `RoomLayout`'s clearance arguments rest on, it
    ///   is the half a plan may never touch, and the old blanket comparison
    ///   never named it.
    /// - **The dressing has to match only among themes that share a plan**,
    ///   which is five of the six against each other and `office` against
    ///   itself. A theme whose plan differs is *required* to place differently;
    ///   asserting otherwise would be asserting the bug.
    ///
    /// ## Amended again: the *count* is per mechanism now, and there are two
    ///
    /// The split above left one blanket line standing — every theme drew the
    /// same *number* of props, whatever plan it was on — and that survived
    /// ADR-007 because a plan moved the bands without changing how many of them
    /// there were. A plan may now place its dressing **by hand**, and then the
    /// four scenery bands and the board/plant lattice do not run at all: the
    /// count is the plan's own placement count, not 20 anchors and 7 columns.
    ///
    /// So the count is asserted **per theme against its own mechanism's
    /// number** — both numbers derived, neither typed — and the cross-theme
    /// comparison survives narrowed to the themes that share a mechanism, with
    /// the other case asserted as an inequality. Two themes on two mechanisms
    /// drawing the same number of props means the hand placement reached
    /// nothing, which is the failure this line is for.
    ///
    /// One consequence worth naming rather than leaving to be discovered: the
    /// slot-by-slot art comparison at the end of the loop is only *slot*-wise
    /// meaningful between two themes that dress by the same mechanism, since
    /// `zip` pairs a hand-placed room's nth placement with a banded room's nth
    /// anchor and truncates to the shorter. Across mechanisms it degrades to
    /// "these two rooms share no picture in the first 27 slots", which is still
    /// true and still worth failing on, and the whole-list inequality above it
    /// is the assertion doing the real work.
    @Test(.enabled(if: SceneArt.isAvailable))
    func changingTheThemeRedressesTheRoomAndMovesNoCharacter() throws {
        let manifest = try SceneFixtures.manifest()
        let ids = manifest.themes.orderedIDs
        #expect(ids.count > 1, "there is only one theme, so this compares nothing")

        let deltas: [WorldDelta] = [
            .agentAppeared(agent: Self.cast(3)[0], agentType: nil, lifecycle: .active),
            .agentAppeared(agent: Self.cast(3)[1], agentType: "Explore", lifecycle: .spawning),
            .agentAppeared(agent: Self.cast(3)[2], agentType: "general-purpose",
                           lifecycle: .spawning),
            .callOpened(agent: Self.cast(3)[1], call: OpenCall(
                toolUseID: ToolUseID("t1"), toolName: "Bash", startedAt: Date(),
                deadline: Date().addingTimeInterval(60))),
        ]

        func render(_ themeID: String)
        -> (props: [String], art: [String], characters: [String],
            seats: [String], plan: RoomPlan) {
            let scene = RoomScene(manifest: manifest, themeID: themeID)
            scene.setViewport(CGSize(width: 720, height: 400))
            var director = SceneDirector(manifest: manifest, themeID: themeID)
            scene.apply(director.apply(deltas))
            // **Seat furniture is compared separately and by column.** [ADR-008]
            // A camera-facing desk's *depth* is derived from that theme's own
            // desk ink so the cut lands on one row of the body in every theme,
            // so its y differs by theme by construction and comparing it here
            // would be asserting the bug. Its x is theme-independent and is
            // asserted in `seats` below; the cut is asserted outright.
            let seatNodes = Set(scene.seatFurnitureNodesForTesting.map(ObjectIdentifier.init))
            let kept = zip(scene.propNodesForTesting, scene.propArtForTesting)
                .filter { !seatNodes.contains(ObjectIdentifier($0.0)) }
            let props = kept.map { "\(Int($0.0.position.x)),\(Int($0.0.position.y))" }
            let art = kept.map(\.1)
            let characters = Self.cast(3).compactMap { agent -> String? in
                guard let character = scene.character(for: agent) else { return nil }
                return [
                    "\(agent)", character.agentVariant,
                    "\(Int(character.position.x)),\(Int(character.position.y))",
                    "\(character.badgeSelection.badge?.rawValue ?? "-")",
                    "\(Int(character.nameplateRect.width))",
                    "\(director.seats[agent] ?? -1)",
                ].joined(separator: "|")
            }
            // The seat furniture's **column**, which is what "the layout is
            // theme-independent" actually means: a chair and a desk on every
            // seat's own point in x, in every theme.
            //
            // **The depth is deliberately not compared, and ADR-008 is why.** A
            // camera-facing desk stands `deskInkHeight − 1 − deskCutAboveFeet`
            // downstage of its occupant, so that its top edge lands on the same
            // row of the *body* whatever the theme's desk happens to be — 11 px
            // for the four 24 px desks, 23 for `mission_control`'s 36 and 31 for
            // `library`'s 44. A constant there fails every theme in one
            // direction or the other [docs/M8-MEASUREMENTS-phase1c.md §2]. The
            // theme-independent fact is the *cut*, and it is asserted below as
            // itself rather than through a y that cannot be equal.
            //
            // **And the desk's x is no longer theme-independent either**, for
            // exactly the reason its y is not. [ADR-009] An away-facing desk
            // stands beside its occupant while it is too narrow to be centred on
            // and centres once it is wide enough to carry a kit slot either side
            // — `RoomLayout.awayDeskOffsetX(metrics:)`, which is ADR-008 §7's own
            // condition as arithmetic. `office` is 64 px and centres; the other
            // five are 32 or 40 and do not. So a desk is compared against **the
            // layout's own answer for its own theme** below, and what is compared
            // across themes is the furniture whose point is genuinely the seat's:
            // the chair, and the station prop beside it.
            // **A piece is named by the role it came from, not by its file.** A
            // role may be drawn with any of its `variants` — the office pod's
            // desktop stock is four objects and its rig four rigs — so the
            // basename of what was drawn is `desk_kit_2`, and classifying on that
            // would put a stocked role in the theme-independent bucket below and
            // compare a picture across themes that do not have it.
            let room = manifest.room(theme: themeID)
            let roleOfFile: [String: String] = [
                RoomScene.surfaceRole, RoomScene.monitorRole, RoomScene.deskKitRole,
            ].reduce(into: [:]) { out, role in
                for file in room.prop(role)?.variants ?? [] { out[file] = role }
            }
            let byRole = (0..<scene.layout.seatCapacity).flatMap { seat in
                scene.furnitureForTesting(seat: seat).map {
                    (seat: seat,
                     role: roleOfFile[$0.path]
                        ?? URL(fileURLWithPath: $0.path).deletingPathExtension()
                            .lastPathComponent,
                     x: Int($0.x))
                }
            }
            let seatRoles: Set<String> = ["desk", "monitor", "desk_kit"]
            let seats = byRole
                .filter { !seatRoles.contains($0.role) }
                .map { "\($0.seat):\($0.x)" }.sorted()
            // Every piece whose position is a function of this theme's own desk
            // art, against the layout that placed it. Stronger than the blanket
            // comparison it replaces: it says the scene draws its furniture where
            // `RoomLayout` says, per theme, rather than that two themes agree.
            let metrics = SceneFixtures.seatMetrics(manifest, theme: themeID)
            let derived = byRole
                .filter { seatRoles.contains($0.role) }
                .map { "\($0.seat):\($0.role):\($0.x)" }.sorted()
            let expected = (0..<scene.layout.seatCapacity).flatMap { seat -> [String] in
                var out = ["\(seat):desk:"
                           + "\(Int(scene.layout.deskPosition(seat, metrics: metrics).x))"]
                if let point = scene.layout.monitorPosition(seat, metrics: metrics) {
                    out.append("\(seat):monitor:\(Int(point.x))")
                }
                // One entry per desktop slot, at that slot's own object's
                // measured ink — the slot decides the column, but whether an
                // object may stand there at all is a function of its height.
                for slot in RoomLayout.PodKitSlot.drawOrder {
                    guard let kit = room.prop(RoomScene.deskKitRole) else { break }
                    let file = kit.variant(slot.rawValue + seat).file
                    let box = SceneFixtures.inkBox(manifest, path: file) ?? kit.contentBox
                    if let point = scene.layout.deskKitPosition(
                        seat, slot: slot, inkHeight: Double(box.height), metrics: metrics) {
                        out.append("\(seat):desk_kit:\(Int(point.x))")
                    }
                }
                return out
            }.sorted()
            #expect(derived == expected, Comment(rawValue:
                "theme \(themeID) drew its desk furniture at \(derived), and its own"
                + " layout puts it at \(expected)"))
            return (props, art, characters, seats, scene.layout.plan)
        }

        let first = render(ids[0])
        #expect(!first.art.isEmpty,
                "no theme drew a prop at all, so nothing here compares anything")
        #expect(first.art.count == first.props.count)
        #expect(!first.seats.isEmpty, "no theme drew any seat furniture")

        var planCounts: [Bool: Int] = [:]
        for id in ids {
            planCounts[render(id).plan.isEmpty, default: 0] += 1
        }
        #expect(planCounts[true] != nil && planCounts[false] != nil, Comment(rawValue:
            "every theme has the same kind of room, so the two branches below are not"
            + " both exercised — planned: \(planCounts[false] ?? 0),"
            + " open: \(planCounts[true] ?? 0)"))

        // **How many props a room draws is a function of its dressing
        // mechanism, and there are two.** [M8]
        //
        // The lattice's number is arithmetic — one prop per scenery anchor plus
        // one per decoration column — and it is derived here rather than typed,
        // for the reason `decorationPlacements` exists at all: a transcription
        // checked against a transcription is not a check. A hand-placed room
        // runs neither of those two loops, so its number is its own placement
        // count. Each theme is checked against **its own** mechanism's number
        // below; the cross-theme comparison that used to carry this on its own
        // is kept, narrowed to the themes that share a mechanism.
        let layout = RoomLayout()
        let lattice = RoomLayout.SceneryBand.allCases
            .reduce(0) { $0 + layout.sceneryAnchors($1).count }
            + layout.decorationColumns.count
        #expect(lattice == 27, Comment(rawValue:
            "the lattice draws \(lattice) props — 20 scenery anchors and 7 decoration"
            + " columns is what every banded theme is pinned to"))
        func expectedPropCount(_ plan: RoomPlan) -> Int {
            plan.dressing.isEmpty ? lattice : plan.dressing.count
        }
        #expect(first.props.count == expectedPropCount(first.plan), Comment(rawValue:
            "theme \(ids[0]) drew \(first.props.count) props and its own dressing mechanism"
            + " places \(expectedPropCount(first.plan))"))

        // **The cut is the theme-independent number, and it is checked over
        // every theme including the first.** [ADR-008]
        var cuts: Set<Int> = []
        for id in ids {
            let metrics = SceneFixtures.seatMetrics(manifest, theme: id)
            for seat in 0..<layout.seatCapacity
            where layout.seatFacing(seat) == .towardCamera {
                let desk = layout.deskPosition(seat, metrics: metrics)
                cuts.insert(Int(desk.y + metrics.deskInkHeight - 1 - layout.seatRowY(seat)))
            }
        }
        #expect(cuts == [Int(layout.deskCutAboveFeet)], Comment(rawValue:
            "a camera-facing desk cuts the body at \(cuts.sorted()) across the themes;"
            + " it must land on one row of the body in all of them"))

        for id in ids.dropFirst() {
            let other = render(id)
            #expect(other.characters == first.characters,
                    "theme \(id) moved a character, its plate, its variant or its badge")
            #expect(other.props.count == expectedPropCount(other.plan), Comment(rawValue:
                "theme \(id) drew \(other.props.count) props and its own dressing mechanism"
                + " places \(expectedPropCount(other.plan))"))
            if other.plan.dressing.isEmpty == first.plan.dressing.isEmpty {
                #expect(other.props.count == first.props.count,
                        "theme \(id) placed a different number of props")
            } else {
                #expect(other.props.count != first.props.count, Comment(rawValue:
                    "theme \(id) dresses its room by hand and theme \(ids[0]) stands its props"
                    + " on the band lattice, and the two drew the same \(other.props.count)"
                    + " props — the hand placement reached nothing"))
            }
            // **Route geometry, in every theme, planned or not.** A plan may
            // redress a room; it may never move a seat. [ADR-007 §2]
            #expect(other.seats == first.seats,
                    "theme \(id) moved a chair or a station prop off its seat's own point")
            if other.plan == first.plan {
                // Same plan, so same geometry and different pictures. The
                // positions are the layout; the paths are the theme.
                #expect(other.props == first.props,
                        "theme \(id) put a prop somewhere theme \(ids[0]) did not")
            } else {
                #expect(other.props != first.props, Comment(rawValue:
                    "theme \(id) is drawn on a different floor plan from \(ids[0]) and"
                    + " placed every prop identically anyway — the plan reached nothing"))
            }
            #expect(other.art != first.art, Comment(rawValue:
                "theme \(id) drew exactly the art theme \(ids[0]) drew — the room was not"
                + " redressed, so `themeID` reached nothing"))
            // And every slot is redressed, not just one of them: two themes
            // sharing a desk while differing in a board would satisfy the line
            // above and still leave most of the room unthemed.
            for (slot, (mine, theirs)) in zip(other.art, first.art).enumerated() {
                #expect(mine != theirs, Comment(rawValue:
                    "theme \(id) shares prop slot \(slot) with theme \(ids[0]): \(mine)"))
            }
        }
    }

    /// **Reading `builder.floor` instead of searching for the flattest tile is
    /// what makes floors themeable**, and this is the difference measured rather
    /// than described.
    ///
    /// The heuristic accepts a tile only if it is fully opaque *and* a single
    /// flat colour, which a patterned floor can never be — so under it every
    /// theme would draw a flat field, and the six themes would differ only in
    /// which flat colour. The declaration is a measurement recorded at import
    /// time, so reading it is not the filename dependency the manifest exists to
    /// prevent.
    ///
    /// The default room declares neither and still resolves through the
    /// heuristic, which is the fallback staying exercised rather than rotting.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theDeclaredFloorIsWhatTheRoomDraws() throws {
        let manifest = try SceneFixtures.manifest()
        var declaredThemes = 0

        for id in manifest.themes.orderedIDs {
            let theme = try #require(manifest.themes.theme(id))
            guard let declared = theme.room.declaredFloor else { continue }
            declaredThemes += 1
            let store = TextureStore(manifest: manifest, themeID: id)
            let tiles = store.roomTileChoice()
            #expect(tiles.floor == declared, "theme \(id) drew a floor it did not declare")
            #expect(tiles.isDeclared)

            // What the heuristic would have picked for this same theme, so
            // the change is visible rather than asserted: the theme ships an
            // authored flat *and* a real tiling floor, and the search can only
            // ever find the flat one.
            let searched = store.flatBuilderTiles()
            #expect(searched.first?.path != declared, Comment(rawValue:
                "theme \(id) declares the same floor the search would have found —"
                + " reading the declaration bought nothing here"))
        }

        #expect(declaredThemes > 0, "no theme declares a floor; nothing was themed")

        // The default room is the one that still goes through the heuristic.
        let plain = TextureStore(manifest: manifest)
        #expect(plain.roomTileChoice().isDeclared == false,
                "the heuristic fallback is no longer exercised by anything")
        #expect(manifest.room.builderTiles.count > 100,
                "the default room's tile list is the one the heuristic searches")
    }

    /// The measurement behind the art-director's finding, kept as a test so the
    /// number in `04-ART-DIRECTION.md` cannot quietly stop being true: **the
    /// heuristic accepts 2 of the room's 141 builder tiles.**
    ///
    /// That is not a bug in the heuristic — a floor with a pattern in it is not
    /// a single flat colour, so no amount of art was ever going to widen this.
    /// It is the reason the declaration exists.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theFlatTileHeuristicAcceptsAlmostNothing() throws {
        let manifest = try SceneFixtures.manifest()
        let store = TextureStore(manifest: manifest)
        let accepted = store.flatBuilderTiles()
        #expect(manifest.room.builderTiles.count == 141)
        #expect(accepted.count == 2, Comment(rawValue:
            "the heuristic now accepts \(accepted.count) of"
            + " \(manifest.room.builderTiles.count) tiles"))
    }
}
