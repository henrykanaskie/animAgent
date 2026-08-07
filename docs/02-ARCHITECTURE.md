# 02 — Architecture

## Data flow

```
Claude Code session(s)
   │  HTTP POST, JSON body, one per hook event
   ▼
Listener            Network.framework, in-process
   │  decode → HookEvent, enqueue, return 202 immediately   [I5]
   ▼
EventQueue          bounded, lock-free handoff to the model actor
   │
   ▼
WorldModel          actor. sessions → agents → open tool calls
   │  emits ordered WorldDelta values
   ▼
SceneDirector       translates deltas into sprite intents
   │
   ▼
RoomScene           SpriteKit. characters, badges, camera
   │
   ▼
NotchPanel          AppKit. reveal, retract, geometry
```

One direction only. Nothing downstream ever calls back upstream. The scene
cannot ask the model a question; it receives deltas and renders them.

## Modules

### `SpriteRoomCore` — no AppKit, no SpriteKit

The whole point of this boundary: the interesting logic is testable headlessly,
and the replay harness can drive it at 1000x speed.

**`Ingest/Listener`**
Binds `127.0.0.1` on a configured port, loopback only, never `0.0.0.0`.
Per request: read body, decode, enqueue, respond `202` empty. If decoding fails,
still respond `202` and count the failure — a malformed event must never slow
the user's session or surface an error into Claude Code. [I5]

**`Ingest/HookEvent`**
Decodes the payload's common fields (`session_id`, `cwd`, `hook_event_name`,
`agent_id`, `agent_type`, `permission_mode`) plus the per-event fields we use
(`tool_name`, `tool_use_id`, `source`, `reason`). Unknown event names decode to
`.unhandled(name:)` rather than throwing — the hook surface grows, and a new
event must never crash the app.

**`Model/WorldModel`** — an `actor`
Owns all mutable state. Single writer. This is what makes I3 and I4 tractable.

```
World
 └── Project (keyed by cwd)
      └── Session (keyed by session_id)
           └── Agent (keyed by agent_id ?? .mainThread)
                ├── agentType: String?
                ├── openCalls: [ToolUseID: OpenCall]     // a SET  [I3]
                └── lifecycle: .spawning | .active | .reporting | .departed
```

`OpenCall` holds the tool name, start time, and a **deadline**. A repeating
sweep closes expired calls and emits `.toolCallAbandoned`. `SessionEnd` closes
everything under that session. [I4]

**`Model/WorldDelta`**
The only thing that leaves the actor. Value types, ordered, self-contained:
`agentAppeared`, `agentDeparted`, `callOpened`, `callClosed`, `callAbandoned`,
`reportDelivered`, `populationChanged`. The scene needs no other input.

### `SpriteRoomScene`

**`SceneDirector`** — maps deltas to intents. Holds the only policy about *how*
a delta looks: which badge a tool maps to, how long a walk takes, what happens
when two deltas for one character arrive in the same frame.

**`Character`** — an `SKNode`. Owns a small animation state machine. Given
"three open calls," it shows one badge plus a count; it does not try to
represent three tools. Deterministic choice, not most-recent, so the badge does
not flicker when calls interleave.

**`RoomCamera`** — population in, integer scale out. Pure function, unit
tested, no SpriteKit types in its signature. [I6]

### `SpriteRoomApp`

**`NotchPanel`** — `NSPanel`, `.nonactivatingPanel`, `.borderless`, level above
the menu bar, `canJoinAllSpaces`, `hidesOnDeactivate = false`. Reveal on pointer
entering the notch region, retract on exit with a short grace period so a
diagonal mouse path does not flicker it. Pointer-only. [I8]

**`ProjectSelector`** — which `cwd` group is displayed. Menu bar item, not a
control inside the panel; the panel stays a pure display surface.

## Concurrency

- Listener runs on its own `DispatchQueue`.
- `WorldModel` is an actor; all mutation is serialized there.
- Deltas cross to `@MainActor` in batches, once per frame, not per event. A
  burst of forty events in one millisecond produces one frame's work.
- Strict concurrency checking is on. Do not silence it with `@unchecked
  Sendable` — if a type needs that, the design is wrong.

## Configuration

The app writes the hook block into `~/.claude/settings.json` on first run, after
asking, and never touches project-level settings files — hooks registered once
at user scope, routed by `cwd`, is the whole point.

**Nothing else is persisted, and this paragraph used to claim otherwise.** It
described port and selected project living in a JSON file under
`~/Library/Application Support/SpriteRoom/`. No such file is read or written.
The port is a command-line flag; the selected project lives in `ProjectRegistry`
in memory and resets every launch. The only thing that directory ever holds is
`settings-backup.json`, written while hooks are installed so the removal path
can restore the user's file byte for byte.

That is consistent with "no persistence of events — the world is live state and
dies with the app" below. If a preference ever does need to survive a launch,
add it deliberately; do not assume this file already exists because a document
once said it did.

## What is deliberately absent

No database. No persistence of events — the world is live state and dies with
the app. No IPC layer. No abstraction over the event source. No dependency
injection framework. If you feel the urge to add one, write an ADR first and
expect it to be rejected.
