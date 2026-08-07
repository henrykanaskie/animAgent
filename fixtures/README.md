# fixtures/

Captured Claude Code hook payloads. Ground truth for the ingest layer.

Every line is one JSON object:

```json
{"_receivedAt": "2026-08-07T08:14:10.670+00:00", "payload": { ... }}
```

`_receivedAt` is the logger's arrival timestamp (ISO8601, UTC, millisecond
precision) and is **ours** — it lets replay reconstruct relative timing. Lines
are in arrival order. `payload` is the request body exactly as Claude Code sent
it: not edited, not normalised, not reordered. Do not "tidy" a payload. If a
payload looks wrong, that is the finding.

A line may also carry `"_synthetic": true`. That flag means the payload was
POSTed to the logger by hand and did **not** come from a Claude Code session.
Only `unknown-events.jsonl` contains such lines, and only after its real ones.

## How these were captured

Claude Code 2.1.224, macOS 15 (Darwin 25.5.0), 2026-08-07.

`tools/hook-logger/logger.py` listened on `127.0.0.1:8787`. A **project-scoped**
`.claude/settings.json` in a throwaway sandbox directory registered a
`type: "http"` hook pointing at it for every hook event name the CLI accepts.
The user's `~/.claude/settings.json` was never touched, so no hooks were
injected into any real session. Each scenario is a separate headless run:

```
claude -p "<scenario prompt>" --permission-mode acceptEdits --model sonnet
```

Isolation was verified after capture: every `cwd` in every fixture is the
sandbox directory, and none is this repository.

**No `SessionStart` event appears in any fixture** — see `docs/FINDINGS-M0.md`.
That absence is real, not an artefact of the logger, and it is *not* caused by
headless mode. M0c drove fourteen real interactive sessions under a pty and
`SessionStart` did not arrive over HTTP in any of them either. The event fires;
it is simply never delivered to a `type: "http"` hook in 2.1.224. A `command`
hook registered in the *same* entry received it every time.

### Interactive captures (M0c)

`interactive-session`, `permission-prompt` and `idle-notification` were captured
from a **real interactive TUI session**, not `claude -p`. A non-tty shell cannot
drive the TUI, so the session was run under an allocated pty
(`os.openpty` + `TIOCSWINSZ`) with keystrokes written into the master side. The
driver is `tools/pty-capture/ptydrive.py`. Every run was bounded by a hard
timeout and the child was killed by process group at the end.

These three needed an interactive session because the events in them cannot
occur without one: nothing prompts for permission and nobody goes idle in a
headless run. The rig, the port and the project-scoped `.claude/settings.json`
are otherwise identical to the headless captures above, and the same `cwd`
assertion was re-run: 27 events, all in the sandbox, none in this repository.

---

## `single-agent-simple.jsonl` — 12 events

One session, one agent, three tool calls run strictly one after another
(`Read`, `Read`, `Bash`). Peak concurrent open calls: 1.

Exists to prove the baseline: that a `PreToolUse` / `PostToolUse` pair sharing a
`tool_use_id` opens and closes exactly one call, and that a clean session
terminates with `Stop` then `SessionEnd`, leaving nothing open. It is the
fixture a regression will break first.

Produced by a prompt that ordered the tools explicitly and forbade batching
("only after that finishes").

---

## `parallel-tools.jsonl` — 14 events

One agent, five `Bash` calls issued in a single tool block, each sleeping four
seconds. Five distinct `tool_use_id`s are open simultaneously. Peak concurrent
open calls: **5**.

Exists to prove **I3**. The five `PostToolUse` events arrive in a *different
order* from the five `PreToolUse` events, so any model that pairs by tool name,
or that assumes the next close belongs to the most recent open, or that stores
one current tool per agent, produces the wrong answer against this file. Replay
must show one agent holding a set of five.

Produced by a prompt demanding five concurrent Bash calls in one block.

---

## `three-subagents.jsonl` — 45 events

The main thread spawns three subagents via the `Agent` tool — two `Explore`,
one `general-purpose` — which run concurrently for different durations and stop
staggered (at +12 s, +19 s, +32 s from spawn). All three are alive at once.

Exists to prove identity resolution: `agent_id` is absent on every main-thread
event and present on every subagent event, two subagents of the same
`agent_type` (`Explore`) are distinct characters, and `SubagentStop` fires once
per `agent_id`. It also documents the async spawn shape — the `Agent` tool's own
`PreToolUse`/`PostToolUse` pair closes in ~16 ms and does **not** bracket the
subagent's life; `SubagentStart` → `SubagentStop` does.

Produced by a prompt dispatching three `Task` calls in one block with
deliberately unequal `sleep` durations.

---

## `killed-session.jsonl` — 8 events

A session that read two files and then started a ten-minute `Bash` job. The
`claude` process and the job were `kill -9`ed four seconds after the `Bash`
`PreToolUse` arrived. The file ends on that `PreToolUse`. There is no matching
`PostToolUse`, no `PostToolBatch`, no `Stop`, and no `SessionEnd`.

Exists to prove **I4**. One `tool_use_id` (`toolu_01LdA9QPuMcXEf2t35ikfzvP`) is
open at end of file and nothing in the stream will ever close it. Replay must
close it via the deadline path, with an injected clock, and end with zero open
calls. A test that passes without advancing the clock is not testing anything.

Produced by launching the session in the background, polling the logger's output
for a `Bash` `PreToolUse`, then `kill -9` on both the job and the CLI. The
long-running job is a shell script rather than a bare `sleep`, because Claude
Code's Bash sandbox refuses a standalone `sleep 600`.

---

## `unknown-events.jsonl` — 12 events (5 real, 7 synthetic)

Two halves, in order.

Lines 1–5 are **real**: a captured session whose `Bash` call was denied at the
permission gate. It carries a real orphan: a `PreToolUse` whose only close is
the `tool_use_id` listed inside the following `PostToolBatch`.

*(This half was originally described as unknown-event traffic because
`UserPromptSubmit` and `PostToolBatch` were both outside the model. Both are
consumed now — `PostToolBatch` since M0a, `UserPromptSubmit` since M4 — so the
only genuinely unknown events in this file are the synthetic ones below.)*

Lines 6–12 are **synthetic**, each flagged `"_synthetic": true`. They were
POSTed to the logger directly, because Claude Code cannot be made to emit an
event name it does not have. They cover: a plausible future name
(`SomeFutureEvent`); an unknown name carrying a `tool_use_id` (`ToolProgress`)
to check that an unrecognised event never mutates open-call state; an unknown
name carrying an `agent_id` (`SubagentHeartbeat`); a real 2.1.224 event name
absent from our table (`UserPromptExpansion`); a payload with **no**
`hook_event_name` field at all; a payload whose `hook_event_name` is the number
`12345`; and a body that is not JSON at all, stored as `{"_raw": ...}`.

Exists to prove that every one of those decodes to `.unhandled` and is counted,
that none of them throws, and that none of them changes the world.

## `tool-failure`

8 events, all **real**, captured after the rest of M0a to close the gap that
milestone left open. One session, two deliberately unhappy tool calls, and it is
the only fixture that exercises both non-`PostToolUse` close paths:

1. A `Read` of a missing file. `PreToolUse` → **`PostToolUseFailure`**, with the
   message in `error` and no `PostToolUse` for that `tool_use_id` at all.
2. A `Bash` call refused at the permission gate. `PreToolUse` → **nothing**.
   Neither `PostToolUse` nor `PostToolUseFailure` ever arrives. Its only close
   is its appearance in the `tool_calls[]` of the following `PostToolBatch`,
   with `tool_response` reading "This Bash command contains multiple
   operations. The following part requires approval: ...".

Case 2 is the whole reason this fixture exists. An ingest layer that closes only
on `PostToolUse` leaks an open call on **every declined permission prompt**, and
that leak is precisely the character-that-types-forever failure I4 exists to
prevent. A replay of this fixture must end with zero open calls **without**
relying on a deadline sweep — if it needs the reaper, the close paths are wrong.

Note also that `PostToolBatch` re-reports the already-closed `Read` call from
case 1. Closing an already-closed `tool_use_id` must therefore be idempotent and
must not emit a second `callClosed` delta.

Produced with `tools/hook-logger/` at project scope, `--permission-mode default`
so the permission gate was live, prompting for a read of a nonexistent file
followed by a `Bash` command requiring approval in a non-interactive session.

---

## `interactive-session.jsonl` — 10 events

The first fixture from a **real interactive TUI session**. One session, one
prompt, two sequential `Read` calls, a clean `/exit`. Peak concurrent open
calls: 1. Replays to zero open calls without the reaper.

Exists to settle `SessionStart`, and it settles it by absence: the session was
started in an already-trusted directory under the standard project-scoped rig,
`SessionEnd` arrived normally at the end, and **no `SessionStart` ever arrived**.
The hook block was demonstrably loaded, so this is not a registration failure.
`SessionStart` does fire — a `command` hook sees it — but an HTTP hook never
does. Lazy session creation is therefore mandatory for reasons that have nothing
to do with headless mode.

It also carries the second interactive-only finding: a **`SubagentStop` with no
`SubagentStart` and no `Agent` tool call anywhere in the session** (line 9). It
has an `agent_id` and an `agent_type` of `""` — present, but empty. Nothing in
this session ever spawned a subagent. Any model that creates a character on
`SubagentStop` draws a phantom here; the correct behaviour, already implemented
at M1, is that `SubagentStop` for an unknown `agent_id` is a no-op.

---

## `permission-prompt.jsonl` — 13 events

One interactive session, two `Bash` calls that both hit the permission gate. The
first is **denied** by selecting "3. No" at the real dialog; the second is
**approved** by selecting "1. Yes". Both produce a `PermissionRequest` and a
`Notification`.

Exists to prove three things, and it contradicts the event model on the third:

1. `PermissionRequest` is real and fires over HTTP. It carries `tool_name`,
   `tool_input` and `permission_suggestions[]` — and **no `tool_use_id`**, so it
   cannot be joined to an open call.
2. `Notification` is real, and `notification_type` is `permission_prompt`, one
   of the two values the badge design assumes.
3. **The denied call is never closed by anything.**
   `toolu_0199hyfQtR1Hf3i3feHZvivV` opens at line 2 and no `PostToolUse`, no
   `PostToolUseFailure` and no `PostToolBatch` ever names it. The
   `PostToolBatch` at line 10 lists only `toolu_015N71EzzTiFqrnLirnMGCCz`, the
   *approved* call. There is not even a `Stop` for the denied turn.

Point 3 is the reason this fixture matters. `03-EVENT-MODEL.md` says a call
refused at the permission gate is closed by the following `PostToolBatch` and
that "every declined permission prompt is that case". That is true of the
headless auto-deny in `tool-failure.jsonl` and **false of an interactive user
denial**, which is the far more common event. Unlike `tool-failure`, this
fixture **cannot** replay to zero open calls without the deadline sweep — it is
a `killed-session`-shaped file that arises from a user clicking "No".

`PermissionDenied` did **not** fire, on either the "3. No" path or the Esc path,
though it was registered for both HTTP and `command` delivery.

---

## `idle-notification.jsonl` — 4 events

One interactive session: a prompt, an answer, then nothing. The session was left
untouched at the prompt for 180 s.

Exists to prove the second `notification_type`. A `Notification` with
`notification_type: "idle_prompt"` and `message: "Claude is waiting for your
input"` arrives **60.02 s after `Stop`**, and arrives exactly **once** — it did
not repeat over the following two minutes of continued idleness. Both values the
attention badge is specified against are now observed rather than assumed.

Note what this fixture does *not* contain: no tool call, and therefore no open
call. The notification is the only thing that happens between `Stop` and
`SessionEnd`.
