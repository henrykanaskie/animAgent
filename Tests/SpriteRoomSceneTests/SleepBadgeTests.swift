import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// The dormant badge on the scene side: what it outranks, what outranks it,
/// what it never touches, and that the art it needs is real.
///
/// Dormancy is `SubagentStop` — "this subagent finished a turn and is still
/// assigned". It was drawn as plain `idle` until the `sleep` badge was wired,
/// on the grounds that nothing we own could honestly draw the difference between
/// finished-and-might-return and waiting-for-work. `badges.states.sleep` is
/// exactly that art: the same UI-sheet component as `attention`, in the same
/// frame, saying the one thing the flag knows. [I1]
struct SleepBadgeTests {

    static let cast = ["06", "07", "09", "10", "17", "19"]

    static func director() -> SceneDirector { SceneDirector(variantIDs: cast) }

    static func ref(_ agent: AgentID = .subagent("a0000000000000001")) -> AgentRef {
        AgentRef(project: "/p", session: "s", agent: agent)
    }

    static func call(_ id: String, _ tool: String) -> OpenCall {
        let start = Date(timeIntervalSince1970: 0)
        return OpenCall(
            toolUseID: id, toolName: tool, startedAt: start,
            deadline: start.addingTimeInterval(60))
    }

    static func badge(of intents: [SpriteIntent]) -> BadgeSelection? {
        intents.reversed().compactMap { intent -> BadgeSelection? in
            if case let .setBadge(_, selection) = intent { return selection }
            return nil
        }.first
    }

    static func hasBadgeIntent(_ intents: [SpriteIntent]) -> Bool {
        intents.contains { if case .setBadge = $0 { return true } else { return false } }
    }

    // MARK: Precedence

    /// **attention > sleep.** Both facts are true at once and there is one
    /// badge anchor, so the actionable one takes it: "waiting on you, now" has
    /// a deadline the user owns and "finished a turn, might come back" does
    /// not. The `Z` is a standing state, so it returns by itself the moment the
    /// attention clears.
    @Test func attentionOutranksSleep() {
        let selection = BadgeSelection.select(
            openToolNames: [String](), attention: .permissionPrompt, isDormant: true)
        #expect(selection.isAttention)
        #expect(selection.isDormant, "dormancy is not forgotten, only outranked")
        #expect(!selection.isSleeping, "the sleep glyph must not win the slot against attention")

        // Clearing the attention puts the `Z` back with no further delta about
        // dormancy, because dormancy never went anywhere.
        let cleared = BadgeSelection.select(
            openToolNames: [String](), attention: nil, isDormant: true)
        #expect(cleared.isSleeping)
    }

    /// **sleep > tool, and it suppresses the `×N`.**
    ///
    /// Unreachable from the live stream — `SubagentStop` abandons every open
    /// call in the batch that sets dormancy, and the only path that opens one
    /// revives the agent first — so this pins the value type's behaviour rather
    /// than a picture anybody can produce. It is written down because
    /// "unreachable" is a property of today's model and `BadgeSelection` is a
    /// value anything may construct.
    @Test func sleepOutranksAToolBadgeAndTheCountGoesWithIt() {
        let selection = BadgeSelection.select(
            openToolNames: ["Bash", "Read"], isDormant: true)
        #expect(selection.isSleeping)
        // The tool badge is still computed, exactly as it is under attention,
        // so waking restores it without the model re-announcing the calls.
        #expect(selection.badge == .magnifier)
        #expect(selection.count == 2)
    }

    /// The three-way order is total and each rung is distinct, so nothing
    /// depends on which of two flags a renderer happens to test first.
    @Test func theBadgeSlotHasOneTotalOrder() {
        let tool = BadgeSelection.select(openToolNames: ["Bash"])
        let sleeping = BadgeSelection.select(openToolNames: ["Bash"], isDormant: true)
        let attentive = BadgeSelection.select(
            openToolNames: ["Bash"], attention: .idlePrompt, isDormant: true)
        #expect(!tool.isAttention && !tool.isSleeping && tool.badge == .terminal)
        #expect(!sleeping.isAttention && sleeping.isSleeping)
        #expect(attentive.isAttention && !attentive.isSleeping)
        #expect(tool != sleeping && sleeping != attentive && tool != attentive)
    }

    // MARK: The director

    /// The badge goes up on `dormancyChanged(true)` and comes down on
    /// `dormancyChanged(false)`, and the character is otherwise untouched.
    @Test func dormancyRaisesTheBadgeAndRevivalTakesItDown() throws {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)])
        #expect(!director.badge(agent).isSleeping)

        let asleep = director.apply([.dormancyChanged(agent: agent, isDormant: true)])
        #expect(try #require(Self.badge(of: asleep)).isSleeping)
        #expect(director.badge(agent).isSleeping)

        let awake = director.apply([.dormancyChanged(agent: agent, isDormant: false)])
        #expect(try #require(Self.badge(of: awake)) == .none)
        #expect(!director.badge(agent).isSleeping)
    }

    /// **Dormancy stands the character up, and it is the only thing in the delta
    /// stream that can.** [ADR-005 §3]
    ///
    /// This test used to be `dormancyNeverChangesTheBody`, and the claim it was
    /// making was true of the room it was written in: the body was keyed on the
    /// open-call set, `SubagentStop` abandons every call in the same batch that
    /// sets dormancy, so the body was already `idle` and the `Z` changed
    /// nothing. That was the tab agreeing with the body by coincidence rather
    /// than by construction — and between two calls of one turn the same body
    /// state was drawn for an agent that was working.
    ///
    /// `dormancyChanged` *is* `SubagentStop`, which is a turn boundary, so it is
    /// exactly the event that ends the seated state. The `Z` now sits over a
    /// character that has stood up, and the two channels say one thing.
    ///
    /// **No new body state.** The pack's `sleep` **body** row is a head on a
    /// pillow drawn from above for compositing onto a top-down bed — M6b cut it
    /// and measured it — so on a character sitting side-on it is a floating
    /// head. What dormancy selects is the standing pose the room already has.
    @Test func dormancyStandsTheCharacterUpAndRevivalSeatsItAgain() {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)])
        #expect(director.bodyState(agent) == .working, "a started subagent is in a turn")

        let asleep = director.apply([.dormancyChanged(agent: agent, isDormant: true)])
        #expect(asleep.contains { if case .setBody(_, .idle, _) = $0 { return true } else { return false } })
        #expect(director.bodyState(agent) == .idle)
        #expect(director.badge(agent).isSleeping, "the tab and the body must say one thing")

        let awake = director.apply([.dormancyChanged(agent: agent, isDormant: false)])
        #expect(awake.contains { if case .setBody(_, .working, _) = $0 { return true } else { return false } })
        #expect(director.bodyState(agent) == .working)
        #expect(BodyState(rawValue: "sleep") == nil, "a dormant body state was added")
    }

    /// Emitted only when it actually changed — a second `SubagentStop` for an
    /// already-dormant agent must not re-set a badge it already wears.
    @Test func aRepeatedDormancyEmitsNoSecondIntent() {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)])
        #expect(Self.hasBadgeIntent(director.apply([
            .dormancyChanged(agent: agent, isDormant: true)])))
        #expect(!Self.hasBadgeIntent(director.apply([
            .dormancyChanged(agent: agent, isDormant: true)])))
    }

    /// A wake that arrives in the same batch as the call that caused it is one
    /// badge change, not two. That is the whole reason the director derives
    /// intents from the state *after* the batch: the real stream puts
    /// `dormancyChanged(false)` and `callOpened` in the same frame, because
    /// `WorldModel.ensureAgent` revives before `PreToolUse` opens anything.
    @Test func wakingAndWorkingInOneBatchIsOneBadgeChange() throws {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)])
        _ = director.apply([.dormancyChanged(agent: agent, isDormant: true)])

        let intents = director.apply([
            .dormancyChanged(agent: agent, isDormant: false),
            .callOpened(agent: agent, call: Self.call("t1", "Bash")),
        ])
        let badges = intents.filter { if case .setBadge = $0 { return true } else { return false } }
        #expect(badges.count == 1)
        let selection = try #require(Self.badge(of: intents))
        #expect(!selection.isSleeping)
        #expect(selection.badge == .terminal)
    }

    /// The badge goes with the character. A departed agent's presentation is
    /// removed, so nothing can carry a stale `Z` into a reused seat.
    @Test func departureTakesTheDormancyWithIt() {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)])
        _ = director.apply([.dormancyChanged(agent: agent, isDormant: true)])
        _ = director.apply([.agentDeparted(agent: agent)])
        _ = director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)])
        #expect(!director.badge(agent).isSleeping)
    }

    // MARK: Against the real capture

    /// **End to end from `four-subagents`** — the capture dormancy was built
    /// for. Four background subagents; two stop, are resumed with
    /// `SendMessage`, and stop again. Every stop must put a `Z` up and every
    /// resume must take one down, and at the end of the replay every character
    /// still on screen is asleep rather than gone.
    @Test func theRealCaptureSleepsAndWakesTheSameCharacters() async throws {
        var director = Self.director()
        var raised = 0
        var lowered = 0
        var sleeping: Set<AgentRef> = []
        var populationWithEverybodyAsleep: Int?

        for batch in try await SceneFixtures.batchedDeltas("four-subagents") {
            for intent in director.apply(batch) {
                guard case let .setBadge(agent, selection) = intent else { continue }
                if selection.isSleeping, !sleeping.contains(agent) {
                    sleeping.insert(agent)
                    raised += 1
                } else if !selection.isSleeping, sleeping.contains(agent) {
                    sleeping.remove(agent)
                    lowered += 1
                }
            }
            if sleeping.count == 4, populationWithEverybodyAsleep == nil {
                populationWithEverybodyAsleep = director.population
            }
        }

        // Six stops across four agents — two of them stop twice — and two
        // revivals, which is the shape `docs/03-EVENT-MODEL.md` records. The
        // capture's other five `SubagentStop`s are the TUI suggestion helper's
        // phantoms, for `agent_id`s that never started, and they are no-ops.
        #expect(raised == 6, "the capture raised \(raised) sleep badges")
        #expect(lowered == 2, "the capture lowered \(lowered) sleep badges")
        #expect(sleeping.count == 4, "\(sleeping.count) of four subagents ended the replay asleep")

        // **The fact the whole feature is about: four dispatched, four drawn.**
        // At the moment the last of them fell asleep the room held all four
        // plus the main thread — where the departing lifecycle this replaced
        // would have been down to one.
        #expect(populationWithEverybodyAsleep == 5,
                "four subagents plus the main thread were not all in the room")
        // And then the session ends and everyone genuinely does leave, which is
        // the path dormancy never blocks. [I4]
        #expect(director.population == 0, "`SessionEnd` did not empty the room")
    }

    /// Nothing but a `SubagentStop` sleeps anybody. A fixture with no subagent
    /// in it must produce no `Z` at all — the badge is not a general-purpose
    /// "idle" glyph and there is no idle badge. [I2]
    @Test func aSessionWithNoSubagentNeverSleeps() async throws {
        var director = Self.director()
        for batch in try await SceneFixtures.batchedDeltas("single-agent-simple") {
            for intent in director.apply(batch) {
                guard case let .setBadge(_, selection) = intent else { continue }
                #expect(!selection.isSleeping)
                #expect(!selection.isDormant)
            }
        }
    }

    // MARK: Art

    /// The manifest key is tracked, so this runs on a fresh clone with no art.
    /// `sleep` lives under `badges.states` beside `attention`, for the identical
    /// reason: it answers to no tool, and `badges.map`'s keys are exhaustively
    /// required.
    @Test func theManifestDeclaresTheSleepBadge() throws {
        let manifest = try SceneFixtures.manifest()
        let art = try #require(manifest.badges.sleep)
        #expect(!art.file.isEmpty)
        #expect(art.provenance == "pack")
        #expect(manifest.badges.states[Manifest.Badges.sleepKey] != nil)
        #expect(ToolBadge(manifestKey: Manifest.Badges.sleepKey) == nil)
        // Two non-tool states now, and they are different files. One glyph
        // serving both would make "needs you" and "finished a turn" the same
        // claim, which they are not.
        #expect(art.file != manifest.badges.attention?.file)
    }

    @Test(.enabled(if: SceneArt.isAvailable))
    @MainActor
    func theSleepTextureLoadsAndIsNeitherAToolBadgeNorAttention() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let sleep = try #require(store.sleepTexture())
        #expect(sleep.size().width > 0)
        #expect(store.attentionTexture() !== sleep)
        for badge in ToolBadge.allCases {
            #expect(store.badgeTexture(badge) !== sleep, "\(badge) reused the sleep art")
        }
    }

    /// The character actually swaps the picture, attention takes the slot off
    /// it, and clearing the attention gives it back.
    ///
    /// **What dormancy draws is no longer the pack's bubble.** It is
    /// `SceneBitmaps.dormancyTab` — see that symbol for the measurement, and
    /// `theDormancyTabIsNotABubble` below for the property. The precedence this
    /// test was written for is untouched: attention still takes the slot and
    /// still gives it back.
    @Test(.enabled(if: SceneArt.isAvailable))
    @MainActor
    func theCharacterDrawsTheSleepGlyphAndAttentionTakesTheSlot() throws {
        let manifest = try SceneFixtures.manifest()
        let store = TextureStore(manifest: manifest)
        let variant = try #require(manifest.characters.orderedVariantIDs.first)
        let character = Character(
            variant: variant, nameplate: NameplateText(lead: "8DE", role: "Explore"), store: store)
        let tab = SceneBitmaps.dormancyTab()

        character.apply(badge: BadgeSelection.select(openToolNames: [String](), isDormant: true))
        #expect(character.isBadgeVisible)
        let drawn = try #require(character.badgeTextureForTesting)
        #expect(drawn !== store.sleepTexture(), "dormancy is back in the bubble")
        #expect(Int(drawn.size().width) == tab.width)
        #expect(Int(drawn.size().height) == tab.height)
        #expect(!character.isBadgeCountVisible)

        character.apply(badge: BadgeSelection.select(
            openToolNames: [String](), attention: .permissionPrompt, isDormant: true))
        #expect(character.badgeTextureForTesting === store.attentionTexture())

        character.apply(badge: BadgeSelection.select(openToolNames: [String](), isDormant: true))
        #expect(character.badgeTextureForTesting === drawn)

        // And a tool badge coming back gets the badge canvas back with it. A
        // node left at the tab's 9x11 would resample a 24x34 bubble into it,
        // which is the shimmer I6 exists to prevent.
        character.apply(badge: BadgeSelection.select(openToolNames: ["Bash"]))
        let bubble = try #require(character.badgeTextureForTesting)
        #expect(Int(bubble.size().width) == manifest.badges.canvas.width)
        #expect(Int(bubble.size().height) == manifest.badges.canvas.height)

        character.apply(badge: .none)
        #expect(!character.isBadgeVisible)
    }

    /// **The one that had to be true and was not.**
    ///
    /// At `1x` the badge slot's *presence* is the loudest thing in the room, and
    /// the pack's `sleep` glyph put a bubble there for an agent that had stopped
    /// — 84% of a working badge's footprint, in a silhouette that is a strict
    /// subset of every tool bubble. Six bubbles read as six busy agents when all
    /// six were `Z`. This pins the fix as a size relation rather than as "the
    /// texture changed", because the texture changing is not what fixed it.
    ///
    /// A quarter is not a threshold anybody tuned to pass: the tab measures 99
    /// px against a bubble's 816, which is 12%, and `dim` — the same bubble at
    /// `alpha 0.3`, the alternative that was tried — measures 100% here, because
    /// alpha does not change extent. That is the whole reason it lost.
    @Test func theDormancyTabIsNotABubble() throws {
        let manifest = try SceneFixtures.manifest()
        let tab = SceneBitmaps.dormancyTab()
        let canvas = manifest.badges.canvas
        #expect(tab.width * tab.height * 4 < canvas.width * canvas.height,
                "the dormancy tab is bubble-sized again")
        // Dark, not white: the bubbles are the bright family and the room's own
        // lettering is the dark one. The tab belongs to the lettering. [I7]
        #expect(tab.at(0, 0) == SceneBitmaps.nameplatePlate)
        // It is drawn, not loaded, so it exists on a checkout with no art — the
        // reason this test needs no `SceneArt` gate while the one above does.
        #expect(tab.opaquePixelCount == tab.width * tab.height)
    }
}
