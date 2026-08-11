import Foundation
import Testing
@testable import SpriteRoomCore
@testable import SpriteRoomScene

/// **The durable half of the hands: what a character holds between its calls.**
///
/// Every test in `HeldObjectTests.HeldObjectSceneTests` was written against a
/// character whose tally had never settled, so all of them kept passing when the
/// guard changed. That is the coverage gap this file closes — it exercises the
/// same rules on a character that *has* a settled work kind, which is every
/// character the room actually draws for more than one call.
///
/// The bug being pinned, stated once: a tool call has a median duration of
/// 0.023 s and the gaps between calls in one turn are seconds, so hands gated on
/// the open-call set alone are empty for almost the whole of a turn. The room
/// showed it and a maintainer reported "no objects", which is how it was found.
@MainActor
struct HeldWorkObjectTests {

    static func character(_ store: TextureStore) -> Character {
        Character(variant: "06", nameplate: NameplateText(lead: "MAIN"), store: store)
    }

    static func working(_ tools: [String]) -> BadgeSelection {
        BadgeSelection.select(openToolNames: tools)
    }

    /// **The bug, in the shape it was reported.** Two calls of one turn with a
    /// gap between them: the hands must not blink.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theHandsStayFullBetweenTwoCallsOfOneTurn() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.setWorkObject(.research)

        character.apply(badge: Self.working(["Read"]))
        #expect(character.heldObjectForTesting == .book, "the open call's own object")

        // The call closes. Post-ADR-005 the body stays seated, and this is the
        // frame that used to go empty.
        character.apply(badge: .none)
        #expect(character.state == .working, "this test is not testing what it claims")
        #expect(character.heldObjectForTesting == .book,
                "the hands emptied between two calls of one turn")

        // And the next call arrives to hands that were never empty.
        character.apply(badge: Self.working(["Read"]))
        #expect(character.heldObjectForTesting == .book)
    }

    /// **The turn ending is what empties the hands**, and it needs no clearing
    /// code: the seated guard already says so, because post-ADR-005 a character
    /// out of its turn is standing.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theTurnEndingEmptiesTheHands() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.setWorkObject(.running)
        character.apply(badge: .none)
        #expect(character.heldObjectForTesting == .console)

        character.apply(state: .idle, facing: .right, startingAt: 0)
        #expect(character.heldObjectForTesting == nil, "a standing character is holding something")

        // The kind is remembered rather than discarded — sitting back down in a
        // later turn of the same life restores it without a second intent.
        #expect(character.workObjectForTesting == .console)
        character.apply(state: .working, facing: .right, startingAt: 0)
        #expect(character.heldObjectForTesting == .console)
    }

    /// **The momentary object wins while a call is genuinely open.** The durable
    /// kind is the floor, not the ceiling: an agent whose tally says `running`
    /// still holds a book for the `Read` it is running right now.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theOpenCallsToolWinsOverTheSettledKind() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.setWorkObject(.running)

        character.apply(badge: Self.working(["Read"]))
        #expect(character.heldObjectForTesting == .book, "the settled kind overrode a live call")

        character.apply(badge: .none)
        #expect(character.heldObjectForTesting == .console, "it did not fall back")
    }

    /// **An unrecognised tool falls back rather than blanking.** `HeldObject
    /// .init(badge:)` still abstains on `questionMark` — the room does not guess
    /// a glyph for a tool nobody mapped [I1] — but that abstention must not
    /// punch a hole in a hand the turn has otherwise earned.
    @Test(.enabled(if: SceneArt.isAvailable))
    func anUnrecognisedToolFallsBackRatherThanBlanking() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.setWorkObject(.research)

        character.apply(badge: Self.working(["Monitor"]))
        #expect(character.heldObjectForTesting == .book,
                "an unmapped tool blanked the hands mid-turn")

        // With no settled kind it is still empty, which is the I1 half intact.
        let bare = Self.character(store)
        bare.apply(state: .working, facing: .right, startingAt: 0)
        bare.apply(badge: Self.working(["Monitor"]))
        #expect(bare.heldObjectForTesting == nil, "an unmapped tool invented an object")
    }

    /// **A gated call keeps the work object and loses the tool object.**
    ///
    /// ADR-003 §1 is right that a gated `Bash` is not running, so the room must
    /// not draw the console for it. It may still draw what the agent has been
    /// doing, because that claim is about the turn and not about the blocked
    /// call — and the agent is still an agent that runs commands while it waits.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aGatedCallKeepsTheWorkObjectAndDropsTheToolObject() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let character = Self.character(store)
        character.apply(state: .working, facing: .right, startingAt: 0)
        character.setWorkObject(.research)

        character.apply(badge: BadgeSelection.select(
            openToolNames: ["Bash"], attention: .permissionPrompt))
        #expect(character.heldObjectForTesting == .book,
                "the gate emptied hands the turn had earned")

        // Dormancy is the other slot-owner and behaves the same way.
        character.apply(badge: BadgeSelection.select(openToolNames: ["Bash"], isDormant: true))
        #expect(character.heldObjectForTesting == .book)

        // Never the console, which is the claim that would be false.
        #expect(character.heldObjectForTesting != .console)
    }

    /// Four kinds, four different pictures. A mapping that collapsed two kinds
    /// onto one object would make the layer say less than it claims to.
    @Test func everyWorkKindHoldsItsOwnDistinctObject() {
        let objects = WorkKind.allCases.map(\.heldObject)
        #expect(Set(objects).count == WorkKind.allCases.count,
                "two work kinds share a held object")
        #expect(WorkKind.authoring.heldObject == .page)
        #expect(WorkKind.research.heldObject == .book)
        #expect(WorkKind.running.heldObject == .console)
        #expect(WorkKind.coordinating.heldObject == .clipboard)
    }

    /// **The headline number, measured rather than argued.**
    ///
    /// Replays every fixture and counts, over the frames where a character is
    /// seated inside a turn, how many have something in their hands under the
    /// old rule (open-call set non-empty) versus the shipped one. The old number
    /// is what the maintainer was looking at when they said there was nothing
    /// there.
    ///
    /// Printed as well as asserted, so a run says what it measured.
    @Test func theHandsAreFullForMostOfATurnRatherThanAlmostNoneOfIt() async throws {
        var seatedInTurn = 0
        var fullUnderOldRule = 0
        var fullUnderNewRule = 0

        for name in try DeskObjectCorpusTests.fixtureNames() {
            var director = SceneDirector(variantIDs: ["00", "01", "02", "03", "04", "05"])
            var settled: [AgentRef: WorkKind] = [:]
            var seated: Set<AgentRef> = []
            var openCalls: [AgentRef: Int] = [:]

            for (at, deltas) in try await SceneFixtures.timedBatchedDeltas(name) {
                for intent in director.apply(deltas, at: at) {
                    switch intent {
                    case let .setDeskObject(agent, kind):
                        settled[agent] = kind
                    case let .setBody(agent, state, _):
                        if state == .working { seated.insert(agent) } else { seated.remove(agent) }
                    case let .setBadge(agent, selection):
                        openCalls[agent] = selection.count
                    default:
                        continue
                    }
                }
                // One sample per batch, over everyone currently seated in a turn.
                for agent in seated {
                    seatedInTurn += 1
                    if (openCalls[agent] ?? 0) > 0 { fullUnderOldRule += 1 }
                    if (openCalls[agent] ?? 0) > 0 || settled[agent] != nil { fullUnderNewRule += 1 }
                }
            }
        }

        let old = Double(fullUnderOldRule) / Double(seatedInTurn) * 100
        let new = Double(fullUnderNewRule) / Double(seatedInTurn) * 100
        print("Hands over fixtures/, sampled per batch while seated in a turn:")
        print("  seated-in-turn samples: \(seatedInTurn)")
        print("  old rule (open call only): \(fullUnderOldRule) — \(String(format: "%.1f", old))%")
        print("  shipped rule:              \(fullUnderNewRule) — \(String(format: "%.1f", new))%")

        // Exact rather than bounded, for the reason the desk corpus test gives:
        // a change to the gate, the tally, the badge table or the turn scoping
        // moves these, and a bounded assertion would absorb all of it silently.
        #expect(seatedInTurn == 370)
        #expect(fullUnderOldRule == 119, "the old rule's share of the corpus moved")
        #expect(fullUnderNewRule == 307, "the shipped rule's share of the corpus moved")

        // **32.2% → 83.0%, and the residual 17% is not a defect.** It is the
        // window between a character sitting down and its tally settling on a
        // kind — an agent's first call has not been classified yet, so there is
        // nothing honest to put in its hands and the room puts nothing. [I1]
        // Closing it would mean guessing a kind from an agent's existence, which
        // is the fiction the adoption floor exists to refuse.
        #expect(old < 35, "the old rule was not the problem it was diagnosed as")
        #expect(new > 80, "the durable half stopped covering most of a turn")
    }
}
