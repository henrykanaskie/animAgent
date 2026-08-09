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

/// **Every document that names a symbol has to be naming one.**
///
/// `MilestoneCriteriaTests` closes that failure for one document and one kind of
/// identifier: a test name in `docs/05-MILESTONES.md`. The rest of `docs/` drifts
/// the same way and had nothing reading it at all. `01-PRD.md`,
/// `02-ARCHITECTURE.md`, `03-EVENT-MODEL.md`, `04-ART-DIRECTION.md` and the three
/// ADRs cite code on almost every page — a type, a property, the test that pins a
/// number — and a rename leaves every one of those citations reading exactly as it
/// did while it was true. It found two on the run that introduced it, both of them
/// a test that had been replaced by a better one.
///
/// ## The dot is the rule, and it is the whole answer to false positives
///
/// A backticked span is treated as a claim about this repository's code when it is
/// **qualified** — `Type.member`, or `Type.Nested.member`, optionally with an
/// argument-label list — and when the `Type` is one this repository declares.
/// Everything else in backticks is left alone. That single rule disposes of the
/// three ways a looser one goes wrong here, without an exemption list:
///
/// - **Names that are not ours.** These documents backtick `PostToolUse`,
///   `WebFetch`, `SessionEnd`, `NSPanel`, `DispatchQueue`, `canJoinAllSpaces` and
///   `ignoresMouseEvents` — hook events, tool names, AppKit. There is nothing to
///   resolve them against and they are not drift. A bare identifier gives no way to
///   tell them from ours, and this was measured rather than assumed: of the five
///   bare three-word identifiers in `docs/` that do not resolve, **three** are
///   AppKit or a key of `~/.claude.json`. So the bare form is not checkable outside
///   `05-MILESTONES.md`, whose subject is tests, and this suite does not pretend
///   otherwise. A qualified span whose head we do not declare — `NSPanel.canJoin…`
///   — is skipped by the same mechanism, not by being listed.
/// - **Paths.** `Manifest.swift` and `Cargo.toml` are `Type.member` shaped. A span
///   whose last component is a file extension is a path and is skipped.
/// - **Names a document mentions *because* they were removed.** This is the one
///   that matters, because the removal is often the point of the sentence, and a
///   rule that cannot tolerate it either fires forever or is switched off. The
///   project already has the convention and `MilestoneCriteriaTests` states it:
///   **backticks are the claim, quotes are the history.** A document recording a
///   name it no longer has writes it in quotes. Both spans this check found were
///   exactly that case — `04-ART-DIRECTION.md` on a costume assertion that has
///   since flipped, `ADR-001-denied-calls.md` on a permission test that was
///   replaced — and both were converted to quotes rather than exempted. The rule
///   needs no list and the prose lost nothing: it still says what the old name was
///   and why it is gone.
///
/// ## What "exists" means, deliberately generously
///
/// The set a component resolves against is every identifier declared anywhere in
/// `Sources/` or `Tests/` — any `func`, `var`, `let`, `case`, or type. It is not
/// scoped to the type the span names, so this cannot tell you a member moved from
/// one type to another. That is on purpose: a check that fires only when a name
/// exists **nowhere** is one whose failures are never arguable, and arguable
/// failures are how a mechanical check turns back into a convention that somebody
/// eventually silences. Scoping it properly needs a parser, and the failure it
/// would add is not the one that has actually happened here three times.
@Suite struct DocumentedSymbolTests {

    static let documentsDirectory: URL = Fixtures.repositoryRoot.appending(path: "docs")

    /// A span ending in one of these is a path, not a symbol.
    static let fileExtensions: Set<String> = [
        "md", "swift", "json", "jsonl", "py", "png", "toml", "txt", "sh", "yml",
        "yaml", "html", "ase", "aseprite", "gif", "ttf", "otf",
    ]

    static let declarationKeywords = [
        "func", "var", "let", "case", "struct", "class", "enum", "actor",
        "protocol", "typealias", "extension",
    ]

    /// Keywords that introduce a *type* name. The head of a qualified span has to
    /// be one of these for the span to be about our code at all.
    static let typeKeywords = ["struct", "class", "enum", "actor", "protocol", "typealias", "extension"]

    // MARK: Reading the sources

    static func swiftFiles() throws -> [URL] {
        var found: [URL] = []
        for directory in ["Sources", "Tests"] {
            let root = Fixtures.repositoryRoot.appending(path: directory)
            guard let walk = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil) else { continue }
            found += walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
        return found
    }

    /// The identifier introduced by each `keyword` on a line, if any.
    ///
    /// The keyword has to stand alone — `letterbox` is not a `let`, and
    /// `deskPosition` is not a `case`. Comment lines are skipped for the reason
    /// `declaredFunctions` gives: a prose mention would enlarge the set the
    /// cross-check resolves *against*, which is how a document could cite a symbol
    /// that exists only in somebody's doc comment and still pass.
    static func declarations(in text: String) -> Set<String> {
        var found: Set<String> = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = line.drop { $0 == " " || $0 == "\t" }
            if code.hasPrefix("//") || code.hasPrefix("*") || code.hasPrefix("/*") { continue }
            for keyword in declarationKeywords {
                var rest = Substring(line)
                while let match = rest.range(of: keyword + " ") {
                    let before = match.lowerBound == rest.startIndex
                        ? nil : rest[rest.index(before: match.lowerBound)]
                    rest = rest[match.upperBound...]
                    if let before, before.isLetter || before.isNumber || before == "_" { continue }
                    let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                    if let first = name.first, first.isLetter || first == "_" {
                        found.insert(String(name))
                    }
                }
            }
        }
        return found
    }

    static func declaredTypes(in text: String) -> Set<String> {
        var found: Set<String> = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = line.drop { $0 == " " || $0 == "\t" }
            if code.hasPrefix("//") || code.hasPrefix("*") || code.hasPrefix("/*") { continue }
            for keyword in typeKeywords {
                var rest = Substring(line)
                while let match = rest.range(of: keyword + " ") {
                    let before = match.lowerBound == rest.startIndex
                        ? nil : rest[rest.index(before: match.lowerBound)]
                    rest = rest[match.upperBound...]
                    if let before, before.isLetter || before.isNumber || before == "_" { continue }
                    let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                    if let first = name.first, first.isUppercase { found.insert(String(name)) }
                }
            }
        }
        return found
    }

    // MARK: Reading the documents

    static func documents() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The dotted components of a span, or `nil` when the span is not a qualified
    /// symbol reference at all.
    ///
    /// Accepts `A.b`, `A.B.c` and `A.b(with:and:)`; rejects anything holding a
    /// space, a slash, a digit-led component, or a lowercase head.
    static func qualifiedComponents(of span: String) -> [String]? {
        var core = span
        if let open = core.firstIndex(of: "(") {
            guard core.hasSuffix(")") else { return nil }
            core = String(core[core.startIndex..<open])
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        for part in parts {
            guard let first = part.first, first.isLetter,
                  part.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        }
        guard let head = parts.first?.first, head.isUppercase else { return nil }
        return parts
    }

    // MARK: The cross-check

    /// **Every symbol `docs/` qualifies by type exists.**
    @Test func everySymbolTheDocumentsQualifyExists() throws {
        var names: Set<String> = []
        var types: Set<String> = []
        for file in try Self.swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            names.formUnion(Self.declarations(in: text))
            types.formUnion(Self.declaredTypes(in: text))
        }

        var checked = 0
        var offenders: [String] = []
        var documents = 0
        for document in try Self.documents() {
            documents += 1
            let text = try String(contentsOf: document, encoding: .utf8)
            for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                for span in MilestoneCriteriaTests.codeSpans(in: String(line)) {
                    guard let parts = Self.qualifiedComponents(of: span),
                          let last = parts.last, !Self.fileExtensions.contains(last),
                          let head = parts.first, types.contains(head)
                    else { continue }
                    checked += 1
                    let unresolved = parts.dropFirst().filter { !names.contains($0) }
                    guard !unresolved.isEmpty else { continue }
                    offenders.append("""
                          \(document.lastPathComponent):\(offset + 1)  \(span) \
                        — \(unresolved.joined(separator: ", ")) is declared nowhere in \
                        Sources/ or Tests/
                        """)
                }
            }
        }

        // Both sides pinned, for the reason the milestone cross-check pins its
        // own: a document reformatted out from under this scan, or a sources walk
        // that stopped finding files, would leave nothing to check and nothing to
        // fail — and would read in the log exactly like a clean run.
        #expect(documents >= 8, "only \(documents) documents were read out of docs/")
        #expect(names.count >= 500, "only \(names.count) declarations were read out of Sources/ and Tests/")
        #expect(types.count >= 50, "only \(types.count) type names were read out of Sources/ and Tests/")
        #expect(checked >= 30, """
            only \(checked) qualified symbol references were read out of docs/ — \
            the scan found nothing to check
            """)

        #expect(offenders.isEmpty, """
            docs/ names \(offenders.count) qualified symbol(s) that do not exist:
            \(offenders.joined(separator: "\n"))
            Point the sentence at the symbol that replaced it. If the sentence is \
            *about* the removal, write the old name in quotes rather than \
            backticks — backticks are the claim, quotes are the history.
            """)
    }

    /// **The spans this check skips are skipped for a stated reason, and the count
    /// of them is not allowed to quietly become everything.**
    ///
    /// `everySymbolTheDocumentsQualifyExists` resolves only spans whose head is a
    /// type we declare. That is the right rule and it is also the rule most able to
    /// go vacuous without anyone noticing: rename `SceneDirector` and every
    /// `SceneDirector.x` citation in the docs stops being *checked* rather than
    /// starting to *fail*, which is the worse of the two outcomes and the silent
    /// one. So the proportion is asserted. On the shipped docs 43 of 43 qualified
    /// spans resolve their head, file paths aside.
    @Test func almostEveryQualifiedSpanInTheDocumentsIsCheckable() throws {
        var types: Set<String> = []
        for file in try Self.swiftFiles() {
            types.formUnion(Self.declaredTypes(in: try String(contentsOf: file, encoding: .utf8)))
        }

        var checkable = 0
        var skipped: [String] = []
        for document in try Self.documents() {
            let text = try String(contentsOf: document, encoding: .utf8)
            for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                for span in MilestoneCriteriaTests.codeSpans(in: String(line)) {
                    guard let parts = Self.qualifiedComponents(of: span),
                          let last = parts.last, !Self.fileExtensions.contains(last),
                          let head = parts.first
                    else { continue }
                    if types.contains(head) {
                        checkable += 1
                    } else {
                        skipped.append("  \(document.lastPathComponent):\(offset + 1)  \(span)")
                    }
                }
            }
        }

        #expect(checkable + skipped.count >= 30)
        #expect(skipped.count * 4 <= checkable, """
            \(skipped.count) of \(checkable + skipped.count) qualified spans in docs/ \
            name a head type this repository does not declare, so they are not \
            cross-checked at all:
            \(skipped.joined(separator: "\n"))
            A handful of these is expected — `NSPanel.canJoinAllSpaces` is not ours \
            to resolve. A jump in the count means one of our own types was renamed \
            and every citation of it went quiet instead of going red.
            """)
    }
}
