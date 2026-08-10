import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **The corpus measurement, and it is the central test of this change.**
/// [ADR-006 §3a]
///
/// Everything else here checks a rule in isolation. This one replays all
/// seventeen captures through the real `WorldModel` and the real `SceneDirector`
/// and asks the two questions the design can only be judged on: *how many
/// characters end up with something on the desk*, and *how often does what is on
/// a desk change*.
///
/// It needs no art — it reads the director, not the scene — so it runs on a
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
    /// clock. **The fixture's clock, not the wall clock** — the dwell floor is
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
    /// ADR-006 §3a predicted 5 of 27 with the threshold it proposed —
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
                let kind = outcome.adopted[agent]?.rawValue ?? "—"
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

        #expect(agents == 27, "the corpus grew or shrank; every number below is measured off it")
        #expect(furnished == 26)
        #expect(agents - furnished == 1)
        #expect(byKind == [.running: 13, .research: 9, .coordinating: 4])
    }

    /// **Abstention is still reachable, and it is reachable for exactly one
    /// reason: no evidence at all.** [I1]
    ///
    /// A gate that admits everything is not a gate. With the floor at one
    /// observed call the *only* way to keep a bare desk is to make no call this
    /// app can classify — and one character in the corpus does exactly that,
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

    // MARK: Stability — the failure mode that matters now

    /// **How often what is on a desk changes, over the whole corpus.**
    ///
    /// ADR-006 §3a measured 32 changes for the naive argmax rule and 5 for its
    /// own gate. The shipped rule is looser than the gate, so this is the number
    /// that has to be looked at rather than assumed — a prop that changes every
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

        // 28 sets for 26 furnished characters: 26 first appearances and **two**
        // replacements, both of them a main agent that changed what it was doing
        // between turns. ADR-006 §3a measured 32 changes for the naive argmax
        // rule and 5 for the threshold it proposed; this is looser than the
        // proposal and still nowhere near the naive rule, because the
        // replacement margin and the turn scoping — not the floor — are what
        // were doing the stabilising.
        #expect(totalChanges == 28)
        #expect(replacements == 2)
        #expect(worstPerCharacter == 2, "some character redecorated more than once")
        // The measured floor is an order of magnitude above the enforced one.
        // The **enforced** bound is what protects a workload the corpus does not
        // contain: at most one change per character per `deskObjectDwell`, so
        // 15 a minute in the worst case the code can produce, against ADR-005's
        // measured median tool call of 23 ms.
        #expect(tightestGap > 50)
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
    /// `ToolBadge.badge(forTool:)` is itself total — its `default` arm is
    /// `questionMark` — so totality here means every tool name that exists or
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

    /// The mapping itself, spelled out — ADR-006 §1's evidence table read back
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

    /// Every kind but one is drawn from a manifest role, and the exception is
    /// the one the pack could not supply at the width bound.
    @Test func threeKindsNameAManifestRoleAndTheFourthIsAuthored() {
        #expect(WorkKind.authoring.propRole == "laptop")
        #expect(WorkKind.research.propRole == "papers")
        #expect(WorkKind.coordinating.propRole == "pad")
        #expect(WorkKind.running.propRole == nil, "running gained a pack single; check the width bound")
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

/// The lexicon — the only free text this app classifies. [ADR-006 §6c rule 5]
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
    /// looks — a lower-case entry would be dead text that never matched anything
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
    /// "Read ... .txt" dispatch), one `running` ("Touch a file via bash" — the
    /// only word in it this lexicon knows is `BASH`), and two abstentions
    /// ("Touch file s1"/"s2", which hold no keyword at all). Asserted by name so
    /// that a lexicon edit has to look at what it did to the real data.
    @Test func everyDispatchDescriptionInTheCorpusClassifiesOrAbstains() async throws {
        var classified: [String: String] = [:]
        for name in try DeskObjectCorpusTests.fixtureNames() {
            for batch in try await SceneFixtures.batchedDeltas(name) {
                for delta in batch {
                    guard case let .agentTasked(_, task) = delta else { continue }
                    classified[task] = WorkKind(dispatchDescription: task)?.rawValue ?? "—"
                }
            }
        }
        print("ADR-006 lexicon over the corpus's dispatch descriptions:")
        for (task, kind) in classified.sorted(by: { $0.key < $1.key }) {
            print("  \(kind.padding(toLength: 13, withPad: " ", startingAt: 0)) \(task)")
        }
        #expect(classified.count == 10, "the corpus's descriptions changed: \(classified.keys.sorted())")
        #expect(classified["Touch file s1"] == "—")
        #expect(classified["Touch file s2"] == "—")
        #expect(classified["Touch a file via bash"] == "running")
        #expect(classified["Read one.txt sleep"] == "research")
        #expect(classified["Read alpha.txt and sleep"] == "research")
        #expect(classified["Read delta/epsilon, sleep, reread alpha"] == "research")
    }

    /// **A description that names two kinds contributes nothing.** The
    /// ambiguity half of rule 5, which the corpus has no example of, so it is
    /// checked against constructed strings — a pure function's own unit test,
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
    /// by a hyphen does not — the honest edge of a whole-word lexicon.
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
    /// ahead. No recency and no ordering dependence — the properties ADR-003 §5
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
    /// desk — which is what stops the first tool call of a new turn rearranging
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
    /// fact editing files. The brief is worth one vote, so two edits tie it and
    /// three beat it — and because the desk is bare at the start, the first edit
    /// already furnishes it.
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
    /// successive change costs twice the last — 128 calls alternating as
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
/// that must never happen — a desk cleared, or a desk restated.
///
/// Synthetic deltas rather than a fixture, deliberately and only here: these are
/// the shapes the corpus does not contain (`authoring` cannot fire anywhere in
/// it — zero `Edit`, zero `Write`, zero `Grep`, zero `Glob` across all seventeen
/// captures) plus the ones that need a clock advanced by hand. The *measured*
/// claims are all in `DeskObjectCorpusTests`, against real captured payloads.
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

    /// **Emitted only when the drawn kind actually changes** — `setNameplate`'s
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
    /// zero `NotebookEdit`, zero `Grep` and zero `Glob`, so `authoring` — the
    /// laptop, the maintainer's own leading example — never fires in any replay
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
        #expect(WorkKind.authoring.propRole == "laptop")
    }

    // MARK: §4a — the tally is scoped to a turn

    /// **The main thread's turn boundary is a tally boundary too.**
    ///
    /// ADR-006 §5d planned for the case where it is not — "subagents get
    /// per-turn tallies; the main agent gets one tally for its whole life" —
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

    // MARK: §3 — the opening claim

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
    /// `agentTasked` is retroactive by construction — the dispatching
    /// `PostToolUse` carries the child's task and lands behind the
    /// `SubagentStart` that seated it — so a claim seeded only at the turn's
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

    // MARK: §4c — the dwell floor

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
        // at all** — which is the frame that actually happens next, since votes
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
    ///   strictly outside a seated character's own canvas — so it cannot cover a
    ///   head at any height, and it cannot reach the character it belongs to;
    /// - its **right edge** stays inside its own desk's footprint, so it stands
    ///   on the desk rather than floating past it — and therefore nowhere near
    ///   the next seat's station prop, which starts a further four pixels out;
    /// - its **bottom edge** is on the desk's measured surface, which is 24 px
    ///   above the floor in five themes and 36 in two.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyDeskObjectStandsOnItsOwnDeskAndOutsideItsCharactersColumn() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let nearEdgeOffset = RoomScene.deskObjectNearEdgeX(manifest: manifest)
        var checked = 0

        for themeID in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            let room = manifest.room(theme: themeID)
            let desk = try #require(room.prop("desk"))
            let surfaceHeight = Double(desk.surfaceY ?? desk.contentBox.height)
            for kind in WorkKind.allCases {
                let (scene, director) = Self.furnished(
                    manifest: manifest, themeID: themeID, count: 4, kind: kind)
                let drawn = scene.deskObjectsForTesting()
                #expect(drawn.count == 4, "\(themeID ?? "room")/\(kind): not every desk was furnished")
                for (agent, object) in drawn {
                    let seat = try #require(director.seats[agent])
                    let seatX = layout.seatPosition(seat).x
                    // The node is anchored on its content box's bottom-centre,
                    // so the ink's own edges are the position ± half the box.
                    let width = Self.contentWidth(of: kind, manifest: manifest, themeID: themeID)
                    let left = object.x - width / 2
                    let right = object.x + width / 2
                    let deskRight = layout.deskPosition(seat).x
                        + Double(desk.contentBox.width) / 2
                    #expect(left == seatX + nearEdgeOffset, Comment(rawValue:
                        "\(themeID ?? "room")/\(kind) seat \(seat): near edge at \(left - seatX)"))
                    #expect(right <= deskRight, Comment(rawValue:
                        "\(themeID ?? "room")/\(kind) seat \(seat): overhangs its own desk"))
                    #expect(object.y == layout.deskSurfacePosition(
                        seat: seat, surfaceHeightAboveFloor: surfaceHeight).y, Comment(rawValue:
                        "\(themeID ?? "room")/\(kind) seat \(seat): not on the surface"))
                    checked += 1
                }
            }
        }
        #expect(checked == 7 * 4 * 4, "the sweep did not cover every theme and kind")
    }

    /// The ink width of one kind's art, from the manifest for the three sourced
    /// kinds and from the authored bitmap for the fourth.
    static func contentWidth(of kind: WorkKind, manifest: Manifest, themeID: String?) -> Double {
        guard let role = kind.propRole else { return Double(DeskMonitorArt.canvasWidth) }
        let room = manifest.room(theme: themeID)
        let prop = room.prop(role) ?? manifest.room.prop(role)
        return Double(prop?.contentBox.width ?? 0)
    }

    /// **A desk object is drawn in front of the desk it stands on**, whichever
    /// way that desk sorted — including `library` and `mission_control`, whose
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
    /// every themed room — which is every room the app actually opens.
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
                let (scene, _) = Self.furnished(
                    manifest: manifest, themeID: themeID, count: 1, kind: kind)
                #expect(scene.deskObjectsForTesting().count == 1,
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
    @Test(.enabled(if: SceneArt.isAvailable))
    func noDeskObjectNodeIsEverRebuiltAcrossAnyFixtureReplay() async throws {
        let manifest = try SceneFixtures.manifest()
        var everSwapped = 0
        for name in try DeskObjectCorpusTests.fixtureNames() {
            let scene = RoomScene(manifest: manifest)
            scene.setViewport(CGSize(width: 720, height: 400))
            var director = SceneDirector(manifest: manifest)
            var identity: [AgentRef: ObjectIdentifier] = [:]
            var textures: [AgentRef: ObjectIdentifier?] = [:]

            var time = 0.0
            for (at, deltas) in try await SceneFixtures.timedBatchedDeltas(name) {
                scene.apply(director.apply(deltas, at: at))
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
                }
            }
        }
        // The corpus's two replacements, seen from the other side: a change of
        // kind is a texture swap on a node that was already there.
        #expect(everSwapped == 2, "the texture-swap path was never exercised")
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
