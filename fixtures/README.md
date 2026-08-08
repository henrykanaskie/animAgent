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

### Interactive captures (M6c) — the ADR-001 verification set

Seven further interactive captures, taken to answer the four open questions in
`docs/ADR-001-denied-calls.md` ("What would have to be true for me to be
confident"). Same rig, same driver, same sandbox, same port. `cwd` assertion
re-run over all seven: **98 events, every one in the sandbox, none in this
repository.** `~/.claude/settings.json` was not touched — sha256
`682e430ad33a11f0e6d5d2e5e17d7696cc1f117083fe8b5d5d784304d822a9b1` before and
after, the same value M0c and M4 recorded.

Two of the seven — `parallel-denial` and `interactive-batch-serial` — were
captured with a **temporary `permissions.allow` block** added to the sandbox's
project-scoped `.claude/settings.json`, so that one call in a batch would run
without gating while another gated. The rules were
`Bash(bash m6job.sh:*)`, `Bash(bash m6short.sh:*)`, `Bash(bash m6short2.sh:*)`,
they were removed afterwards, and the file is back to hooks-only. This is
recorded because it is the one way these two files differ from the M0c rig, and
it is load-bearing for what they prove. The helper scripts they invoke
(`m6job.sh`, `m6short.sh`, `m6short2.sh` — bare `sleep`s wrapped in a shell
script, because Claude Code's Bash sandbox refuses a standalone `sleep`) live in
the sandbox alongside `longjob.sh`.

The driver scripts are in `tools/pty-capture/`, one per fixture, named to match.
Two notes on provenance there. `parallel-denial.json` is the script as it stood
for the run that produced `parallel-denial.jsonl`; the same path was edited and
re-run four times while the batch behaviour was being pinned down, and the run
that produced `denied-batch-cancel.jsonl` was the first of those — its script is
not preserved, and it differed only in the order of the two commands in the
prompt and in denying the first dialog rather than the second.

Findings are written up in `docs/FINDINGS-M0.md` ("Payloads — M6c follow-up")
and scored against the ADR in its verification section.

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

---

## `subagent-permission.jsonl` — 14 events

One interactive session. The main thread makes one `Agent` call; the
`general-purpose` subagent it launches makes one `Bash` call, which hits the
permission gate and is **approved**. Peak concurrent open calls: **2** (the
parent's `Agent` call and the child's `Bash`).

Exists to answer one question, and it answers it: **`PermissionRequest` carries
`agent_id`.**

```json
{"prompt_id": "01ae4810-…", "permission_mode": "default",
 "agent_id": "ab2378e6a85dea269", "agent_type": "general-purpose",
 "hook_event_name": "PermissionRequest", "tool_name": "Bash",
 "tool_input": {"command": "touch /private/tmp/claude-501/m6-sub.txt; echo \"exit=$?\"", …},
 "permission_suggestions": [ … ]}
```

Same `agent_id` as the `SubagentStart` 2.76 s earlier and as the gated
`PreToolUse` 18 ms earlier. So a gate raised inside a subagent is attributable to
that subagent by the sanctioned identity key, and `docs/ADR-001-denied-calls.md`
risk 3 does not occur.

Two further things it records:

- **The `Notification` that follows does *not* carry `agent_id`** — it arrives
  6.016 s after the `PermissionRequest`, matching M0c's 6.006–6.032 s, and by
  the identity rules it can only mean the main thread. The gate belongs to the
  subagent; the badge lands on the main character. That is a real mis-attribution
  in the attention badge, unrelated to the ADR.
- **`Agent` ran synchronously here.** `toolu_01PLtuHaiz8sCVVkAPGXebfJ` opens at
  t=3.504 and closes at t=19.805, after its child's `SubagentStop` at t=19.802.
  So the main thread held an open call *while a permission dialog was on screen* —
  see the ADR verification section, which is where that matters.

Produced by a prompt ordering exactly one `general-purpose` subagent whose whole
task was one `touch` outside the sandbox, with the main thread forbidden to run
Bash itself.

---

## `parallel-denial.jsonl` — 11 events

One interactive session. **One assistant message containing two `Bash` tool_use
blocks** — verified in the session transcript, both under
`msg_011Cdon1LFyaSt8tstaodER8`. Call A is `bash m6short.sh` (a 45 s sleep,
pre-allowed so it does not gate); call B is a `touch` outside the sandbox, which
gates and is **denied**. A real `UserPromptSubmit` follows 36.7 s later.

Peak concurrent open calls: **1**. That number is the finding.

```
  0.000  UserPromptSubmit
  3.613  PreToolUse   Bash  toolu_01Viqu91FLjT4mP3xeV2ysEi   bash m6short.sh
 49.972  PostToolUse  Bash  toolu_01Viqu91FLjT4mP3xeV2ysEi
 49.976  PreToolUse   Bash  toolu_01Hx2iz7zzhiGuNfFCzVRXRg   touch …/m6-deny.txt
 49.991  PermissionRequest  Bash
 55.998  Notification       permission_prompt
 86.709  UserPromptSubmit                       ← real, user typed again
 87.748  Stop
147.774  Notification       idle_prompt
209.157  SessionEnd
```

The two calls of one batch ran **strictly one after another**: B's `PreToolUse`
arrives 4 ms after A's `PostToolUse`, not alongside A's open. The gated call was
therefore never open at the same time as its sibling, and the sibling could not
be caught by an agent-level mark. `interactive-batch-serial.jsonl` is the
control that shows this is not caused by the gate.

`toolu_01Hx2iz7zzhiGuNfFCzVRXRg` is a second real instance of the interactive
denial orphan: open at 49.976, no `PostToolUse`, no `PostToolUseFailure`, named
in no `PostToolBatch`, no `Stop` for its turn. Like `permission-prompt`, this
file does **not** replay to zero open calls without the reaper.

---

## `denied-batch-cancel.jsonl` — 4 events

The same experiment with the order reversed — call A is the `touch` that gates,
call B is `bash m6job.sh` — and A is **denied**. Again one assistant message with
two `tool_use` blocks; again verified in the transcript, where **both** get a
`tool_result` reading "The user doesn't want to proceed with this tool use."

```
 0.000  UserPromptSubmit
 4.330  PreToolUse         Bash  toolu_01JsGRTCvgHVcyEctbey6ZAL  touch …/m6-deny.txt
 4.347  PermissionRequest  Bash
10.356  Notification             permission_prompt
```

That is the whole file. **Call B never emits a `PreToolUse` at all.** Denying the
first call of a batch cancels the rest before they open, so a cancelled sibling
never becomes an open call and cannot leak. The session was killed by the driver
after the denial, so there is no `SessionEnd`; `toolu_01JsGRTC…` is open at end
of file, exactly like `killed-session`.

---

## `interactive-batch-serial.jsonl` — 9 events

The control for the two above, and the reason their result can be attributed to
the TUI rather than to the permission gate. One assistant message, two `Bash`
calls, **both pre-allowed** so neither gates, each a ~40–45 s sleep.

```
 0.000  UserPromptSubmit
 2.416  PreToolUse   Bash  toolu_01N8grGD62XKzeYoU3i6ympd  bash m6short.sh
48.722  PostToolUse  Bash  toolu_01N8grGD62XKzeYoU3i6ympd
48.727  PreToolUse   Bash  toolu_01WjGW2cngX7QpyYGm4sMuwR  bash m6short2.sh
88.810  PostToolUse  Bash  toolu_01WjGW2cngX7QpyYGm4sMuwR
88.815  PostToolBatch
90.349  Stop
112.473 SessionEnd
```

Peak concurrent open calls: **1**, with no permission gate anywhere in the file.

**This does not weaken `parallel-tools.jsonl` and must not be read as doing so.**
That fixture holds five genuinely simultaneous `tool_use_id`s and still proves
I3; it was captured **headless** (`claude -p --permission-mode acceptEdits`).
What this file establishes is narrower and is about the interactive TUI only: in
2.1.224's TUI, a batch's `Bash` calls were serialised in every attempt made.
Absence of observation is not evidence of absence — nothing may assume the TUI
*cannot* run two calls at once. I3 is unaffected either way, because I3 is about
what the model must tolerate, not about what the TUI happens to do this week.

---

## `queued-prompt.jsonl` — 9 events

One interactive session. A long `Bash` (`bash m6job.sh`, tool `timeout`
300000 ms) hits the gate and is **approved**. 54 s into its run the user types a
second prompt and presses Enter — the TUI shows "Press up to edit queued
messages" — and the message is answered when the call finishes.

```
  0.000  UserPromptSubmit                     ← the only one in the file
  2.527  PreToolUse         Bash  toolu_017G4mwvtSM7fcPc8z1BXsdX
  2.543  PermissionRequest  Bash
  8.563  Notification             permission_prompt
250.112  PostToolUse        Bash  toolu_017G4mwvtSM7fcPc8z1BXsdX
250.116  PostToolBatch
251.318  Stop
252.903  SubagentStop
289.901  SessionEnd
```

**No `UserPromptSubmit` fires for the queued message.** Not when it is typed, not
when it is picked up. The session transcript shows what happens instead: a
`queue-operation` / `enqueue` record at the keystroke (17:32:28.804), a
`queue-operation` / `remove` at pickup (17:35:41.939, 12 ms after the
`tool_result`), and delivery as an `attachment` of type `queued_command` rather
than as a new user turn. The assistant answers it at 17:35:43.122. No hook
observes any of it.

Exists to settle when `UserPromptSubmit` fires relative to the keystroke. The
answer is that a queued prompt produces no `UserPromptSubmit` at all, so nothing
downstream can be woken by one — and equally, nothing downstream can rely on one
arriving when a user types ahead.

---

## `denial-then-work.jsonl` — 28 events

The companion `permission-prompt.jsonl` never had: an interactive denial in a
session that then **keeps working for another four minutes**. One `Bash` denied
at the dialog, then three further user turns doing real work (two `Read`s, a
`ToolSearch`, an ungated `Bash`), then a clean `/exit`.

```
  0.000  UserPromptSubmit
  3.138  PreToolUse         Bash  toolu_01WXAhzmcL2iKm1mdYfuLczp  touch …/m6-deny4.txt
  3.151  PermissionRequest  Bash
  9.167  Notification             permission_prompt
 34.984  UserPromptSubmit                       ← user's next real prompt
 37.873  PreToolUse/PostToolUse/PostToolBatch  Read
 39.751  Stop
 99.783  Notification             idle_prompt
107.181  UserPromptSubmit
…
190.702  Stop
252.062  SessionEnd
```

`toolu_01WXAhzmcL2iKm1mdYfuLczp` opens at t=3.138 and **nothing in the stream
ever closes it** — 249 s later `SessionEnd` does. `permission-prompt.jsonl` ends
40 s after its denial, before any plausible gate deadline could have fired; this
one runs 217 s past the user's next prompt, so a 60 s gate deadline falls
strictly inside the stream. Under the ADR-001 rule the shortened deadline lands
at 94.98 s (mark at 3.151, `UserPromptSubmit` at 34.984, G = 60 s), with 157 s of
real session activity still to come.

Note that `spriteroom-replay` will not show that: it sweeps once, after the last
event, so `SessionEnd` closes the orphan at 252.062 and the 94.98 s instant is
never evaluated. The value of this file is as input to a clock-injecting test —
advance to 94 and the call is open, advance to 95 and it is gone, against real
data with a real tail. See the verification section of
`docs/ADR-001-denied-calls.md`.

Like `permission-prompt` and `parallel-denial`, it does **not** replay to zero
open calls without the reaper.

One incidental correction it carries: `idle_prompt` fires **twice** here, at
99.783 and 171.469 — 60.03 s and 60.02 s after the `Stop`s at 39.751 and
111.444. `03-EVENT-MODEL.md` says it "fires exactly once"; that is true per idle
stretch, not per session, and this file is the counterexample to the stronger
reading.

---

## `concurrent-permission-gates.jsonl` — 23 events

Two `general-purpose` subagents launched in one assistant message, each with one
gated `Bash`. **Two `PermissionRequest`s are outstanding at the same time.**

```
 3.302  SubagentStart      a7298874eca5a457d
 4.394  SubagentStart      ac26da513c96ad388
 6.434  PreToolUse         Bash  toolu_01Csk3X8GWhXpdhVii44jaVu   agent ac26da513c96ad388
 6.446  PermissionRequest  Bash                                   agent ac26da513c96ad388
 7.907  PreToolUse         Bash  toolu_01Evfo4Ytq2AzNpsm1NCftzf   agent a7298874eca5a457d
 7.919  PermissionRequest  Bash                                   agent a7298874eca5a457d
12.466  Notification             permission_prompt
38.263  PostToolUse        Bash  toolu_01Csk3X8GWhXpdhVii44jaVu   ← first one answered
40.510  UserPromptSubmit                                          ← synthetic; no agent_id
```

The two gates are open together for **31.8 s** before either is answered, and
they belong to **different `agent_id`s**. So "at most one permission prompt open
at a time" is false — as a global statement. What was never observed is *one
agent* holding two gates at once; within a single agent's batch the calls
serialise (see `parallel-denial` and `interactive-batch-serial`).

It also captures a synthetic `UserPromptSubmit` (t=40.510, no `agent_id`,
1.19 s before the first `Stop`) arriving while a **subagent** still has an open
gated call — the interleaving `docs/ADR-001-denied-calls.md` reasons about.

The driver's await consumed the second dialog's text before it could answer it,
so the second gate was never resolved and the session was killed at the timeout.
That is why there is no `SessionEnd` and why `toolu_01Evfo4Ytq2AzNpsm1NCftzf` is
open at end of file. Left as captured: it is a real shape (a user who walks away
from a dialog), and tidying it would mean editing a payload.

---

## `four-subagents.jsonl` — 115 events

**Four subagents of one `agent_type` (`general-purpose`), dispatched together
into one interactive session, running concurrently for 70 s.** Captured
2026-08-08 under a pty against Claude Code 2.1.224, project-scoped hooks in a
throwaway sandbox; one `session_id`, one `cwd`, 172.40 s end to end.

It exists because `three-subagents` cannot catch the failure it is named for.
That capture is two `Explore` and one `general-purpose`, so a model that keyed
identity on `agent_type` would still draw two characters and look nearly right.
Here all four share the type, so anything keyed on the type — or on a truncated
id, or on a nameplate string derived from one — collapses four characters into
one and is off by three. The four ids are
`ab69ae01f1e4353c6`, `aae859812d39a1892`, `ab7894b769ddc7a5e`,
`afec77672e42e6ab7`; no two share even their last three characters, so it
exercises M5c's plate discriminator as well as the model's key.

Two further shapes it is the only capture of:

**`SubagentStart` is not once per agent.** These were dispatched with
`run_in_background`, and the parent later resumed two of them with
`SendMessage`. Each resume emits a **second `SubagentStart`** ~20 ms after the
`SendMessage` `PreToolUse` — 6 starts across 4 agents. M4 recorded that "a
subagent can come back"; what it could not show is that the return arrives as a
lifecycle event rather than only as the child's next tool call.

**A background subagent spends much of its life stopped — and this is the
capture that changed what the room does about it.** `SubagentStop` *used to*
depart the character, so the room's subagent count tracked who was mid-turn
rather than how many the user had dispatched:

```
 7.398  4 subagents   ← all four spawned
31.850  3             ← ab69… stops
33.913  2             ← aae8… stops
41.165  3             ← SendMessage resumes ab69…
42.109  4             ← SendMessage resumes aae8…
56.720  3
63.055  2
70.181  1             ← one subagent on screen, four still assigned
76.880  0
```

Between the fourth spawn and the last stop the room held all four for **39.1 s
of 69.5 s (56%)**, dropped to two for 7.3 s and to **one for 6.7 s** — while the
parent had four agents assigned throughout. That is exactly what "only one
subagent has been registered even though there should be 4" looks like from the
outside, and it is how the maintainer reported it.

**That reading was retracted.** This file previously called the timeline above
"truthful under the current reading of `SubagentStop`". It was not: each
individual transition was faithful, but departing on a *turn boundary* made the
room assert "this agent is gone" when the data said only "this agent finished a
turn" — and the six starts above are captured proof it comes back. Departing was
the fiction. [I1]

A stopped subagent now goes **dormant**: it keeps its seat, is revived in place
by any later event, and departs only on `SessionEnd` or the idle sweep. Replayed
against the model today the population never falls below four between the fourth
spawn and `SessionEnd`, which is
`thePopulationNeverFallsBelowFourOnceTheFourthSubagentExists` — this fixture's
reason for existing, and a test that was seen red against the old behaviour
before the change was made.

It carries **six phantom `SubagentStop`s** (12 stops, 6 real) from the TUI's
suggestion helper, each with `agent_type: ""` and an `agent_id` that never
started — the shape `interactive-session` first showed, here six times in one
session, which is the volume a model that spawns a character to walk it off
would have to survive.

Replays clean: zero abandoned, zero open at end of stream, zero unhandled. Not
one of the required eight; it is a regression fixture for identity, and adding
to that list is a maintainer decision.

Produced under `tools/pty-capture/ptydrive.py` from a prompt demanding four
`Agent` calls in one message, all `subagent_type: general-purpose`, all
`run_in_background: true`.
