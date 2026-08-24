import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **The corpus measurement, and it is the central test of this change.**
/// [ADR-006 §3a]
///
/// Everything else here checks a rule in isolation. This one replays all
/// eighteen captures through the real `WorldModel` and the real `SceneDirector`
/// and asks the two questions the design can only be judged on: *how many
/// characters end up with something on the desk*, and *how often does what is on
/// a desk change*.
///
/// It needs no art (it reads the director, not the scene) so it runs on a
/// fresh clone.
struct DeskObjectCorpusTests {

    /// Every capture in `fixtures/`, walked rather than listed, so a capture
    /// added later is measured rather than missed.
    static func fixtureNames() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(
                atPath: SceneFixtures.repositoryRoot.appending(path: "fixtures").path)
            .filter { $0.hasSuffix(".jsonl") }
            .map { String($0.dropLast(6)) }
            .sorted()
    }

    /// What one fixture replay produced.
    struct Outcome {
        /// Every agent the room ever drew a character for.
        var agents: Set<AgentRef> = []
        /// The kind each agent's desk ended on, for the agents that earned one.
        var adopted: [AgentRef: WorkKind] = [:]
        /// Every `setDeskObject` intent, in order, with the fixture instant it
        /// was emitted at.
        var changes: [(agent: AgentRef, kind: WorkKind, at: Date)] = []
    }

    /// One fixture, replayed at its own pace against a director with a real
    /// clock. **The fixture's clock, not the wall clock**: the dwell floor is
    /// four seconds of fixture time and a test that used `Date()` would measure
    /// how fast this machine is.
    static func replay(_ name: String) async throws -> Outcome {
        var director = SceneDirector(variantIDs: ["00", "01", "02", "03", "04", "05"])
        var outcome = Outcome()
        for (at, deltas) in try await SceneFixtures.timedBatchedDeltas(name) {
            for delta in deltas {
                if case let .agentAppeared(agent, _, _) = delta { outcome.agents.insert(agent) }
            }
            for intent in director.apply(deltas, at: at) {
                guard case let .setDeskObject(agent, kind) = intent else { continue }
                outcome.adopted[agent] = kind
                outcome.changes.append((agent, kind, at))
            }
        }
        return outcome
    }

    // MARK: The headline numbers

    /// **How many characters in the whole corpus end up with a prop, and how
    /// many keep the bare desk.**
    ///
    /// ADR-006 §3a predicted 5 of 27 with the threshold it proposed,
    /// three votes and twice the runner-up. The maintainer retuned the object
    /// mid-build from *a readout a person might rely on* to *a prop on the
    /// table*, and the threshold came down to one observed call with a
    /// replacement margin (`WorkTally.adoptionFloor`, `.replacementFloor`,
    /// `.majorityRatio`). These are the numbers under the shipped rule, printed
    /// as well as asserted so a run says what it measured rather than only that
    /// it agreed.
    ///
    /// The counts are exact rather than bounded, deliberately: a change to the
    /// gate, the lexicon, the badge table or the turn scoping moves them, and a
    /// test that only checked "most agents get one" would absorb every one of
    /// those silently.
    @Test func mostAgentsInTheCorpusEndUpWithSomethingOnTheDesk() async throws {
        var agents = 0
        var furnished = 0
        var byKind: [WorkKind: Int] = [:]
        var lines: [String] = []

        for name in try Self.fixtureNames() {
            let outcome = try await Self.replay(name)
            agents += outcome.agents.count
            furnished += outcome.adopted.count
            for (_, kind) in outcome.adopted { byKind[kind, default: 0] += 1 }
            for agent in outcome.agents.sorted(by: { "\($0)" < "\($1)" }) {
                let kind = outcome.adopted[agent]?.rawValue ?? "-"
                lines.append("  \(name.padding(toLength: 28, withPad: " ", startingAt: 0))"
                             + " \(Self.short(agent))  \(kind)")
            }
        }

        print("ADR-006 desk objects over fixtures/:")
        print(lines.joined(separator: "\n"))
        print("  \(furnished) of \(agents) agents furnished;"
              + " \(agents - furnished) kept the bare desk")
        print("  by kind: " + byKind
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: " "))

        // **`authoring` appears here for the first time at the eighteenth
        // capture.** Every number in this test was measured over a corpus that
        // held zero `Edit`, `Write` and `NotebookEdit` calls, so the laptop was
        // unreachable on real data and this dictionary had three keys where
        // ADR-006 declares four. `authoring-subagents` closes that: two of its
        // four agents end on `authoring`, and the kind is no longer a claim
        // resting on unit tests of the derivation agreeing with itself.
        #expect(agents == 31, "the corpus grew or shrank; every number below is measured off it")
        #expect(furnished == 30)
        #expect(agents - furnished == 1)
        #expect(byKind == [.running: 14, .research: 10, .coordinating: 4, .authoring: 2])
    }

    /// **Abstention is still reachable, and it is reachable for exactly one
    /// reason: no evidence at all.** [I1]
    ///
    /// A gate that admits everything is not a gate. With the floor at one
    /// observed call the *only* way to keep a bare desk is to make no call this
    /// app can classify, and one character in the corpus does exactly that,
    /// which is what keeps this from being a rule with no false case. The
    /// converse is asserted too: no agent that made a classifiable call was left
    /// bare, which is the claim the retuning was for.
    ///
    /// The check is against the delta stream rather than against the director's
    /// state at the end of the run, because by then `SessionEnd` has departed
    /// almost everybody and a departed agent has no presentation to ask.
    @Test func onlyAnAgentWithNoClassifiableCallAtAllKeepsABareDesk() async throws {
        var bare = 0
        for name in try Self.fixtureNames() {
            let outcome = try await Self.replay(name)
            var classifiable: [AgentRef: Int] = [:]
            for batch in try await SceneFixtures.batchedDeltas(name) {
                for delta in batch {
                    guard case let .callOpened(agent, call) = delta,
                          WorkKind(toolName: call.toolName) != nil else { continue }
                    classifiable[agent, default: 0] += 1
                }
            }
            for agent in outcome.agents {
                let calls = classifiable[agent] ?? 0
                if outcome.adopted[agent] == nil {
                    bare += 1
                    #expect(calls == 0, Comment(rawValue:
                        "\(name)/\(Self.short(agent)) kept a bare desk after \(calls)"
                        + " classifiable tool call(s)"))
                } else {
                    #expect(calls > 0, Comment(rawValue:
                        "\(name)/\(Self.short(agent)) was furnished with no classifiable call"))
                }
            }
        }
        #expect(bare == 1, "abstention stopped being reachable over this corpus")
    }

    // MARK: Stability: the failure mode that matters now

    /// **How often what is on a desk changes, over the whole corpus.**
    ///
    /// ADR-006 §3a measured 32 changes for the naive argmax rule and 5 for its
    /// own gate. The shipped rule is looser than the gate, so this is the number
    /// that has to be looked at rather than assumed: a prop that changes every
    /// few seconds is worse than a prop that is wrong.
    ///
    /// Both halves are asserted: the total, and the worst case any single
    /// character produced.
    @Test func aDeskObjectSettlesAndThenStaysPut() async throws {
        var totalChanges = 0
        var replacements = 0
        var worstPerCharacter = 0
        var tightestGap = Double.infinity

        for name in try Self.fixtureNames() {
            let outcome = try await Self.replay(name)
            totalChanges += outcome.changes.count
            var seen: [AgentRef: [Date]] = [:]
            for change in outcome.changes {
                if seen[change.agent] != nil { replacements += 1 }
                seen[change.agent, default: []].append(change.at)
            }
            for (agent, instants) in seen {
                worstPerCharacter = max(worstPerCharacter, instants.count)
                if instants.count > 1 {
                    print("  redecorated: \(name)/\(Self.short(agent)) "
                          + outcome.changes
                        .filter { $0.agent == agent }
                        .map(\.kind.rawValue).joined(separator: " → "))
                }
                for (earlier, later) in zip(instants, instants.dropFirst()) {
                    let gap = later.timeIntervalSince(earlier)
                    tightestGap = min(tightestGap, gap)
                    #expect(gap >= SceneDirector.deskObjectDwell, Comment(rawValue:
                        "\(name)/\(Self.short(agent)) changed its desk twice \(gap)s apart,"
                        + " inside the \(SceneDirector.deskObjectDwell)s dwell floor"))
                }
            }
        }

        print("ADR-006 desk-object churn: \(totalChanges) sets over the corpus,"
              + " \(replacements) of them replacements,"
              + " worst character \(worstPerCharacter),"
              + " tightest gap \(tightestGap.isFinite ? "\(tightestGap)s" : "n/a")")

        // 37 sets for 30 furnished characters: 30 first appearances and **seven**
        // replacements. ADR-006 §3a measured 32 changes for the naive argmax
        // rule and 5 for the threshold it proposed; this is looser than the
        // proposal and still under the naive rule, because the replacement
        // margin and the turn scoping (not the floor) are what do the
        // stabilising.
        //
        // **These four numbers were 28 / 2 / 2 / >50 until the eighteenth
        // capture, and what moved them is the first capture of a real working
        // session rather than a sandbox scenario.** A scripted capture does one
        // kind of thing; `authoring-subagents` has a main agent that runs a
        // build, reads, dispatches, edits and writes inside one session, so it
        // redecorates four times where no sandbox character redecorated more
        // than twice. The corpus was not wrong, it was narrow, which is the
        // whole argument for capturing real sessions [#72].
        #expect(totalChanges == 37)
        #expect(replacements == 7)
        #expect(worstPerCharacter == 4, "some character redecorated more than the corpus has shown")
        // **The enforced floor held; the comfortable margin did not.** Every gap
        // still cleared `deskObjectDwell`: the per-gap assertion above is the
        // one that matters and it did not fire, but the measured floor is now
        // **2.7x** the enforced 4 s, where the sandbox corpus made it look like
        // an order of magnitude. That sentence used to be in this comment and
        // was true only of scripted work.
        //
        // The **enforced** bound is what protects a workload even this capture
        // does not contain: at most one change per character per
        // `deskObjectDwell`, so 15 a minute in the worst case the code can
        // produce, against ADR-005's measured median tool call of 23 ms.
        #expect(tightestGap > 10)
    }

    /// **Replay is deterministic**: two runs of the same capture produce the same
    /// desks in the same order. The tally is a counter over a set, and
    /// dictionary iteration order is not stable across runs, so "the argmax is
    /// deterministic" is a claim that has to be checked rather than assumed.
    @Test func twoReplaysOfOneFixtureProduceTheSameDesks() async throws {
        for name in ["four-subagents", "three-subagents", "parallel-tools"] {
            let first = try await Self.replay(name)
            let second = try await Self.replay(name)
            #expect(first.adopted == second.adopted, "\(name)")
            #expect(first.changes.map(\.kind) == second.changes.map(\.kind), "\(name)")
        }
    }

    /// Last 4 characters of an agent id, for a printable line.
    static func short(_ agent: AgentRef) -> String {
        let text = "\(agent.agent)"
        return text.count <= 12 ? text : "…" + String(text.suffix(11))
    }
}

/// The vocabulary itself: `WorkKind` and its two derivations. Pure functions,
/// no art, no fixtures.
struct WorkKindTests {

    /// **`WorkKind.init?(badge:)` is a total function of `ToolBadge`**, checked
    /// against the committed enum rather than against ADR-006 §1c's table.
    ///
    /// `ToolBadge.badge(forTool:)` is itself total: its `default` arm is
    /// `questionMark`, so totality here means every tool name that exists or
    /// ever will has an answer, and the answer for two of the seven classes is
    /// *say nothing*.
    @Test func everyBadgeClassHasAnAnswerAndTwoOfThemAbstain() {
        var answered = 0
        for badge in ToolBadge.allCases {
            switch badge {
            case .plug, .questionMark:
                #expect(WorkKind(badge: badge) == nil, "\(badge) guessed a work kind")
            default:
                #expect(WorkKind(badge: badge) != nil, "\(badge) has no work kind")
                answered += 1
            }
        }
        #expect(ToolBadge.allCases.count == 7, "the badge table changed; §1c's mapping needs re-deriving")
        #expect(answered == 5)
    }

    /// The mapping itself, spelled out: ADR-006 §1's evidence table read back
    /// through the tool names rather than through the badge names, since tool
    /// names are what the payload carries.
    @Test func theToolNamesMapToTheKindsTheADRsTableNames() {
        let expected: [String: WorkKind?] = [
            "Edit": .authoring, "Write": .authoring, "NotebookEdit": .authoring,
            "Read": .research, "Glob": .research, "Grep": .research,
            "ToolSearch": .research, "WebSearch": .research, "WebFetch": .research,
            "Bash": .running, "BashOutput": .running, "KillShell": .running,
            "TodoWrite": .coordinating, "Agent": .coordinating, "SendMessage": .coordinating,
            "mcp__anything__at_all": nil, "Monitor": nil, "SomeToolNobodyHasWritten": nil,
        ]
        for (tool, kind) in expected {
            #expect(WorkKind(toolName: tool) == kind, "\(tool)")
        }
    }

    /// **An unmapped tool furnishes nothing, ever.** The question-mark badge's
    /// own rule, one layer out: guessing a glyph for an unrecognised tool is
    /// forbidden, and a piece of furniture is a much bigger surface to be wrong
    /// on. [I1]
    @Test func anUnrecognisedToolCastsNoVote() {
        var tally = WorkTally()
        for _ in 0..<20 {
            tally.record(WorkKind(toolName: "Monitor"))
            tally.record(WorkKind(toolName: "mcp__ide__getDiagnostics"))
        }
        #expect(tally.isEmpty)
        #expect(tally.observedVotes == 0)
        #expect(tally.adopted(incumbent: nil) == nil)
    }

    /// **Every kind is authored now, and none names a manifest role.**
    ///
    /// It was three-from-the-pack and one authored until the three were rendered
    /// at the panel's true size and found unreadable there: all isometric, and
    /// a diagonal wedge loses its diagonal first. `DeskWorkArt` replaced them.
    /// The roles are still declared in the manifest and `propRole` is still the
    /// seam that would read them, so this pins the shipped state rather than
    /// forbidding the arrangement.
    @Test func everyKindIsAuthoredAndNamesNoManifestRole() {
        for kind in WorkKind.allCases {
            #expect(kind.propRole == nil, "\(kind.rawValue) names a pack role again")
        }
        // Each one still resolves to a picture, from one of the two authored
        // sources: a kind that named nothing and drew nothing would be a bare
        // desk that no rule asked for.
        for kind in WorkKind.allCases {
            let authored = DeskWorkArt.bitmap(kind) ?? DeskMonitorArt.bitmap()
            #expect(authored.width > 0 && authored.height > 0, "\(kind.rawValue) draws nothing")
        }
    }

    /// The roles named above are ones the manifest actually declares. This is
    /// the half `everyPropRoleTheSceneDrawsIsOneTheManifestNames` cannot see,
    /// because these are drawn outside `propNodes`.
    @Test func theRolesTheKindsNameAreDeclaredInTheManifest() throws {
        let manifest = try SceneFixtures.manifest()
        for kind in WorkKind.allCases {
            guard let role = kind.propRole else { continue }
            #expect(manifest.room.prop(role) != nil, "\(kind) names \(role), which the manifest has not")
        }
    }
}

/// The lexicon: the only free text this app classifies. [ADR-006 §6c rule 5]
struct WorkKindLexiconTests {

    /// The four lists are disjoint, so a single word can never vote twice and
    /// "matched two kinds" always means two *different* words disagreeing.
    @Test func theFourKeywordListsShareNoWord() {
        for (kind, list) in WorkKind.keywords {
            for (other, otherList) in WorkKind.keywords where other != kind {
                let shared = list.intersection(otherList)
                #expect(shared.isEmpty, "\(kind) and \(other) share \(shared.sorted())")
            }
        }
        #expect(WorkKind.keywords.count == 4)
    }

    /// **Every keyword is a word this lexicon could actually see.** Upper case
    /// and letters only, because the classifier upper-cases and splits before it
    /// looks: a lower-case entry would be dead text that never matched anything
    /// and nobody would find out.
    @Test func everyKeywordIsInTheFormTheSplitProduces() {
        for (kind, list) in WorkKind.keywords {
            for word in list {
                #expect(word == word.uppercased(), "\(kind): \(word) is not upper case")
                #expect(word.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" },
                        "\(kind): \(word) holds a character the split would cut it at")
            }
        }
    }

    /// **Every dispatch description in `fixtures/` classifies to one kind or to
    /// nothing**, which is §6c rule 5's own checkable, run over the real
    /// captures rather than over invented strings.
    ///
    /// The corpus's ten descriptions come out as: seven `research` (every
    /// "Read ... .txt" dispatch), one `running` ("Touch a file via bash": the
    /// only word in it this lexicon knows is `BASH`), and two abstentions
    /// ("Touch file s1"/"s2", which hold no keyword at all). Asserted by name so
    /// that a lexicon edit has to look at what it did to the real data.
    @Test func everyDispatchDescriptionInTheCorpusClassifiesOrAbstains() async throws {
        var classified: [String: String] = [:]
        for name in try DeskObjectCorpusTests.fixtureNames() {
            for batch in try await SceneFixtures.batchedDeltas(name) {
                for delta in batch {
                    guard case let .agentTasked(_, task) = delta else { continue }
                    classified[task] = WorkKind(dispatchDescription: task)?.rawValue ?? "-"
                }
            }
        }
        print("ADR-006 lexicon over the corpus's dispatch descriptions:")
        for (task, kind) in classified.sorted(by: { $0.key < $1.key }) {
            print("  \(kind.padding(toLength: 13, withPad: " ", startingAt: 0)) \(task)")
        }
        #expect(classified.count == 13, "the corpus's descriptions changed: \(classified.keys.sorted())")
        #expect(classified["Touch file s1"] == "-")
        #expect(classified["Touch file s2"] == "-")
        #expect(classified["Touch a file via bash"] == "running")
        #expect(classified["Read one.txt sleep"] == "research")
        #expect(classified["Read alpha.txt and sleep"] == "research")
        #expect(classified["Read delta/epsilon, sleep, reread alpha"] == "research")
        // **The lexicon's first contact with descriptions nobody wrote for it.**
        // The ten above were authored as capture prompts, in a sandbox, by
        // someone who knew what the classifier looks for. These three came off a
        // real session [#72] and **two of them abstain**, which is rule 5
        // working, not failing, but it is the first measurement of how often
        // *say nothing* is the answer on descriptions written for a colleague
        // rather than for a test. One in three classified.
        #expect(classified["Audit doc-symbol drift with Grep/Glob"] == "research")
        #expect(classified["Inventory fixture-count pins"] == "-")
        #expect(classified["Verify and persist the pin inventory"] == "-")
    }

    /// **A description that names two kinds contributes nothing.** The
    /// ambiguity half of rule 5, which the corpus has no example of, so it is
    /// checked against constructed strings: a pure function's own unit test,
    /// not a fixture standing in for captured data.
    @Test func aDescriptionMatchingTwoKindsAbstains() {
        #expect(WorkKind(dispatchDescription: "Write the migration and run the tests") == nil)
        #expect(WorkKind(dispatchDescription: "Read the logs then fix the parser") == nil)
        #expect(WorkKind(dispatchDescription: "Plan the refactor") == nil)
        // One kind named twice is still one kind.
        #expect(WorkKind(dispatchDescription: "Read and review the manifest") == .research)
    }

    /// A description with no keyword in it abstains too, and so does an empty
    /// one. The lexicon is total: every string has an answer and most strings'
    /// answer is nothing.
    @Test func aDescriptionNamingNoKindAbstains() {
        #expect(WorkKind(dispatchDescription: "") == nil)
        #expect(WorkKind(dispatchDescription: "s1") == nil)
        #expect(WorkKind(dispatchDescription: "Touch file s1") == nil)
        #expect(WorkKind(dispatchDescription: "!!! ??? ,,,") == nil)
    }

    /// The split is `SceneDirector.taskLine(_:)`'s own, so a keyword still
    /// counts when it arrives punctuated, and a keyword glued to something else
    /// by a hyphen does not: the honest edge of a whole-word lexicon.
    @Test func theSplitIsTheOneTheNameplateAlreadyUses() {
        #expect(WorkKind(dispatchDescription: "read alpha.txt,") == .research)
        #expect(WorkKind(dispatchDescription: "READ ALPHA") == .research)
        #expect(WorkKind(dispatchDescription: "re-read alpha") == nil)
        #expect(WorkKind(dispatchDescription: "rereading alpha") == nil)
    }
}

/// The gate arithmetic, on the value type that holds it.
struct WorkTallyTests {

    static func tally(_ counts: [WorkKind: Int], claim: WorkKind? = nil) -> WorkTally {
        var tally = WorkTally()
        tally.seedOpeningClaim(claim)
        for (kind, count) in counts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            for _ in 0..<count { tally.record(kind) }
        }
        return tally
    }

    // MARK: Authoring precedence

    /// **The reported case, as the numbers it was reported in.** A coding
    /// session edits a few files and runs many commands to build and test them;
    /// under pure counting that is `running` by a factor of thirteen, which is
    /// why a maintainer watching a live session could not find a laptop.
    @Test func aFewEditsOutrankManyCommands() {
        let tally = Self.tally([.authoring: 3, .running: 40])
        #expect(tally.count(.running) == 40, "the arithmetic under test is real")
        #expect(tally.adopted(incumbent: nil) == .authoring)
        // And it takes the desk off an established incumbent, which the majority
        // ratio would otherwise refuse: 3 is not twice 40.
        #expect(tally.adopted(incumbent: .running) == .authoring)
        #expect(tally.adopted(incumbent: .research) == .authoring)
    }

    /// **One edit is an event, two is a habit.** The floor exists so that a
    /// research agent saving a single note does not sit behind a laptop for the
    /// rest of its life.
    @Test func oneStrayEditDoesNotHijackTheTurn() {
        #expect(Self.tally([.authoring: 1, .running: 40]).adopted(incumbent: nil) == .running)
        #expect(Self.tally([.authoring: 2, .running: 40]).adopted(incumbent: nil) == .authoring)
        #expect(WorkTally.authoringPrecedenceFloor == 2, "the floor moved without the reasoning")
    }

    /// **A brief cannot trigger it.** The rule reads observed calls only, so an
    /// agent *told* to implement something still shows what it is actually
    /// doing until it actually edits twice. [I1]
    @Test func aDispatchDescriptionCannotClaimAuthoringPrecedence() {
        // The claim alone: one authoring vote, zero observed.
        let claimed = Self.tally([.running: 4], claim: .authoring)
        #expect(claimed.observedCount(.authoring) == 0)
        #expect(claimed.adopted(incumbent: nil) == .running)

        // Even a claim plus one real edit is still one real edit.
        let claimedAndOne = Self.tally([.authoring: 1, .running: 40], claim: .authoring)
        #expect(claimedAndOne.count(.authoring) == 2, "the claim is still a vote")
        #expect(claimedAndOne.observedCount(.authoring) == 1)
        #expect(claimedAndOne.adopted(incumbent: nil) == .running)
    }

    /// Clearing a turn clears the observed counts with the votes. A tally that
    /// forgot only half would let last turn's edits decide this turn.
    @Test func clearingTheTurnForgetsObservedAuthoringToo() {
        var tally = Self.tally([.authoring: 5])
        #expect(tally.adopted(incumbent: nil) == .authoring)
        tally.clear()
        #expect(tally.observedCount(.authoring) == 0)
        #expect(tally.observedVotes == 0)
        #expect(tally.adopted(incumbent: .running) == .running, "a cleared tally changed the desk")
    }

    /// **Nothing on a bare desk without at least one observed call.** The floor
    /// is one, so this is the whole of what stops the room furnishing a desk
    /// from a dispatch description alone.
    @Test func anEmptyTallyFurnishesNothing() {
        #expect(WorkTally().adopted(incumbent: nil) == nil)
        #expect(Self.tally([:], claim: .authoring).adopted(incumbent: nil) == nil)
        #expect(Self.tally([.research: 1]).adopted(incumbent: nil) == .research)
    }

    /// **One observed call is enough to furnish a bare desk**, which is the
    /// retuned floor. One `Bash` really is evidence that this agent ran
    /// something.
    @Test func oneObservedCallFurnishesABareDesk() {
        for kind in WorkKind.allCases {
            #expect(Self.tally([kind: 1]).adopted(incumbent: nil) == kind)
        }
    }

    /// **A tie changes nothing, in either direction.** With an incumbent it
    /// keeps the incumbent; with a bare desk it stays bare until something pulls
    /// ahead. No recency and no ordering dependence: the properties ADR-003 §5
    /// protects for the badge, and they are reachable here in a way they were
    /// not at the original threshold.
    @Test func aTieNeverMovesAnything() {
        let split = Self.tally([.research: 3, .running: 3])
        #expect(split.adopted(incumbent: nil) == nil)
        #expect(split.adopted(incumbent: .research) == .research)
        #expect(split.adopted(incumbent: .running) == .running)
        // An incumbent that is not even in the tie is still not replaced by one.
        #expect(split.adopted(incumbent: .authoring) == .authoring)
    }

    /// **Replacing costs more than appearing.** One stray call cannot overturn a
    /// desk, which is what stops the first tool call of a new turn rearranging
    /// furniture, since the tally is turn-scoped and the incumbent starts every
    /// turn with zero votes of its own.
    @Test func oneStrayCallNeverOverturnsAnOccupiedDesk() {
        #expect(Self.tally([.running: 1]).adopted(incumbent: .research) == .research)
        #expect(Self.tally([.running: 2]).adopted(incumbent: .research) == .running)
    }

    /// **And it costs twice the incumbent's own votes.** An agent that has read
    /// three files and run three commands this turn does not swap on the
    /// seventh call.
    @Test func aChallengerHasToDoubleTheIncumbentsVotes() {
        #expect(Self.tally([.research: 3, .running: 4]).adopted(incumbent: .research) == .research)
        #expect(Self.tally([.research: 3, .running: 5]).adopted(incumbent: .research) == .research)
        #expect(Self.tally([.research: 3, .running: 6]).adopted(incumbent: .research) == .running)
    }

    /// **The maintainer's own honest case**: an agent told to plan that is in
    /// fact editing files.
    ///
    /// **Read the second edit carefully: it no longer wins for the reason this
    /// test was written for.** The original rule was pure counting, so the brief
    /// was worth one vote, two edits tied it and three beat it. Since
    /// `authoringPrecedenceFloor`, the second *observed* edit takes the desk
    /// outright and the arithmetic is never reached. The assertions are
    /// unchanged and still correct; only the mechanism behind the last one
    /// moved, and a test that passes for a different reason than its comment
    /// claims is worth strictly less than one that says so.
    ///
    /// The 1–1 tie in the middle is still genuine tie-breaking, and it is still
    /// what stops a brief furnishing a desk on its own. [I1]
    @Test func aBriefIsWorthExactlyOneRealCall() {
        var tally = WorkTally()
        tally.seedOpeningClaim(.coordinating)
        #expect(tally.adopted(incumbent: nil) == nil, "a brief alone furnished a desk")
        tally.record(.authoring)
        #expect(tally.count(.authoring) == 1 && tally.count(.coordinating) == 1)
        #expect(tally.adopted(incumbent: nil) == nil, "a 1–1 tie adopted something")
        tally.record(.authoring)
        #expect(tally.adopted(incumbent: nil) == .authoring)
    }

    /// **Nothing this function returns ever takes an object away.** [ADR-006
    /// §4b] Checked over every combination of a cleared tally and an incumbent,
    /// because "never cleared" is a property the caller relies on and the caller
    /// does not re-check it.
    @Test func noTallyEverReturnsNothingOverAnIncumbent() {
        for incumbent in WorkKind.allCases {
            #expect(WorkTally().adopted(incumbent: incumbent) == incumbent)
            for other in WorkKind.allCases {
                let adopted = Self.tally([other: 1]).adopted(incumbent: incumbent)
                #expect(adopted != nil, "\(other) over \(incumbent) cleared the desk")
            }
        }
    }

    /// **The worst churn the vote rule alone can produce, measured rather than
    /// argued.**
    ///
    /// The adoption floor came down to one call and the question that raises is
    /// how often a desk can change hands. Answer: the challenger has to double
    /// the incumbent's votes, and votes only accumulate within a turn, so each
    /// successive change costs twice the last: 128 calls alternating as
    /// adversarially as they can be arranged produce **seven** changes, not 128
    /// and not 64. The dwell floor is a second, looser bound on top of this; the
    /// arithmetic is what makes the room stable, and it would still be stable
    /// with no clock at all.
    @Test func theVoteRuleAloneBoundsChangesWithinATurnLogarithmically() {
        var tally = WorkTally()
        var incumbent: WorkKind?
        var changes = 0
        // Feed whichever kind would most like to take the desk next, which is
        // the fastest any real stream could possibly flip it.
        for _ in 0..<128 {
            tally.record(incumbent == .research ? .running : .research)
            let adopted = tally.adopted(incumbent: incumbent)
            if adopted != incumbent { changes += 1 }
            incumbent = adopted
        }
        #expect(changes == 7, "128 adversarial calls produced \(changes) desk changes")
        #expect(changes <= Int(log2(128.0)) + 1)
    }

    /// Vote order does not matter, which is what makes the desk a function of an
    /// agent's state rather than of the order its calls happened to interleave
    /// in. [I3]
    @Test func theSameVotesInAnyOrderGiveTheSameDesk() {
        var forwards = WorkTally()
        var backwards = WorkTally()
        let sequence: [WorkKind] = [.research, .running, .research, .coordinating, .research]
        for kind in sequence { forwards.record(kind) }
        for kind in sequence.reversed() { backwards.record(kind) }
        #expect(forwards == backwards)
        #expect(forwards.adopted(incumbent: nil) == backwards.adopted(incumbent: nil))
    }
}

/// The director's own rules: turn scoping, the dwell floor, and the two things
/// that must never happen: a desk cleared, or a desk restated.
///
/// Synthetic deltas rather than a fixture, deliberately and only here: these are
/// the shapes the corpus does not contain, plus the ones that need a clock
/// advanced by hand. The *measured* claims are all in `DeskObjectCorpusTests`,
/// against real captured payloads.
///
/// **This comment used to say `authoring` could not fire anywhere in the corpus
///: zero `Edit`, zero `Write`, zero `Grep`, zero `Glob` across every capture.
/// Half of that stopped being true on 2026-08-14.** `authoring-subagents` [#72]
/// holds two `Edit`s, two `Write`s and a `NotebookEdit`, and two of its agents
/// end on `authoring`, so the kind is measured now and not only constructed.
/// `Grep` and `Glob` are still absent and, per `fixtures/README.md`, cannot be
/// captured on this machine at all, so the synthetic cases below are still the
/// only coverage those two tool names have.
struct DeskObjectDirectorTests {

    static let cast = ["06", "07", "09", "10", "17", "19"]

    static func ref(_ agent: AgentID) -> AgentRef {
        AgentRef(project: "/p", session: "s", agent: agent)
    }

    static func call(_ id: String, _ tool: String) -> OpenCall {
        let start = Date(timeIntervalSince1970: 0)
        return OpenCall(
            toolUseID: id, toolName: tool, startedAt: start,
            deadline: start.addingTimeInterval(60))
    }

    static let epoch = Date(timeIntervalSince1970: 1_000_000)
    static func at(_ seconds: TimeInterval) -> Date { epoch.addingTimeInterval(seconds) }

    static func kinds(_ intents: [SpriteIntent]) -> [WorkKind] {
        intents.compactMap { if case let .setDeskObject(_, kind) = $0 { return kind } else { return nil } }
    }

    // MARK: The intent

    /// **Emitted only when the drawn kind actually changes**: `setNameplate`'s
    /// discipline, which is the whole of ADR-006 §5b's ask. Twenty `Read`s
    /// produce one intent, not twenty.
    @Test func aDeskObjectIsStatedOnceAndNotRestated() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.mainThread)
        director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)],
                       at: Self.at(0))
        var emitted: [WorkKind] = []
        for index in 0..<20 {
            emitted += Self.kinds(director.apply(
                [.callOpened(agent: agent, call: Self.call("t\(index)", "Read"))],
                at: Self.at(Double(index))))
        }
        #expect(emitted == [.research])
        #expect(director.deskObject(agent) == .research)
    }

    /// **The one kind the corpus cannot produce**, exercised here because it
    /// cannot be exercised there: `fixtures/` holds zero `Edit`, zero `Write`,
    /// zero `NotebookEdit`, zero `Grep` and zero `Glob`, so `authoring`: the
    /// laptop, the maintainer's own leading example: never fires in any replay
    /// in this suite. This is a unit test of the derivation and it is not a
    /// substitute for seeing it happen on captured data.
    @Test func editingFilesPutsALaptopOnTheDesk() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.mainThread)
        director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)],
                       at: Self.at(0))
        let intents = director.apply(
            [.callOpened(agent: agent, call: Self.call("t1", "Edit"))], at: Self.at(1))
        #expect(Self.kinds(intents) == [.authoring])
        // And the kind resolves to the authored laptop, whose silhouette steps
        // outward at the hinge: the feature no other desk object has.
        // Plain `!= nil` rather than `#require`: `bitmap(_:screen:)` gained a
        // defaulted argument when the screen state landed, and the `#require`
        // macro then reports the call as never-optional and fails the build
        // under `-warnings-as-errors`. The assertion is the same one.
        #expect(DeskWorkArt.bitmap(.authoring) != nil)
        #expect(DeskWorkArt.design(.authoring) == DeskWorkArt.laptop)
    }

    // MARK: §4a: the tally is scoped to a turn

    /// **The main thread's turn boundary is a tally boundary too.**
    ///
    /// ADR-006 §5d planned for the case where it is not: "subagents get
    /// per-turn tallies; the main agent gets one tally for its whole life",
    /// because the ADR was written before `turnChanged` existed. It exists, so
    /// the fallback is dead text: a `Stop` clears the main agent's votes exactly
    /// as `SubagentStop` clears a subagent's.
    @Test func theMainAgentsTallyIsScopedToItsTurnLikeEverybodyElses() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.mainThread)
        director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)],
                       at: Self.at(0))
        director.apply([.callOpened(agent: agent, call: Self.call("t1", "Read")),
                        .callOpened(agent: agent, call: Self.call("t2", "Read"))], at: Self.at(1))
        #expect(director.workTally(agent).count(.research) == 2)

        director.apply([.turnChanged(agent: agent, hasTurn: false)], at: Self.at(2))
        #expect(director.workTally(agent).isEmpty, "Stop did not clear the main agent's tally")
        // §4b: the votes went and the desk did not.
        #expect(director.deskObject(agent) == .research)
    }

    /// The subagent half of the same rule.
    @Test func aSubagentsTurnBoundaryClearsItsTallyAndLeavesItsDeskAlone() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.subagent("a1"))
        director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)],
                       at: Self.at(0))
        director.apply([.callOpened(agent: agent, call: Self.call("t1", "Bash"))], at: Self.at(1))
        #expect(director.deskObject(agent) == .running)

        director.apply([.dormancyChanged(agent: agent, isDormant: true)], at: Self.at(2))
        #expect(director.workTally(agent).isEmpty)
        #expect(director.deskObject(agent) == .running, "SubagentStop took the furniture away")
    }

    /// **Nothing ever takes an object off a desk**, over a whole life: work,
    /// turn end, revival, another turn. The only intent this channel has is
    /// `setDeskObject`, which carries a non-optional kind, so this is checked at
    /// the stream as well as at the state.
    @Test func noSequenceOfDeltasEverClearsADesk() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.subagent("a1"))
        var seen: [WorkKind] = []
        let script: [(TimeInterval, [WorldDelta])] = [
            (0, [.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)]),
            (1, [.callOpened(agent: agent, call: Self.call("t1", "Read"))]),
            (2, [.callClosed(agent: agent, toolUseID: "t1", toolName: "Read", outcome: .succeeded)]),
            (3, [.dormancyChanged(agent: agent, isDormant: true)]),
            (4, [.attentionChanged(agent: agent, attention: .permissionPrompt)]),
            (5, [.dormancyChanged(agent: agent, isDormant: false)]),
            (6, [.gateChanged(agent: agent, isGated: true)]),
            (7, [.gateChanged(agent: agent, isGated: false)]),
        ]
        for (seconds, deltas) in script {
            seen += Self.kinds(director.apply(deltas, at: Self.at(seconds)))
            #expect(director.deskObject(agent) == (seconds >= 1 ? .research : nil),
                    "at t=\(seconds)")
        }
        #expect(seen == [.research])
    }

    // MARK: §3: the opening claim

    /// **A dispatch description alone never furnishes a desk.** The description
    /// is inference about intent written before the agent acted; it is worth one
    /// vote and it is not worth the only vote. [ADR-006 §3 step 1]
    @Test func aDispatchDescriptionOnItsOwnLeavesTheDeskBare() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.subagent("a1"))
        director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)],
                       at: Self.at(0))
        let intents = director.apply(
            [.agentTasked(agent: agent, task: "Read the logs")], at: Self.at(1))
        #expect(Self.kinds(intents).isEmpty)
        #expect(director.deskObject(agent) == nil)
        #expect(director.workTally(agent).count(.research) == 1, "the claim was not counted")
        #expect(director.workTally(agent).observedVotes == 0)
    }

    /// **The claim is counted even though it arrives after the turn opened.**
    /// `agentTasked` is retroactive by construction: the dispatching
    /// `PostToolUse` carries the child's task and lands behind the
    /// `SubagentStart` that seated it, so a claim seeded only at the turn's
    /// opening event would be missed for every subagent in `fixtures/`.
    @Test func aTaskThatArrivesAfterTheTurnOpenedStillVotes() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.subagent("a1"))
        director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)],
                       at: Self.at(0))
        director.apply([.callOpened(agent: agent, call: Self.call("t1", "Bash"))], at: Self.at(1))
        director.apply([.agentTasked(agent: agent, task: "Read the logs")], at: Self.at(2))
        #expect(director.workTally(agent).count(.research) == 1)
        #expect(director.workTally(agent).count(.running) == 1)
        // And it is counted once, not once per frame the agent is touched in.
        director.apply([.callOpened(agent: agent, call: Self.call("t2", "Bash"))], at: Self.at(3))
        #expect(director.workTally(agent).count(.research) == 1)
    }

    /// The claim is re-seeded in the *next* turn, so a long-lived subagent's
    /// brief keeps its one vote per turn rather than one vote per life.
    @Test func theOpeningClaimIsSeededOncePerTurn() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.subagent("a1"))
        director.apply([.agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active)],
                       at: Self.at(0))
        director.apply([.agentTasked(agent: agent, task: "Read the logs")], at: Self.at(1))
        director.apply([.dormancyChanged(agent: agent, isDormant: true)], at: Self.at(2))
        #expect(director.workTally(agent).isEmpty)
        director.apply([.dormancyChanged(agent: agent, isDormant: false)], at: Self.at(3))
        #expect(director.workTally(agent).count(.research) == 1, "the claim was not re-seeded")
    }

    // MARK: §4c: the dwell floor

    /// **A desk may be furnished the instant the votes allow it and may only be
    /// *changed* after the floor.** The asymmetry is the rule: appearing is the
    /// room learning something; changing is the room correcting itself.
    @Test func aChangeInsideTheDwellFloorIsRefusedAndAnAppearanceIsNot() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.mainThread)
        director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)],
                       at: Self.at(0))
        // Appearance: no wait at all.
        #expect(Self.kinds(director.apply(
            [.callOpened(agent: agent, call: Self.call("t1", "Read"))], at: Self.at(0))) == [.research])
        // A change earned one second later, well inside the four-second floor.
        var intents = director.apply(
            [.callOpened(agent: agent, call: Self.call("t2", "Bash")),
             .callOpened(agent: agent, call: Self.call("t3", "Bash"))], at: Self.at(1))
        #expect(Self.kinds(intents).isEmpty, "the desk changed inside the dwell floor")
        #expect(director.deskObject(agent) == .research)
        // And it lands once the floor expires, on a frame carrying **no deltas
        // at all**, which is the frame that actually happens next, since votes
        // only arrive on events and this agent may not produce another one.
        intents = director.apply([], at: Self.at(3.9))
        #expect(Self.kinds(intents).isEmpty)
        intents = director.apply([], at: Self.at(4.0))
        #expect(Self.kinds(intents) == [.running], "the deferred change never landed")
        #expect(director.deskObject(agent) == .running)
    }

    /// A refused change that stops being earned is dropped rather than
    /// remembered: the flag is a deferral, not a queue.
    @Test func aDeferredChangeThatStopsBeingEarnedIsForgotten() {
        var director = SceneDirector(variantIDs: Self.cast)
        let agent = Self.ref(.mainThread)
        director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)],
                       at: Self.at(0))
        director.apply([.callOpened(agent: agent, call: Self.call("t1", "Read"))], at: Self.at(0))
        director.apply([.callOpened(agent: agent, call: Self.call("t2", "Bash")),
                        .callOpened(agent: agent, call: Self.call("t3", "Bash"))], at: Self.at(1))
        #expect(director.deskObject(agent) == .research)
        // The turn ends before the floor expires. The votes go with it, so the
        // change is no longer earned and the desk keeps what it had.
        director.apply([.turnChanged(agent: agent, hasTurn: false)], at: Self.at(2))
        let intents = director.apply([], at: Self.at(10))
        #expect(Self.kinds(intents).isEmpty, "a change nothing earned any more still landed")
        #expect(director.deskObject(agent) == .research)
    }

    /// **Two characters, one clock**: the floor is per character, so a busy
    /// neighbour cannot delay or hurry anybody's desk.
    @Test func theDwellFloorIsPerCharacterAndNotPerRoom() {
        var director = SceneDirector(variantIDs: Self.cast)
        let first = Self.ref(.mainThread)
        let second = Self.ref(.subagent("a1"))
        director.apply([
            .agentAppeared(agent: first, agentType: nil, lifecycle: .active),
            .agentAppeared(agent: second, agentType: "Explore", lifecycle: .active),
        ], at: Self.at(0))
        director.apply([.callOpened(agent: first, call: Self.call("t1", "Read"))], at: Self.at(0))
        // The second character's first object is an appearance, not a change,
        // even though the first character set one a moment ago.
        let intents = director.apply(
            [.callOpened(agent: second, call: Self.call("t2", "Bash"))], at: Self.at(0.1))
        #expect(Self.kinds(intents) == [.running])
        #expect(director.deskObject(first) == .research)
        #expect(director.deskObject(second) == .running)
    }
}

/// What actually reaches the screen: where the object stands, what it is drawn
/// from, and that its node is never rebuilt.
///
/// Mixed suite like `RoomSceneTests` and `ThemeSceneTests`: the claims about
/// *placement arithmetic* are checked against `RoomLayout` and the manifest and
/// run on any checkout; the claims about *what is on screen* need the pack and
/// carry the art gate.
@MainActor
struct DeskObjectSceneTests {

    static func cast(_ count: Int) -> [AgentRef] {
        (0..<count).map { index in
            AgentRef(
                project: "/p", session: "s",
                agent: index == 0 ? .mainThread : .subagent(String(format: "a%016x", index)))
        }
    }

    /// A scene and a director, with `count` characters already seated and each
    /// one's desk furnished with `kind`.
    static func furnished(
        manifest: Manifest, themeID: String? = nil, count: Int, kind: WorkKind
    ) -> (scene: RoomScene, director: SceneDirector) {
        let scene = RoomScene(manifest: manifest, themeID: themeID)
        scene.setViewport(CGSize(width: 720, height: 400))
        var director = SceneDirector(manifest: manifest, themeID: themeID)
        let agents = cast(count)
        let tool = ["Edit", "Read", "Bash", "TodoWrite"][
            [WorkKind.authoring, .research, .running, .coordinating].firstIndex(of: kind)!]
        var deltas: [WorldDelta] = agents.map {
            .agentAppeared(agent: $0, agentType: nil, lifecycle: .active)
        }
        for (index, agent) in agents.enumerated() {
            let start = Date(timeIntervalSince1970: 0)
            deltas.append(.callOpened(agent: agent, call: OpenCall(
                toolUseID: "t\(index)", toolName: tool, startedAt: start,
                deadline: start.addingTimeInterval(60))))
        }
        scene.apply(director.apply(deltas, at: Date(timeIntervalSince1970: 1)))
        return (scene, director)
    }

    // MARK: Placement [ADR-006 §2c]

    /// **The near edge, the far edge and the surface, checked in scene pixels
    /// against every seat of every theme.**
    ///
    /// The three things §2c's placement rule actually promises:
    ///
    /// - the object's **left edge** is at `seat + 16`, which is the first column
    ///   strictly outside a seated character's own canvas, so it cannot cover a
    ///   head at any height, and it cannot reach the character it belongs to;
    /// - its **right edge** stays inside its own desk's footprint, so it stands
    ///   on the desk rather than floating past it, and therefore nowhere near
    ///   the next seat's station prop, which starts a further four pixels out;
    /// - its **bottom edge** is on the desk's measured surface, which is 24 px
    ///   above the floor in five themes and 36 in two.
    ///
    /// **And that a camera-facing seat's desk carries nothing at all.** [ADR-008
    /// §5] This test asserted `drawn.count == 4`: every seated character has an
    /// object, and that is no longer true, deliberately: the desk at a
    /// camera-facing seat stands between the occupant and the viewer, so an
    /// object on it faces upstage and there is no rear view of a screen anywhere
    /// in the catalogue. Silence is the answer, and the count is now asserted
    /// against the seats whose facing shows one, with the empty ones checked
    /// **by name** rather than by subtraction: a count that happened to match
    /// while the wrong seats were bare would pass either way.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyDeskObjectStandsOnItsOwnDeskAndOutsideItsCharactersColumn() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let nearEdgeOffset = RoomScene.deskObjectNearEdgeX(manifest: manifest)
        let showing = (0..<4).filter { layout.seatFacing($0).showsDeskTopObject }
        #expect(!showing.isEmpty && showing.count < 4, "the sweep tests neither branch")
        var checked = 0

        for themeID in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            let room = manifest.room(theme: themeID)
            let desk = try #require(room.prop("desk"))
            let surfaceHeight = Double(desk.surfaceY ?? desk.contentBox.height)
            let metrics = SceneFixtures.seatMetrics(manifest, theme: themeID)
            for kind in WorkKind.allCases {
                let (scene, director) = Self.furnished(
                    manifest: manifest, themeID: themeID, count: 4, kind: kind)
                let drawn = scene.deskObjectsForTesting()
                let seats = Set(drawn.keys.compactMap { director.seats[$0] })
                #expect(seats == Set(showing), Comment(rawValue:
                    "\(themeID ?? "room")/\(kind): objects on seats \(seats.sorted()), "
                    + "expected \(showing)"))
                for (agent, object) in drawn {
                    let seat = try #require(director.seats[agent])
                    let seatX = layout.seatPosition(seat).x
                    // The node is anchored on its content box's bottom-centre,
                    // so the ink's own edges are the position ± half the box.
                    let width = Self.contentWidth(of: kind, manifest: manifest, themeID: themeID)
                    let left = object.x - width / 2
                    let right = object.x + width / 2
                    let deskX = layout.deskPosition(seat, metrics: metrics).x
                    let deskLeft = deskX - Double(desk.contentBox.width) / 2
                    let deskRight = deskX + Double(desk.contentBox.width) / 2
                    // **On a pod the rule is the slot, not the near edge.**
                    // [ADR-009] A pod's desktop is two 32px slots on a 64px slab;
                    // the theme's screen rig takes the left one and this takes the
                    // right, so the object is *centred* on `deskX + slot` rather
                    // than left-aligned to the body's canvas edge.
                    //
                    // The near-edge rule is not weakened by that, it is
                    // inapplicable: ADR-006 §2c pushes the object clear of the
                    // body so it cannot cover a head, and only a camera-facing
                    // seat could be covered that way, which draws no object at
                    // all. Every seat that reaches this line is away-facing, so
                    // its desk is genuinely upstage and `rowDepth` draws the body
                    // over the object at any x. What is asserted instead is the
                    // property that still bites: the object stands wholly on its
                    // own desk.
                    if metrics.isDeskPod {
                        #expect(object.x == deskX + layout.podSlotOffsetX(metrics: metrics),
                                Comment(rawValue:
                            "\(themeID ?? "room")/\(kind) seat \(seat): not in the pod's"
                            + " right kit slot"))
                        #expect(left >= deskLeft, Comment(rawValue:
                            "\(themeID ?? "room")/\(kind) seat \(seat): hangs off the left"
                            + " of its own desk"))
                    } else {
                        #expect(left == seatX + nearEdgeOffset, Comment(rawValue:
                            "\(themeID ?? "room")/\(kind) seat \(seat): near edge at \(left - seatX)"))
                    }
                    #expect(right <= deskRight, Comment(rawValue:
                        "\(themeID ?? "room")/\(kind) seat \(seat): overhangs its own desk"))
                    #expect(object.y == layout.deskSurfacePosition(
                        seat: seat, surfaceHeightAboveFloor: surfaceHeight,
                        metrics: metrics).y, Comment(rawValue:
                        "\(themeID ?? "room")/\(kind) seat \(seat): not on the surface"))
                    checked += 1
                }
            }
        }
        #expect(checked == 7 * 4 * showing.count,
                "the sweep did not cover every theme and kind")
    }

    /// The ink width of one kind's art: the authored bitmap's own width for
    /// every kind that names no role, and the manifest's content box for any
    /// kind that names one.
    ///
    /// **This used to answer `DeskMonitorArt.canvasWidth` for every authored
    /// kind**, which was true while the monitor was the only authored object and
    /// silently wrong the moment it was not: it mis-measured the 26 px laptop
    /// and paper stack by exactly 3 px and reported it as a placement bug.
    static func contentWidth(of kind: WorkKind, manifest: Manifest, themeID: String?) -> Double {
        guard let role = kind.propRole else {
            return Double(DeskWorkArt.bitmap(kind)?.width ?? DeskMonitorArt.canvasWidth)
        }
        let room = manifest.room(theme: themeID)
        let prop = room.prop(role) ?? manifest.room.prop(role)
        return Double(prop?.contentBox.width ?? 0)
    }

    /// **A desk object is drawn in front of the desk it stands on**, whichever
    /// way that desk sorted: including `library` and `mission_control`, whose
    /// desks go *behind* the body because they are taller than the shortest head.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aDeskObjectSortsInFrontOfItsOwnDesk() throws {
        let manifest = try SceneFixtures.manifest()
        for themeID in [nil, "library", "mission_control"] {
            let (scene, director) = Self.furnished(
                manifest: manifest, themeID: themeID, count: 2, kind: .running)
            for (agent, object) in scene.deskObjectsForTesting() {
                let seat = try #require(director.seats[agent])
                let desk = try #require(
                    scene.furnitureForTesting(seat: seat)
                        .first { $0.path == manifest.room(theme: themeID).prop("desk")?.file })
                #expect(object.z > desk.z, "\(themeID ?? "room"): the object sank into its desk")
            }
        }
    }

    /// **Every theme draws every kind**, including the six that declare no
    /// desk-top roles of their own. Without the fallback to the root `room`'s
    /// declarations, three of the four kinds would silently draw nothing in
    /// every themed room, which is every room the app actually opens.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyThemeDrawsEveryKindEvenThoughNoneDeclaresTheRoles() throws {
        let manifest = try SceneFixtures.manifest()
        for themeID in manifest.themes.orderedIDs {
            let room = manifest.room(theme: themeID)
            for kind in WorkKind.allCases {
                if let role = kind.propRole {
                    #expect(room.prop(role) == nil, Comment(rawValue:
                        "\(themeID) now declares \(role) itself; this test's premise is gone"))
                }
                // **Enough agents to fill a seat that shows an object.** [ADR-008]
                // This seated one character and asserted one object. Seat 0
                // faces the camera and camera-facing desks carry nothing, so a
                // room of one draws none: correctly. The claim being made here
                // is about the *role fallback*, not about seat 0, so the cast is
                // grown until a seat that shows an object is occupied and the
                // count is asserted against that seat.
                let layout = RoomLayout()
                let count = try #require(
                    (1...layout.seatCapacity).first { seats in
                        (0..<seats).contains { layout.seatFacing($0).showsDeskTopObject }
                    })
                let (scene, _) = Self.furnished(
                    manifest: manifest, themeID: themeID, count: count, kind: kind)
                let expected = (0..<count)
                    .filter { layout.seatFacing($0).showsDeskTopObject }.count
                #expect(scene.deskObjectsForTesting().count == expected,
                        "\(themeID)/\(kind) drew nothing")
            }
        }
    }

    // MARK: The node

    /// **A bare desk is a hidden node, not a missing one.** Every seated
    /// character has exactly one desk-object node from the moment it is drawn,
    /// so the change that furnishes a desk is a texture and a flag rather than a
    /// node appearing in the tree.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aCharacterWhoseWorkTheRoomCannotNameHasAHiddenNodeAndABareDesk() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 720, height: 400))
        var director = SceneDirector(manifest: manifest)
        let agents = Self.cast(3)
        scene.apply(director.apply(agents.map {
            .agentAppeared(agent: $0, agentType: nil, lifecycle: .active)
        }, at: Date(timeIntervalSince1970: 0)))

        #expect(scene.deskObjectNodesForTesting.count == 3, "a seated character has no node")
        #expect(scene.deskObjectsForTesting().isEmpty, "something was drawn with no evidence for it")
        #expect(scene.deskObjectNodesForTesting.values.allSatisfy { $0.isHidden })
    }

    /// **A kind that changes swaps a texture and never a node**, which is
    /// ADR-002 §6 rule 1's discipline applied to the one slot rule 1 does not
    /// cover. `noPropNodeIsEverRebuiltAcrossAnyFixtureReplay` guards the room's
    /// own furniture and cannot see this, because a desk object is per-character
    /// furniture and lives outside `propNodes` exactly as a station's does.
    ///
    /// **The swap count is now cross-checked rather than pinned**, and the
    /// reason is ADR-006 §12: the drawn texture is a function of *two* facts,
    /// the kind and the screen state, and only the first of them used to exist.
    /// It was `== 2` (the corpus's two kind replacements) and 45 of the 47
    /// swaps it now sees are turn boundaries turning a screen off or on, which
    /// is the feature working rather than the invariant breaking. A restated
    /// constant would have been a number nobody could derive again, so the
    /// expectation is *recomputed from the intent stream* on the same per-frame
    /// granularity the observation uses, and the two have to agree exactly.
    @Test(.enabled(if: SceneArt.isAvailable))
    func noDeskObjectNodeIsEverRebuiltAcrossAnyFixtureReplay() async throws {
        let manifest = try SceneFixtures.manifest()
        var everSwapped = 0
        var predicted = 0
        var replacements = 0
        var screenChanges = 0
        for name in try DeskObjectCorpusTests.fixtureNames() {
            let scene = RoomScene(manifest: manifest)
            scene.setViewport(CGSize(width: 720, height: 400))
            var director = SceneDirector(manifest: manifest)
            var identity: [AgentRef: ObjectIdentifier] = [:]
            var textures: [AgentRef: ObjectIdentifier?] = [:]
            // What the intents say each desk should be drawing: the kind, and
            // the screen state, which starts lit for every character that walks
            // in. `nil` kind is the bare desk, which draws no texture at all.
            var drawn: [AgentRef: (kind: WorkKind?, screen: DeskScreen)] = [:]
            var seen: [AgentRef: String] = [:]
            /// Agents whose seat draws no desk object at all.
            var bare: [AgentRef: Bool] = [:]

            var time = 0.0
            for (at, deltas) in try await SceneFixtures.timedBatchedDeltas(name) {
                let intents = director.apply(deltas, at: at)
                for intent in intents {
                    switch intent {
                    case let .spawnCharacter(agent, _, _, seat, _, _):
                        // **A camera-facing seat's desk draws nothing at all**,
                        // so its texture never changes and it must not be
                        // predicted to. [ADR-008 §5] Recording the seat here is
                        // the whole of the change: the prediction is still a
                        // pure function of the intent stream, it just knows
                        // which desks are in the picture.
                        drawn[agent] = (nil, .lit)
                        bare[agent] = !RoomLayout().seatFacing(seat).showsDeskTopObject
                    case let .setDeskObject(agent, kind):
                        if drawn[agent]?.kind != nil, bare[agent] != true { replacements += 1 }
                        drawn[agent] = (kind, drawn[agent]?.screen ?? .lit)
                    case let .setDeskScreen(agent, screen):
                        if drawn[agent]?.kind != nil, bare[agent] != true { screenChanges += 1 }
                        drawn[agent] = (drawn[agent]?.kind, screen)
                    default: break
                    }
                }
                scene.apply(intents)
                time += 1.0 / 60.0
                scene.advance(to: time)
                for (agent, node) in scene.deskObjectNodesForTesting {
                    let id = ObjectIdentifier(node)
                    if let known = identity[agent] {
                        #expect(known == id, "\(name): a desk-object node was rebuilt")
                    }
                    identity[agent] = id
                    let texture = node.texture.map(ObjectIdentifier.init)
                    if let known = textures[agent], known != texture, known != nil {
                        everSwapped += 1
                    }
                    textures[agent] = texture
                    // The same observation over the intents: the texture is a
                    // pure function of (kind, screen), so it changes exactly
                    // when that pair does on a desk that already had something
                    // on it.
                    if let state = drawn[agent], let kind = state.kind, bare[agent] != true {
                        let key = kind.textureKey(screen: state.screen)
                        if let known = seen[agent], known != key { predicted += 1 }
                        seen[agent] = key
                    }
                }
            }
        }
        print("""
            desk-object texture swaps over the corpus: \(everSwapped): \
            \(replacements) kind replacements, \(screenChanges) screen changes
            """)
        #expect(everSwapped == predicted,
                "the scene swapped \(everSwapped) textures where the intents say \(predicted)")
        // Two until the eighteenth capture; `authoring-subagents` adds two more,
        // both of them a character that changed what it was doing inside one
        // real session. The assertion above is the one that matters and it did
        // not move: the scene swapped exactly the textures the intents predicted.
        #expect(replacements == 4, "the corpus's four kind replacements are gone")
        #expect(screenChanges > 0, "no turn boundary ever reached a furnished desk")
        #expect(everSwapped > replacements, "the screen never reached the node")
    }

    /// The node goes when the character does, so a departed agent leaves nothing
    /// standing on a desk somebody else is about to sit at. [I4]
    @Test(.enabled(if: SceneArt.isAvailable))
    func aDepartedCharacterTakesItsDeskObjectWithIt() async throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 720, height: 400))
        var director = SceneDirector(manifest: manifest)
        var time = 0.0
        for (at, deltas) in try await SceneFixtures.timedBatchedDeltas("four-subagents") {
            scene.apply(director.apply(deltas, at: at))
            time += 1.0 / 60.0
            scene.advance(to: time)
        }
        #expect(!scene.deskObjectNodesForTesting.isEmpty, "the replay furnished nothing at all")
        // Run the exit animations out: `four-subagents` ends in a `SessionEnd`,
        // which departs everybody, and the node is retired when the character is
        // actually removed rather than when the intent arrives.
        for _ in 0..<600 {
            time += 1.0 / 60.0
            scene.advance(to: time)
        }
        #expect(scene.deskObjectNodesForTesting.isEmpty, "a desk object outlived its character")
    }
}
