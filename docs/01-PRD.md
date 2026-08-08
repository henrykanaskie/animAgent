# 01 — Product requirements

## Problem

When you dispatch Claude Code subagents, you lose the thread. The terminal shows
a wall of collapsing tool calls; a team of five agents produces output faster
than you can read it. You end up either staring at scrollback or walking away
and trusting it blindly.

The information you actually want at a glance is small: *how many agents are
running, what is each one doing right now, and has anything finished.* That fits
in a glance. It does not fit in a log.

## Who it is for

A developer running Claude Code on a Mac, with a terminal or editor in front of
them and the session doing work they are not reading line by line.

## The core interaction

1. Hooks POST every lifecycle event to a local listener inside the app.
2. The app maintains live state per agent per project.
3. Pointing at the notch drops down a panel showing that project's room.
4. Characters idle, work, spawn, and walk over to report — all driven by events.
5. Pointer leaves, panel retracts. Nothing is clicked. Nothing is read.

## Scope — v1

- Ingest all relevant hook events over HTTP from any number of local sessions.
- Group by project (`cwd`); user selects which project is displayed.
- One character per distinguishable agent: main thread plus each subagent.
- Character states: idle, working (with a badge indicating the tool), spawning,
  reporting, leaving.
- Subagent report animation: walk to the main agent's anchor, deliver, return.
- Camera scale is an integer step [I6], chosen to fit the viewport. It no longer
  tracks population: `004b587` made the room draw wide at every population, on
  the maintainer's instruction that it "doesn't need to be so zoomed in". The
  ladder is untouched; only the preference changed.
- Notch panel: hover to reveal, retract on exit.
- A room **theme per project**: a fixed set of themed prop dressings, one in
  effect at a time, defaulting to a deterministic function of `cwd` and
  changeable by the user from the menu bar. Added by `docs/ADR-002-themed-rooms.md`;
  see the non-goals below for what it does *not* open up.

## Explicit non-goals — v1

Each of these is a real idea that is deliberately deferred. Do not build them.

- Reading or displaying prompt/response *content*. This is a status surface, not
  a transcript. It also keeps the app from ever holding your source code.

  **The second sentence is the load-bearing one, and it is meant categorically:
  the app never opens, stats, lists or watches any path under a project's
  `cwd`.** `cwd` is a routing key and a display string, nothing else. That rules
  out the one mechanism that could have made a room's theme genuinely reflect
  *what* a project is — detecting its language, framework or tooling from its
  files — and `docs/ADR-002-themed-rooms.md` §3b rejects it explicitly rather
  than leaving it as an unexplored option. The promise is worth more than the
  feature, and its worth is almost entirely in being unqualified. That ADR
  proposes promoting this into `CLAUDE.md` as an invariant.
- Historical playback, timelines, scrubbing.
- Metrics: token counts, cost, duration charts.
- Any control over the agents. Read-only, always. No "stop this agent" button.
- Multiple projects on screen simultaneously.
- Remote or cloud sessions.
- ~~Customisation, theming, user-supplied sprites.~~ **Half overridden.** The
  maintainer asked for themed rooms after M5, and `docs/ADR-002-themed-rooms.md`
  is the decision. What is now in scope: a **fixed** set of themes built from
  packs we already own, one per project, defaulted deterministically from `cwd`
  and overridable by the user. What remains a non-goal, unchanged:
  **user-supplied sprites, user-authored themes, and any customisation beyond
  picking one entry from that fixed list.** The user picks from the list; they do
  not add to it. Recorded as an override rather than deleted, so it stays visible
  that this was a deliberate reversal and what part of it was *not* reversed.

## Success criteria

Testable, not aspirational:

- **S1** — A tool call appears on screen within 250 ms of the hook firing.
- **S2** — Ingest adds under 10 ms to the hook's round trip at p99.
- **S3** — After any session ends by any means, including `kill -9`, no
  character remains in a working state.
- **S4** — With 6 concurrent agents, every character is individually
  identifiable at the resulting zoom level.
- **S5** — A cold observer watching the panel for 15 seconds can correctly say
  how many agents are running and whether any are idle.

- **S6** — The same project draws the same room on every launch, and on two
  launches of the same binary against the same `cwd`. Added with the per-project
  theme; it is the property that mechanism most easily loses by accident, and a
  room that redecorates itself between launches reads as a rendering bug.

S5 is still the real one. The others are how you get there.

## Failure modes to design against

- **The strobe.** Fast tool calls producing sub-frame animation. Handled by
  I2/I3: state has duration, so a 3 ms call simply never gets an ambient loop.
- **The ghost.** A character stuck working after its session died. See I4.
- **The mush.** Too many agents, sprites scaled below legibility. See I6; at the
  `1x` floor, population is capped and overflow is deferred to v2.
- **The lie.** Animation implying communication the data does not describe.
  See I1. This is the one that quietly destroys the product's only value.
