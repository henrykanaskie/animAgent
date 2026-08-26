import Foundation
import SpriteKit
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **The report beat goes to somebody.**
///
/// The maintainer, watching the shipped app: *"When they complete/turn in their
/// work, they aren't walking to the main agent, they just walk down and pass the
/// envelope to no one."*
///
/// They were right, and it was a regression with a price tag on it. M6f deleted
/// the reporter's lateral leg to buy back the 96 px of delivery row that leg
/// needed (one row per ring, because three same-side reporters can walk at once)
/// and took `contentBand` from 300 to 170. What was left is a character that
/// stands up, steps to the front of the room, turns, and mimes a hand-over into
/// empty floor. The beat *depicts* a transfer between two characters and only one
/// of them is there, which is a picture asserting something no arrangement of the
/// data supports. [I1]
///
/// What paid for the fix is the nameplate: `2806f5c` put the task on it and cost
/// 8 px (170 → 178), then `2caa864` cut it to one row and gave back 18 (178 →
/// **160**). A `2x` view of the 720×400 panel is 200 px, so there were 40 px of
/// headroom. **One** shared delivery row is 32 of them.
///
/// The two objections M6f rejected that option on are both answered, and neither
/// is answered by assurance:
///
/// 1. *"It makes the guarantee depend on a scheduler."* It does not, because
///    there is no schedule. `DeliveryFloor` grants a claim on a **stretch of the
///    row**, and a reporter refused one plays the in-place beat immediately.
///    Nothing waits, so there is no queue to bound and nothing to reap but the
///    claim: see `aRefusedReporterPlaysTheInPlaceBeatInTheSameFrame` and
///    `theDeliveryRowComesBackWhenTheBeatEndsAndWhenItsCharacterLeaves`.
/// 2. *"It puts a lateral corridor back across the one row every arrival steps
///    through."* It does not, because the corridor is not on that row:
///    `theRoomsOneLateralCorridorMeetsNoOtherRoute`. The objection was written
///    when arrivals began one seat pitch outward *along the walkway*; M6f itself
///    deleted that, so the reason had expired before the trade was refused.
@MainActor
struct ReportDeliveryTests {

    static let panel = CGSize(width: 720, height: 400)

    /// One main agent and `count - 1` subagents, seated and settled.
    static func room(_ count: Int, manifest: Manifest)
    -> (scene: RoomScene, director: SceneDirector, cast: [AgentRef]) {
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(Self.panel)
        var director = SceneDirector(manifest: manifest)
        let cast = RoomSceneTests.cast(count)
        scene.apply(director.apply(cast.enumerated().map { index, ref in
            .agentAppeared(
                agent: ref, agentType: index == 0 ? nil : "general-purpose",
                lifecycle: index == 0 ? .active : .spawning)
        }))
        return (scene, director, cast)
    }

    /// Advances a scene by `seconds` at 60 Hz from `time`, calling `each` frame.
    static func run(
        _ scene: RoomScene, from time: inout TimeInterval, seconds: TimeInterval,
        each body: (TimeInterval) -> Void = { _ in }
    ) {
        let end = time + seconds
        while time < end {
            time += 1.0 / 60.0
            scene.advance(to: time)
            body(time)
        }
    }

    // MARK: The central claim

    /// **The reporter ends up beside the character it is reporting to.**
    ///
    /// Stated the way the maintainer's complaint states it: as a fact about who
    /// is next to whom at the moment of the hand-over, not as a fact about a
    /// coordinate. At the instant the reporter plays `deliver`:
    ///
    /// - the anchor is the character **nearest** to it, strictly; and
    /// - it is within one seat pitch, which is the room's own unit of "not next
    ///   to each other".
    ///
    /// **It was run against the code it replaces and failed for every seat, in
    /// both clauses.** A reporter used to deliver in its own column on the
    /// walkway, so the distance to the anchor was the seat's own offset:
    ///
    /// | reporter | to its anchor | to the nearest character |
    /// |---|---:|---:|
    /// | seats 1, 2 | 101.2 px | 101.2 px, a tie with the next ring out |
    /// | seats 3, 4 | 194.6 px | 135.8 px, a stranger |
    /// | seats 5, 6 | 289.8 px | 101.2 px, a stranger |
    ///
    /// Reports are fired one at a time and waited out, so the delivery row is free
    /// every time and this measures the geometry rather than the contention.
    /// `mostReportsInTheCorpusGetTheWalk` measures the contention.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aReporterEndsUpBesideTheCharacterItIsReportingTo() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let pitch = layout.seatPosition(1).x - layout.seatPosition(0).x
        // Every seat the room has, so the far ring is measured and not assumed.
        var (scene, director, cast) = Self.room(layout.seatCapacity, manifest: manifest)
        var time = 0.0
        Self.run(scene, from: &time, seconds: 4)

        var measured: [String] = []
        for (index, reporter) in cast.enumerated().dropFirst() {
            scene.apply(director.apply([.reportDelivered(agent: reporter)]))
            let character = try #require(scene.character(for: reporter))
            var delivered = false
            Self.run(scene, from: &time, seconds: 12) { _ in
                guard !delivered, character.state == .deliver else { return }
                delivered = true

                let me = character.position
                var distances: [(AgentRef, Double)] = []
                for other in cast where other != reporter {
                    guard let node = scene.character(for: other) else { continue }
                    distances.append((other, hypot(Double(node.position.x - me.x),
                                                   Double(node.position.y - me.y))))
                }
                let nearest = distances.min { $0.1 < $1.1 }
                let toAnchor = distances.first { $0.0 == cast[0] }?.1 ?? .infinity
                measured.append(String(
                    format: "  seat %d: %.1f px to the main agent, nearest is %.1f px",
                    index, toAnchor, nearest?.1 ?? .infinity))

                #expect(nearest?.0 == cast[0], Comment(rawValue:
                    "seat \(index) handed its report to nobody: the nearest character"
                    + " to it is \(nearest.map { "\($0.0)" } ?? "none") at"
                    + " \(nearest?.1 ?? .infinity) px, and its anchor is"
                    + " \(toAnchor) px away"))
                #expect(toAnchor < pitch, Comment(rawValue:
                    "seat \(index) delivered \(toAnchor) px from its anchor, which is"
                    + " further than the \(pitch) px that separates two strangers"))
            }
            #expect(delivered, "seat \(index) never played the hand-over")
            // Wait the beat out so the next reporter meets a free row.
            Self.run(scene, from: &time, seconds: 14)
            #expect(!character.isScripted, "seat \(index) never got home")
        }
        print("WHERE THE REPORT LANDS\n" + measured.joined(separator: "\n"))
    }

    /// The layout half of the same claim, over every anchor and every reporter,
    /// including the nested parents `agentLinked` can produce, which the scene
    /// test above cannot reach without a fixture that has them.
    @Test func everyDeliveryPointIsADeliveryGapFromItsAnchorOnTheReportersOwnSide() {
        let layout = RoomLayout()
        for anchor in 0..<layout.seatCapacity {
            for reporter in 0..<layout.seatCapacity where reporter != anchor {
                let point = layout.deliveryPosition(anchorSeat: anchor, reporterSeat: reporter)
                let anchorX = layout.seatPosition(anchor).x
                let reporterX = layout.seatPosition(reporter).x
                #expect(abs(point.x - anchorX) == layout.deliveryGap, Comment(rawValue:
                    "seat \(reporter) stops \(abs(point.x - anchorX)) px from seat"
                    + " \(anchor), not \(layout.deliveryGap)"))
                #expect(point.y == layout.deliveryRowY)
                // Its own side, so a round trip never crosses the anchor's chair.
                #expect((point.x - anchorX).sign == (reporterX - anchorX).sign,
                        "seat \(reporter) walked past seat \(anchor) to reach it")
                // And it never overshoots its own column, which is what makes the
                // corridor a stretch *between* the two of them.
                #expect(min(anchorX, reporterX) <= point.x && point.x <= max(anchorX, reporterX))
            }
        }
    }

    // MARK: Objection 2 - the corridor

    /// **The one row a character travels along meets no other route in the room.**
    ///
    /// Proved the way `RoomLayout.isBackRow(seat:)` proves its own claim: by
    /// enumerating every route the layout can produce and showing that not one
    /// waypoint of any of them, other than a report's own, is on `deliveryRowY`
    /// or below it. Every route in this room is one of
    ///
    /// | route | shape |
    /// |---|---|
    /// | `entranceRoute` | walkway → chair, one column, upstage |
    /// | `homeRoute` | (row → column) → chair, upstage after the first leg |
    /// | `upstageExit` | chair → wall line, one column, upstage |
    /// | `inPlaceDeliveryRoute` | chair → walkway, one column |
    /// | `deliveryRoute` | chair → walkway → **row** → anchor |
    ///
    /// and only the last reaches the row at all. So a reporter walking sideways
    /// meets nobody's corridor: there is nobody else's corridor there to meet.
    /// The walkway *is* crossed (twice, on the way down and on the way back)
    /// and both crossings are inside the reporter's own seat column, which is
    /// the property every other route in the room already rests on.
    ///
    /// The props are checked too, because a theme could otherwise stand a plant
    /// in the corridor: `RoomScene.decorationPlacements` is asked rather than
    /// transcribed.
    @Test func theRoomsOneLateralCorridorMeetsNoOtherRoute() throws {
        let layout = RoomLayout()
        let exitMetrics = SceneFixtures.seatMetrics(try SceneFixtures.manifest(), theme: "office")

        // 1. Nothing but a report has a waypoint on the delivery row or below it.
        for seat in 0..<layout.seatCapacity {
            var routes: [(String, [ScenePoint])] = [
                ("entrance", layout.entranceRoute(forSeat: seat)),
                ("exit", [layout.upstageExit(forSeat: seat, metrics: exitMetrics)]),
                ("approach", [layout.seatApproach(seat)]),
                ("seat", [layout.seatPosition(seat)]),
                ("in-place report", layout.inPlaceDeliveryRoute(reporterSeat: seat)),
                // Home from the walkway, which is where every non-report beat
                // that leaves a chair puts a character.
                ("home from the walkway",
                 layout.homeRoute(forSeat: seat, fromY: layout.aisleY)),
            ]
            for anchor in 0..<layout.seatCapacity where anchor != seat {
                routes.append(("report to \(anchor), home",
                               layout.homeRoute(forSeat: seat, fromY: layout.deliveryRowY)))
            }
            for (name, route) in routes {
                for point in route {
                    #expect(point.y > layout.deliveryRowY
                            || point.x == layout.seatPosition(seat).x, Comment(rawValue:
                        "seat \(seat)'s \(name) route puts a waypoint on the delivery"
                        + " row at x=\(point.x), off its own column"))
                }
            }
        }

        // 2. Every leg of a report is either vertical inside the reporter's own
        //    column, or lateral on the delivery row. Nothing else, and in
        //    particular no diagonal: a corner cut here would drag a plate
        //    across three rows.
        for seat in 0..<layout.seatCapacity {
            let column = layout.seatPosition(seat).x
            for anchor in 0..<layout.seatCapacity where anchor != seat {
                var legs = [layout.seatPosition(seat)]
                legs += layout.deliveryRoute(anchorSeat: anchor, reporterSeat: seat)
                legs += layout.homeRoute(forSeat: seat, fromY: layout.deliveryRowY)
                for (from, to) in zip(legs, legs.dropFirst()) {
                    let vertical = from.x == to.x && from.x == column
                    let lateral = from.y == to.y && from.y == layout.deliveryRowY
                    #expect(vertical || lateral, Comment(rawValue:
                        "seat \(seat)'s report to \(anchor) walks a diagonal from"
                        + " (\(from.x), \(from.y)) to (\(to.x), \(to.y))"))
                }
                #expect(legs.last?.x == column, "seat \(seat) did not get home to its column")
                #expect(legs.last?.y == layout.seatRowY(seat))
            }
        }

        // 3. Nothing the room *places* is on the row either, in any theme: the
        //    placements are asked of the scene, not copied.
        for placement in RoomScene.decorationPlacements(layout: layout) {
            #expect(placement.point.y > layout.deliveryRowY, Comment(rawValue:
                "a \(placement.role) stands on the delivery row at x=\(placement.point.x)"))
        }
        // Including the furniture a turned seat pushes **downstage** of its
        // occupant, which is the one thing ADR-008 moves toward this row: a
        // camera-facing desk and an away-facing chair back both stand in front
        // of the body, and neither may reach the corridor.
        let metrics = SceneFixtures.seatMetrics(try SceneFixtures.manifest())
        for seat in 0..<layout.seatCapacity {
            #expect(layout.deskPosition(seat, metrics: metrics).y > layout.deliveryRowY)
            #expect(layout.stationPropPosition(seat).y > layout.deliveryRowY)
            if let chair = layout.chairPosition(seat, metrics: metrics) {
                #expect(chair.y > layout.aisleY, Comment(rawValue:
                    "seat \(seat)'s chair stands at y=\(chair.y), on or past the walkway"))
            }
        }
    }

    /// **Two reporters on the row at once are as far apart as their claims are.**
    ///
    /// `DeliveryFloor` refuses a claim that comes within `clearance` of a live
    /// one, and a claim covers every x its beat occupies from the moment it drops
    /// onto the row to the moment it leaves, so the separation is a property of
    /// the two intervals rather than of the phase either beat happens to be in.
    /// The clearance is one plate plus the lattice's own margin, which is the
    /// unrounded seat pitch: the delivery row separates two reporters by exactly
    /// what the seat rows separate two neighbours by.
    @Test func twoGrantedCorridorsAreAlwaysAPlateApart() {
        let layout = RoomLayout()
        let clearance = RoomLayout.deliveryClearance(
            plateWidth: SceneBitmaps.maximumNameplateWidth,
            plateHeight: SceneBitmaps.maximumNameplateHeight,
            tile: layout.tile)
        #expect(clearance >= Double(SceneBitmaps.maximumNameplateWidth),
                "the clearance is narrower than a nameplate")

        // Every pair of reports the room can produce, at every anchor, granted in
        // both orders. Whatever is granted must be a plate apart in x at every
        // point of both corridors.
        var granted = 0
        var refused = 0
        for anchor in 0..<layout.seatCapacity {
            for first in 0..<layout.seatCapacity where first != anchor {
                for second in 0..<layout.seatCapacity where second != anchor && second != first {
                    var floor = DeliveryFloor(clearance: clearance)
                    let a = layout.deliveryCorridor(anchorSeat: anchor, reporterSeat: first)
                    let b = layout.deliveryCorridor(anchorSeat: anchor, reporterSeat: second)
                    let tookIt = floor.claim(id: first, corridor: a, budget: 30)
                    #expect(tookIt, "the first claim on an empty row was refused")
                    if floor.claim(id: second, corridor: b, budget: 30) {
                        granted += 1
                        let gap = max(a.lowerBound - b.upperBound, b.lowerBound - a.upperBound)
                        #expect(gap >= clearance, Comment(rawValue:
                            "seats \(first) and \(second) both walk to \(anchor) with"
                            + " \(gap) px between their corridors"))
                        #expect(gap >= Double(SceneBitmaps.maximumNameplateWidth))
                    } else {
                        refused += 1
                        // A refusal is only ever because the two overlap or come
                        // within the clearance, never a policy about who is
                        // allowed to walk.
                        let gap = max(a.lowerBound - b.upperBound, b.lowerBound - a.upperBound)
                        #expect(gap < clearance)
                    }
                }
            }
        }
        #expect(granted > 0, "no pair of reporters can ever share the row; that is a lock")
        #expect(refused > 0, "every pair is granted; the exclusion does nothing")
        print("DELIVERY ROW PAIRS: \(granted) granted, \(refused) refused")

        // Opposite sides of one anchor is the pairing that must always be
        // granted, because it is the common one (the room's two halves both
        // reporting to the main agent) and it is granted by the lattice: the two
        // delivery points are one seat pitch apart.
        let left = layout.deliveryCorridor(anchorSeat: 0, reporterSeat: 2)
        let right = layout.deliveryCorridor(anchorSeat: 0, reporterSeat: 1)
        var floor = DeliveryFloor(clearance: clearance)
        let tookLeft = floor.claim(id: 2, corridor: left, budget: 30)
        let tookRight = floor.claim(id: 1, corridor: right, budget: 30)
        #expect(tookLeft)
        #expect(tookRight, "the two halves of the room cannot report at the same time")
    }

    // MARK: Objection 1 - the scheduler that is not one

    /// **A reporter that cannot have the row does not wait for it.** It plays the
    /// beat that shipped before the row existed, in the same frame, in its own
    /// column.
    ///
    /// This is the whole of the answer to "is waiting honest, and what bounds
    /// it": nothing waits, so there is no bound to state and no queue to drain.
    /// The room shows a slightly less informative picture of a report that
    /// happened, at the moment it happened, which is a rendering decision inside
    /// what the data said. [I1]
    @Test(.enabled(if: SceneArt.isAvailable))
    func aRefusedReporterPlaysTheInPlaceBeatInTheSameFrame() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        // Seats 1 and 3 are the same side of the main agent, so their corridors
        // both end a delivery gap from seat 0 and cannot be granted together.
        var (scene, director, cast) = Self.room(5, manifest: manifest)
        var time = 0.0
        Self.run(scene, from: &time, seconds: 4)

        scene.apply(director.apply([.reportDelivered(agent: cast[1])]))
        Self.run(scene, from: &time, seconds: 0.5)
        scene.apply(director.apply([.reportDelivered(agent: cast[3])]))

        let first = try #require(scene.character(for: cast[1]))
        let second = try #require(scene.character(for: cast[3]))
        #expect(second.isScripted, "the refused reporter did not move at all")

        var firstY: Double?
        var secondY: Double?
        Self.run(scene, from: &time, seconds: 16) { _ in
            if first.state == .deliver, firstY == nil { firstY = Double(first.position.y) }
            if second.state == .deliver, secondY == nil { secondY = Double(second.position.y) }
        }
        let where1 = firstY.map { "\($0)" } ?? "never"
        let where2 = secondY.map { "\($0)" } ?? "never"
        #expect(firstY == layout.deliveryRowY, Comment(rawValue:
            "the first reporter delivered at y=\(where1), not on the delivery row"))
        #expect(secondY == layout.aisleY, Comment(rawValue:
            "the second reporter delivered at y=\(where2): it should have been"
            + " refused the row and used the walkway"))
        // Both delivered, and neither is still holding anything.
        #expect(!first.isScripted && !second.isScripted)
        #expect(Double(first.position.y) == layout.seatRowY(1))
        #expect(Double(second.position.y) == layout.seatRowY(3))
    }

    /// **The row comes back.** Three ways, and the first two are the ones that
    /// actually run: the beat finishing, and the character leaving mid-beat.
    ///
    /// A leaver is the interesting one. `exitCharacter` takes it out of
    /// `characters` at the top of its exit while it is still several seconds from
    /// the end of its walk, so a claim keyed on the agent would come back while
    /// the character was still standing in the corridor. It is keyed on the
    /// character, and released when that character stops running a script. [I4]
    @Test(.enabled(if: SceneArt.isAvailable))
    func theDeliveryRowComesBackWhenTheBeatEndsAndWhenItsCharacterLeaves() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        var (scene, director, cast) = Self.room(5, manifest: manifest)
        var time = 0.0
        Self.run(scene, from: &time, seconds: 4)

        // 1. The beat finishing. Seat 1 walks; seat 3 is refused while it does;
        //    seat 3 walks once seat 1 is home.
        scene.apply(director.apply([.reportDelivered(agent: cast[1])]))
        Self.run(scene, from: &time, seconds: 16)
        #expect(scene.deliveryRowHoldersForTesting.isEmpty, Comment(rawValue:
            "the row is still held by \(scene.deliveryRowHoldersForTesting) after the"
            + " beat ended: every later report in this session would be refused"))

        scene.apply(director.apply([.reportDelivered(agent: cast[3])]))
        let third = try #require(scene.character(for: cast[3]))
        var deliveredAt: Double?
        Self.run(scene, from: &time, seconds: 16) { _ in
            if third.state == .deliver, deliveredAt == nil {
                deliveredAt = Double(third.position.y)
            }
        }
        #expect(deliveredAt == layout.deliveryRowY, "the row was never given back")
        #expect(scene.deliveryRowHoldersForTesting.isEmpty)

        // 2. A character that reports and leaves in the same frame keeps the row
        //    for the whole of its walk and gives it back when it is gone.
        scene.apply(director.apply([
            .reportDelivered(agent: cast[2]), .agentDeparted(agent: cast[2]),
        ]))
        Self.run(scene, from: &time, seconds: 0.5)
        #expect(scene.deliveryRowHoldersForTesting == [2], Comment(rawValue:
            "a leaver mid-report holds \(scene.deliveryRowHoldersForTesting); it is"
            + " still walking the corridor and the row is not free"))
        Self.run(scene, from: &time, seconds: 22)
        #expect(scene.character(for: cast[2]) == nil, "the leaver never left")
        #expect(scene.deliveryRowHoldersForTesting.isEmpty,
                "the leaver took its stretch of the row with it")
    }

    /// **A seat is not a claim, and this is the case that proves it has to be
    /// that way.**
    ///
    /// A subagent goes dormant on the same event that starts its report, so it is
    /// immediately the longest-dormant character in the room and its seat is the
    /// first one a new agent can be given, while it is still several seconds
    /// from the end of its walk. Keyed by seat, the newcomer's own report would
    /// overwrite a claim whose holder is standing in the corridor, and the two
    /// would walk through each other.
    ///
    /// Keyed by a per-beat id, the newcomer is simply refused and delivers in
    /// place. The seat is reused; the claim is not.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aSeatHandedOnMidBeatDoesNotHandOnTheDeliveryRowWithIt() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        var (scene, director, cast) = Self.room(3, manifest: manifest)
        var time = 0.0
        Self.run(scene, from: &time, seconds: 4)

        // Seat 1 reports and leaves in the same frame: it walks the corridor and
        // then out, and its seat is free from this instant.
        scene.apply(director.apply([
            .reportDelivered(agent: cast[1]), .agentDeparted(agent: cast[1]),
        ]))
        let leaver = try #require(scene.charactersOnScreen.first { $0.state != .working })
        #expect(scene.deliveryRowHoldersForTesting == [1])

        let newcomer = AgentRef(project: "/p", session: "s", agent: .subagent("bbbbbbbbbbbbbbbb"))
        scene.apply(director.apply([
            .agentAppeared(agent: newcomer, agentType: "general-purpose", lifecycle: .spawning),
        ]))
        #expect(director.seats[newcomer] == 1, "the newcomer did not take the freed seat")

        // Let it walk in and sit, then have it report while the leaver is still
        // out there.
        Self.run(scene, from: &time, seconds: 2.5)
        #expect(leaver.isScripted, "the leaver finished too early; the overlap never happened")
        #expect(scene.deliveryRowHoldersForTesting == [1],
                "the leaver's claim was released while it was still walking")

        scene.apply(director.apply([.reportDelivered(agent: newcomer)]))
        let second = try #require(scene.character(for: newcomer))
        var deliveredAt: Double?
        Self.run(scene, from: &time, seconds: 6) { _ in
            if second.state == .deliver, deliveredAt == nil {
                deliveredAt = Double(second.position.y)
            }
        }
        #expect(deliveredAt == layout.aisleY, Comment(rawValue:
            "the newcomer delivered at y=\(deliveredAt.map { "\($0)" } ?? "never"): it"
            + " took the delivery row from a character that was still standing on it"))
    }

    /// **And the reaper of last resort**, on the floor itself, because the
    /// condition it guards against (a claim whose release never runs) cannot be
    /// produced through the scene by construction.
    ///
    /// A claim's clock starts at the first `reap` after it rather than at the
    /// claim, so the floor is correct against any clock origin. `RoomScene`'s is
    /// the render loop's, which starts at system uptime.
    @Test func aClaimNobodyGivesBackIsReapedOnItsOwnDeadline() {
        var floor = DeliveryFloor(clearance: 84)
        let took = floor.claim(id: 1, corridor: 100...200, budget: 5)
        let overlapping = floor.claim(id: 3, corridor: 150...400, budget: 5)
        #expect(took)
        #expect(!overlapping, "an overlapping corridor was granted")

        // The render loop's clock is enormous and starts wherever it starts. The
        // first sweep must not expire a claim it has only just seen.
        #expect(floor.reap(at: 91_000).isEmpty, "the claim expired against an unstarted clock")
        #expect(floor.reap(at: 91_004).isEmpty)
        #expect(floor.reap(at: 91_005) == [1])
        #expect(floor.isEmpty)
        let afterReap = floor.claim(id: 3, corridor: 150...400, budget: 5)
        #expect(afterReap, "the reaped stretch was not usable afterwards")

        // A re-claim under an id that already holds the row always succeeds: it
        // is the same beat being restarted, and a beat is one character.
        let again = floor.claim(id: 3, corridor: 150...400, budget: 5)
        #expect(again, "a beat could not be restarted under its own id")
        #expect(floor.occupiedIDs == [3])
    }

    // MARK: The beat's own length [ADR-005 §8]

    /// **The walk makes the beat longer, and ADR-005 has a rule about that.**
    ///
    /// > A body one-shot may be admitted only if **its duration is shorter than
    /// > the 99th-percentile inter-arrival time of its own trigger, per agent**,
    /// > measured on `fixtures/`.
    ///
    /// ADR-005 §8 ran that against `deliver` alone (1.25 s of animation) and
    /// passed it easily. What this change lengthens is the whole beat around it:
    /// a report used to be one tile down, the hand-over, one tile back, and it is
    /// now a walk to the anchor and back. So the rule is re-run against the beat
    /// rather than against the animation, which is the honest reading of it: the
    /// thing that collides with the next trigger is the thing that is still
    /// playing.
    ///
    /// **The numbers, measured rather than estimated.** A report to the main
    /// agent (which is every report in `fixtures/` and every report from a
    /// subagent whose parent has gone) runs **6.1 s** from ring 1, **7.0 s** from
    /// ring 2 and **11.5 s** from ring 3. The absolute worst case the layout can
    /// produce is **19.5 s**: a far-ring seat reporting to a nested parent on the
    /// *opposite* far ring, which is a walk across the whole room and back.
    ///
    /// Against that, the shortest gap between two `SubagentStop`s **of one
    /// agent** anywhere in `fixtures/` is **29.14 s** (`four-subagents`,
    /// `aae859812d39a1892`; the only other pair is 45.03 s). The corpus has two
    /// data points and that is stated rather than dressed up as a distribution.
    ///
    /// **The 19.5 s case is not capped, and that is a decision.** Capping it
    /// means either a threshold nobody can derive, or refusing the walk to a
    /// distant anchor, which is the defect this whole change exists to fix,
    /// reintroduced for the case where the two characters are hardest to
    /// associate by eye. The length of the walk is how far apart the two agents
    /// are sitting, which is a true fact about the room. What it costs is that
    /// one beat holds most of the delivery row for those 19.5 s, so a report
    /// landing inside that window gets the in-place beat.
    ///
    /// This is not a collision guard: a second report for one agent restarts
    /// that agent's own beat and `DeliveryFloor` re-grants it its own claim, so
    /// nothing breaks if the bound is ever exceeded. It is the tripwire that
    /// makes lengthening the beat again a decision somebody takes on purpose.
    @Test func theLongestReportBeatIsWellInsideOneAgentsOwnReportingGap() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        // The `deliver` animation, from the manifest, the same number
        // `RoomScene` puts in the claim's budget.
        var deliverSeconds = 0.0
        for variant in manifest.characters.variants.values {
            guard let animation = variant.animation(.deliver) else { continue }
            let frames = animation.frames.values.map(\.count).max() ?? 0
            deliverSeconds = max(deliverSeconds, Double(frames) / max(1, animation.fps))
        }
        #expect(deliverSeconds > 0, "no variant draws a hand-over")

        func beat(anchor: Int, reporter: Int) -> TimeInterval {
            var total = deliverSeconds
            var from = layout.seatPosition(reporter)
            let legs = layout.deliveryRoute(anchorSeat: anchor, reporterSeat: reporter)
                + layout.homeRoute(forSeat: reporter, fromY: layout.deliveryRowY)
            for point in legs {
                total += Character.duration(from: from, to: point)
                from = point
            }
            return total
        }

        var longest = (seconds: 0.0, anchor: 0, reporter: 0)
        var rows: [String] = []
        for reporter in 1..<layout.seatCapacity {
            let seconds = beat(anchor: 0, reporter: reporter)
            rows.append(String(format: "  seat %d (ring %d): %5.2f s",
                               reporter, layout.ring(ofSeat: reporter), seconds))
            for anchor in 0..<layout.seatCapacity where anchor != reporter {
                let all = beat(anchor: anchor, reporter: reporter)
                if all > longest.seconds { longest = (all, anchor, reporter) }
            }
        }
        print("REPORT BEAT LENGTHS, to the main agent\n" + rows.joined(separator: "\n"))
        print(String(format: "  longest over every anchor: %.2f s (seat %d → seat %d)",
                     longest.seconds, longest.reporter, longest.anchor))

        // The corpus's own number, restated here so a failure says what it is
        // being compared against rather than just that a constant moved.
        let shortestOwnGap = 29.14
        #expect(longest.seconds < shortestOwnGap, Comment(rawValue:
            "the longest report beat is \(longest.seconds) s and one agent has"
            + " reported twice \(shortestOwnGap) s apart in fixtures/: the beat"
            + " would still be playing when its own trigger came round again"))
        // The case the room actually produces, kept separate from the worst case
        // the layout can produce, because they are 8 s apart and only the first
        // has ever happened: every subagent in `fixtures/` reports to the main
        // agent, and the furthest seat from the main agent is ring 3.
        let toMain = beat(anchor: 0, reporter: layout.seatCapacity - 1)
        #expect(toMain < shortestOwnGap / 2, Comment(rawValue:
            "a report to the main agent from the furthest seat is \(toMain) s,"
            + " against a \(shortestOwnGap) s gap between one agent's own reports"))
        #expect(longest.seconds < 20, Comment(rawValue:
            "the longest beat the layout can produce is \(longest.seconds) s, it"
            + " was 19.47, and it is a character walking the width of the room"))
    }

    // MARK: The corpus

    /// **How often the walk actually plays, on the captures this project has.**
    ///
    /// The cost of the fallback is that the same report can look different on two
    /// occasions, and the only honest way to state that cost is to measure how
    /// often it is paid. Two fixtures carry report beats: `three-subagents` and
    /// `four-subagents`, the latter with twelve `SubagentStop`s and a minimum gap
    /// of 1.26 s between two of them.
    ///
    /// The measurement is on the **picture**: which row the character was standing
    /// on when it played `deliver`. It does not ask the bookkeeping, so it cannot
    /// agree with a bookkeeping bug.
    @Test(.enabled(if: SceneArt.isAvailable))
    func mostReportsInTheCorpusGetTheWalk() async throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        var walked = 0
        var inPlace = 0
        var rows: [String] = []

        for name in ["three-subagents", "four-subagents"] {
            let scene = RoomScene(manifest: manifest)
            scene.setViewport(Self.panel)
            var seen: Set<ObjectIdentifier> = []
            var here = (walk: 0, place: 0)
            _ = try await SceneFixtures.replayInFixtureTime(
                name, into: scene, director: SceneDirector(manifest: manifest)
            ) { _ in
                for character in scene.charactersOnScreen where character.state == .deliver {
                    // One reading per hand-over: `deliver` does not loop, so a
                    // character plays it once per beat.
                    let key = ObjectIdentifier(character)
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    if Double(character.position.y) == layout.deliveryRowY {
                        here.walk += 1
                    } else {
                        #expect(Double(character.position.y) == layout.aisleY, Comment(
                            rawValue: "\(name): a hand-over on y=\(character.position.y),"
                            + " which is neither the delivery row nor the walkway"))
                        here.place += 1
                    }
                }
                // A character that finished a beat may report again later.
                for character in scene.charactersOnScreen where !character.isScripted {
                    seen.remove(ObjectIdentifier(character))
                }
            }
            // The denominator, from the model rather than from the scene: every
            // `reportDelivered` this capture produces has to have been drawn as
            // one beat or the other, or the fixture has a report the room never
            // showed at all.
            var reports = 0
            for batch in try await SceneFixtures.timedBatchedDeltas(name) {
                for delta in batch.deltas {
                    if case .reportDelivered = delta { reports += 1 }
                }
            }
            #expect(here.walk + here.place == reports, Comment(rawValue:
                "\(name): \(reports) reports in the deltas, \(here.walk + here.place)"
                + " hand-overs on screen"))

            walked += here.walk
            inPlace += here.place
            rows.append("  \(name): \(reports) reports, \(here.walk) walked to the"
                        + " anchor, \(here.place) delivered in place")
        }

        print("REPORT BEATS OVER fixtures/\n" + rows.joined(separator: "\n"))
        #expect(walked + inPlace > 0, "no report beat was observed; this measures nothing")
        // **Nine of nine, as the corpus stands.** The captures never put two
        // same-side reports close enough together to contend: the shortest gap
        // between any two `SubagentStop`s in `fixtures/` is 1.26 s, and both of
        // that pair are on opposite sides of the main agent. So the fallback is
        // real, proved by `aRefusedReporterPlaysTheInPlaceBeatInTheSameFrame`, and
        // no capture this project holds reaches it.
        #expect(inPlace == 0, Comment(rawValue:
            "\(inPlace) of \(walked + inPlace) reports fell back to the in-place beat:"
            + " the corpus used to reach it zero times, so either the beat got"
            + " longer or the claim is not being given back"))
        #expect(walked > inPlace, Comment(rawValue:
            "only \(walked) of \(walked + inPlace) reports walked to their anchor:"
            + " the fallback has become the common case, which is the fix not"
            + " landing"))
    }
}
