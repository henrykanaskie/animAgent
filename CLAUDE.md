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

**I2 — Ambient only inside an open tool call.** A character idles unless it has
at least one open tool call. Inside one, it runs an ambient loop for as long as
the call lasts. Never fill dead air with invented activity.

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
- Swift Package Manager for the core modules; a thin Xcode app target on top so
  the logic is testable from the command line.

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
2. `swift test` passes.
3. The replay harness runs `fixtures/` end to end with no orphaned state at the
   end of the run.
4. The diff touches only files in the task's declared scope.
5. Docs that the change invalidated have been updated in the same change.

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
