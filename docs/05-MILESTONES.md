# 05 — Milestones

Each milestone has exit criteria that are **checkable by the build-verifier
without judgment**. "Looks good" is not an exit criterion anywhere in this file.

Milestones are sequential. Do not start M(n+1) before M(n) exits. The ordering
is deliberate: it front-loads the things that would invalidate later work.

---

## M0 — Ground truth

Nothing is designed until we have seen real payloads. This milestone exists
because every downstream assumption depends on the shape of the data.

**Build:** a throwaway HTTP logger. Register it at user scope for all events.
Run real sessions: a simple one, one with parallel tool calls, one dispatching
three subagents, one killed mid-`Bash`.

**Exit:**
- `fixtures/` contains the **eight** files listed in `03-EVENT-MODEL.md`. It was
  five. `tool-failure` joined once M0a proved a permission-denied call is closed
  by nothing but the following `PostToolBatch`; `permission-prompt` joined at
  ADR-001, once M0c proved that claim is true only of the *headless* auto-deny
  and that an interactively denied call is closed by nothing at all; and
  `denial-then-work` joined once ADR-001 shipped, because it is the only capture
  in which the shortened deadline actually fires inside the stream.

  The count is deliberately not frozen. A fixture enters this list when it is
  the only thing that would prove a rule — not to round the number up.
- A short `docs/FINDINGS-M0.md` records: which events actually fired, whether
  `agent_id` appeared exactly where expected, observed `tool_use_id` overlap,
  and anything in `03-EVENT-MODEL.md` that reality contradicts.
- Any contradiction is fixed in the docs **before** M1 starts.

Owner: `test-engineer`, with `planner`.

---

## M1 — Ingest and world model, headless

No window. No pixels. This runs in a terminal and prints deltas.

**Exit:**
- `swift build --build-tests -Xswiftc -warnings-as-errors` clean, and
  `swift test` green. The build flags are not decoration: plain `swift build`
  compiles no test target and so cannot see a warning in one. This applies to
  every milestone in this file, not only M1.
- Replay of all five fixtures produces expected delta sequences.
- `killed-session` fixture leaves **zero** open calls after deadlines elapse
  (test uses an injected clock, not `sleep`).
- `parallel-tools` fixture never shows an agent with a single-valued tool state.
- Listener responds `202` in under 5 ms measured at p99 over 10k requests.
- `SpriteRoomCore` imports neither AppKit nor SpriteKit — checked in CI.

Owner: `ingest-engineer`. Tests by `test-engineer`.

---

## M2 — Room on screen, ordinary window

Still not the notch. A plain resizable window, so scene work is not blocked on
panel work.

**Exit:**
- Characters render for every agent in a replayed fixture.
- All **six** body states play: `idle`, `working`, `walk`, `deliver`, `spawn`,
  `depart`. Was seven — `read` is dropped, because M0 confirmed Modern Interiors
  ships no `read a book` animation. `attention` is badge-only by design and is
  not a body state. [I1]
- Nameplates render and are legible at the resulting zoom. M0 found the cast is
  **not** separable by silhouette — the closest usable pair differs by 7.3% of
  outline and several premades are silhouette-identical — so the nameplate is a
  primary identity channel, not decoration. A room whose characters are
  distinguishable only by hue fails this criterion.
- Badge appears on `PreToolUse`, disappears on the matching `PostToolUse`.
- `RoomCamera` unit tests: population → integer scale, never fractional.
- Replaying `three-subagents` at real time produces no flicker: no character
  changes badge more than once per open-call change.

Owner: `scene-engineer`, with `art-director` for the manifest.

---

## M3 — The notch panel

**Exit:**
- Panel reveals on pointer entry to the notch region, retracts on exit.
- Focus never leaves the frontmost app — verified by typing into a text editor
  continuously while revealing and retracting the panel 20 times, with no lost
  keystrokes.
- Panel is visible over full-screen spaces.
- Diagonal pointer paths across the notch region do not cause reveal/retract
  oscillation.

Owner: `ui-engineer`.

---

## M4 — Live, end to end

The first milestone where a real session drives the room.

**Exit:**
- Hook block written to `~/.claude/settings.json` on first run, with consent,
  and correctly removed on request.
- Real multi-subagent session renders live.
- Measured added latency to the user's tool calls is under 10 ms at p99. [S2]
- `kill -9` on the session leaves no character working within the deadline. [S3]
- Project selector switches views with ≥2 projects running simultaneously.

Owner: `ingest-engineer` and `ui-engineer` jointly, `build-verifier` gates.

---

## M5 — Final art and polish

**Exit:**
- Final sprite sheets replace placeholders with **no code change** — manifest
  swap only.
- Palette lint passes over the manifest. [I7]
- Screenshots at `3x`, `2x`, and `1x` attached to the milestone record.
- Six-agent legibility check passes at the resulting zoom. [S4]

Owner: `art-director`, verified by `build-verifier` with screenshots.

---

## M6 — A wider room, readable identity, and themes

M5 shipped a room and the maintainer lived with it. Five requests came back — a
bigger room, characters more designed for what they are doing, a cooler
environment than a classroom, a theme related to the project, and dynamism — plus
a bug report ("only one of four subagents appeared") that turned out to be a
fiction the room was telling rather than a transport fault. `ADR-002` answers the
five and says **no** to two of them precisely, which is most of its value.

Twelve commits, `004b587`..`eedd89c`. **This milestone was written after the work
shipped**, because ADR-002 §15 recorded that an M6-sized body of work across three
agents had no milestone and therefore could not be gated. Writing it late has one
consequence worth stating: a criterion below marked **open** is open *today*, and
was not scoped that way to make the milestone pass. M3's focus criterion carried
an honest partial until a human closed it by hand; the same rule applies here.
Do not close one of these by editing the criterion.

**Exit:**

- The M1 build and test gate, which applies to every milestone in this file.
  Plus: `swift run spriteroom-replay --all` over **17** fixtures, exit 0.

  **Exactly three fixtures legitimately hold an orphan at end of stream** —
  `killed-session`, `concurrent-permission-gates`, `denied-batch-cancel` — and
  they are exactly the three with no `SessionEnd`. The final sweep closes each.
  A verifier that treats any of the three as a failure is reading a rule that was
  true only before the ADR-001 verification captures landed: an interactively
  denied call is closed by nothing at all. The rule that still holds is that a
  fixture which *reaches* `SessionEnd` must reach zero without the sweep, and
  `tool-failure` must reach zero without the reaper at all.
- **The room is drawn at `1x` at every population.** `RoomCamera`'s
  `comfortablePopulation` is empty by default, so population no longer pulls the
  camera in, and a camera explicitly told to prefer a closer scale still gets it —
  this is a policy change, not a deletion of the ladder's upper rungs. `1x` is
  still the floor and every emitted scale is still an integer [I6].
  `oneAgentIsDrawnWideInsideThePanel`,
  `aCameraCanStillPreferACloserScaleIfItIsToldTo`,
  `oneIsTheFloorAndTheRoomNeverGoesBelowIt`,
  `everyPopulationMapsToAnIntegerOnTheLadder`.

  **Open — the foreground row is permanently on screen.** M5 placed it strictly
  below the content band so it fell out of frame at the tightest zoom; with `1x`
  the only scale in play, it never does. `foregroundDecorationIsEntirelyOutsideTheContentBand`
  still passes because it checks the band, not the viewport, so **nothing
  currently catches this** and no verifier can gate it. What would settle it: a
  decision from the maintainer on whether the wide default keeps the row, and
  then either art that earns its place in the foreground or a camera that crops
  it. Do not close this criterion by editing the test that does not test it.
- **A nameplate leads with the part that distinguishes it.** Two rows: a solid
  accent band carrying the discriminator at double size, type small beneath.
  Measured on rendered pixels rather than asserted — two same-typed plates differ
  in **at least four times** the separation the single-line plate gave (61.5% of
  pixels against 21.7%), cap height 14 px from 7, stroke 2 px from 1. No plate
  exceeds the seat pitch, no two plates ever intersect, and a truncated type still
  says it was truncated — the ellipsis is lossy but *visibly* lossy, and no
  abbreviation scheme degrades honestly over arbitrary text.
  `sameTypedSubagentPlatesDifferByFourTimesTheOldSeparation`,
  `theDiscriminatorIsTheTailOfTheAgentIDAndSurvivesOddIDs`, `noPlateExceedsTheSeatPitch`,
  `noTwoNameplatesEverIntersectAcrossResumedSubagents`,
  `aTruncatedTypeStillSaysItWasTruncated`. This carries M2's criterion forward:
  M0 found the cast is not separable by silhouette, so the plate is a primary
  identity channel and not decoration.

  **Open — clearance in transit.** 96 px of seat pitch against a 65 px plate
  leaves 48 px of half-pitch, so a character walking the aisle is always within a
  plate width of some station. Real captures pass by 20–31 px; a synthetic worst
  case does not. Closing it structurally needs a 5-tile pitch — 4 tiles misses by
  one pixel — and 5 tiles stops five agents fitting the panel at `1x`. This is a
  trade for the maintainer, not a defect, and it is recorded so it is not
  rediscovered.
- **Six themes in the manifest**, each binding every prop role the scene draws,
  each resolving a floor and a wall at the declared tile size, each carrying
  `assignable`, and `themes.default` naming a theme that exists. No theme name and
  no filename is hard-coded in the scene sources. `everyThemeBindsEveryRoleTheSceneDraws`,
  `everyThemeResolvesAFloorAndAWallOfTheDeclaredTileSize`,
  `theDeclaredDefaultNamesADeclaredTheme`,
  `noThemeNameAndNoFilenameIsWrittenDownInTheSceneSources`.
- **`scripts/lint-palette.py` passes over `room` and over every theme
  separately, on the same thresholds, with no threshold weakened.** [I7] The
  verifier records the six-theme table, because the interesting number is the
  margin and not the pass. The tightest is `mission_control` at **0.427** min
  character contrast against a 0.40 floor — a 0.027 margin, spent deliberately at
  M6b on a prop value band floored at 0.46, which took that theme's
  wall-minus-darkest-prop from 0.169 to 0.302 and made it the strongest anchor of
  the six rather than the weakest.
- **ADR-002, app half.** A project's theme is derived from a rendezvous hash of
  its `cwd` and is overridable per project from the menu bar's **Room ▸** submenu.
  The choice persists to `~/Library/Application Support/SpriteRoom/themes.json`,
  written only on a user pick and never on a hook event path [I5]. Every
  unusable shape of that file means "no stored choices" and none is fatal; a theme
  the manifest no longer has falls back for that project alone and the entry is
  kept. Adding a theme moves only a small fraction of projects, and every theme in
  the pool is reachable. Nothing in the menu has a keyboard shortcut [I8].
  `aStoredChoiceOutranksTheDerivedDefault`,
  `anUnknownThemeIdFallsBackForThatProjectAloneAndIsNotDeleted`,
  `everyUnusableShapeMeansNoStoredChoices`, `addingAThemeMovesOnlyASmallFractionOfProjects`,
  `everyThemeInThePoolIsReachable`, `pickingAThemeReportsItsManifestIdNotItsTitle`,
  `theCurrentThemeIsTheOneThatIsChecked`,
  `aManifestWithNoThemesSaysSoRatherThanShowingAnEmptySubmenu`,
  `nothingInTheMenuHasAKeyboardShortcut`.

  This is the first thing the app has ever persisted, so
  `docs/02-ARCHITECTURE.md`'s Configuration section must name `themes.json`
  rather than claim nothing is persisted. Checkable by reading it. [ADR-002 §15]
- **ADR-002, scene half.** Changing the theme redresses the room and moves no
  character. Stations are per `agent_type`; the absent `agent_id` is the main
  station whatever the type says. The declared floor is what the room draws.
  `changingTheThemeRedressesTheRoomAndMovesNoCharacter`, `agentsOfOneTypeShareOneStation`,
  `aTypedSubagentTakesANumberedStation`, `absentAgentIDIsTheMainStationWhateverTheTypeSays`,
  `theDeclaredFloorIsWhatTheRoomDraws`.
- **Scenery does not track activity.** This is an exit criterion because
  "dynamism" was asked for and refused: the task is unobservable, and the tool mix
  is already above each head, faster and sharper than a room could restate it
  [I1]. What does move with activity is the seated pose, bound to the badge class,
  and it may change only when the badge does — `poseChangesNeverOutnumberBadgeChangesAtRealTime`.
- **`SubagentStop` does not remove a character.** A stopped subagent goes
  dormant, keeps its seat, and is revived in place by any later event — not only
  by a second `SubagentStart`, which `four-subagents` proves is not guaranteed to
  arrive. It departs on `SessionEnd` or the idle sweep, and dormancy carries **no
  deadline of its own**, because that would be a number with nothing behind it.
  Departing on a turn boundary was the fiction: it asserted "this agent is gone"
  from data that said only "this agent finished a turn" [I1].
  `aBackgroundSubagentGoesDormantAndIsRevivedInPlace`,
  `sessionEndDepartsEveryDormantSubagent`, `theIdleSweepDepartsEveryDormantSubagent`,
  `aSubagentGoingDormantDisarmsItsMark`, and against real data
  `thePopulationNeverFallsBelowFourOnceTheFourthSubagentExists`, which was seen
  red against the old behaviour before the change was made.
- **`fixtures/four-subagents.jsonl` exists and replays clean without the
  reaper.** Four subagents of one `agent_type` in one session, so anything keyed
  on the type — or on a truncated id, or on a nameplate string derived from one —
  collapses four characters into one and is off by three. `three-subagents`
  cannot catch that, being two `Explore` and one `general-purpose`.
  `fourSameTypedSubagentsAreFourCharacters`, `allFourSubagentsAreInTheRoomTogether`,
  `fourSubagentsReplaysCleanWithoutTheReaper`.
- **The report is a round trip.** Removing departure exposed a second fiction the
  scene had been carrying: the report walk was an *exit style* carried by the
  departure that followed it, and `reported` was never cleared, so at `SessionEnd`
  every character converged on the anchor and replayed a delivery from minutes
  earlier. A report now takes nobody out of the room, is not replayed at
  departure, and a reporter approaches on its own side of the anchor so a round
  trip does not cross it twice. A leaver caught in the aisle exits through its own
  station, and a longer walk never finishes sooner than a shorter one.
  `aReportInAnEarlierFrameDoesNotReplayItselfAtDeparture`,
  `aReportIsAWalkOnItsOwnAndTakesNobodyOutOfTheRoom`,
  `aReporterApproachesItsAnchorFromItsOwnSideAndTurnsToFaceIt`,
  `aDeliveryStationStaysClaimedUntilTheReporterIsHomeAgain`,
  `aLeaverCaughtInTheAisleGoesOutThroughItsOwnStation`,
  `aWalkTakesTimeInProportionToItsLengthAtEveryLength`.

  **Open — delivery slots are claimed lowest-free, not seat-ordered**, so two
  reporters arriving on the same side can cross rather than queue in seat order.
  Not observed to look wrong in any capture; recorded because it is a known
  difference between what the code does and what the room should mean.
- **Every badge in the tool→badge table has art on disk, and the four authored
  ones say they are authored and why.** `magnifier`, `terminal`, `globe` and
  `plug` exist in no pack we own; they are drawn in the pack's own bubble and
  colours and marked `provenance: "authored"`. `everyBadgeInTheTableHasArtAndAFileOnDisk`,
  `authoredBadgesSayTheyAreAuthoredAndWhy`, `badgeProvenanceIsRecorded`.

  Those four landed at **M5c**, after M5 exited and before M6 opened, and were
  never gated by a milestone of their own. They are gated here because this is the
  first milestone written after them — recorded rather than backdated.

  **Open — the `sleep` badge is art and a manifest key, not something the room
  draws.** `badges.states.sleep` is in the manifest at `eedd89c` with a file on
  disk, and `SpriteRoomCore` carries the `dormant` lifecycle that would drive it.
  `SpriteRoomScene` does not reference it: `Manifest` exposes `badges.states`
  only through `attentionKey`, so a dormant character currently draws the same as
  an idle one. What would settle it: the scene reading a second `badges.states`
  entry, and a test asserting that a dormant character wears it and an idle one
  does not.
- **Open — `characters.poses.working` does not exist.** ADR-002 §7 specifies the
  table and §5 promised a second seated pose only *if* the inventory found one
  usable. It did not: the pack's second seated row is pixel-identical to the first
  above image row 39, and every theme's desk and chair cover rows 40–63 — measured
  at **96 differing pixels of 288,000** across all six rooms, about 24 per
  character. An absent table is the honest state, because a table whose two
  entries render identically would make §7 look satisfied while the complaint it
  answers stayed true. No other row in the sheet is seated, so nothing else can
  fill it. Closing this needs art that does not exist, which is a purchase or an
  authoring decision, not an implementation task.
- **Open — nothing checks `preview-theme.py`'s geometry.** Its `prop_origin`
  returned a y-up offset where a y-down blit needed a top row: up to ~80 px of
  error at `1x`, most of two tiles, and invisible because it was consistent. Every
  theme accepted at M6 was accepted against a wrong picture. The bug is fixed and
  the scene was never affected — but this is the tool the project accepts a theme
  with, and its docstring already said "the geometry is a transcription, and
  transcriptions drift". Nothing checked it then and nothing checks it now. What
  would settle it: a pixel comparison of a preview against the scene, which needs
  a window server and is therefore art-gated like the rest of the pixel suite.
- **Open — three animated props are cut to `assets/processed/animated/` and were
  not in the manifest at `eedd89c`.** `props.roles.<role>` held one `file`; an
  animated prop needs a frame list and a rate. The additive `animation` key is
  proposed in `docs/04-ART-DIRECTION.md`, with `file` still first so an old reader
  draws frame 0 and is correct. Each adopted prop must idle on its own loop and
  react to nothing — a prop that animates in response to activity is the room
  asserting what the data did not say [I1] — and its moving pixel fraction is
  measured, because I7 binds harder on a moving prop. **The key is being landed
  as this is written**, so check the manifest and the git log before scoring
  this one against `eedd89c`.

Owner: `scene-engineer`, `ui-engineer` and `art-director`, with ADR-002 written
before any of them started. `build-verifier` gates, and reports the six-theme
lint table and every criterion marked open above.

---

## Deferred to v2, on purpose

Population overflow beyond the `1x` floor; a colour-tag fallback if `1x` badges
prove illegible; historical playback. Do not pull these forward
without an ADR, and note that the first two only become real problems at agent
counts we have not observed yet.

---

## Addendum — M0 also verifies the art

M0 was scoped to hook payloads. It now has a second half, for the same reason:
`04-ART-DIRECTION.md` was written from store pages, not from the files.

**Also exit M0 with:**
- The three packs downloaded, and `docs/FINDINGS-M0.md` extended with: actual
  character canvas size, actual pose names and frame counts, whether the
  `_sit` poses exist and are side-view only, and whether the 32× set is
  complete.
- Every badge in the tool→badge table matched to a real filename in the UI
  pack, or flagged as missing.
- Any claim in `04-ART-DIRECTION.md` that the download contradicts, corrected
  before M1.
- A `.gitignore` entry covering `assets/`, and the credit line drafted.

The art half and the payload half are independent and can run in parallel.
