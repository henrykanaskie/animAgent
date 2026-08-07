# 03 — Event model

The contract between the hook surface and the room. Read this before touching
ingest or the scene. Everything here is either taken from the hooks reference or
is a decision recorded as such.

## Identity resolution

Run on every event, in this order:

1. `cwd` → project bucket.
2. `session_id` → session within that project.
3. `agent_id` present → that subagent. **Absent → the main thread agent.**
4. `agent_type` → sprite variant and nameplate. Absent → default variant.

Two subagents of the same `agent_type` are different characters; identity is
`agent_id`, never the type. Do not merge them into one avatar.

## Events we consume

| Event | Effect on the world |
|---|---|
| `SessionStart` | Create session. Create the main-thread agent. Character walks in. |
| `SubagentStart` | Create agent under `agent_id`. Character spawns beside the anchor. |
| `PreToolUse` | Open a call keyed by `tool_use_id`. Character enters/keeps working. |
| `PostToolUse` | Close that `tool_use_id`. |
| `PostToolUseFailure` | Close that `tool_use_id`, flagged failed. |
| `PostToolBatch` | Reconcile: close any call for this agent not seen closing. Safety net for I3. |
| `SubagentStop` | Agent enters `.reporting` → walks to anchor → delivers → departs. |
| `Stop` | Main agent goes idle. Turn over. |
| `SessionEnd` | Close every open call in the session. All characters leave. [I4] |
| `Notification` | Main agent shows an attention badge (`permission_prompt`, `idle_prompt`). Badge only — no body animation exists for this. |

Everything else decodes to `.unhandled` and is counted, not dropped silently.
A rising `.unhandled` count is how we notice the hook surface has grown.

## Pairing rule

`PreToolUse` and `PostToolUse` for one call share a `tool_use_id`. That is the
join key. **Never pair by tool name, and never assume the next `PostToolUse` for
an agent closes the most recent `PreToolUse`** — parallel calls make both wrong.

```
open:  openCalls[tool_use_id] = OpenCall(tool, startedAt, deadline)
close: openCalls.removeValue(forKey: tool_use_id)
agent is working  ⟺  !openCalls.isEmpty
```

## Reaping

Every open call has a deadline. Defaults, revisit with data:

| Tool class | Deadline |
|---|---|
| `Read`, `Glob`, `Grep`, `TodoWrite` | 30 s |
| `Edit`, `Write`, `NotebookEdit` | 60 s |
| `Bash`, `Task`, `WebFetch`, `mcp__*` | 15 min |
| unknown | 5 min |

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
| checklist | `TodoWrite`, `Task` |
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

## Fixtures

`fixtures/` holds captured payloads from real sessions. Capture procedure is in
`docs/06-WORKFLOW.md`. Required coverage before M2 is signed off:

- `single-agent-simple` — one session, sequential tools.
- `parallel-tools` — one agent, ≥3 concurrent `tool_use_id`s. Proves I3.
- `three-subagents` — spawn, overlap, staggered stops.
- `killed-session` — `PreToolUse` with no matching close, no `SessionEnd`.
  Proves I4 via the deadline path.
- `unknown-events` — payloads with an unrecognised `hook_event_name`.

A change to the ingest layer that does not run green against all five is not
done.

## Hook registration

Registered once at user scope in `~/.claude/settings.json`, matcher `*`, so it
covers every project and routes by `cwd`. The block the app writes lives in
`.claude/settings.example.json` in this repo. Note there is no `async` field for
HTTP hooks — the session waits on our response, which is the entire reason for
I5.
