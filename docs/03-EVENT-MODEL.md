# 03 — Event model

The contract between the hook surface and the room. Read this before touching
ingest or the scene. Everything here is either taken from the hooks reference,
verified against captured payloads in `fixtures/`, or is a decision recorded as
such. Claims not yet seen in a real capture are marked **[unverified]** — they
stay, because absence of observation is not evidence of absence, but nothing
downstream may assume them. Verified against Claude Code **2.1.224**; see
`docs/FINDINGS-M0.md`.

## Identity resolution

Run on every event, in this order:

1. `cwd` → project bucket.
2. `session_id` → session within that project.
3. `agent_id` present → that subagent. **Absent → the main thread agent.**
4. `agent_type` → sprite variant and nameplate. Absent → default variant.

Two subagents of the same `agent_type` are different characters; identity is
`agent_id`, never the type. Do not merge them into one avatar.

Rule 3 is confirmed across every captured event: `agent_id` appears on subagent
events and is *absent as a key* — not null — on main-thread events. It is an
opaque string (`a` + 17 hex chars).

`agent_type` is **not** a subagent marker and must never be used as one. It also
appears on the main thread of a session started with `--agent`, where there is
no `agent_id`. Only rule 3 decides main-vs-subagent.

Nothing may wait for a lifecycle event to create identity. A session, and its
main-thread agent, are created **lazily on the first event of any kind** that
carries their `session_id`. `SessionStart` did not fire at all in any captured
headless session, so any model that requires it starts empty and stays empty.

## Events we consume

| Event | Effect on the world |
|---|---|
| `SessionStart` | Decoration only: record `source`, `model`, `session_title`. Never a precondition — it did not fire in any captured session, so the session and its main agent are created lazily by whatever event arrives first. |
| `SubagentStart` | Create agent under `agent_id`. Character spawns beside the anchor. Carries `agent_id` and `agent_type`, nothing else. |
| `PreToolUse` | Open a call keyed by `tool_use_id`. Character enters/keeps working. |
| `PostToolUse` | Close that `tool_use_id`. |
| `PostToolUseFailure` | Close that `tool_use_id`, flagged failed. Fires *instead of* `PostToolUse`, never alongside it; the message is in `error`, not `tool_response`. |
| `PostToolBatch` | Close every `tool_use_id` in `tool_calls[]`. A primary close path, not a sweep — see below. |
| `SubagentStop` | Agent enters `.reporting` → walks to anchor → delivers → departs. |
| `Stop` | Main agent pauses. **Not** "turn over" — it fires once per assistant message stream, several times in one user turn when async subagents wake the main thread. Never treat it as end-of-session or as a reap trigger. |
| `SessionEnd` | Close every open call in the session. All characters leave. [I4] |
| `Notification` | Main agent shows an attention badge (`permission_prompt`, `idle_prompt`). Badge only — no body animation exists for this. **[unverified]** — never observed in headless capture, which has no one to notify. |

Everything else decodes to `.unhandled` and is counted, not dropped silently.
A rising `.unhandled` count is how we notice the hook surface has grown.

"Everything else" is not hypothetical. 2.1.224 defines at least sixteen further
event names we do not consume, including `UserPromptSubmit`,
`UserPromptExpansion`, `StopFailure`, `PreCompact`, `PostCompact`,
`PermissionRequest`, `PermissionDenied`, `TaskCreated`, and `TaskCompleted`. All
of them will reach the listener under a `*` registration. They must decode, be
counted, and change nothing.

## Pairing rule

`PreToolUse` and its close share a `tool_use_id`. That is the join key.
**Never pair by tool name, and never assume the next close for an agent closes
the most recent `PreToolUse`** — parallel calls make both wrong. In
`fixtures/parallel-tools.jsonl` five concurrent calls close in a different order
from the one they opened in, which is the proof.

There are **three** close paths, and all three are mandatory:

```
open:   openCalls[tool_use_id] = OpenCall(tool, startedAt, deadline)

close:  PostToolUse         → remove(tool_use_id)
        PostToolUseFailure  → remove(tool_use_id), flagged failed
        PostToolBatch       → for each tool_calls[].tool_use_id: remove

agent is working  ⟺  !openCalls.isEmpty
```

`PostToolBatch` is not optional tidying. A tool call refused at the permission
gate emits `PreToolUse` and then **neither** `PostToolUse` nor
`PostToolUseFailure`; its only close is its appearance in the following
`PostToolBatch`. Every declined permission prompt is that case. Handling only
`PostToolUse` leaks an open call on each one and produces the character that
types forever. [I4]

**Closing is idempotent.** `PostToolBatch` re-reports calls that a preceding
`PostToolUse` or `PostToolUseFailure` already closed — both appear for the same
`tool_use_id` in `fixtures/tool-failure.jsonl`. Closing an already-closed id
must be a no-op and must **not** emit a second `.callClosed`. A delta stream
with duplicate closes makes the scene's open-call count drift negative, which
shows up much later as a character stuck idle while it is working.

## Reaping

Every open call has a deadline. Defaults, revisit with data:

| Tool class | Deadline |
|---|---|
| `Read`, `Glob`, `Grep`, `TodoWrite` | 30 s |
| `Edit`, `Write`, `NotebookEdit` | 60 s |
| `Bash`, `WebFetch`, `mcp__*` | 15 min |
| `Agent` | 30 s |
| unknown | 5 min |

`Agent` is the subagent-dispatch tool. Its hook name is `Agent`, not `Task` —
`Task` is the model-facing name and never appears in a payload. It launches
asynchronously and its own call closes in milliseconds, so it gets a short
deadline; the subagent's life is tracked by `agent_id`, not by this call.

On expiry: close the call, emit `.callAbandoned`, increment a counter. The
character returns to idle. It does **not** display an error — an abandoned call
is usually our blind spot, not the user's failure.

Additional sweeps: `SessionEnd` closes all. A session with no event for 30
minutes is presumed dead and closed. Both are belt and braces for I4; keep both.

## Tool → badge mapping

The body shows *that* work is happening; a badge above the head shows *which
kind*. There are no held props — see `04-ART-DIRECTION.md` for why that model
was dropped.

Collapse aggressively; a user cannot distinguish twelve icons at `2x`.

| Badge | Tools |
|---|---|
| document | `Edit`, `Write`, `NotebookEdit` |
| magnifier | `Read`, `Glob`, `Grep` |
| terminal | `Bash`, `BashOutput`, `KillShell` |
| globe | `WebSearch`, `WebFetch` |
| checklist | `TodoWrite`, `Agent` |
| plug | `mcp__*` (any) |
| question mark | anything unmapped |

Unmapped tools get the question mark and are logged. Never invent a badge for a
tool you do not recognise — the question mark is honest, a guess is not. [I1]

**Multiple open calls:** display the badge for the *lowest-ordinal* tool in the
table above, plus a small `×N`. Deterministic ordering means the badge is
stable while calls interleave; most-recent-wins would flicker. [I3]

**Body state while working** is the sitting pose, regardless of tool. The tool
identity lives entirely in the badge. This is what lets a new tool name appear
tomorrow without new art.

## The reporting animation

`SubagentStop` is the only event that licenses the walk. What it actually means
is "this subagent finished and its result went to its parent." The walk is a
*dramatisation of that fact*, which is allowed. What is not allowed:

- Showing a subagent walking over mid-task because it produced output.
- Showing dialogue, speech bubbles with content, or any hint of what was said.
- Showing agents talking to each other. There is no event for that. [I1]

Because the main agent's anchor is always on screen, a report from an
off-screen subagent is still visible: it walks in, delivers, leaves.

**Do not time the walk off the spawning tool call.** Subagents launch
asynchronously: the `Agent` call's `PreToolUse`/`PostToolUse` pair closes in
~16 ms while the subagent runs for minutes. A subagent's life is
`SubagentStart` → `SubagentStop`, keyed by `agent_id`, and nothing else.

The parent link, when we need one, is `tool_response.agentId` on the `Agent`
tool's `PostToolUse` — it maps the parent's `tool_use_id` to the child's
`agent_id`. There is no `parent_agent_id` field. If that link is missing, the
subagent anchors to the main agent rather than guessing. [I1]

## Fixtures

`fixtures/` holds captured payloads from real sessions. The capture tool is
`tools/hook-logger/`; the procedure and the provenance of each file are in
`fixtures/README.md`. Required coverage before M2 is signed off:

- `single-agent-simple` — one session, sequential tools.
- `parallel-tools` — one agent, ≥3 concurrent `tool_use_id`s. Proves I3.
  Captured with 5, closing out of order.
- `three-subagents` — spawn, overlap, staggered stops.
- `killed-session` — `PreToolUse` with no matching close, no `SessionEnd`.
  Proves I4 via the deadline path.
- `tool-failure` — a `PostToolUseFailure` close, and a permission-denied call
  whose only close is the following `PostToolBatch`. Proves both non-
  `PostToolUse` close paths. Must replay to zero open calls *without* the
  deadline sweep firing; if the reaper is needed, the close paths are wrong.
- `unknown-events` — payloads with an unrecognised `hook_event_name`.

A change to the ingest layer that does not run green against all six is not
done.

Capture at **project scope**, in a throwaway directory, never at user scope. A
`*` registration in `~/.claude/settings.json` injects hooks into the developer's
own live session; project scope isolates the run and lets the `cwd` assertion
prove it did.

## Hook registration

Claude Code supports a native HTTP hook type — the session POSTs the hook input
JSON straight to a URL. No shim script:

```json
{ "type": "http", "url": "http://127.0.0.1:<port>/hook" }
```

Optional fields: `timeout` (seconds), `headers`, `statusMessage`, `once`, `if`.

The app registers one such entry per consumed event at user scope in
`~/.claude/settings.json`, matcher `*`, so it covers every project and routes by
`cwd`. The block the app writes lives in `.claude/settings.example.json` in this
repo.

There is no `async` field on the HTTP hook schema — `command` hooks have one,
HTTP hooks do not. The session blocks on our response. Measured: a listener that
holds for 3 s adds 3 s to every tool call. That is the entire reason for I5.
