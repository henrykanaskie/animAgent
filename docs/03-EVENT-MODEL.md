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
| `SubagentStart` | Create agent under `agent_id`. Character spawns beside the anchor. Carries `agent_id` and `agent_type`, nothing else. **Not once per agent** — a background subagent resumed with `SendMessage` emits a second one ~20 ms after that call's `PreToolUse`. Creation stays idempotent for that reason, and for a **known** `agent_id` this event is the *revival* path: it returns a dormant character to `active` **in place**, emitting `dormancyChanged(isDormant: false)` and nothing else. No second character, no second seat, no re-spawn walk — the one visible change is the `sleep` badge coming down. |
| `PreToolUse` | Open a call keyed by `tool_use_id`. Character enters/keeps working. |
| `PostToolUse` | Close that `tool_use_id`. |
| `PostToolUseFailure` | Close that `tool_use_id`, flagged failed. Fires *instead of* `PostToolUse`, never alongside it; the message is in `error`, not `tool_response`. |
| `PostToolBatch` | Close every `tool_use_id` in `tool_calls[]`. A primary close path, not a sweep — see below. |
| `SubagentStop` | Agent enters `.reporting` → walks to anchor → delivers → **returns to its seat and goes `dormant`**, wearing the `sleep` badge. Emits `reportDelivered` and then `dormancyChanged(isDormant: true)`. It does **not** depart: this is a turn boundary, not a death, and the agent can be resumed. Its open calls are abandoned (`.agentStopped`) and its permission-gate mark is disarmed — the turn completed, so nothing is pending. See "`SubagentStop` is a turn boundary, not a death" below. |
| `Stop` | Main agent pauses. **Not** "turn over" — it fires once per assistant message stream, several times in one user turn when async subagents wake the main thread. Never treat it as end-of-session or as a reap trigger. It **disarms** that agent's permission-gate mark (below): the turn completed. Still emits nothing. **It needs no dormancy of its own** — checked, not assumed: `Stop` emits no delta and sets no lifecycle, and the main agent departs only on `SessionEnd` and the idle sweep, so it already stays in the room across a turn boundary, which is the whole of what dormancy buys a subagent. Marking it dormant would also be the weaker claim, since `Stop` fires once per assistant message stream and several times in one user turn. |
| `PermissionRequest` | **An agent-level marker, and nothing else.** Records for that agent: a permission gate is open, plus the set of `tool_use_id`s it held open at that instant. No join by name, no join by recency, no `tool_use_id` read from the event — it carries none. Emits no delta and does not clear the attention badge. See "The interactively denied tool call" below. |
| `SessionEnd` | Close every open call in the session. All characters leave. [I4] Observed `reason`s: `prompt_input_exit`, `clear`. **Not** "the process is exiting" — `/clear` ends a session and the same process continues under a new `session_id`. |
| `Notification` | Raises an attention badge; emits `attentionChanged`. Badge only — no body animation exists for this and repurposing one would be fiction. [I1] Verified at M0c: `notification_type` is exactly `permission_prompt` ("Claude needs your permission") or `idle_prompt` ("Claude is waiting for your input"). Carries no `tool_use_id` and **no `agent_id`, not even when the gate belongs to a subagent** — so it names no character, and which one it badges is decided by the rule under "Who the badge lands on" below. |

**Notification timing, because the badge is a timed thing.** `permission_prompt`
arrives 6.0 s after the permission gate opens, not instantly (three occurrences,
6.014 / 6.006 / 6.032 s after `PermissionRequest`; a fourth at M6c, 6.016 s).
`idle_prompt` arrives **60.02 s after `Stop`** and fires once per **idle
stretch**. So an `idle_prompt` badge means "this has been waiting a while", not
"this is waiting"; `Stop` with an empty open-call set already says the latter,
immediately and for free. Nothing may drive a "currently idle" state off
`idle_prompt`.

**Once per stretch, not once per session.** This document used to say "exactly
once — a session left idle a further 145 s produced no second one". The
measurement is right and the non-repeat *within* one stretch is right; the word
"once" read as once per session, and that is wrong.
`fixtures/denial-then-work.jsonl` has **two**, at t=99.783 and t=171.469, 60.03 s
and 60.02 s after the `Stop`s at 39.751 and 111.444, with real work in between.
It fires once per `Stop` that is followed by 60 s of quiet. Nothing may expect a
repeat *inside* a stretch, and nothing may assume at-most-one across a session —
in particular, badge state must be idempotent in both directions rather than
one-shot.

## The attention badge

Implemented at M6. `Notification` was a no-op until then, correctly — it had
never been captured. M0c captured it, both values are real, and M0b had already
sourced a real `attention` badge from the pack, so the design in this document
became implementable without inventing anything.

**The badge is the whole representation.** There is no body state for "waiting
on a human" — the pack ships none, and the six body states are fixed. A
character blocked at a permission gate keeps whatever body its open-call set
says: `working` if it holds calls, `idle` if it does not. [I1/I2]

`badges.states.attention` in `assets/manifest.json`, **not** `badges.map` —
`map` is keyed by `ToolBadge` and every one of its keys is required, while
attention answers to no tool. One glyph serves every `notification_type`: they
all mean "this session wants you", which is what the glyph asserts, and a
per-type icon would need art nobody has drawn. An unrecognised
`notification_type` is carried verbatim and still badges, which is the
question-mark badge's reasoning on a second axis — we know an alert fired, we do
not know which kind, and the honest generic is not a guess.

### Who the badge lands on

**A `Notification` names no character.** It carries no `agent_id` — and M6c
settled that this is true even when the gate belongs to a subagent, which is the
case that made the original rule fiction. In `fixtures/subagent-permission.jsonl`
a `general-purpose` subagent's `Bash` hits the gate, the `PermissionRequest`
carries `agent_id: ab2378e6a85dea269`, and the `permission_prompt`
`Notification` 6.016 s later carries none at all. Read through the identity rule
alone the second event is a main-thread event, so **the main character said
"needs your permission" while the agent actually blocked was a subagent** — and
worse, in that capture the main thread was genuinely working, inside a
synchronous `Agent` call. That is the room asserting something the data does not
say. [I1]

The marker ADR-001 introduced records exactly which agents have an open gate, so
the badge is attributed from it rather than from the notification's silence:

| `notification_type` | Badged |
|---|---|
| `permission_prompt`, ≥1 agent in the session marked with an open gate | **every marked agent** |
| `permission_prompt`, no agent marked | the main thread |
| `idle_prompt`, or anything unrecognised | the main thread |

**Every marked agent, not "the" marked agent.** Concurrent gates are real and
captured: `fixtures/concurrent-permission-gates.jsonl` has two subagents' gates
open together for **31.8 s**. Each of those agents genuinely is waiting on a
human, so each badge is true, and a rule that picked one of them would have to
invent a reason. The gates are on different `agent_id`s, which is exactly what a
per-agent mark handles and a session-level flag could not.

**The no-mark fallback is not a corner case, it is the ordinary path.** For a
main-thread gate the main thread *is* the marked agent, so this table changes
nothing about the required fixtures. And when nothing is marked at all — a
session where `PermissionRequest` never arrived — the notification still
happened and nothing tells us whose it is; the main agent is the honest default,
which is the same fallback this document already takes for an unlinked subagent.
[I1]

**`idle_prompt` is about the session, not about a gated call.** It fires 60 s
after a `Stop`, when nothing is being asked of anyone in particular, so it goes
to the main thread whatever is marked. An unrecognised `notification_type` goes
the same way for the same reason: we know an alert fired, we do not know it is a
gate, and assuming one would be a guess.

Ahead of all of it sits the identity rule: if a `Notification` ever *does* carry
an `agent_id`, that answers the question and no inference is wanted. The
decision lives in exactly one place, `WorldModel.attentionTargets(for:of:resolved:)`.

### When it clears

**The next consumed event from the same agent clears it.** That is the whole
rule.

There is no "notification answered" event. Nothing in 2.1.224 observes the
click: `PermissionDenied` has never fired, on either denial path. So the badge
must be cleared by inference, and the only honest inference is *the session
moved*. Both captured `notification_type`s mean "blocked on the human", and
while blocked the main thread emits nothing at all — so a main-thread event is
evidence the human acted. Measured in `fixtures/permission-prompt.jsonl`:

| Path | Cleared by | Delay |
|---|---|---|
| permission approved | that call's own `PostToolUse` | **1.81 s** |
| permission denied | the user's next `UserPromptSubmit` | **49.37 s** |
| idle | `SessionEnd` (character departs) | — |

**Same agent, not same session.** Only events carrying no `agent_id` clear the
main thread's badge. Without that restriction an async subagent churning
`Read`s into the same `session_id` would wipe the badge off a main thread that
is genuinely still at a dialog — `fixtures/three-subagents.jsonl` is full of
exactly those interleavings — and so would the phantom `SubagentStop` the TUI's
suggestion helper emits on every interactive turn.

**The rule is unchanged now that a badge can sit on a subagent**, because it was
already agent-scoped rather than session-scoped. A gated subagent's badge clears
on *that subagent's* next consumed event, which on the approve path is the gated
call's own `PostToolUse`: **5.525 s** in `fixtures/subagent-permission.jsonl`,
against the 1.81 s the main-thread approve path measures — the difference is
when the close landed, not a different rule. Main-thread traffic does not clear
it, which is the same restriction read in the other direction, and it is what
lets `fixtures/concurrent-permission-gates.jsonl` answer one of two open gates
and take down exactly one of the two badges.

**Three kinds do not clear it.** `Notification` itself; anything `unhandled`,
which by the standing rule changes nothing at all; and `PermissionRequest`,
which is consumed as of ADR-001 but is the *announcement of the wait*, not
evidence it ended — it arrives 6 s *before* the notification it precedes, and a
second gate opening while the first badge is up would otherwise erase a badge
that is still true. `SessionEnd` is excluded only because it is redundant: it
departs the character, and a badge on a character that no longer exists is not a
state.

Note the shape of that third exclusion: **consuming an event and having it clear
the badge are separate decisions.** `PermissionRequest` is the first event to
take one without the other, and nothing about consuming an event implies it
clears anything.

**Erring early is deliberate.** M4's rule — *a late reap is a blind spot, an
early one is fiction* — is about a state that asserts "working", so it argues
for a long deadline. This badge has the opposite polarity: it is a positive
assertion, so a **late** clear is the fiction ("Claude needs your permission"
when it does not) and an early clear is only a miss. The same principle
therefore points the other way here.

**Reapable without a deadline of its own.** [I4] Three paths bound it: the
agent's next consumed event, `SessionEnd`, and the 30-minute session-idle sweep,
which departs the character entirely. A fourth timer was considered and
rejected — it would be a number with nothing behind it, and it would make the
badge lie by omission in the one case where the true statement is "still
waiting": an `idle_prompt` on a session nobody has come back to is correct for
exactly as long as nobody has come back to it.

**Two things the rule gets wrong, stated rather than papered over.**

- Between clicking "No" and typing again, the badge asserts a wait that has
  ended — 49.37 s in the capture. No rule can do better without an event that
  does not exist.
- A permission *approved* for a long-running tool leaves the badge up for that
  tool's whole run, because nothing fires between the approval and the call's
  close. The badge therefore never outlives the call it sits beside, so it
  introduces no unbounded state — but it is stale for that window. If living
  with it proves annoying, a bounded timeout is the obvious refinement, and it
  is a decision that wants somebody watching the room rather than a constant
  picked in the dark.

### Precedence in the badge slot

There is **one** badge anchor and there are three things that can want it. The
order is **attention > sleep > tool**, and the two comparisons are argued
separately because they are different kinds of question.

A character can hold open calls *and* have a notification outstanding — that is
what every permission prompt looks like, since `PermissionRequest` lands ~16 ms
after `PreToolUse` and the call then sits at the gate.

**Attention outranks every tool badge, and it suppresses the `×N`.**

1. It is the only badge a glance can *act* on. The tool badge says what is
   happening; the attention badge says the room needs you. For a surface whose
   one sentence is "you glance at the notch and know what your agents are
   doing", letting an unactionable icon hide an actionable one inverts the
   product.
2. It is the *more truthful* of the two. A call parked at a permission gate is
   not running, so drawing `terminal` over a gated `Bash` asserts work that is
   not happening while the attention glyph asserts a wait that is. [I1]
3. Showing both would need a second badge position, and the manifest carries
   exactly one badge anchor. A second slot would be an eyeballed offset dressed
   as data — the reason M5 left the monitors unplaced.

The `×N` goes because it annotates a *tool* badge ("N calls, of which this is
the lowest ordinal"). Pinned to the attention glyph it would read as N
notifications, which is never true — `idle_prompt` fires once and notifications
are counted nowhere.

Determinism is unaffected. Attention is a single flag, so the badge stays a pure
function of the character's state and still changes at most once per change of
that state; the lowest-ordinal rule below is untouched and resumes the moment
the badge clears. [I3]

**Attention also outranks the `sleep` badge, and this one is not a truth
question.** Both facts are true at once: the agent finished a turn *and*
something is waiting on the human. It is decided on which of two true things is
worth the one anchor, and the same reason 1 settles it — `sleep` is a status and
attention is a request, and a status hiding a request inverts a surface whose
one sentence is "you glance at the notch and know what your agents are doing".
"Waiting on you, now" has a deadline the user owns; "finished a turn, might come
back" does not. Nothing is lost by the loss, because dormancy is a standing
state rather than an event: the `Z` comes back by itself the moment the
attention clears, and the agent's next consumed event does both — it clears the
attention *and* revives the agent, one delta each, in the same batch.

The combination is narrow but genuinely reachable, so it is decided rather than
assumed away: `PermissionRequest` arms an agent's gate mark **without** going
through the creation path, so it does not revive a dormant agent, and a later
`permission_prompt` badges every marked agent. It also arrives on the
project-switch reconstruction path, which replays both facts at once.

**`sleep` outranks the tool badge, and that combination is unreachable.** A
dormant agent has no open calls: `SubagentStop` abandons every one of them in
the same batch that sets dormancy, and the only event that opens a call —
`PreToolUse` — revives the agent before the call opens. The order is written
down anyway, because "unreachable" is a property of today's model and the badge
selection is a value type anything may construct. If the two ever do co-occur,
`sleep` is right for the same reason attention beats a gated `Bash`: the calls
would be stale and the turn boundary would not be.

Everything else decodes to `.unhandled` and is counted, not dropped silently.
A rising `.unhandled` count is how we notice the hook surface has grown.

"Everything else" is not hypothetical. 2.1.224 defines at least fourteen further
event names we do not consume, including `UserPromptExpansion`, `StopFailure`,
`PreCompact`, `PostCompact`, `PermissionDenied`, `TaskCreated`, and
`TaskCompleted`. All of them will reach the listener under a `*` registration.
They must decode, be counted, and change nothing.

`PermissionRequest` used to be on that list. **It is consumed as of ADR-001** —
see the table above and "The interactively denied tool call" below. That is a
real cost, recorded rather than glossed: the unhandled counter exists to notice
the hook surface growing, and it is one name poorer.

- **`PermissionRequest` is real and fires over HTTP**, ~16 ms after the
  `PreToolUse` for the same call. It carries `tool_name`, `tool_input` and
  `permission_suggestions[]` — and **no `tool_use_id`**. It therefore cannot be
  joined to an open call without pairing by tool name, which the pairing rule
  below forbids, and it is not joined to one: it is consumed as a "this agent is
  blocked on a human" signal, which is what it is. Marking performs no join at
  all, so it cannot join wrongly.
- **`PermissionDenied` still has never fired.** **[unverified]** — registered
  over both HTTP and `command` delivery and tested against both denial paths a
  user has (selecting "No" at the dialog, and Esc to cancel). Neither produced
  it. The name exists; the condition that emits it is unknown.

The app registers only the eleven events listed under "Hook registration", so in
normal operation the others never arrive at all — but the listener is not
allowed to depend on that, because a `*` registration written by hand, or a
future release that widens what a registration covers, would deliver them
anyway.

**`PermissionRequest` is registered**, with matcher `*`, in
`HookInstaller.events` and `.claude/settings.example.json` together — that is the
shape it was captured firing under, not a guess. This paragraph used to say it
was consumed but *not* registered, and that has been stale since the entry
landed; it mattered, because without the registration the marker never arms and
every rule below is dead code in a real install. The badge attribution above
depends on the same registration for the same reason.

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

The consequence used to be live: `Bash` carries the 15-minute deadline, so
clicking "No" on a `Bash` prompt left that character working for fifteen
minutes — the signature bug of this project on the most ordinary interaction
there is.

**`docs/ADR-001-denied-calls.md` was accepted on 2026-08-07 and implemented in
the same change.** Read it for why each alternative was rejected; the shipped
rule is below. Note what it did *not* do: **no close path changed.** There are
still exactly three, they still close exactly the ids they always closed, and
this fixture's denied call still has none of them. What changed is a *deadline*,
which is tool-keyed policy that already lived in the `Reaper`.

One other thing narrows the symptom without touching a close path either: the
attention badge is wired as of M6 and outranks the tool badge, so while the
dialog is up the character shows "needs you" rather than a `terminal` glyph. The
residual — the window *after* a denial — is what the rule below is for.

### The interactively denied tool call

Three rules. They are what ADR-001 recommends as (d), and they exist because
each of its two halves fixes the other's flaw: a `PermissionRequest` is a
reliable arming signal that cannot tell approve from deny, and a
`UserPromptSubmit` is a discriminator that cannot tell a real prompt from a
synthetic one.

1. **Mark.** A `PermissionRequest` records, for the agent it belongs to: a gate
   is open, and these are the `tool_use_id`s that agent held open at that
   instant. The marked set is simply the agent's open-call set, which the model
   already holds. **No join is performed** — not by name, not by recency — so
   none can be performed wrongly. [I3]
2. **Disarm.** Any close of any call in the marked set (the approve path: the
   gated call closes normally), or a `Stop` (the turn completed).
3. **Shorten.** A `UserPromptSubmit` for that same agent while the mark is still
   set pulls every still-open marked call's deadline in to `now + G`.
   **Shortened, not closed.** The reaper still does the closing and still emits
   `.callAbandoned`; the character just returns to idle.

`G` is 60 s, and where that number comes from is under "Reaping" below.

Rule 3 pulls *in* only. A call whose own deadline is already sooner than
`now + G` keeps it — this rule may never grant a call more life than the
deadline table below allows.

Agent attribution for rule 1 is the **ordinary identity rule and nothing else**:
`agent_id` present → that subagent, absent → the main thread. **Risk 3 of the
ADR is settled, in the rule's favour** — a subagent's gate does carry an
`agent_id` (`fixtures/subagent-permission.jsonl`, M6c; eight further
`PermissionRequest`s across six sessions agree). The decision still lives in
exactly one place, `WorldModel.gateOwner(of:)`.

**That per-agent scoping is load-bearing, not incidental.** ADR-001 excludes the
synchronous-`Agent` hazard by claiming a main thread inside a synchronous `Agent`
call is not simultaneously raising a permission prompt. It is:
`subagent-permission.jsonl` has the parent's `Agent` call open from t=3.504 to
t=19.805 with the child's dialog on screen from t=6.279. The conclusion survives
only because the gate is marked on the **child**, so nothing can shorten the
parent's call. A session-scoped mark — the natural simplification, since the mark
holds no `tool_use_id` — would reintroduce the bug. Do not widen the scope.

**What it can get wrong**, stated rather than papered over: the mark covers *all*
of the agent's open calls, because nothing in the event names the gated one. A
main-thread batch mixing a gated call with a sibling that legitimately runs past
`G` after the user's next prompt reaps the sibling early, which is fiction. It
needs a shape no capture contains, and it is the rule's one acknowledged hazard.

**What it deliberately does not do** is close anything on a `UserPromptSubmit`
alone. That was option (b), and it is refuted by capture: in
`three-subagents.jsonl` `toolu_017StzPCoy…` runs 8.05 s across one synthetic
prompt and `toolu_01NDyNkE17…` runs 15.05 s across two, and both were genuinely
working. Neither is marked, so neither is touched — there is a test named for
exactly that.

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

### `G` — the one deadline not keyed by tool

| | |
|---|---|
| **A call marked at a permission gate, once a `UserPromptSubmit` says the human answered** | **`now + G`, G = 60 s** |

Set by rule 3 of "The interactively denied tool call" above, and never applied to
anything the mark did not cover. It replaces whatever the table says for that
call — but only downwards.

`G` is a measurement, not a taste. The only thing it has to survive is the gap
between a synthetic `UserPromptSubmit` and the close of a call that is genuinely
still running, and that gap is measured twice in `fixtures/three-subagents.jsonl`
and nowhere else: 8.05 s and 15.05 s. 60 s is four times the larger — 3.99×, to
the precision the second decimal deserves — so it keeps four times the observed
head-room while cutting the worst case from 900 s to 60 s, 15×.

**It is a number to revisit with more captures, not a constant of nature.** Two
straddles from one fixture is the whole evidence base. It lives in
`Reaper.permissionGateGraceInterval` with that reasoning attached, and the test
that pins it *derives* the straddles from the fixture rather than restating them,
so a capture with a longer one turns this from an argument into a red test.

On expiry: close the call, emit `.callAbandoned`, increment a counter. The
character returns to idle. It does **not** display an error — an abandoned call
is usually our blind spot, not the user's failure.

Additional sweeps: `SessionEnd` closes all. A session with no event for 30
minutes is presumed dead and closed. Both are belt and braces for I4; keep both.

**The permission-gate mark is reapable too** [I4]. It is not a call, so it has no
deadline of its own, but it is per-agent open state and it answers to the same
paths: `SessionEnd`, the agent's departure, and the idle sweep. It is held
*inside* the agent's own state rather than in a table beside it, so all three
clear it by construction — a parallel store would be one more thing to remember
to clear, which is one more thing to leak.

**Dormancy added a fourth path, and it had to.** A subagent that stops now keeps
its `AgentState` instead of having it deleted, so departure no longer clears the
mark at that moment. `SubagentStop` therefore disarms it explicitly. The abandon
of the agent's open calls covers the ordinary case already — abandoning a marked
call disarms by rule 2 — but not the legal *empty* mark, which is a snapshot of an
open-call set that happened to be empty; that would otherwise ride into dormancy
and be badged by a later `permission_prompt` it has nothing to do with. [I1] The
disarm is independently correct rather than merely convenient: it is rule 2 read
for a subagent, since `Stop` disarms the main thread's mark because the turn
completed and `SubagentStop` is that same fact.

**Dormancy itself is reapable for the same structural reason**: it is a field of
`AgentState`, so `SessionEnd` and the idle sweep take it with the character
without anybody remembering to.

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

**Two badges are not in this table and both outrank all of it.** Neither is a
tool; both live under `badges.states` rather than `badges.map`; and while either
is up it replaces the tool badge and suppresses the `×N`.

| Badge | Raised by | Cleared by |
|---|---|---|
| attention | `Notification` | the badged agent's next consumed event |
| sleep | `SubagentStop` (`dormancyChanged`) | the same agent's next consumed event, which revives it |

They are cleared by the same rule because they are the same kind of fact: a
statement about an agent that stopped, which that agent's next event refutes.
The order between them, and against the tool badge, is under "Precedence in the
badge slot" above.

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
off-screen subagent is still visible: it walks in, delivers, **and goes back to
its seat.** The beat itself is unchanged — the walk and the hand-over are the one
licensed dramatisation and they still fire on exactly this event. What changed is
where the character ends up afterwards, and why: see "`SubagentStop` is a turn
boundary, not a death" below.

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

### `SubagentStop` is a turn boundary, not a death

M4 recorded that "a subagent can come back". `fixtures/four-subagents.jsonl`
shows *how*, and how often. Four `general-purpose` subagents were dispatched
with `run_in_background` into one session; two of them stopped, were resumed by
the parent with `SendMessage`, and each resume emitted a **second
`SubagentStart`**. So one `agent_id` produced two full spawn→stop cycles inside
172 s.

The consequence was a fact about the room, and it is worth stating plainly
because it is what an unhappy user saw: **the number of subagent characters
tracked who was mid-turn, not how many agents the user dispatched.** In that
capture, between the fourth spawn and the last stop, all four were on screen for
39.1 s of 69.5 s — 56% — and the room dropped to two for 7.3 s and to **one for
6.7 s**, while the parent still had four agents assigned the whole time.

The paragraph that stood here said this was truthful, that "four dispatched, one
drawn" was a *correct* rendering, and that whether such an agent should keep a
presence in the room was a product decision not taken here. **The first two are
wrong and the third is now taken.** Departing on `SubagentStop` makes the room
assert *this agent is gone* when the data says only *this agent finished a turn*
— and this capture is the proof it can come back. That is the [I1] violation, not
the fix for one. The product's one sentence is "you glance at the notch and know
what your agents are doing"; a room that cannot be counted does not deliver it.

### The decision: a subagent that stops goes dormant

**A subagent that stops does not leave the room.** It plays the report beat and
then returns to its seat, `dormant`, and stays there.

- The `.reporting` beat is untouched: `reportDelivered` fires on the same event,
  in the same place, and licenses the same walk-to-anchor-and-deliver. Only the
  destination changed. `dormancyChanged(isDormant: true)` rides behind it on the
  same event — two facts, in the order they happened.
- **A second `SubagentStart` for a known `agent_id` revives it in place** —
  `dormant` → `active`, one `dormancyChanged(isDormant: false)` and nothing
  else, no second character, no second seat, no
  re-spawn walk. Reached through the same idempotent creation path every event
  goes through, so a resumed agent whose `SubagentStart` we missed is revived by
  its own next `PreToolUse` instead.
- **A dormant agent still departs on the paths that genuinely mean gone**:
  `SessionEnd` and the 30-minute session-idle sweep. [I4]
- **Dormancy carries no deadline of its own, deliberately.** "Depart after N
  minutes dormant" would be a number with nothing behind it, and it would
  recreate this exact bug for any agent resumed later than N. An assignment is
  live for as long as its session is, and the session is already bounded twice.
- The mark is disarmed on the way in, which is ADR-001 (d) rule 2 read for a
  subagent — see "Reaping" below.

**A dormant character wears the `sleep` badge: a blue `Z` over an otherwise
ordinary idle character, in its own seat, under its own plate.** Nothing else
about it moves.

This paragraph used to say the opposite, and the reversal is recorded rather
than overwritten because the old argument was half right. It ran: "finished and
might come back" and "between tool calls" are different facts and the room would
be better for separating them, but nothing we own can draw the difference —
there are six body states and none means dormant, and the single badge anchor
holds one non-tool glyph, `attention`, which asserts "the room needs you" and
would be a lie here. Inventing a pose is what [I1] forbids. So both rendered
`idle`, no `WorldDelta` carried the lifecycle, and the seam was named for
whenever a scene earned an honest treatment.

**The body half of that survives and is now measured.** M6b cut the pack's
`sleep` row: six frames of a head lying on a pillow, drawn from above, with no
body, and the pack's own diagram shows it composited onto a top-down bed. On a
character sitting side-on in an office chair it is a floating head at chest
height. There is no dormant body state and there must not be one.

**The badge half does not survive, because its premise stopped being true.**
Modern Interiors' UI sheet carries a blue `Z` speech bubble — the same 548-pixel
component, in the same frame, as `attention` — and `badges.states` exists
precisely for badge states that answer to no tool. It ships as
`badges.states.sleep`, it needs no new manifest key and no new body state, and
it measures identically to `question_mark` (saturation 0.710, darkest value
0.337), so the badge exemption's own sentence still holds at eight badges. It
asserts exactly what the flag knows and nothing more, which is the whole test.
[I1]

So the seam the old paragraph named is the delta that now exists:
**`dormancyChanged(agent:isDormant:)`**, emitted by `SubagentStop` beside
`reportDelivered` and cleared by the revival every consumed event performs. It
is a `Bool` rather than an `AgentLifecycle` on purpose — the other four cases
are either already carried on `agentAppeared`, never rested in (`reporting`
holds no clock), or already have a delta (`departed` is `agentDeparted`), so a
delta carrying the whole enum could express three transitions the model never
makes.

The badge goes up on the same event that starts the report walk, so a reporting
character carries the `Z` through the beat. That is correct rather than
tolerated: the turn is over from the instant `SubagentStop` arrives, and the
walk is the room saying so.

What survives from the old paragraph: a report of "four dispatched, one drawn" is
still not by itself evidence of a lost event, and diagnosing one still starts by
asking which agents were mid-turn rather than by hunting the transport.

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
- `permission-prompt` — a real interactive permission dialog, denied then
  approved. **Joined the set at ADR-001**, on the condition this document
  already set for it: it is the fixture that proves the interactive-denial fix,
  so from the moment there is a fix it is required coverage. Carries
  `PermissionRequest`, both `Notification` types' first half, and the
  never-closed denied call. Like `killed-session` it does **not** replay to zero
  open calls without the reaper, by nature — a user clicking "No" produces a
  call that nothing in the stream ever closes, and no rule can invent one. What
  ADR-001 changed is the number: 900 s became 60 s.

- `denial-then-work` — a real interactive denial in a session that **carries on
  working for 157 s afterwards**. Joined the set by maintainer decision once
  ADR-001 shipped. `permission-prompt` proves the denied call exists;
  this one proves the fix *fires*, because it is the only fixture whose
  shortened deadline falls inside its own stream. The orphan opens at t=3.14,
  the gate marks it, the user's real prompt at t=34.98 sets the deadline to
  t=94.98, and it is reaped there with three later calls still to come.
  Consequently it is also the one required fixture that replays **differently**
  with the clock advancing — which is the point of it, and why it is the single
  exclusion from `advancingTheClockChangesNothingInTheRequiredFixtures`.
  It also carries two `idle_prompt` notifications, and is the capture that
  refuted "fires exactly once".

  `parallel-denial` was considered alongside it and left out: it records that
  the 2.1.224 TUI serialises a batch's tool calls, which is a finding about the
  TUI rather than a rule this layer has to keep.

A change to the ingest layer that does not run green against all eight is not
done.

**Interactive coverage, added at M0c.** Three further captures, from real TUI
sessions driven under an allocated pty rather than `claude -p`. They cover
events the original six cannot contain:

- `interactive-session` — a real interactive session, start to `/exit`. Settles
  `SessionStart` by absence, and carries the phantom `SubagentStop`.
- `permission-prompt` — **now one of the required seven**, listed above.
- `idle-notification` — `Notification` with `notification_type: idle_prompt`,
  60 s after `Stop`.

The other two remain outside the required list. That list was an exit criterion
signed off at M2; `permission-prompt` joined it because this document had
already named the condition under which it should ("the fixture that would prove
the fix"), and ADR-001 is that fix.

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
