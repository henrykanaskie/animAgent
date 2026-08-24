import Testing

@testable import SpriteRoomScene

/// The art notice is the whole mechanism by which a green run is unambiguous:
/// it is what tells a reader whether 49 art-dependent tests ran or were skipped.
/// Until `SceneArt.notice(survey:gated:required:)` existed it was built inline
/// inside `theSuiteSaysOutLoudWhetherItCheckedTheArt` and merely printed, so
/// **on a machine with art the other two branches were never evaluated by
/// anything at all.** The text that exists to prevent a silent lie was itself
/// unchecked.
///
/// These are text tests. Rendering the ABSENT branch does not prove 49 tests
/// skip: nothing here can prove that on a machine that has the art. What it
/// proves is that when that branch is reached, it says the true thing. The
/// counterpart is `PanelNoticeTests` on the window-server gate.
@Suite struct ArtNoticeTests {

    private static func survey(
        paths: Set<String> = [], missing: [String] = [], error: String? = nil
    ) -> SceneArt.Survey {
        var survey = SceneArt.Survey()
        survey.paths = paths
        survey.missingPaths = missing
        survey.manifestError = error
        return survey
    }

    // MARK: PRESENT

    @Test func thePresentNoticeSaysTheArtWasVerified() {
        let notice = SceneArt.notice(
            survey: Self.survey(paths: ["a.png", "b.png"]), gated: 49, required: false)
        #expect(notice.contains("SPRITE ROOM ART: PRESENT"))
        #expect(notice.contains("all 2 declared asset paths"))
        #expect(notice.contains("49 art-dependent tests RAN"))
        // The claim the other branches must never make.
        #expect(notice.contains("The art was verified."))
        #expect(!notice.contains("SKIPPED"))
        #expect(!notice.contains("VERIFIED NOTHING"))
    }

    // MARK: ABSENT - the fresh-clone state, unreachable on a machine with art

    @Test func theAbsentNoticeSaysTheRunVerifiedNothing() {
        let notice = SceneArt.notice(
            survey: Self.survey(paths: ["a.png", "b.png", "c.png"], missing: ["b.png", "c.png"]),
            gated: 49, required: false)
        #expect(notice.contains("SPRITE ROOM ART: ABSENT: 2 of 3 declared asset paths"))
        #expect(notice.contains("49 art-dependent tests were SKIPPED"))
        #expect(notice.contains("THIS RUN VERIFIED NOTHING ABOUT THE ART."))
        #expect(notice.contains("First missing: b.png"))
        // It must never claim the run checked anything.
        #expect(!notice.contains("The art was verified."))
    }

    /// The notice has to know which mode it is in. Printing "set this to make it
    /// a failure" directly above the failure that variable has just caused is
    /// the line that teaches people to stop reading the notice.
    @Test func theAbsentNoticeTellsTheTruthAboutWhichModeItIsIn() {
        let base = Self.survey(paths: ["a.png"], missing: ["a.png"])
        let advisory = SceneArt.notice(survey: base, gated: 49, required: false)
        #expect(advisory.contains("Set SPRITE_ROOM_REQUIRE_ART=1 to make this a failure"))
        #expect(!advisory.contains("is SET, so this is a FAILURE"))

        let enforcing = SceneArt.notice(survey: base, gated: 49, required: true)
        #expect(enforcing.contains("SPRITE_ROOM_REQUIRE_ART is SET, so this is a FAILURE below."))
        #expect(!enforcing.contains("Set SPRITE_ROOM_REQUIRE_ART=1 to make this"))
    }

    // MARK: NO MANIFEST - a corrupt checkout, not a missing-art state

    /// **A broken manifest used to report itself as missing art.** `assets/` is
    /// gitignored but `assets/manifest.json` is tracked, so a manifest that will
    /// not parse is a corrupt checkout and needs a different instruction than a
    /// fresh clone does. The counts are the tell: both are zero, because nothing
    /// parsed to declare a path, and "0 of 0 paths missing" sends a reader
    /// hunting for absent files when the wrong file is the one in the repo.
    @Test func aBrokenManifestIsNotReportedAsMissingArt() {
        let notice = SceneArt.notice(
            survey: Self.survey(error: "dataCorrupted at themes.sets"), gated: 49, required: false)
        #expect(notice.contains("SPRITE ROOM ART: NO MANIFEST: dataCorrupted at themes.sets"))
        #expect(notice.contains("is TRACKED, so this is a broken checkout"))

        // The wording that would send the reader the wrong way.
        #expect(!notice.contains("0 of 0"))
        #expect(!notice.contains("ABSENT"))
        #expect(!notice.contains("assets/ is gitignored"))
        #expect(!notice.contains("Set SPRITE_ROOM_REQUIRE_ART=1"))
    }

    /// `manifestError` outranks everything: a survey that somehow carries both
    /// an error and paths is still a broken checkout, because no path it
    /// collected can be trusted.
    @Test func theManifestErrorOutranksAnyPathsTheSurveyCollected() {
        let notice = SceneArt.notice(
            survey: Self.survey(paths: ["a.png"], missing: ["a.png"], error: "unexpected EOF"),
            gated: 49, required: false)
        #expect(notice.contains("NO MANIFEST: unexpected EOF"))
        #expect(!notice.contains("ABSENT"))
    }

    // MARK: the required-mode failure - where the "0 of 0" defect actually was

    /// **This is the regression the notice tests above do not cover.** The
    /// notice always branched on `manifestError` first and so always said NO
    /// MANIFEST; the sentence that said "0 of 0 paths missing" was the
    /// `SPRITE_ROOM_REQUIRE_ART=1` failure, which had one message for both
    /// unavailable states. Assert on the counts, because the counts are the
    /// nonsense: a manifest that will not parse declares nothing, so nothing can
    /// be missing.
    @Test func aBrokenManifestDoesNotFailWithACountOfNothing() throws {
        let why = try #require(
            SceneArt.requirementFailure(
                survey: Self.survey(error: "dataCorrupted at themes.sets"), required: true))
        #expect(why.contains("assets/manifest.json could not be read"))
        #expect(why.contains("dataCorrupted at themes.sets"))
        #expect(!why.contains("0 of 0"))
        #expect(!why.contains("paths missing"))
        #expect(!why.contains("not on disk"))
    }

    @Test func genuinelyMissingArtStillReportsItsCounts() throws {
        let why = try #require(
            SceneArt.requirementFailure(
                survey: Self.survey(paths: ["a.png", "b.png"], missing: ["b.png"]), required: true))
        #expect(why.contains("the art is not on disk: 1 of 2 paths missing, first b.png"))
    }

    @Test func thereIsNoFailureWhenTheGateIsAdvisoryOrTheArtIsThere() {
        // Art absent but the variable is not set: a skip, not a failure.
        #expect(SceneArt.requirementFailure(
            survey: Self.survey(paths: ["a.png"], missing: ["a.png"]), required: false) == nil)
        // Required and present: nothing to say.
        #expect(SceneArt.requirementFailure(
            survey: Self.survey(paths: ["a.png"]), required: true) == nil)
        // A broken manifest is only a failure when the gate is enforcing.
        #expect(SceneArt.requirementFailure(
            survey: Self.survey(error: "boom"), required: false) == nil)
    }

    // MARK: shape

    @Test func everyBranchIsFramedByTheSameRule() {
        let rule = String(repeating: "=", count: 78)
        for survey in [
            Self.survey(paths: ["a.png"]),
            Self.survey(paths: ["a.png"], missing: ["a.png"]),
            Self.survey(error: "boom"),
        ] {
            let lines = SceneArt.notice(survey: survey, gated: 49, required: false)
                .components(separatedBy: "\n")
            #expect(lines.first == rule)
            #expect(lines.last == rule)
            #expect(lines.count > 2, "a branch rendered no body between the rules")
        }
    }
}
