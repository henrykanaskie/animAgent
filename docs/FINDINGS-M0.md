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
