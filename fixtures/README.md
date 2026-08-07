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

Because these are headless `-p` runs, **no `SessionStart` event appears in any
fixture** — see `docs/FINDINGS-M0.md`. That absence is real, not an artefact of
the logger.

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
permission gate. Three of its five `hook_event_name`s — `UserPromptSubmit`,
`PostToolBatch`, and the orphaned `PreToolUse` they surround — are events
`03-EVENT-MODEL.md` either does not model or models incorrectly, so this half is
genuine unknown-event traffic. It also carries a real orphan: a `PreToolUse`
whose only close is the `tool_use_id` listed inside the following
`PostToolBatch`.

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
