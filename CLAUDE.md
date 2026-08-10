# Sprite Room — project constitution

A macOS app that renders live Claude Code activity as a small pixel-art room of
working characters. It drops down from the notch. Each agent is a character.
Each tool call is something the character is visibly doing.

Every agent working on this repo loads this file. It is the shortest document
here and the one that outranks the others. If a doc and this file disagree,
this file wins and the doc is wrong — say so rather than following it.

---

## The one-sentence product

You glance at the notch and know what your agents are doing.

Not a log viewer. Not a metrics dashboard. A window into a room.

---

## Invariants (do not violate without an ADR)

These were derived from the constraints of the data source and the medium. Each
one has a reason. Breaking one silently is the failure mode this file exists to
prevent.

**I1 — No fiction.** Every visible behavior traces to a real hook event. If the
data does not say it happened, the room does not show it. When you cannot
represent something truthfully, show nothing.

**I2 — Ambient only inside an open tool call.** A character runs an ambient loop
**if and only if** it holds at least one open tool call, and runs it for as long
as the call lasts. Never fill dead air with invented activity.

**This governs motion.** Three things are governed separately and may carry a
fact the motion does not, each ratified by its own ADR and each already shipped:

- a character's **posture** — seated at its station, or standing — which traces
  to the turn boundaries the hook stream carries, holds a single still frame in
  either case, and may never move a pixel that an open call has not licensed
  [ADR-005];
- the **badge slot**, which may hold an attention or sleep state, or a bounded
  beat after a call closes — provided the body asserts no ongoing work for any
  frame of it [ADR-003];
- the **pilot lamp**, which is not a character, traces to a measured fact about
  this process, and **says nothing about any agent** [ADR-004].

All three carve-outs are narrow on purpose, and the third is void if its own
third condition is dropped: a lamp that beat on real hook traffic would be an
activity-keyed motion channel competing with the cast, which is the thing I2
exists to prevent. Nothing here licenses a character animating without an open
call.

The first sentence used to read "a character idles unless it has at least one
open tool call", which named a *state* where it meant a *motion*. `idle` is a
standing pose, so that reading had a character leave its desk for the 2.35 s
median gap between two calls of one turn and come back for the 23 ms median call
— an assertion no event supports. ADR-005 is the amendment; it changes nothing
about when a body may move.

**I3 — State is keyed by `tool_use_id`, not by agent.** Tool calls run in
parallel; one agent can hold several at once. Agent state is a *set* of open
calls. Any model that stores one current tool per agent is wrong and will
produce flicker and stuck characters.

**I4 — Every open state must be reapable.** `PostToolUse` may never arrive:
crashes, kills, ^C. Every open `tool_use_id` carries a deadline. `SessionEnd`
force-closes everything for that session. A character that types forever is the
signature bug of this project.

**I5 — The ingest handler never does work.** Respond `202` with an empty body
immediately, push onto an internal queue, return. No rendering, no disk, no
locks held across a response. Claude Code blocks on HTTP hooks; latency here is
latency on the user's every tool call.

**I6 — Camera zoom snaps to integer scales.** `3x`, `2x`, `1x`. Never a
continuous float. Fractional scaling resamples pixel art into shimmer. `1x` is
the floor; below it the art is being destroyed, not shrunk.

**I7 — Palette separation.** The room is desaturated and low-contrast.
Characters own the saturation and the darkest values. At small sizes silhouette
and value contrast are what read — not detail. Enforced by lint over the asset
manifest, not by good intentions.

**I8 — The panel never steals focus.** Non-activating panel. That means no
keyboard events, ever. Pointer-only interaction. Do not design a shortcut.

---

## Identity model

From the hook payload's common input fields:

- `agent_id` — present **only** inside a subagent. Its **absence is the main
  agent.** This is the avatar key.
- `agent_type` — the agent name (`Explore`, `security-reviewer`, ...). Chooses
  the sprite variant and the nameplate.
- `session_id` — one Claude Code session.
- `cwd` — routes the event to a project. The user picks one project to view.

Do not invent an identity scheme on top of these. Do not hash the transcript
path. If attribution is ambiguous, the character does not appear.

---

## Stack

- Swift 6, strict concurrency. macOS 14+.
- **AppKit** for the panel (`NSPanel`, non-activating, `.statusBar` level or
  above, `canJoinAllSpaces`).
- **SpriteKit** for the room. Nearest-neighbour filtering on every texture.
- **Network.framework** for the HTTP listener, in-process. One binary. No
  daemon, no Electron, no external server.
- Swift Package Manager throughout. `spriteroom` is an SPM executable target,
  not an Xcode app target and not a `.app` bundle — the panel sets its own
  activation policy at launch, so the bundle bought nothing. This line used to
  promise "a thin Xcode app target on top"; it never existed, and the goal it
  was there to serve — logic testable from the command line — is delivered by
  the `SpriteRoomCore` boundary instead.

## Layout

```
Sources/
  SpriteRoomCore/      pure logic — no AppKit, no SpriteKit, fully testable
    Ingest/            listener, decoding, queue
    Model/             agents, sessions, open-call sets, reaping
  SpriteRoomScene/     SpriteKit scene, camera, characters, badges
  SpriteRoomApp/       AppKit panel, notch geometry, lifecycle
Tests/
  SpriteRoomCoreTests/ replay tests against fixtures/
fixtures/              captured real hook payloads — ground truth
docs/                  specs; read the one for your task
.claude/agents/        the team
```

`SpriteRoomCore` must not import AppKit or SpriteKit. This is checked. It is
what makes the whole system testable without a screen.

---

## Definition of done

A task is done when **all** of these hold. Agent opinion is not on this list.

1. `swift build --build-tests -Xswiftc -warnings-as-errors` succeeds.

   Plain `swift build` compiles **no test target**, so it cannot see a warning
   in one — for most of this project's life that made "no warnings" a check on
   roughly half the code. `--build-tests` compiles them; `-warnings-as-errors`
   is what makes "a warning is a failure" true mechanically instead of
   depending on someone reading the log. It also defeats the stale-cache
   failure mode: a warm cache cannot hide a warning from this command, because
   a build carrying one could not have succeeded.
2. `swift test` passes **from the committed state** — a checkout holding
   `assets/manifest.json` and no art.

   `assets/` is not redistributable, so the tests that read pixels are gated on
   `SceneArt.isAvailable` (`Tests/SpriteRoomSceneTests/SceneFixtures.swift`) and
   skip on a fresh clone. `ArtAvailabilityTests` always runs and prints how many
   skipped, so a green run never silently implies the art was checked. On a
   machine that is *supposed* to hold the art — a release build, a packaging
   step — run `SPRITE_ROOM_REQUIRE_ART=1 swift test`, which turns missing art
   from a skip into a failure.

   The same arrangement covers the window server: an `NSPanel` cannot be built
   without a GUI session, so the panel tests are gated on
   `PanelWindowServer.isAvailable` (`Tests/SpriteRoomAppTests/PanelFixtures.swift`)
   and skip on any headless runner. `PanelAvailabilityTests` always runs and
   prints whether the panel was checked, **naming the three I8 assertions
   individually when it was not** — because a green run that skipped them is a
   run that verified nothing about the invariant this project most needs held,
   and the one the maintainer had to check by hand. On a machine that is
   supposed to have a window server, run
   `SPRITE_ROOM_REQUIRE_WINDOW_SERVER=1 swift test`.
3. The replay harness runs `fixtures/` end to end with no orphaned state at the
   end of the run.
4. The diff touches only files in the task's declared scope.
5. Docs that the change invalidated have been updated in the same change.

Gating a test on a precondition it cannot control — no window server, no art on
disk — is not disabling it, **provided the skip is visible in the run's output**.
Silencing an assertion is. That is the whole boundary.

Both gates honour that sentence; a new gate that does not is not finished. The
window-server gate spent its first weeks without a notice or a pinned count, so
26 tests — every I8 assertion among them — could have skipped on a headless
runner with the summary line reading exactly like a run that checked them. It
was found by an audit, not by the suite, which is the argument for the notice.

If you cannot satisfy 1–3, the task is not done and you say so plainly. Do not
report partial work as complete. Do not disable a test to make it pass.

---

## Working agreements

- **Read before writing.** `docs/03-EVENT-MODEL.md` before touching ingest.
  `docs/04-ART-DIRECTION.md` before touching sprites. Do not infer a spec.
- **Small diffs.** One task, one concern. If a task requires touching three
  modules, it was scoped wrong — say so and hand it back to the planner.
- **No speculative generality.** No plugin systems, no theming engine, no
  abstraction for a second data source. There is one data source.
- **Fixtures over mocks.** If you need event data, capture it or use
  `fixtures/`. Hand-written payloads drift from reality and hide bugs.
- **Report blockers immediately.** A subagent that guesses to avoid returning
  empty-handed is worse than one that stops and asks.
