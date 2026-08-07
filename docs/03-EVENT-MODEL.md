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

`agent_type` may also be the **empty string** — present as a key, with no value.
M0c saw this on every interactive `SubagentStop` from the TUI's suggestion
helper. Rule 4 says "absent → default variant"; an empty string is neither
absent nor a usable nameplate, so treat empty as absent.

Nothing may wait for a lifecycle event to create identity. A session, and its
main-thread agent, are created **lazily on the first consumed event** that
carries their `session_id`. `SessionStart` has never been seen by this app's
transport — not in five headless runs, and not in fourteen real interactive
sessions driven under a pty at M0c — so any model that requires it starts empty
and stays empty.

M0c established *why*, and the reason is stronger than the one M0a recorded.
`SessionStart` does fire; it is simply **never delivered to a `type: "http"`
hook**. A `command` hook registered in the same entry received it in all 8
sessions where both were registered, while the HTTP endpoint received none. So
this is not a property of headless mode, and it will not be fixed by a matcher.
See `docs/FINDINGS-M0.md`.

There is a second reason lazy creation is load-bearing, also from M0c: **`/clear`
ends the session and silently starts a new one.** It emits `SessionEnd` with
`reason: "clear"`, and the next prompt in the same process carries a different
`session_id` whose first event is an ordinary `UserPromptSubmit`. One `claude`
process hosts a sequence of sessions, and only the first of them could ever have
had a startup event at all.

*Consumed*, not "any event" — an earlier draft of this line said any event, and
that contradicted the rule that an unhandled event changes nothing. Unhandled
events are counted and refresh the session's liveness timer, but must never
create a session, an agent, or tool state. Otherwise a synthetic event arriving
after `SessionEnd` resurrects a dead session, and an unrecognised event carrying
an `agent_id` spawns a character out of something we do not understand. [I1]

That resolution had a cost, and M4 paid it off: a session whose turn produced no
tool call had no character at all, because `UserPromptSubmit` was not in the
consume table below. An agent that was thinking was invisible. The fix taken was
to **consume `UserPromptSubmit`** — the event genuinely happened, and an idle
character is a truthful thing to draw [I2] — rather than to weaken the unhandled
rule. It creates the session and its main agent and has no other effect.

## Events we consume

| Event | Effect on the world |
|---|---|
| `SessionStart` | **Unreachable over HTTP — do not build on it.** The event is real and fires on every session (`source: startup` / `clear`, plus `model` on startup), but 2.1.224 never delivers it to a `type: "http"` hook, and this app registers nothing else. Keep the decode so the name is recognised rather than counted unhandled; the handler will not run. `session_title` does not exist in the payload — the field list here was wrong. |
| `UserPromptSubmit` | Creates the session and its main-thread agent, and **nothing else**. The character it draws is idle, because nothing has been called yet. Consumed for one reason: without it the main character does not exist until the session's first tool call, so a turn spent thinking draws an empty room. [I2] |
| `SubagentStart` | Create agent under `agent_id`. Character spawns beside the anchor. Carries `agent_id` and `agent_type`, nothing else. |
| `PreToolUse` | Open a call keyed by `tool_use_id`. Character enters/keeps working. |
| `PostToolUse` | Close that `tool_use_id`. |
| `PostToolUseFailure` | Close that `tool_use_id`, flagged failed. Fires *instead of* `PostToolUse`, never alongside it; the message is in `error`, not `tool_response`. |
| `PostToolBatch` | Close every `tool_use_id` in `tool_calls[]`. A primary close path, not a sweep — see below. |
| `SubagentStop` | Agent enters `.reporting` → walks to anchor → delivers → departs. |
| `Stop` | Main agent pauses. **Not** "turn over" — it fires once per assistant message stream, several times in one user turn when async subagents wake the main thread. Never treat it as end-of-session or as a reap trigger. |
| `SessionEnd` | Close every open call in the session. All characters leave. [I4] Observed `reason`s: `prompt_input_exit`, `clear`. **Not** "the process is exiting" — `/clear` ends a session and the same process continues under a new `session_id`. |
| `Notification` | Main agent shows an attention badge. Badge only — no body animation exists for this. Verified at M0c: `notification_type` is exactly `permission_prompt` ("Claude needs your permission") or `idle_prompt` ("Claude is waiting for your input"). Carries no `tool_use_id` and no `agent_id`, so it can only mean the main thread. |

**Notification timing, because the badge is a timed thing.** `permission_prompt`
arrives 6.0 s after the permission gate opens, not instantly (three occurrences,
6.014 / 6.006 / 6.032 s after `PermissionRequest`). `idle_prompt` arrives
**60.02 s after `Stop`** and fires exactly **once** — a session left idle a
further 145 s produced no second one. So an `idle_prompt` badge means "this has
been waiting a while", not "this is waiting"; `Stop` with an empty open-call set
already says the latter, immediately and for free. Nothing may drive a
"currently idle" state off `idle_prompt`, and nothing may expect a repeat.

Everything else decodes to `.unhandled` and is counted, not dropped silently.
A rising `.unhandled` count is how we notice the hook surface has grown.

"Everything else" is not hypothetical. 2.1.224 defines at least fifteen further
event names we do not consume, including `UserPromptExpansion`, `StopFailure`,
`PreCompact`, `PostCompact`, `PermissionRequest`, `PermissionDenied`,
`TaskCreated`, and `TaskCompleted`. All of them will reach the listener under a
`*` registration. They must decode, be counted, and change nothing.

Two of those are no longer hypothetical either, and M0c settled what they are
worth:

- **`PermissionRequest` is real and fires over HTTP**, ~16 ms after the
  `PreToolUse` for the same call. It carries `tool_name`, `tool_input` and
  `permission_suggestions[]` — and **no `tool_use_id`**. It therefore cannot be
  joined to an open call without pairing by tool name, which the pairing rule
  below forbids. It is a "this agent is blocked on a human" signal, not a close
  signal. Not consumed.
- **`PermissionDenied` still has never fired.** **[unverified]** — registered
  over both HTTP and `command` delivery and tested against both denial paths a
  user has (selecting "No" at the dialog, and Esc to cancel). Neither produced
  it. The name exists; the condition that emits it is unknown.

The app registers only the eleven events above, so in normal operation the
others never arrive at all — but the listener is not allowed to depend on that,
because a `*` registration written by hand, or a future release that widens what
a registration covers, would deliver them anyway.

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
`PostToolBatch`. Handling only `PostToolUse` leaks an open call on each one and
produces the character that types forever. [I4]

**That paragraph used to end "Every declined permission prompt is that case."
M0c proved it false, and the correction is not a small one.** There are two
denial shapes:

| Denial | Close path |
|---|---|
| Headless auto-deny — `fixtures/tool-failure.jsonl` | the following `PostToolBatch` |
| **Interactive user denial** — "No" at the dialog, or Esc — `fixtures/permission-prompt.jsonl` | **none at all** |

In `fixtures/permission-prompt.jsonl` the denied call
`toolu_0199hyfQtR1Hf3i3feHZvivV` receives no `PostToolUse`, no
`PostToolUseFailure`, no mention in any `PostToolBatch` (the following one lists
only the later approved call), and its turn produces no `Stop`. Nothing in the
stream closes it. Its only closes are `SessionEnd` and the deadline sweep.

Nothing above is weakened: `PostToolBatch` remains a mandatory primary close
path. What was wrong was the coverage claim. **`PostToolBatch` covers the
headless denial and none of the interactive ones**, and interactive denial is
the common case for a real user.

The consequence is live: `Bash` carries the 15-minute deadline, so clicking
"No" on a `Bash` prompt currently leaves that character working for fifteen
minutes. That is the signature bug of this project on the most ordinary
interaction there is. **Deliberately not fixed here** — the close-path model is
verified and load-bearing and changing it is the maintainer's call. The options
on the table, recorded so the next person does not have to rediscover them:
a shorter deadline for a call known to be sitting at a permission gate; treating
a session's next `UserPromptSubmit` as closing anything still open from the
previous prompt; or consuming `PermissionRequest` and joining it by
`tool_name` + `tool_input`, which the pairing rule forbids and which should
probably stay forbidden. The first two do not break any existing rule.

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
| `Bash`, `WebFetch`, `Agent`, `mcp__*` | 15 min |
| unknown | 5 min |

`Agent` is the subagent-dispatch tool. Its hook name is `Agent`, not `Task` —
`Task` is the model-facing name and never appears in a payload. The subagent's
life is tracked by `agent_id`, never by this call.

**`Agent` dispatches both synchronously and asynchronously, and we cannot tell
which in advance.** M0 captured the async form: `tool_response.isAsync == true`,
`status: async_launched`, the call closing in ~16 ms while the subagent ran for
minutes. M4 observed the synchronous form: the call stayed open for the
subagent's entire life. Both are real.

It therefore carries the long deadline. The 30 s it used to carry assumed the
async form, and against the synchronous form it rendered a lie — the parent's
call was abandoned at 30 s while the parent was genuinely still working, so the
character went idle mid-task. **A late reap is a blind spot; an early one is
fiction.** [I1] The cost of the long deadline, a genuinely lost close lingering,
is already covered twice by `SessionEnd` and the 30-minute idle sweep.

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

**`SubagentStop` arrives for agents that never started.** Interactive sessions
run an internal helper that generates the TUI's follow-up suggestions, and it
emits a `SubagentStop` carrying an `agent_id`, an `agent_type` of `""`, and an
`agent_transcript_path` — with no `SubagentStart`, and in sessions where the
`Agent` tool was never called at all. Four occurrences at M0c, 1.69–2.08 s after
`Stop`, in every interactive turn that used a tool.

So `SubagentStop` for an unknown `agent_id` **must** be a no-op. It is not a
tidy edge case; it fires on ordinary turns, and a model that spawns a character
in order to walk it off screen puts a nameless phantom in the room several times
per session. [I1] This is implemented as of M1 and is now evidenced by
`fixtures/interactive-session.jsonl` rather than argued from taste.

**Do not time the walk off the spawning tool call.** Subagents launch
asynchronously: the `Agent` call's `PreToolUse`/`PostToolUse` pair closes in
~16 ms while the subagent runs for minutes. A subagent's life is
`SubagentStart` → `SubagentStop`, keyed by `agent_id`, and nothing else.

The parent link is `tool_response.agentId` on a `PostToolUse` — it maps the
`tool_use_id` of the call that launched or resumed a subagent to that subagent's
`agent_id`. There is no `parent_agent_id` field. If the link is missing, the
subagent anchors to the main agent rather than guessing. [I1]

Implemented in M4. Three things about it are worth writing down, because two of
them were not visible in the M0 capture:

- **It is always retroactive.** `SubagentStart` arrives *before* the
  `PostToolUse` that carries the link, so the character is already on screen
  when we learn who it reports to. The model therefore emits a separate
  `agentLinked` delta rather than folding the parent into `agentAppeared`, and
  holds the link pending if the child is not there yet.
- **It is not only the `Agent` tool.** `SendMessage` — continuing an existing
  subagent — returns a `tool_response.agentId` too, and observing it is how a
  resumed subagent gets linked. Keying the decode on `tool_response.agentId`
  rather than on `tool_name == "Agent"` is deliberate.
- **`Agent` is not always asynchronous.** M0 captured `isAsync: true,
  status: async_launched`, where the dispatch call closes in ~16 ms. In a live
  M4 session the same tool ran *synchronously*: the `Agent` call stayed open for
  the subagent's whole lifetime and closed after its `SubagentStop`. Both shapes
  occur. Nothing may assume either — which is exactly why a subagent's life is
  tracked by `agent_id` and never by its spawning call.

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

**Interactive coverage, added at M0c.** Three further captures, from real TUI
sessions driven under an allocated pty rather than `claude -p`. They are not in
the required six — that list is an exit criterion that has already been signed
off and is not mine to rewrite — but they are ground truth and they cover events
the six cannot contain:

- `interactive-session` — a real interactive session, start to `/exit`. Settles
  `SessionStart` by absence, and carries the phantom `SubagentStop`.
- `permission-prompt` — a real permission dialog, denied then approved. Carries
  `PermissionRequest`, both `Notification` types' first half, and the
  never-closed denied call. **This one does not replay to zero open calls
  without the reaper**, by nature, exactly like `killed-session`.
- `idle-notification` — `Notification` with `notification_type: idle_prompt`,
  60 s after `Stop`.

`permission-prompt` is the one that should join the required set if the
interactive-denial close path above is ever resolved, because it is the fixture
that would prove the fix.

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
repo, and a test asserts the two agree.

`UserPromptSubmit` and `PostToolBatch` are registered **without** a matcher.
That is the shape both were captured working under; neither takes a tool name,
so a matcher has nothing to match.

`Notification` is registered with matcher `*` and was confirmed at M0c to fire
under exactly that shape, with no other `Notification` entry present.

**The `SessionStart` registration is inert.** It costs nothing and is worth
keeping so the entry is already correct if a future release starts delivering
it, but no HTTP hook in 2.1.224 ever receives that event — tested against six
matcher forms at once (none, `*`, `startup`, `resume`, `clear`, `compact`) over
8 sessions. Nothing should be surprised that it never arrives, and nothing
should be built on it arriving.

M4 verified the registration end to end against the real file: install, a
session in a directory with no project-level settings whose events arrived
anyway, then removal restoring the file byte for byte.

There is no `async` field on the HTTP hook schema — `command` hooks have one,
HTTP hooks do not. The session blocks on our response. Measured: a listener that
holds for 3 s adds 3 s to every tool call. That is the entire reason for I5.
