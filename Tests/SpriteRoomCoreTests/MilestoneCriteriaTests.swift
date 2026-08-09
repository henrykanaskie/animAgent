import Foundation
import Testing

/// **The milestones gate on named tests, so the names have to resolve.**
///
/// `docs/05-MILESTONES.md` closes a criterion by naming the tests that prove
/// it. A criterion naming a function nobody can run is a criterion that cannot
/// fail — the same shape as an assertion arranged so it cannot produce the
/// failure it names, and it goes unnoticed for the same reason: reading the
/// bullet tells you a test exists, and nothing checks that reading.
///
/// It had happened three times before this suite was written, all in M6 and all
/// found by a hand cross-check rather than by anything in the repository:
/// `noThemeNameAndNoFilenameIsWrittenDownInTheSceneSources` and
/// `aLeaverCaughtInTheAisleGoesOutThroughItsOwnStation` had been renamed, and
/// `aDeliveryStationStaysClaimedUntilTheReporterIsHomeAgain` was deleted by the
/// same commit whose adjacent paragraph says its subject is deleted, leaving the
/// bullet above still citing it.
///
/// Nothing here reads the milestone's prose or scores a criterion. It checks one
/// mechanical thing: every identifier the document names as a test is one.
@Suite struct MilestoneCriteriaTests {

    static let document: URL = Fixtures.repositoryRoot
        .appending(path: "docs")
        .appending(path: "05-MILESTONES.md")

    static let testsDirectory: URL = Fixtures.repositoryRoot.appending(path: "Tests")

    // MARK: Reading the document

    /// The backticked spans of one line, in order. The document uses single
    /// backticks throughout and holds no fenced blocks, so the odd fields of a
    /// split are exactly the code spans.
    static func codeSpans(in line: String) -> [String] {
        line.split(separator: "`", omittingEmptySubsequences: false)
            .enumerated()
            .filter { $0.offset % 2 == 1 }
            .map { String($0.element) }
    }

    /// **What counts as the document naming a test**: a backticked
    /// lowerCamelCase identifier of at least three words.
    ///
    /// The threshold is not taste, it is measured against both sides. Every
    /// `@Test` function in `Tests/` carries at least two capitals — asserted
    /// below by `everyTestIsNamedLikeASentence`, so the rule cannot quietly stop
    /// being true — while every two-word identifier the document
    /// backticks is a symbol rather than a test: `comfortablePopulation`,
    /// `reportingSlots`, `claimStation`, `releaseStation`, `ensureAgent`.
    ///
    /// A symbol that does have three words is written qualified, the way the
    /// document already writes `RoomCamera`'s `comfortablePopulation` and
    /// `Reaper.permissionGateGraceInterval`; the dot takes it out of this set.
    /// If an unqualified three-word symbol is ever introduced this test goes red
    /// and asks for the qualification — which is a smaller cost than the failure
    /// it is here to catch.
    ///
    /// There is no exemption list, for the reason `ThemeTests` gives for not
    /// having one: an exemption list is how a mechanical rule turns back into a
    /// convention. A milestone that wants to record a name it no longer has —
    /// M6 does it three times — writes it in quotes rather than backticks.
    /// Backticks are the claim; quotes are the history.
    static func namesATest(_ span: String) -> Bool {
        guard let first = span.first, first.isLowercase, first.isLetter else { return false }
        guard span.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        return span.filter(\.isUppercase).count >= 2
    }

    /// Every test identifier the document names, with the line it is on.
    static func claimedTests() throws -> [(line: Int, name: String)] {
        let text = try String(contentsOf: document, encoding: .utf8)
        var claims: [(line: Int, name: String)] = []
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() {
            for span in codeSpans(in: String(line)) where namesATest(span) {
                claims.append((offset + 1, span))
            }
        }
        return claims
    }

    // MARK: Reading the suite

    static func swiftFiles() throws -> [URL] {
        guard let walk = FileManager.default.enumerator(
            at: testsDirectory, includingPropertiesForKeys: nil)
        else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// The identifier following each `func` keyword in a file, paired with the
    /// index of the line it was declared on.
    ///
    /// Comment lines are skipped, and that direction matters: a prose mention of
    /// a function name would enlarge the set the cross-check resolves *against*,
    /// which is how a milestone could cite a test that exists only in a comment
    /// and still pass.
    static func declaredFunctions(in text: String) -> [(line: Int, name: String)] {
        var found: [(line: Int, name: String)] = []
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() {
            let code = line.drop { $0 == " " || $0 == "\t" }
            if code.hasPrefix("//") || code.hasPrefix("*") { continue }
            var rest = Substring(line)
            while let keyword = rest.range(of: "func ") {
                rest = rest[keyword.upperBound...]
                let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if let first = name.first, first.isLetter || first == "_" {
                    found.append((offset + 1, String(name)))
                }
            }
        }
        return found
    }

    /// Every `func` name in `Tests/`, whichever target it lives in. The document
    /// names tests across all three, and a criterion is no less broken for
    /// citing a scene test than a core one.
    static func functionNames() throws -> Set<String> {
        var names: Set<String> = []
        for file in try Self.swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            names.formUnion(declaredFunctions(in: text).map(\.name))
        }
        return names
    }

    /// Functions carrying a `@Test` attribute, which may sit on the declaration
    /// or on any of the three lines above it — `@Test(.enabled(if:))` and
    /// `@Test(arguments:)` are both wrapped that way in this suite.
    ///
    /// The attribute has to *open* the line. Anything else picks up every doc
    /// comment that mentions the attribute, including the ones in this file.
    static func testFunctions(in text: String) -> [(line: Int, name: String)] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var found: [(line: Int, name: String)] = []
        for (offset, line) in lines.enumerated()
        where line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("@Test") {
            for lookahead in offset..<min(offset + 4, lines.count) {
                let declarations = declaredFunctions(in: String(lines[lookahead]))
                if let first = declarations.first {
                    found.append((lookahead + 1, first.name))
                    break
                }
            }
        }
        return found
    }

    // MARK: The cross-check

    /// **Every test `docs/05-MILESTONES.md` names exists.**
    ///
    /// The failure this closes permanently: a rename or a deletion that leaves a
    /// milestone citing a function nobody can run. The exit criterion still
    /// reads as proven and no longer is, and the only thing that would have
    /// noticed was somebody grepping every backtick in the file by hand.
    @Test func everyTestTheMilestonesNameExists() throws {
        let claims = try Self.claimedTests()
        let functions = try Self.functionNames()

        // The extraction is the part that can go quietly vacuous: a document
        // reformatted out from under this regex-free scan would leave nothing to
        // check and nothing to fail. Both sides are pinned to an order of
        // magnitude for that reason, low enough not to fight ordinary edits.
        #expect(claims.count >= 40, """
            only \(claims.count) test names were read out of \
            docs/05-MILESTONES.md — the scan found nothing to check
            """)
        #expect(functions.count >= 300, """
            only \(functions.count) functions were read out of Tests/ — \
            the walk found nothing to check against
            """)

        let missing = claims.filter { !functions.contains($0.name) }
        #expect(missing.isEmpty, """
            docs/05-MILESTONES.md names \(missing.count) test(s) that do not \
            exist in Tests/:
            \(missing.map { "  05-MILESTONES.md:\($0.line)  \($0.name)" }.joined(separator: "\n"))
            A criterion naming a function nobody can run is a criterion that \
            cannot fail. Point it at the test that replaced it, or — if the \
            property is now held by construction — say that, and say what \
            proves it now.
            """)
    }

    /// **The filter above is safe because every test is named like a sentence.**
    ///
    /// `namesATest` discards two-word identifiers so that symbols such as
    /// `claimStation` are not read as test names. That is only sound while no
    /// real test is named in two words: one that was would be silently skipped
    /// by the cross-check, which is exactly the arrangement this whole suite
    /// exists to prevent. So the convention is asserted rather than assumed.
    @Test func everyTestIsNamedLikeASentence() throws {
        var offenders: [String] = []
        var counted = 0
        for file in try Self.swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for test in Self.testFunctions(in: text) {
                counted += 1
                if test.name.filter(\.isUppercase).count < 2 {
                    offenders.append(
                        "  \(file.lastPathComponent):\(test.line)  \(test.name)")
                }
            }
        }

        #expect(counted >= 300, "only \(counted) @Test functions were found in Tests/")
        #expect(offenders.isEmpty, """
            \(offenders.count) test(s) are named in fewer than three words, so a \
            milestone naming one would be skipped by \
            `everyTestTheMilestonesNameExists` instead of checked:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
