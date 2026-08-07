# FINDINGS — M0

What real hook payloads actually look like, and what the assets actually
contain. Written during M0 so nothing downstream is designed against a guess.

---

## Payloads

Owner: `test-engineer`. Captured 2026-08-07, Claude Code **2.1.224**, macOS
(Darwin 25.5.0). Evidence: `fixtures/*.jsonl` (91 lines across five files) and
the `HookSchema` definitions embedded in the `claude` binary.

Captures were run in a throwaway sandbox project with a **project-scoped**
`.claude/settings.json`. `~/.claude/settings.json` was not touched, so no hooks
were injected into any real session. Every `cwd` in every fixture is the sandbox
directory — checked programmatically, zero off-sandbox events.

### HTTP hooks: native, and blocking

**`02-ARCHITECTURE.md`'s core assumption holds.** Claude Code supports a
first-class HTTP hook type. A hook entry may be `{"type": "http", "url": "..."}`
and the CLI POSTs the hook input JSON to that URL directly. No shim script, no
`curl` wrapper. The schema, verbatim from the binary:

```
type: "http"          HTTP hook type
url:  string().url()  URL to POST the hook input JSON to
timeout: number       seconds, optional
headers: record<string,string>   optional; $VAR interpolation via allowedEnvVars
statusMessage: string optional
once: boolean         optional
if: <condition>       optional
```

The five hook types the CLI accepts are `command`, `prompt`, `agent`, `http`,
and `mcp_tool`.

`03-EVENT-MODEL.md` claims there is no `async` field for HTTP hooks and that the
session therefore waits on our response. **Both halves confirmed.** The
`command` hook schema carries `async`, `asyncRewake`, and `rewakeMessage`; the
`http` schema carries none of them. Measured empirically with a listener that
slept 3 s before answering: a two-tool session took 20.7 s wall against a 12.0 s
baseline, i.e. the two `PreToolUse` hooks each added their full 3 s to the
user's turn. **I5 is not a stylistic preference. It is the difference between a
working app and a tool-call tax.**

The registration-scope claim ("registered once at user scope") is correct but
incomplete: project-scoped `.claude/settings.json` also works, and is how these
fixtures were captured. Worth knowing, because it is the only safe way to test
hook changes without touching the developer's own session.

### Which events actually fired

Exact `hook_event_name` strings observed across all captures:

| String | Observed | Notes |
|---|---|---|
| `UserPromptSubmit` | yes, 8x | not in our consume table; see below |
| `PreToolUse` | yes, 24x | |
| `PostToolUse` | yes, 22x | |
| `PostToolUseFailure` | yes, 1x | **real** |
| `PostToolBatch` | yes, 13x | **real**, and load-bearing |
| `SubagentStart` | yes, 3x | **real** |
| `SubagentStop` | yes, 3x | |
| `Stop` | yes, 7x | fires more than once per turn |
| `SessionEnd` | yes, 6x | |
| `SessionStart` | **never** | see gap below |
| `Notification` | **never** | see gap below |
| `PermissionRequest` / `PermissionDenied` | **never** | registered, never fired |

The three events the brief flagged as possibly invented are **all real**. The
binary's hook-event-name array in 2.1.224 is:

```
PreToolUse, PostToolUse, PostToolUseFailure, PostToolBatch, Notification,
UserPromptSubmit, UserPromptExpansion, SessionStart, SessionEnd, Stop,
StopFailure, SubagentStart, SubagentStop, PreCompact, PostCompact,
PermissionRequest, PermissionDenied, Setup, TeammateIdle, TaskCreated,
TaskCompleted, Elicitation, ElicitationResult, ConfigChange, WorktreeCreate, ...
```

`03-EVENT-MODEL.md`'s table was conservative, not speculative. It named nine
events and all nine exist. It is missing at least sixteen others.

### `agent_id` — the load-bearing claim, verified

`CLAUDE.md` and `03-EVENT-MODEL.md` both stake the identity model on `agent_id`
being present only inside a subagent, absent for the main thread. **Confirmed,
without exception, across all 91 captured events.** Every event carrying
`agent_id` was produced inside a subagent; no main-thread event carried it.

Main thread — `fixtures/three-subagents.jsonl` line 2, the `Agent` tool call
that *spawns* a subagent. Note there is no `agent_id` key at all; it is absent,
not null:

```json
{"session_id": "713a9c5d-9c0f-42e1-9048-173777c6bd06",
 "cwd": ".../m0-capture", "prompt_id": "558b59f7-...", "permission_mode": "acceptEdits",
 "effort": {"level": "high"}, "hook_event_name": "PreToolUse", "tool_name": "Agent",
 "tool_input": {"description": "Read alpha.txt and sleep", "subagent_type": "Explore"},
 "tool_use_id": "toolu_01QSg56NdKCtC53mnSGWu8eo"}
```

Inside that subagent — same file, line 13:

```json
{"session_id": "713a9c5d-9c0f-42e1-9048-173777c6bd06",
 "cwd": ".../m0-capture", "prompt_id": "558b59f7-...", "permission_mode": "acceptEdits",
 "agent_id": "a793beae9fa532d0f", "agent_type": "Explore",
 "effort": {"level": "high"}, "hook_event_name": "PreToolUse", "tool_name": "Read",
 "tool_use_id": "toolu_01NdqvLHLSnW7dccJfpjjWyF"}
```

The CLI's own schema says the same thing in as many words:

> `agent_id` — "Subagent identifier. Present only when the hook fires from
> within a subagent (e.g., a tool called by an AgentTool worker). Absent for the
> main thread, even in `--agent` sessions. Use this field (not `agent_type`) to
> distinguish subagent calls from main-thread calls."

Format: seventeen lowercase hex characters prefixed `a`, e.g.
`a793beae9fa532d0f`. Treat it as an opaque string.

**One caveat the docs did not have.** `agent_type` is *not* a subagent marker:

> `agent_type` — "Present when the hook fires from within a subagent (alongside
> `agent_id`), or on the main thread of a session started with `--agent`
> (without `agent_id`)."

So a `--agent` session's main thread carries `agent_type` and no `agent_id`.
Anything keying identity off `agent_type` will misclassify that session. Not
observed in capture (all runs used the default agent) — verified from schema
only, and marked as such in the doc.

Observed `agent_type` values: `Explore`, `general-purpose`. Both are the
`subagent_type` string from the spawning `Agent` call's `tool_input`, echoed
back — so custom agent names from `.claude/agents/` will appear here verbatim.

### `tool_use_id` overlap — I3 confirmed with real concurrency

Peak concurrent open `tool_use_id`s, computed by replaying each fixture:

| Fixture | Peak open, one agent | Peak open, all agents | Open at EOF |
|---|---|---|---|
| `single-agent-simple` | 1 | 1 | 0 |
| `parallel-tools` | **5** | 5 | 0 |
| `three-subagents` | 1 | 2 | 0 |
| `killed-session` | 1 | 1 | **1** |
| `unknown-events` | 1 | 1 | 0 |

`parallel-tools` holds five concurrent `Bash` calls on one agent — above the >=3
the fixture spec requires. The close order differs from the open order:

```
open   Cai7qy  016NnP  01RvXb  018gju  01PEpE
close  016NnP  01RvXb  Cai7qy  01PEpE  018gju
```

That is the empirical death of "the next `PostToolUse` closes the most recent
`PreToolUse`." `03-EVENT-MODEL.md` already forbade that assumption on reasoning;
it is now forbidden on evidence.

`three-subagents` shows only 2 concurrent calls across all agents, because each
subagent happened to work sequentially. Agent-level overlap is what that fixture
proves: all three subagents were alive simultaneously for ~11 s, and stopped
staggered at +12 s, +19 s, +32 s.

### `PostToolBatch` is not a safety net. It is the only close path for some calls

`03-EVENT-MODEL.md` described `PostToolBatch` as a reconciliation "safety net."
That understates it. Two observed cases produce a `PreToolUse` that **never**
gets a `PostToolUse` or a `PostToolUseFailure`, and whose only close signal is
its `tool_use_id` appearing in the next `PostToolBatch`:

1. A tool call denied at the permission gate. Captured in
   `fixtures/unknown-events.jsonl` — `PreToolUse` for `Bash`, then straight to
   `PostToolBatch` whose `tool_calls[0].tool_response` is
   `"This command requires approval"`.
2. A `Bash` command refused by Claude Code's own sandbox. Here the block landed
   *before* the `PreToolUse` hook, so no open was created at all — but the call
   still appeared in the following `PostToolBatch`.

Case 1 is not exotic. Every permission prompt a user declines produces it. An
ingest that closes only on `PostToolUse` will leak an open call on every denial
and leave a character typing forever — the exact signature bug I4 exists to
prevent. `PostToolBatch` must be a first-class close path, not a sweep.

Its shape:

```json
{"hook_event_name": "PostToolBatch",
 "tool_calls": [{"tool_name": "Bash", "tool_input": {},
                 "tool_use_id": "toolu_01XEQDQ34JoR47bTirmyt2PF",
                 "tool_response": "This command requires approval"}]}
```

It carries `agent_id` when it fires inside a subagent, so it routes like any
other event.

### `PostToolUseFailure` replaces `PostToolUse`, it does not accompany it

Captured by asking for a `Read` of a missing file:

```json
{"hook_event_name": "PostToolUseFailure", "tool_name": "Read",
 "tool_use_id": "toolu_01Erc2RFpnHEWASf1us4E6Gf",
 "error": "File does not exist. Note: your current working directory is ..."}
```

No `PostToolUse` was emitted for that `tool_use_id`. The failure event is the
close. Note the field is `error`, a string — not `tool_response`.

### Subagents spawn asynchronously; the `Agent` tool call is not the subagent

The single most surprising finding. The `Agent` tool's own
`PreToolUse`/`PostToolUse` pair opens and closes in **~16 ms**, while the
subagent it launched runs for another 12–32 s. The `PostToolUse` body:

```json
{"tool_response": {"isAsync": true, "status": "async_launched",
                   "agentId": "a793beae9fa532d0f",
                   "resolvedModel": "claude-sonnet-5", "outputFile": "..."}}
```

Consequences for the world model:

- A subagent's lifetime is `SubagentStart` -> `SubagentStop`, keyed by
  `agent_id`. It is **not** the open duration of the spawning tool call.
- `tool_response.agentId` on the `Agent` `PostToolUse` is the join from the
  parent's `tool_use_id` to the child's `agent_id`. That is how you know which
  character spawned which — there is no `parent_agent_id` field.
- The 15-minute deadline `03-EVENT-MODEL.md` assigned to `Task` is irrelevant:
  the call closes in milliseconds.

When a subagent finishes, its result reaches the main thread as a synthetic
`UserPromptSubmit` whose `prompt` is a `<task-notification>` block containing
`<task-id>` (the `agent_id`) and `<tool-use-id>` (the spawning call). The main
agent then emits another `Stop`. `SubagentStop` arrives ~40 ms before that
notification, so `SubagentStop` remains the right trigger for the walk.

### `Stop` fires several times per turn

`03-EVENT-MODEL.md` said `Stop` means "Main agent goes idle. Turn over."
Reality: `Stop` fires every time the main assistant's message stream ends, which
in `three-subagents` happened **four times** in one user turn — once after
dispatching the subagents, and once after each async result woke it. `Stop` is
"the main agent paused", not "the turn is over."

If `Stop` sets the main character to idle, that is fine and even accurate. If
anything treats `Stop` as end-of-session or as a reap trigger, it will fire
three times too early.

### The `Task` tool is called `Agent`

`tool_name` for a subagent dispatch is the literal string `"Agent"`. There is no
tool named `Task` in the payloads. `03-EVENT-MODEL.md`'s deadline table and
badge table both named `Task`; both were wrong. The model's *prompt-facing* name
is `Task`, which is why the doc got it — but hooks see `Agent`.

### Gaps — things I could not capture

Recorded honestly rather than synthesised.

**`SessionStart` never fired.** Not once, across five headless runs. Tested with
no matcher, with `"matcher": "*"`, and with the settings file passed explicitly
via `--settings`. `SessionEnd` fired every time in the same runs, so the hook
block was definitely loaded. The most likely explanation is that `claude -p`
does not emit `SessionStart`; I could not test interactive TUI mode from a
non-tty agent shell, so **whether it fires interactively is unverified.**

This matters more than it looks. `03-EVENT-MODEL.md` made `SessionStart`
responsible for creating the session and the main-thread agent. If it does not
arrive, nothing creates them. **The world model must create sessions and the
main agent lazily, on first event of any kind.** Treat `SessionStart` as an
optional decoration (it carries `source`, `model`, and `session_title`), never
as a precondition. This is now written into the doc.

**`Notification` never fired.** Registered for all notification types; nothing
arrived in headless mode, which is expected — headless has no one to notify. The
attention-badge behaviour is therefore **unverified**, not disproved. Left in
the doc, marked.

**`PermissionRequest` / `PermissionDenied` never fired**, even on the run where
a `Bash` call was refused with "This command requires approval". Both event
names exist in 2.1.224. Unverified.

**No `tool-failure` fixture shipped.** `PostToolUseFailure` and the
permission-denied orphan were both captured and are quoted above, and the orphan
survives inside `fixtures/unknown-events.jsonl`, but there is no dedicated
fixture for the failure path because the five-fixture list does not have a slot
for one. Recommend adding a sixth, `tool-failure`, before M1 exits — it is the
cheapest capture on this list and it guards a real leak.

### Contradictions found, and fixed in `docs/03-EVENT-MODEL.md`

All fixed in this change. Line numbers are against the pre-fix revision.

| Line | Was | Reality |
|---|---|---|
| 23 | `SessionStart` creates the session and main agent | Never fired in headless `-p`. Session creation must be lazy. |
| 27 | `PostToolUseFailure` "closes flagged failed" | Correct, but it *replaces* `PostToolUse` and its field is `error`, not `tool_response`. Made explicit. |
| 28 | `PostToolBatch` is a "safety net" | It is the sole close path for permission-denied calls. Promoted to a primary close. |
| 30 | `Stop` = "turn over" | Fires once per assistant pause; 4x in one turn. |
| 32 | `Notification` badge behaviour | Never observed. Marked unverified. |
| 34 | "Everything else decodes to `.unhandled`" | Still right, but "everything else" is 16+ real events, not a hypothetical. Named the big ones. |
| 38-47 | Pairing rule and pseudocode name only `PostToolUse` | Three close paths exist. Pseudocode corrected. |
| 57 | Deadline table lists `Task` at 15 min | Tool is `Agent` and it closes in ms. Corrected. |
| 81 | Badge table maps `Task` -> checklist | Tool is `Agent`. Corrected. |
| 98-107 | Reporting animation | Correct, and now evidenced. Added the async-spawn note so nobody times the walk off the `Agent` call. |
| 111-112 | "Capture procedure is in `docs/06-WORKFLOW.md`" | That file does not exist. Repointed at `tools/hook-logger/` and `fixtures/README.md`. |
| 124-130 | Hook registration | HTTP hooks confirmed native; no `async` field confirmed; blocking confirmed by measurement. Added the project-scope note and the schema. |

Also added to the identity section: `agent_type` can appear on a main thread in
a `--agent` session, so it must never be used to detect a subagent.

---

## Payloads — M0c follow-up: the interactive events

Owner: `test-engineer`. Captured 2026-08-07, Claude Code **2.1.224**, same
machine and same sandbox as M0a. This section closes the three rows M0a had to
leave `[unverified]`, and it overturns two things M0a and the event model both
believed.

M0a's blocker was that a TUI cannot be driven from a non-tty shell. The fix was
to **allocate a pty** — `os.openpty()`, a `TIOCSWINSZ` ioctl for the window
size, the child's stdin/stdout/stderr on the slave side and keystrokes written
into the master. `tools/pty-capture/ptydrive.py` is that driver; the three step
scripts beside it reproduce the three captures. It works: fourteen real
interactive sessions were driven, prompts submitted, a permission dialog
answered by arrow keys, and `/exit` typed.

Evidence: **80 hook events over HTTP across 14 distinct interactive sessions**,
plus a parallel `command`-hook channel described below. Every `cwd` is the
sandbox; zero events from this repository. The inherited `CLAUDECODE`,
`CLAUDE_CODE_ENTRYPOINT` and related variables were stripped from the child's
environment so it could not mistake itself for a nested session.

### `SessionStart` fires. It is never delivered to an HTTP hook.

This is the finding that changes the most, and M0a's conclusion was wrong in an
interesting direction. M0a wrote "`SessionStart` never fires". It does fire.
What it never does is arrive over the transport this app uses.

The experiment that separates the two: register **both** an HTTP hook and a
`command` hook in the *same* `SessionStart` entry, and point the command hook at
a script that relays its stdin, byte for byte, to a second logger on another
port. Same event, same entry, same run.

Result, over 8 sessions: the command hook received `SessionStart` **every
time**; the HTTP logger received it **zero times**. Tested with six matcher
forms simultaneously — no matcher, `"*"`, `startup`, `resume`, `clear`,
`compact` — and with the sandbox already trusted, so no trust dialog delayed
settings loading.

A third observation makes it near-certain the HTTP hook is not dispatched at
all, rather than dispatched and failing: with the logger deliberately killed,
the TUI printed `UserPromptSubmit hook error / connect ECONNREFUSED
127.0.0.1:8787` and `Stop hook error` in the same session where the relay proved
`SessionStart` had fired — and **no `SessionStart` hook error was ever shown**.
(The TUI has no message surface at startup, so this corroborates rather than
proves the internal mechanism. The operational fact does not depend on it.)

The payload, verbatim from the command hook:

```json
{"session_id": "ed6adb3e-3554-4525-bb67-f3bf0f156548",
 "transcript_path": "/Users/.../ed6adb3e-....jsonl",
 "cwd": ".../m0-capture",
 "hook_event_name": "SessionStart",
 "source": "startup",
 "model": "claude-opus-5"}
```

And on `/clear`, where `model` is absent:

```json
{"session_id": "ee2691cf-9d2b-4268-ad6b-c2594930bcef",
 "transcript_path": "...", "cwd": ".../m0-capture",
 "hook_event_name": "SessionStart", "source": "clear"}
```

**There is no `session_title` field.** `03-EVENT-MODEL.md`'s consume table told
us to record `source`, `model` and `session_title`; only the first two exist,
and the row is unreachable anyway.

What this changes:

- **Lazy session creation stays, and its justification gets stronger.** It was
  resting on "headless does not emit it", which was a fact about `-p`. It now
  rests on "our transport never receives it", which is a fact about us. Nothing
  may wait for `SessionStart`, in any mode.
- The `SessionStart` row in the consume table is not "decoration only". It is
  **dead code** — the app registers HTTP hooks exclusively, so the handler can
  never run. Session `source` and `model` are not recordable by this app.
- No fixture can contain a `SessionStart`, because the logger is an HTTP
  endpoint. The two payloads above are the record.

### `/clear` ends the session and silently starts another

Unrelated to the above but found alongside it. Typing `/clear` emits
`SessionEnd` with `reason: "clear"`, and the next prompt in the *same process*
carries a **different `session_id`**. Confirmed twice:
`3ccda105…` → `04b14e25…`, and `67f619ac…` → `ee2691cf…`.

So `SessionEnd` is not "the process is going away", and one `claude` process
hosts a sequence of sessions over its life. The new session announces itself
with nothing at all — its first event is an ordinary `UserPromptSubmit`. Lazy
creation handles this correctly and by accident; it is worth knowing that it is
load-bearing for `/clear`, not only for startup.

Observed `SessionEnd` reasons: `clear`, `prompt_input_exit`.

### `Notification` is real, and both badge values are real

Settled, and the badge design in `03-EVENT-MODEL.md` is vindicated exactly as
written. Two `notification_type` values observed, which are the two the doc
names:

```json
{"hook_event_name": "Notification",
 "message": "Claude needs your permission",
 "notification_type": "permission_prompt"}
```

```json
{"hook_event_name": "Notification",
 "message": "Claude is waiting for your input",
 "notification_type": "idle_prompt"}
```

Full field set: `session_id`, `transcript_path`, `cwd`, `prompt_id`,
`hook_event_name`, `message`, `notification_type`. Note there is **no
`tool_use_id`** and **no `agent_id`** on either — a `Notification` routes to a
project and a session, and within the session it can only mean the main thread.
`permission_mode` is absent too, which is a small asymmetry with every other
event.

Timings, because the badge is a timed thing:

- `permission_prompt` arrives **6.0 s after** the `PermissionRequest`, three
  times, within 30 ms (6.014, 6.006, 6.032). It is not instantaneous with the
  dialog appearing; there is a deliberate delay.
- `idle_prompt` arrives **60.02 s after `Stop`** and fires **once**. Two runs,
  60.021 s and 60.031 s. In the longer run the session then sat idle for a
  further 145 s and no second notification came.

The 60 s figure matters: an attention badge driven off `idle_prompt` appears a
full minute after the agent actually went quiet, so it is a "this has been
waiting a while" signal, not an "it is waiting" signal. `Stop` with an empty
open-call set already says the latter.

Registration note: `Notification` fires with `"matcher": "*"`, which is the form
the app registers and the form in `.claude/settings.example.json`. Verified
under the standard rig with no other `Notification` entry present.

### `PermissionRequest` is real. `PermissionDenied` is not — still.

`PermissionRequest` fires over HTTP, reliably, 6 times across the captures. It
lands **~16 ms after the `PreToolUse`** for the same call:

```json
{"session_id": "...", "cwd": ".../m0-capture",
 "prompt_id": "...", "permission_mode": "default",
 "effort": {"level": "high"},
 "hook_event_name": "PermissionRequest",
 "tool_name": "Bash",
 "tool_input": {"command": "touch /private/tmp/claude-501/m0c-probe.txt",
                "description": "Create probe file"},
 "permission_suggestions": [
   {"type": "addDirectories", "directories": ["/private/tmp/claude-501"],
    "destination": "session"},
   {"type": "setMode", "mode": "acceptEdits", "destination": "session"}]}
```

**It has no `tool_use_id`.** That is the whole story for the close-path
question. `PermissionRequest` identifies a tool call by `tool_name` and
`tool_input` and nothing else, and `03-EVENT-MODEL.md`'s pairing rule forbids
joining on tool name for good reason. So it is **not** a cleaner signal than the
`PostToolBatch` path — it is not a close signal at all, and it cannot even name
the call it is about. What it is good for is the fact that the agent is now
blocked on a human.

`PermissionDenied` **never fired**. It was registered for HTTP *and* for
`command` relay, and tested on both denial paths a user actually has:

- Selecting "3. No" at the dialog. Nothing.
- Pressing Esc to cancel. Nothing.

The name exists in 2.1.224's event array. It stays `[unverified]` — absence of
observation is still not evidence of absence, and I have not found the condition
that produces it.

### The finding I did not go looking for: an interactively denied call is never closed

This is the one that contradicts a load-bearing part of the event model, so it
is stated carefully and it is **not** acted on here.

`03-EVENT-MODEL.md` says:

> A tool call refused at the permission gate emits `PreToolUse` and then
> **neither** `PostToolUse` nor `PostToolUseFailure`; its only close is its
> appearance in the following `PostToolBatch`. Every declined permission prompt
> is that case.

The first sentence is right. The last sentence is wrong. In
`fixtures/permission-prompt.jsonl`, the user selects "3. No" and the call
`toolu_0199hyfQtR1Hf3i3feHZvivV`:

- gets no `PostToolUse`,
- gets no `PostToolUseFailure`,
- is **not** named by the `PostToolBatch` that follows (which lists only the
  later, approved call), and
- gets no `Stop` for its turn either.

Nothing in the stream ever closes it. The Esc-cancel path behaves identically —
in that capture the `PreToolUse` is followed only by `PermissionRequest`,
`Notification`, and eventually `SessionEnd`.

So there are two different permission-denial shapes and M0a only saw one:

| Denial | Close path |
|---|---|
| Headless auto-deny (`tool-failure.jsonl`) | the following `PostToolBatch` |
| Interactive user denial, "No" or Esc | **none** — `SessionEnd` or the reaper |

`PostToolBatch` is still a mandatory primary close path; nothing here weakens
that. What is wrong is the belief that it covers *every* denial. Interactively
it covers none of them.

The product consequence is concrete. `Bash` carries the 15-minute deadline
(rightly — M4 made that case). So today, a user who clicks "No" on a `Bash`
permission prompt leaves a character typing for **fifteen minutes**. That is the
signature bug of this project [I4], on the single most common interactive
interaction there is, and no fixture before this one could have caught it
because no fixture came from a session with a human in it.

I am not fixing it. `PostToolBatch` is load-bearing and verified, the close-path
model is not mine to redesign, and there are at least three defensible answers
(a short deadline for a call known to be sitting at a permission gate; treating
the next `UserPromptSubmit` in a session as closing anything still open from the
previous prompt; consuming `PermissionRequest` as a state marker and joining it
by `tool_name` + `tool_input`, which the pairing rule currently forbids). The
first two do not require breaking the pairing rule. Recording it, with the
fixture that proves it, and handing it over.

**Weighed at M6 — see `docs/ADR-001-denied-calls.md` (status: PROPOSED).** The
short version: the `UserPromptSubmit` option is **refuted by captured data**
— two `Bash` calls in `three-subagents` are genuinely still running across
synthetic prompts, for 8.05 s over one and 15.05 s over two, so that rule
abandons working characters; the pairing rule should **not** be narrowed,
because `tool_name` + `tool_input` is not even a unique key inside one batch;
and consuming `PermissionRequest` as an *agent-level marker* is legitimate,
because marking performs no join. The recommendation combines the two:
mark on `PermissionRequest`, discriminate approve-from-deny on the following
`UserPromptSubmit`, and change only the **deadline** so no close path is
touched. Nothing is implemented.

### `SubagentStop` with no subagent

Interactive sessions emit a `SubagentStop` for an agent that never started. It
appears in `fixtures/interactive-session.jsonl` and in three other captures —
four occurrences, in sessions where **no `Agent` tool was ever called**:

```json
{"agent_id": "a9f8fcc5e1dfe8a82", "agent_type": "",
 "hook_event_name": "SubagentStop", "stop_hook_active": false,
 "agent_transcript_path": ".../subagents/agent-a9f8fcc5e1dfe8a82.jsonl",
 "last_assistant_message": "now read src/gamma.txt",
 "background_tasks": [], "session_crons": []}
```

`last_assistant_message` is always a follow-up suggestion ("now read
src/gamma.txt", "delete the duplicate copies in slow/ and nohook/"), so this is
an internal helper the TUI runs to populate its suggestion UI. It arrives
**1.69–2.08 s after `Stop`** (four occurrences).

It is not on every turn. Of the eight interactive sessions that reached a
`Stop`, the four that made at least one tool call all produced it, and the four
whose turn made no tool call all did not. None of the eight ever called the
`Agent` tool or emitted a `SubagentStart`.

Two things follow:

- `agent_type` can be the **empty string** — present as a key, but empty. The
  identity rules say "absent → default variant"; an empty string is neither
  absent nor a usable nameplate. It must be treated as absent.
- A model that spawns a character on `SubagentStop` puts a nameless phantom in
  the room on **every interactive turn**. M1 already decided `SubagentStop` for
  an unknown `agent_id` is a no-op, on the reasoning that spawning a character
  just to walk it off screen is silly. That decision was right for a better
  reason than the one it was made for, and it is now evidenced rather than
  argued. [I1]

### What was left alone

`~/.claude/settings.json` was **not touched**. sha256
`682e430ad33a11f0e6d5d2e5e17d7696cc1f117083fe8b5d5d784304d822a9b1`, unchanged
throughout, and matching the value M4 recorded. All capture ran against the
project-scoped `.claude/settings.json` in the sandbox, which was restored to its
M0a contents after the delivery-channel experiment.

One file was necessarily modified: `~/.claude.json` gained a
`hasTrustDialogAccepted` entry for the sandbox directory. An interactive session
in an untrusted folder shows a trust gate and loads no settings until it is
answered — which is itself worth recording, because **hooks do not fire at all
in an untrusted directory**, including `SessionEnd`. That is state, not
settings, it is unavoidable for any interactive capture, and it is one key on a
throwaway path.

---

## Art

Owner: `art-director`. Measured 2026-08-07 against the files in `assets/`, using
`scripts/pnglite.py` (stdlib PNG decode) — no claim below comes from a store
page. Reproduce any of it with the scripts in `scripts/`.

### The two headlines

**1. Six of the seven tool badges cannot be sourced.** The
`docs/03-EVENT-MODEL.md` badge table needs document, magnifier, terminal, globe,
checklist, plug and question mark. Only **question mark** exists. Modern
Interiors' `4_User_Interface_Elements` is an *emote* set — hearts, `?`, `!`,
sleep `Z`, music notes, moons, sun, coins, weapons, cursors, speech bubbles. It
contains no application icons at all. The **Modern User Interface** pack that
`04-ART-DIRECTION.md` assumed would supply them has not been purchased and is
not on disk. The six are placeholders and are flagged `"provenance":
"placeholder"` in the manifest.

**2. The licences are not identical, and the free pack is radioactive.**

| Pack | Commercial use | Editing | Credit |
|---|---|---|---|
| Modern Office Revamped v1.2 | permitted | permitted | "Credits are **appreciated**" |
| Modern Interiors (full, `moderninteriors-win/`) | permitted | permitted | "Credits **required** (limezu.itch.io)" |
| `Modern tiles_Free/` | **forbidden** | **forbidden for commercial** | not stated |

`04-ART-DIRECTION.md` claimed all three shared a licence. For the two we use the
terms are equivalent in substance, but credit is *appreciated* in one and
*required* in the other — so the About-panel credit is **mandatory**, not a
courtesy. Doc corrected.

`assets/Modern tiles_Free/` is the free sampler ("around 1% of material of the
full asset"). Its licence forbids commercial use *and* forbids editing the
sprites for a commercial project. **Nothing from it is in the manifest and
`scripts/process-assets.py` never reads it.** Recommend deleting the folder — it
is the same art the full pack already provides, and a single file from it
leaking into the build contaminates the whole thing.

### What is present

| Pack | Path | Status |
|---|---|---|
| Modern Office Revamped v1.2 | `assets/Modern_Office_Revamped_v1.2/` | present, 1047 PNGs |
| Modern Interiors (full) | `assets/moderninteriors-win/` | present |
| Modern Interiors (free sampler) | `assets/Modern tiles_Free/` | present, **must not be used** |
| Modern User Interface | — | **absent** |

### Character canvas and sheet layout

**32×64, not 32×32.** `04-ART-DIRECTION.md` said "expected 32×32. Verify." It is
wrong; characters are twice as tall as they are wide.

A premade sheet at the 32× set is `1792×1312` = **56 columns of 32px × 20 rows
of 64px**, plus 32px of unused trailing padding (20 × 64 = 1280; 1312 − 1280 =
32). Row bands were confirmed by scanning for opaque-row runs; every band falls
inside its 64px slot.

Row → pose, read off `Spritesheet_animations_GUIDE.png` and cross-checked
against per-row column occupancy on the sheet itself:

| Row | Pose | Frames | Row | Pose | Frames |
|---|---|---|---|---|---|
| 0 | base | 4 | 10 | **gift** | 40 |
| 1 | **idle** | 24 | 11 | lift | 56 |
| 2 | **walk** | 24 | 12 | throw | 56 |
| 3 | sleep | 13 | 13 | hit | 24 |
| 4 | **sit** | 12 | 14 | punch | 24 |
| 5 | sit (2nd) | 12 | 15 | stab | 48 |
| 6 | phone | 14 | 16 | grab gun | 16 |
| 7 | phone/book | 26 | 17 | gun idle | 24 |
| 8 | push cart | 48 | 18 | shoot | 13 |
| 9 | pick up | 48 | 19 | hurt | 13 |

**Direction order within a row is `right, up, left, down`.** Established two
ways, not assumed: blocks 0 and 2 are pixel-exact mirrors (distance 0 under
horizontal flip), and of the other two, block 1 shows no skin or eyes in the
head band while block 3 shows two eyes and a mouth.

The pack ships a real **`walk`**, not a run. `04-ART-DIRECTION.md`'s instruction
to "slow the frame rate rather than redrawing" came from the free sampler, which
ships `run`. It does not apply and has been removed.

### `_sit` poses: side-view only — confirmed

Both sit rows are 12 frames in 4 blocks of 3. In a normal pose row blocks 0/2
mirror (sides) and blocks 1/3 are front/back. **In the sit rows blocks 1 and 3
are also exact mirrors**, so all four blocks are side views — the front and back
slots were filled with side art. There is no front- or back-facing sit at any
size. The buyer report was right. The manifest declares `working` with `right`
and `left` only.

### Poses that do not exist

- **`read a book`** — not a row in the guide, not on any sheet. The `Books/`
  folder holds six static props for the generator, not an animation. State
  dropped; `04-ART-DIRECTION.md` already marked it optional.
- **back-view sit** — see above.

`gift` **does** exist (row 10, 40 frames, 4 directions × 10), so the `deliver`
state for the `SubagentStop` beat is sourced and needed no redesign.

This leaves **six** body states, not seven: `idle`, `working`, `walk`,
`deliver`, `spawn`, `depart`. `docs/05-MILESTONES.md` M2 says "all seven
animation states play" — that exit criterion should read six. Flagged for the
planner; `05-MILESTONES.md` is outside this task's scope.

### Is the 32× set complete? Yes.

| Set | 16× | 32× | 48× |
|---|---|---|---|
| Interiors `Theme_Sorter_Shadowless_Singles` | 5330 | **5330** | 5330 |
| Interiors `Theme_Sorter_Singles` (shadowed) | 5381 | **5470** | 5296 |
| Interiors `Theme_Sorter_Black_Shadow_Singles` | 5253 | **5253** | 5253 |
| Office singles | 339 | **339** | 339 |
| Premade characters | 20 | **20** | 20 |
| UI sheet | 1 | **1** | 1 |

The shadowless singles — the variant this project prefers — are **identical at
all three sizes**, zero filename differences. The buyer report that content is
"missing at 32 and 48" is refuted as stated: for the shadowed set 32× has the
**most** files of the three (5470); it is 48× that is thinnest. Office singles
are identical across sizes by filename.

Office singles are `64×96` at the 32× set — a fixed 2×3-tile canvas with the
object padded in, not one tile. Room Builder tiles are a true `32×32`.

### Badge table, matched against real files

| Badge | File | Provenance |
|---|---|---|
| document | `assets/placeholder/badges/32x32/document.png` | **placeholder** |
| magnifier | `assets/placeholder/badges/32x32/magnifier.png` | **placeholder** |
| terminal | `assets/placeholder/badges/32x32/terminal.png` | **placeholder** |
| globe | `assets/placeholder/badges/32x32/globe.png` | **placeholder** |
| checklist | `assets/placeholder/badges/32x32/checklist.png` | **placeholder** |
| plug | `assets/placeholder/badges/32x32/plug.png` | **placeholder** |
| question mark | `assets/processed/badges/32x32/question_mark.png` | pack — `UI_32x32.png` (260,16,24,34) |
| attention (`Notification`) | `assets/processed/badges/32x32/attention.png` | pack — `UI_32x32.png` (324,22,24,28) |

Badge canvas is **24×34**, derived from the emote artwork's own bounds. The UI
sheet divides exactly into 18×16 cells of 32px, **but the artwork is not
cell-aligned** — bubbles sit at +4px in x and are 28–34px tall, hanging across
the row boundary below. Slicing on the nominal grid clips every one, so
`process-assets.py` cuts by connected-component bounding box and records the
rectangle. Reproducible, not eyeballed.

### Cast selection and the silhouette check

The pack ships **20 premade characters**, so no generator run and no Windows VM
is needed. (`CHARACTER_GENERATOR.txt` also shows the "generator" is just layered
PNGs to composite in any editor; the Windows-only tool is a third-party
convenience.)

Selection was by measurement:

- **01, 02, 03, 05 fail I7** — they peak at 0.494/0.494/0.494/0.463 saturation
  and carry nothing above 0.55. Excluded; the lint would reject them.
- Of the 16 that qualify, the max-min-pairwise-silhouette-distance 6-subset is
  **06, 07, 09, 10, 17, 19**.

**The flatten-to-black check does not really pass, and this is a finding, not a
detail.** The closest pair in the selected cast differs by 88 pixels of 2048 —
**7.3% of their combined outline**. Across the chosen six the range is 7.3% to
20.6%. Worse, several premades are silhouette-*identical*: 01≡02, and
05≡11≡14≡20 (distance exactly 0). They are one body with different hair colour,
which is what a generator cast is.

No selection fixes this, because the bodies are identical by construction.
Consequence, recorded in `04-ART-DIRECTION.md`: **silhouette cannot be the sole
identity channel**, and the nameplate is promoted from decoration to a primary
one. If the six-agent legibility check [S4] fails at M5, the honest options are
a stronger nameplate, a per-character accent that reads at `1x`, or commissioned
bodies — not weakening the rule.

### I7 palette lint — run, and passing

`scripts/lint-palette.py` over `assets/manifest.json`, measured:

| Check | Threshold | Measured | |
|---|---|---|---|
| room max saturation | < 0.25 | **0.183** | pass |
| character peak saturation | > 0.55 | **0.598** (weakest, variant 06) | pass |
| value contrast, darkest character px vs mean room value | ≥ 0.40 | **0.472** | pass |

Supporting numbers: room mean value 0.785 over 502,276 visible pixels; room
darkest value 0.659; every character's darkest pixel 0.314. The room cannot own
the darkest pixel on screen.

**It did not pass on the first attempt.** The room value band was `[0.45, 0.85]`,
giving a room mean of 0.70 and a contrast of **0.386** — a fail. The fix was to
lighten the room to `[0.55, 0.92]`, not to move the threshold. I7 says the room
is the low-contrast layer; it does not say 40% is negotiable.

The lint was verified to actually fail: injecting an over-saturated room tile, an
under-saturated character, a low-contrast character and a missing file produces
four distinct named errors and exit code 1.

One real bug was found in the lint while testing it: it originally only
collected manifest paths beginning with `assets/`, so art declared anywhere else
was skipped **silently** — the exact failure a lint exists to prevent. It now
treats any `.png` string that resolves on disk as art, and errors on any
`assets/`-prefixed path that does not resolve.

### Claims in `04-ART-DIRECTION.md`: confirmed / refuted / uncheckable

**Confirmed**

- The `_sit` poses are side-view only; no back-view sitting pose ships.
- The packs ship shadow options and several tiles carry a baked grey shadow that
  does not blend with arbitrary floors. Exact colour `RGB(167,151,150)`, 16560
  pixels in the 32× sheet.
- Modern Interiors supplies shadowless variants, so "prefer the shadowless
  variants where supplied" is satisfiable there.
- The combined theme sheets are the wrong thing to slice; the singles are the
  right source where singles exist.
- No font ships with either pack — no `.ttf`/`.otf` anywhere.
- The palette pass must be a script: it is, it is idempotent, and three
  consecutive runs produce byte-identical output.
- Room tiles genuinely need desaturating — 329 of 339 Office singles exceed the
  0.25 saturation ceiling before processing.
- 8 fps frame rate is workable for every sourced state.

**Refuted**

- ~~"Licence terms are identical across all three."~~ Credit is *appreciated*
  for Office and *required* for Interiors; the free sampler forbids commercial
  use entirely.
- ~~"Three LimeZu packs."~~ Two are on disk. Modern User Interface was never
  purchased.
- ~~"Character sprites: expected 32×32."~~ They are **32×64**.
- ~~"Room tiles: 16×16 at the 16× set, scaling accordingly."~~ Object singles
  are a 2×3-tile canvas (64×96 at 32×); only Room Builder tiles are one tile.
- ~~"Use the 32× set unless M0 finds it incomplete."~~ It is complete; 32× is
  the fullest shadowed set of the three.
- ~~"the pack ships a run cycle, not a walk. Slow the frame rate."~~ The full
  pack ships a real `walk`. That claim came from the free sampler.
- ~~"`read` ← `read a book`."~~ No such animation exists.
- ~~"Build the manifest from the singles, not the sheets."~~ True where singles
  exist, but floors/walls, characters and badges ship **only** as sheets. Taken
  literally the rule leaves the room with no floor. Amended with a per-sheet
  verdict.
- ~~"The generator is Windows and Linux only… export the full cast under a VM."~~
  20 premades ship in the pack; the generator is layered PNGs, not an app.
- ~~"Badges: the UI icon set's native size."~~ There is no UI icon set. Badge
  canvas is 24×34, derived from the emote artwork.
- ~~"Silhouette carries identity at `1x`."~~ Aspirationally right, factually not
  satisfiable with this art — 7.3% at the closest selected pair, 0% for several
  premades. Rule kept, consequence documented.

**Could not check**

- Whether the **Modern User Interface** pack contains suitable document,
  magnifier, terminal, globe, checklist and plug icons. It is not purchased.
  *Would be resolved by:* buying it and re-running `process-assets.py` with
  rectangles for the six.
- Whether a **back-view sitting pose** exists in some other LimeZu product. Not
  in either pack here. *Would be resolved by:* inspecting any pack that claims
  one; the room layout does not depend on it either way.
- Whether the chosen pixel **font** is legible at `1x` beside this art. No font
  is sourced yet. *Would be resolved by:* rendering a nameplate at `1x` once one
  is chosen — this now matters more than it did, since the nameplate carries
  identity.
- Whether **six agents** remain legible at the resulting zoom [S4]. Needs a
  running scene. *Would be resolved by:* the M5 screenshot check.
- The **48× and 16× sets** were inventoried by count and filename but not
  imported or rendered. Only 32× is processed. *Would be resolved by:*
  `process-assets.py --sizes 16x16 48x48`.
- Whether the 176 legitimate pixels lost to the shadow strip are visible in any
  specific tile. Sampled and judged invisible at `1x`; not exhaustively
  reviewed. *Would be resolved by:* a per-tile diff against the shadowless
  sheet, which requires tile-to-sheet correspondence the singles do not carry.

### Credit line, for the `ui-engineer`

Modern Interiors requires credit, so this ships — it is not optional.

> **Art**
> Pixel art by **LimeZu** — [limezu.itch.io](https://limezu.itch.io)
> *Modern Interiors* and *Modern Office* asset packs, used under licence.

Also carried in `assets/manifest.json` under `credit` (`required: true`, plus
`text` and `url`) so the About panel can read it rather than hard-coding a
string that drifts.

### `.gitignore` — confirmed, with one problem

`assets/` **is** gitignored (`.gitignore:3`), verified with `git check-ignore`.
The purchased art is not in the repo and redistribution is not happening.

**But `assets/manifest.json` is gitignored too**, and it is the contract the
scene builds against. A fresh clone has no manifest, so M2 cannot build until
someone runs the scripts with the purchased packs in place. The manifest holds
only filenames and metadata — no art — so committing it redistributes nothing.

Recommended, but **not applied** — `.gitignore` is outside this task's declared
scope and this is a repo-policy call:

```
assets/
!assets/manifest.json
```

Until that lands, the build path from a clean clone is:

```
python3 scripts/process-assets.py
python3 scripts/generate-placeholders.py
python3 scripts/build-manifest.py
python3 scripts/lint-palette.py
```

### What the manifest currently contains

1340 asset paths, every one re-stat'd before the file was written.

- **6 character variants** × 6 states (`idle`, `working`, `walk`, `deliver`,
  `spawn`, `depart`), 94 frames each, 32×64, anchor bottom-centre, 8 fps.
- **Room**: 141 Room Builder floor/wall tiles (32×32) + 339 Office object
  singles (64×96). The singles are flagged `"identified": false` — the pack
  names them by index only, so **no single is known to be a desk, chair or
  monitor** without opening it. Picking the handful the room layout needs is
  scene work and is not done.
- **7 badges** (1 pack, 6 placeholder) + the `attention` badge, canvas 24×34,
  anchor bottom-centre.
