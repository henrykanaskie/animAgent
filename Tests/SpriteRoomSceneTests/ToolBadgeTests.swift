import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// The mapping table from `docs/03-EVENT-MODEL.md`, and the determinism that
/// makes criterion 6 hold.
struct ToolBadgeTests {

    @Test(arguments: [
        ("Edit", ToolBadge.document), ("Write", .document), ("NotebookEdit", .document),
        ("Read", .magnifier), ("Glob", .magnifier), ("Grep", .magnifier),
        ("ToolSearch", .magnifier),
        ("Bash", .terminal), ("BashOutput", .terminal), ("KillShell", .terminal),
        ("WebSearch", .globe), ("WebFetch", .globe),
        ("TodoWrite", .checklist), ("Agent", .checklist), ("SendMessage", .checklist),
    ])
    func theTableMapsAsWritten(tool: String, badge: ToolBadge) {
        #expect(ToolBadge.badge(forTool: tool) == badge)
    }

    /// **What the fixtures actually contain, asked of the fixtures.**
    ///
    /// The table used to be a list somebody wrote down, and the way it was found
    /// wanting was a maintainer reading a live capture's log line — `unmapped
    /// tools: Monitor×1, SendMessage×2, ToolSearch×5`. That is the right
    /// evidence and the wrong place for it to live, because nothing fails when a
    /// capture grows a tool the table has never heard of.
    ///
    /// So the inventory is taken from `fixtures/` at test time and compared
    /// against one hand-written set: the tools we have looked at and left at the
    /// question mark **on purpose**. A new tool in a new capture lands in
    /// neither the mapped set nor that list and fails here, which forces the
    /// same decision to be made deliberately rather than absorbed as another
    /// question mark on screen.
    ///
    /// Reads the captures; writes nothing. Needs no art.
    @Test func everyToolInEveryFixtureIsEitherMappedOrDeliberatelyNot() throws {
        let observed = try Self.toolNamesInFixtures()
        #expect(observed.count >= 6, "the fixture walk found \(observed.count) tools — too few")

        let unmapped = observed.filter(ToolBadge.isUnmapped).sorted()
        let mapped = observed.subtracting(unmapped).sorted()
        print("TOOL BADGE COVERAGE over fixtures/: "
              + mapped.map { "\($0)→\(ToolBadge.badge(forTool: $0).manifestKey)" }
                .joined(separator: ", ")
              + " | question_mark by decision: \(unmapped.joined(separator: ", "))")

        // `Monitor` carries either a shell `command` or a `ws` WebSocket and the
        // name does not say which, so no bucket is true of every call of it.
        // The question mark asserts only "we do not recognise this", which is
        // the one statement that stays true either way. [I1]
        #expect(unmapped == ["Monitor"], Comment(rawValue:
            "fixtures hold unmapped tools \(unmapped) — map the ones that have an honest home"
            + " and add the ones that do not to this list, with the reason"))
    }

    /// Every distinct `tool_name` in every capture, from the decoded events
    /// rather than by grepping the JSON — a tool that only ever appears in a
    /// `PostToolBatch` entry is still a tool that was badged.
    static func toolNamesInFixtures() throws -> Set<String> {
        let directory = SceneFixtures.repositoryRoot.appending(path: "fixtures")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var tools: Set<String> = []
        for name in names.sorted() where name.hasSuffix(".jsonl") {
            for entry in try HookLog.load(contentsOf: directory.appending(path: name)) {
                switch entry.event?.kind {
                case let .preToolUse(_, toolName, _):
                    tools.insert(toolName)
                case let .postToolUse(_, toolName, _), let .postToolUseFailure(_, toolName, _):
                    if let toolName { tools.insert(toolName) }
                case let .postToolBatch(calls):
                    for call in calls { if let name = call.toolName { tools.insert(name) } }
                default:
                    break
                }
            }
        }
        return tools
    }

    @Test func everyMCPToolIsThePlug() {
        #expect(ToolBadge.badge(forTool: "mcp__slack__send") == .plug)
        #expect(ToolBadge.badge(forTool: "mcp__anything_at_all") == .plug)
    }

    /// Never invent a badge for a tool you do not recognise. The question mark
    /// is honest; a guess is not. [I1]
    @Test func anythingUnrecognisedIsTheQuestionMark() {
        #expect(ToolBadge.badge(forTool: "SomeToolShippedTomorrow") == .questionMark)
        #expect(ToolBadge.badge(forTool: "") == .questionMark)
        #expect(ToolBadge.isUnmapped("SomeToolShippedTomorrow"))
        #expect(!ToolBadge.isUnmapped("Bash"))
    }

    @Test func ordinalsFollowTheTableOrder() {
        #expect(ToolBadge.document < ToolBadge.magnifier)
        #expect(ToolBadge.magnifier < ToolBadge.terminal)
        #expect(ToolBadge.terminal < ToolBadge.globe)
        #expect(ToolBadge.globe < ToolBadge.checklist)
        #expect(ToolBadge.checklist < ToolBadge.plug)
        #expect(ToolBadge.plug < ToolBadge.questionMark)
    }

    @Test func noOpenCallsMeansNoBadge() {
        #expect(BadgeSelection.select(openToolNames: [String]()) == .none)
        #expect(BadgeSelection.none.badge == nil)
    }

    /// Lowest ordinal wins, plus the total. Most-recent-wins would flicker;
    /// ordering does not. [I3]
    @Test func lowestOrdinalWinsAndTheCountIsTheWholeSet() {
        let selection = BadgeSelection.select(openToolNames: ["Bash", "Read", "Write"])
        #expect(selection.badge == .document)
        #expect(selection.count == 3)
    }

    /// The property criterion 6 rests on: the selection cannot depend on the
    /// order calls happened to arrive in.
    @Test func selectionIsIndependentOfOrder() {
        let tools = ["Bash", "Read", "mcp__x__y", "WebFetch", "TodoWrite"]
        let reference = BadgeSelection.select(openToolNames: tools)
        for _ in 0..<200 {
            #expect(BadgeSelection.select(openToolNames: tools.shuffled()) == reference)
        }
    }

    @Test func addingACallOfALowerOrdinalIsTheOnlyThingThatChangesTheBadge() {
        var open = ["Bash"]
        #expect(BadgeSelection.select(openToolNames: open).badge == .terminal)
        open.append("KillShell")            // same badge, higher count
        #expect(BadgeSelection.select(openToolNames: open).badge == .terminal)
        #expect(BadgeSelection.select(openToolNames: open).count == 2)
        open.append("Read")                 // lower ordinal, badge moves
        #expect(BadgeSelection.select(openToolNames: open).badge == .magnifier)
    }

    @Test func manifestKeysRoundTrip() {
        for badge in ToolBadge.allCases {
            #expect(ToolBadge(manifestKey: badge.manifestKey) == badge)
        }
        #expect(ToolBadge(manifestKey: "question_mark") == .questionMark)
        #expect(ToolBadge(manifestKey: "not_a_badge") == nil)
    }
}
