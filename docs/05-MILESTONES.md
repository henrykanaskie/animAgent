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
- `fixtures/` contains the six files listed in `03-EVENT-MODEL.md`. It was five;
  `tool-failure` was added once M0a proved a permission-denied call is closed by
  nothing but the following `PostToolBatch`.
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
