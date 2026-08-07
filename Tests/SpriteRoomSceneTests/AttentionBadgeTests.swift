import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// The attention badge on the scene side: what it outranks, what it hides,
/// and that the art it needs is real.
struct AttentionBadgeTests {

    static let cast = ["06", "07", "09", "10", "17", "19"]

    static func director() -> SceneDirector { SceneDirector(variantIDs: cast) }

    static func ref(_ agent: AgentID = .mainThread) -> AgentRef {
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

    // MARK: Precedence

    /// **Attention outranks the tool badge.** A `Bash` parked at a permission
    /// gate is not running — the badge that says "this needs you" is both the
    /// actionable one and the truthful one.
    @Test func attentionOutranksAnOpenToolCall() {
        let selection = BadgeSelection.select(
            openToolNames: ["Bash", "Read"], attention: .permissionPrompt)
        #expect(selection.isAttention)
        #expect(selection.attention == .permissionPrompt)
        // The tool badge is still *computed* — the open calls did not stop
        // existing — so answering the prompt restores it without the model
        // having to re-announce anything.
        #expect(selection.badge == .magnifier)
        #expect(selection.count == 2)
    }

    /// The `×N` is an annotation on a *tool* badge. Pinned to the attention
    /// glyph it would read as N notifications, which is never a thing we
    /// count: `idle_prompt` fires exactly once.
    @Test func attentionSuppressesTheCountOnScreen() throws {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])

        _ = director.apply([
            .callOpened(agent: agent, call: Self.call("a", "Bash")),
            .callOpened(agent: agent, call: Self.call("b", "Bash")),
        ])
        #expect(director.badge(agent).count == 2)
        #expect(!director.badge(agent).isAttention)

        let raised = director.apply([
            .attentionChanged(agent: agent, attention: .permissionPrompt)])
        let selection = try #require(Self.badge(of: raised))
        #expect(selection.isAttention)
        // The count survives in the value; the renderer is what hides it.
        #expect(selection.count == 2)
    }

    /// Attention says nothing about the body. There is no animation for
    /// "waiting on a human" and repurposing one would be fiction, so the badge
    /// is the whole representation. [I1]
    @Test func attentionNeverChangesTheBody() {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])
        _ = director.apply([.callOpened(agent: agent, call: Self.call("a", "Bash"))])
        #expect(director.bodyState(agent) == .working)

        let intents = director.apply([
            .attentionChanged(agent: agent, attention: .permissionPrompt)])
        #expect(!intents.contains { if case .setBody = $0 { return true } else { return false } })
        #expect(director.bodyState(agent) == .working)

        // And an idle character stays idle rather than gaining a pose.
        var idle = Self.director()
        _ = idle.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])
        let idleIntents = idle.apply([
            .attentionChanged(agent: agent, attention: .idlePrompt)])
        #expect(idle.bodyState(agent) == .idle)
        #expect(!idleIntents.contains {
            if case .setBody = $0 { return true } else { return false }
        })
    }

    /// Clearing puts the tool badge back exactly as it was.
    @Test func clearingRestoresTheToolBadge() throws {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])
        _ = director.apply([.callOpened(agent: agent, call: Self.call("a", "Bash"))])
        let before = director.badge(agent)

        _ = director.apply([.attentionChanged(agent: agent, attention: .permissionPrompt)])
        #expect(director.badge(agent) != before)

        let cleared = director.apply([.attentionChanged(agent: agent, attention: nil)])
        #expect(director.badge(agent) == before)
        #expect(Self.badge(of: cleared) == before)
    }

    /// Both `notification_type`s draw the same glyph — there is one attention
    /// badge and it asserts the one thing they share — but they are different
    /// values, so a delta stream that swaps one for the other is a change.
    @Test func thePromptTypesAreDistinctValuesShowingOneGlyph() {
        let permission = BadgeSelection.select(openToolNames: [String](),
                                               attention: .permissionPrompt)
        let idle = BadgeSelection.select(openToolNames: [String](), attention: .idlePrompt)
        #expect(permission != idle)
        #expect(permission.isAttention && idle.isAttention)
        #expect(permission.badge == nil && idle.badge == nil)
    }

    /// A badge with no open calls at all is still drawn: `idle_prompt` fires
    /// on a session that is doing nothing, which is the whole point of it.
    @Test func anIdleCharacterCanStillCarryTheBadge() {
        let selection = BadgeSelection.select(openToolNames: [String](), attention: .idlePrompt)
        #expect(selection.isAttention)
        #expect(selection.count == 0)
        #expect(BadgeSelection.none.isAttention == false)
    }

    // MARK: Determinism — criterion 6

    /// Adding attention must not make the badge depend on arrival order.
    @Test func selectionStaysIndependentOfOrder() {
        let tools = ["Bash", "Read", "mcp__x__y", "WebFetch", "TodoWrite"]
        for attention in [nil, AttentionKind.permissionPrompt, .idlePrompt] {
            let reference = BadgeSelection.select(openToolNames: tools, attention: attention)
            for _ in 0..<100 {
                #expect(BadgeSelection.select(
                    openToolNames: tools.shuffled(), attention: attention) == reference)
            }
        }
    }

    /// The badge is emitted only when it actually changed — a repeated
    /// notification must not produce a second `setBadge`.
    @Test func arepeatedAttentionEmitsNoSecondIntent() {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])
        let first = director.apply([
            .attentionChanged(agent: agent, attention: .permissionPrompt)])
        #expect(first.contains { if case .setBadge = $0 { return true } else { return false } })
        let second = director.apply([
            .attentionChanged(agent: agent, attention: .permissionPrompt)])
        #expect(!second.contains { if case .setBadge = $0 { return true } else { return false } })
    }

    /// Raised and cleared inside one frame's batch is no change at all. The
    /// director derives from the state after the whole batch, so nothing
    /// flashes for a sixtieth of a second.
    @Test func raisedAndClearedInOneBatchShowsNothing() {
        var director = Self.director()
        let agent = Self.ref()
        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])
        let intents = director.apply([
            .attentionChanged(agent: agent, attention: .permissionPrompt),
            .attentionChanged(agent: agent, attention: nil),
        ])
        #expect(!intents.contains { if case .setBadge = $0 { return true } else { return false } })
    }

    // MARK: Against the real capture

    /// End to end from the fixture: the real `permission-prompt` stream
    /// produces exactly two badge-on/badge-off pairs on the main character.
    @Test func theRealCaptureDrivesTwoBadgesUpAndTwoDown() async throws {
        var director = Self.director()
        var attentionStates: [Bool] = []
        var showing = false
        for batch in try await SceneFixtures.batchedDeltas("permission-prompt") {
            for intent in director.apply(batch) {
                guard case let .setBadge(_, selection) = intent else { continue }
                if showing != selection.isAttention {
                    showing = selection.isAttention
                    attentionStates.append(showing)
                }
            }
        }
        #expect(attentionStates == [true, false, true, false])
    }

    // MARK: Art

    /// The manifest key is tracked, so this runs on a fresh clone with no art.
    /// `attention` lives under `badges.states`, not `badges.map` — it answers
    /// to no tool, and `map`'s keys are exhaustively required.
    @Test func theManifestDeclaresTheAttentionBadge() throws {
        let manifest = try SceneFixtures.manifest()
        let art = try #require(manifest.badges.attention)
        #expect(!art.file.isEmpty)
        // M0b sourced it from the pack, and it is still pack art. Corrected at
        // M5b: this used to say it and `question_mark` were the only two real
        // badges and that the other six were "pending a purchase". The purchase
        // was made. It supplied `document` and `checklist`. Corrected again at
        // M5c: the remaining four are not placeholders either — no icon for them
        // exists in any pack we own and no further pack is coming, so they were
        // drawn here and are `authored`. See
        // `ManifestTests.badgeProvenanceIsRecorded` for the exact split.
        #expect(art.provenance == "pack")
        #expect(manifest.badges.states[Manifest.Badges.attentionKey] != nil)
        // And it is not a tool badge.
        #expect(ToolBadge(manifestKey: Manifest.Badges.attentionKey) == nil)
    }

    @Test(.enabled(if: SceneArt.isAvailable))
    @MainActor
    func theAttentionTextureLoadsAndIsNotAToolBadge() throws {
        let store = TextureStore(manifest: try SceneFixtures.manifest())
        let attention = try #require(store.attentionTexture())
        #expect(attention.size().width > 0)
        for badge in ToolBadge.allCases {
            #expect(store.badgeTexture(badge) !== attention, "\(badge) reused the attention art")
        }
    }

    /// The character actually swaps the glyph, and puts the tool badge back.
    @Test(.enabled(if: SceneArt.isAvailable))
    @MainActor
    func theCharacterDrawsTheAttentionGlyphAndRestoresTheToolBadge() throws {
        let manifest = try SceneFixtures.manifest()
        let store = TextureStore(manifest: manifest)
        let variant = try #require(manifest.characters.orderedVariantIDs.first)
        let character = Character(variant: variant, nameplate: "MAIN", store: store)

        character.apply(badge: BadgeSelection.select(openToolNames: ["Bash", "Bash"]))
        #expect(character.isBadgeVisible)
        #expect(character.isBadgeCountVisible)
        let toolTexture = character.badgeTextureForTesting

        character.apply(badge: BadgeSelection.select(
            openToolNames: ["Bash", "Bash"], attention: .permissionPrompt))
        #expect(character.isBadgeVisible)
        #expect(character.badgeTextureForTesting !== toolTexture)
        #expect(character.badgeTextureForTesting === store.attentionTexture())
        #expect(!character.isBadgeCountVisible, "the ×N must not annotate the attention glyph")

        character.apply(badge: BadgeSelection.select(openToolNames: ["Bash", "Bash"]))
        #expect(character.badgeTextureForTesting === toolTexture)
        #expect(character.isBadgeCountVisible)
    }
}
