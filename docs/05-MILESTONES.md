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
  `exactlyTheFixturesWithNoSessionEndOrphanAtEndOfStream`,
  `everyFixtureThatReachesSessionEndReachesZeroWithoutTheSweep`,
  `everyFixtureReachesZeroOpenCallsAfterTheSweep`,
  `toolFailureClosesEverythingWithoutTheReaper`,
  `toolFailureNeedsNoReaperEvenWithTheClockAdvancing`.

  **This criterion named no test until 2026-08-08 and was guarded by nothing.**
  `spriteroom-replay --all` prints the orphan counts and exits 0 whatever they
  are, and the suite's own orphan test iterated the eight fixtures in
  `Fixtures.required` — which hold one of the three — under the name
  "onlyKilledSessionLeavesAnOrphanAtEndOfStream". True within the eight, false
  across the seventeen, and arranged so it could not produce the failure it
  named. The first two tests above replace it over all seventeen, and both sides
  of the rule are **derived** — the orphan set by replaying, the `SessionEnd` set
  from the payloads — so a capture added tomorrow is scored by it rather than
  escaping it until somebody remembers a name. The count of three is pinned as
  well as the equality: a new capture with no `SessionEnd` turns them red on
  purpose, and the number moves here and in the tests together, or not at all.
- **The room is drawn at `1x` at every population.** `RoomCamera`'s
  `comfortablePopulation` is empty by default, so population no longer pulls the
  camera in, and a camera explicitly told to prefer a closer scale still gets it —
  this is a policy change, not a deletion of the ladder's upper rungs. `1x` is
  still the floor and every emitted scale is still an integer [I6].
  `oneAgentIsDrawnWideInsideThePanel`,
  `aCameraCanStillPreferACloserScaleIfItIsToldTo`,
  `oneIsTheFloorAndTheRoomNeverGoesBelowIt`,
  `everyPopulationMapsToAnIntegerOnTheLadder`.

  **Closed at M6d.** The row is removed, and the rule that replaced it is
  stronger than the one it lost: **nothing decorative is drawn nearer the camera
  than the seat row** (`theRoomDrawsNoDecorationInFrontOfTheCharacters`, over
  `room` and all six themes). M5's rule was about *zoom*, so the wide camera
  retired it; this one is about *depth*, so no camera policy can. The foreground
  is the walkway now.

  **Decided by the maintainer, 2026-08-08: `1x` at every population stays.** The
  lattice grew the content band from 145 to 241 px, which puts `2x` at 482 px
  against a 400 px panel — so two of three rungs are now geometrically
  unreachable, `3x` having already been dead before the change. The ladder is
  untouched and integer, nothing prefers a closer rung, and
  `aCameraCanStillPreferACloserScaleIfItIsToldTo` proves the mechanism survives.
  Recorded as a spend, not a defect.
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
  `noTwoNameplatesEverIntersect`, `noTwoNameplatesEverIntersectAcrossResumedSubagents`,
  `aTruncatedTypeStillSaysItWasTruncated`. This carries M2's criterion forward:
  M0 found the cast is not separable by silhouette, so the plate is a primary
  identity channel and not decoration.

  **This criterion was deleted by accident at `70f5793` and restored here.** The
  reconciliation that closed four items anchored a patch on a string that sat
  *inside* this bullet, removing its text and leaving its tail welded to the
  criterion above. M6's own instruction is "do not close one of these by editing
  the criterion"; deleting one is worse, and it was found by an audit rather than
  by anything in the repository. Nothing gates this file.

  **Closed at M6d, and both proposed fixes were refuted first.** Widening the
  pitch does not work: the failure is two characters walking one line in
  opposite directions, and they cross at **zero** separation at any pitch.
  Staggering the plate vertically needs `s <= 6` or `s >= 58` by arithmetic, and
  the 6 px of headroom available is in the branch that buys nothing. The room is
  a **lattice**: every character is confined to its own seat's column or its own
  ring's delivery row, so two plates can meet only if they share a horizontal
  strip *and* come within a plate width in x, which the geometry forbids.
  Worst synthetic case went from **−26.0 px** to **+6.0 px**.

  Arrivals were the last beat to close, and the number recorded here before was
  wrong: it was not a 6 px clearance but **−25.60 px**, a real overlap, missed
  because the sweep paired seats two rings apart instead of one. Fixed by
  arrivals coming upstage from the character's own ring's delivery row — which
  keeps M5's "visible from its first frame" rather than trading it.
  `theAisleIsGuaranteedClearAtTheStationsAndNotBetweenThem`,
  `noAdversarialPairingOfBeatsEverTouchesTwoPlates`,
  `everySeatWalksInFromInsideTheFrame`.

  **Decided by the maintainer, 2026-08-08: the fading departure stays.** There is
  no frame edge behind the desks and a flat wall gives nothing to disappear
  behind, so the fade is the honest end of an upstage exit. The alternatives were
  a hard pop at the wall line and an occluder band that cut visibly across the
  sprite.
- **Six themes in the manifest**, each binding every prop role the scene draws,
  each resolving a floor and a wall at the declared tile size, each carrying
  `assignable`, and `themes.default` naming a theme that exists. No theme name is
  hard-coded anywhere under `Sources/`, and no art filename in the one module that
  loads a texture. `everyThemeBindsEveryRoleTheSceneDraws`,
  `everyThemeResolvesAFloorAndAWallOfTheDeclaredTileSize`,
  `theDeclaredDefaultNamesADeclaredTheme`,
  `noThemeNameAndNoArtFilenameIsWrittenDownInSources`.
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
  trip does not cross it twice. A leaver caught mid-report comes home up its own
  column and goes out upstage, and a longer walk never finishes sooner than a
  shorter one.
  `aReportInAnEarlierFrameDoesNotReplayItselfAtDeparture`,
  `aReportIsAWalkOnItsOwnAndTakesNobodyOutOfTheRoom`,
  `aReporterApproachesItsAnchorFromItsOwnSideAndTurnsToFaceIt`,
  `aLeaverCaughtMidReportComesHomeUpItsOwnColumnAndLeavesUpstage`,
  `aWalkTakesTimeInProportionToItsLengthAtEveryLength`.

  **Closed at M6d, by construction rather than by ordering.** The delivery
  position is now a pure function of the reporter's seat, so there are no shared
  slots to claim and nothing can be claimed out of order. `DeliveryStation`,
  `reportingSlots`, `claimStation` and `releaseStation` are deleted.

  **Two of the tests named above were renamed and one was deleted, and this
  bullet went on naming all three.** The deleted one was
  "aDeliveryStationStaysClaimedUntilTheReporterIsHomeAgain", removed by the same
  commit whose paragraph above says its subject is deleted — a criterion left
  citing a function nobody can run, which is a criterion that cannot fail. What
  it used to prove is now held by construction and is asserted where the
  construction is: `aReporterApproachesItsAnchorFromItsOwnSideAndTurnsToFaceIt`
  checks the delivery point is a pure function of `(anchorSeat, reporterSeat)`
  and sits on the reporter's own delivery row, over every pairing of seats, so
  there is no shared slot for a second reporter to take. `theAisleIsGuaranteedClearAtTheStationsAndNotBetweenThem`
  and `noAdversarialPairingOfBeatsEverTouchesTwoPlates` cover the collision the
  claim was there to rule out. The renames were mechanical: the leaver test
  above, and `noThemeNameAndNoArtFilenameIsWrittenDownInSources` in the themes
  bullet.

  All three were found by an audit rather than by anything in this repository,
  which is the same complaint ADR-002 §15 made about M6 having no milestone.
  `everyTestTheMilestonesNameExists` now resolves every test name backticked in
  this file against the `func`s in `Tests/` on every run, so the next rename is
  a red test rather than a silent hole in a criterion.

  It has no exemption list, because an exemption list is how a mechanical rule
  turns back into a convention. **A name that no longer exists is written in
  quotes rather than backticks** — the two above, and the one in the replay
  criterion. Backticks are the claim; quotes are the history.
- **Every badge in the tool→badge table has art on disk, and the four authored
  ones say they are authored and why.** `magnifier`, `terminal`, `globe` and
  `plug` exist in no pack we own; they are drawn in the pack's own bubble and
  colours and marked `provenance: "authored"`. `everyBadgeInTheTableHasArtAndAFileOnDisk`,
  `authoredBadgesSayTheyAreAuthoredAndWhy`, `badgeProvenanceIsRecorded`.

  Those four landed at **M5c**, after M5 exited and before M6 opened, and were
  never gated by a milestone of their own. They are gated here because this is the
  first milestone written after them — recorded rather than backdated.

  **Closed at M6d.** The scene draws it. Wiring it required a `WorldDelta` case
  that had been explicitly refused when dormancy shipped, on the grounds that
  nothing we own could honestly draw the difference between *finished a turn* and
  *waiting for work* — the `Z` bubble is real pack art saying exactly the true
  thing, so the refusal is reversed with its reason recorded rather than
  overwritten. Precedence is **attention > sleep > tool**, and the middle
  comparison turned out reachable where it was expected not to be:
  `PermissionRequest` arms a gate mark without going through `ensureAgent`, so it
  does not revive a dormant agent.
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
- **`preview-theme.py`'s geometry is checked against the real scene.** Closed at
  M6f. `preview-theme.py --verify` renders the room the scene actually draws —
  `spriteroom --render --theme`, offscreen, no window server, which is what makes
  this closeable at all; the criterion as written assumed one was needed — and
  compares floor, wall and every copy of every prop pixel for pixel over the
  whole tile field, in an empty room. It runs as a stage in
  `scripts/lint-palette.py` rather than as a command someone remembers, because
  the lint already imported `role_placements()` and its motion budget was priced
  on that transcription with nothing tying the number to a renderer.

  Seven injections are watched failing, including both historical bugs.
  `SPRITE_ROOM_REQUIRE_SCENE=1` turns the no-binary skip into a failure.

  **It found two more defects on its first run, and they are open.**

  **Open — every prop in the preview stands one pixel into the floor.** All six
  themes, all 21 copies. `prop_origin` returns `y + bottom_row` where a y-down
  blit needs `y + bottom_row + 1`. This is M6b's own bug with one pixel left
  behind: that fix corrected which *end of the canvas* the offset was measured
  from, not which *side of the line* the bottom row sits on.

  **Open — the depth bias is transcribed with the wrong sign, and this one is not
  cosmetic.** The scene sorts `zPosition = rowDepth(y) + bias` where
  `rowDepth = 1000 − y`, so z runs opposite to y and a positive bias pulls a prop
  *forward*; the preview sorts `y + bias` with larger keys painted first, which
  pushes it *back*. Scene order is chair → character → desk; the preview's is the
  reverse. **So every picture this tool has ever written shows the character
  sitting in front of its desk** — the exact cue the desk offset exists to
  produce. It hid because four of six themes use a desk whose ink never touches
  the chair's; it shows only in `mission_control` and `library`.

  Both sit in a named register printed on every run, so the check stays green
  without a silent tolerance and still fails if the offset changes, stops being
  uniform, or anything disagrees outside the recorded overlap. Fixing either does
  not turn it red.
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

~~Population overflow beyond the `1x` floor;~~ a colour-tag fallback if `1x`
badges prove illegible; historical playback. Do not pull these forward
without an ADR, and note that the second only becomes a real problem at agent
counts we have not observed yet.

**Overflow was pulled forward, and not as a feature.** Deferring it had assumed
the room degraded gracefully past its seat count; it did not — `seatColumn` and
`ring` both wrap mod `seatCapacity`, so the eighth agent was drawn on top of the
first and the room showed seven characters while eight were running. That is S5
failing and a false claim about the data [I1], so it was a defect rather than a
deferral. What shipped is the smallest truthful thing: seven seats, and a plate
that says how many more there are. See `04-ART-DIRECTION.md`, "Seven seats, and
what the room says about the eighth agent".

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
