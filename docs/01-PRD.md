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
- Camera zooms in integer steps to fit the current population.
- Notch panel: hover to reveal, retract on exit.

## Explicit non-goals — v1

Each of these is a real idea that is deliberately deferred. Do not build them.

- Reading or displaying prompt/response *content*. This is a status surface, not
  a transcript. It also keeps the app from ever holding your source code.
- Historical playback, timelines, scrubbing.
- Metrics: token counts, cost, duration charts.
- Any control over the agents. Read-only, always. No "stop this agent" button.
- Multiple projects on screen simultaneously.
- Remote or cloud sessions.
- Customisation, theming, user-supplied sprites.

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

S5 is the real one. The others are how you get there.

## Failure modes to design against

- **The strobe.** Fast tool calls producing sub-frame animation. Handled by
  I2/I3: state has duration, so a 3 ms call simply never gets an ambient loop.
- **The ghost.** A character stuck working after its session died. See I4.
- **The mush.** Too many agents, sprites scaled below legibility. See I6; at the
  `1x` floor, population is capped and overflow is deferred to v2.
- **The lie.** Animation implying communication the data does not describe.
  See I1. This is the one that quietly destroys the product's only value.
