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

`agent_type` now drives three visible channels, not one, and all three are on the
**agent** volatility band [ADR-002 §6 rule 2] — decided at spawn, carried on
`SpriteIntent.spawnCharacter`, stored in a `let`, and never rewritten:

| Channel | From | Absent / empty `agent_type` | No `agent_id` |
|---|---|---|---|
| Nameplate | the string itself | `subagent` | `MAIN` |
| **Station** — the desk and chair at its seat | rendezvous over the theme's numbered stations | `station.default` | `station.main` |
| **Costume** — what it is wearing | the wardrobe's `roles` table, else rendezvous over the neutral pool | nothing | nothing |

The station's rules are ADR-002 §4 and its art contract is §7. The reason it is
named here at all is that until M6h it resolved and **reached nothing**:
`Manifest.Station` had no caller, the id never left `SceneDirector`, and a
manifest with six visually wild stations in every theme rendered byte-identical
to one with none. It is drawn now, and the assertion that would have caught its
absence is
`StationSceneTests.twoAgentsOfDifferentTypeDrawDifferentPixelsAtTheirSeats` —
the maintainer's own question, mechanised: *can you tell one agent from another
by looking at the room?*

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
| `UserPromptSubmit` | Creates the session and its main-thread agent, and **nothing else**. The character it draws is **seated and still** — at its desk, running nothing — because a prompt is the start of a turn and nothing has been called yet [ADR-005]. Consumed for one reason: without it the main character does not exist until the session's first tool call, so a turn spent thinking draws an empty room. [I2] A *second* prompt emits no delta, because the agent already exists — unless it is answering that agent's permission gate, which clears the mark and emits `gateChanged(isGated: false)`; see the `Stop` row and "The interactively denied tool call". |
| `SubagentStart` | Create agent under `agent_id`. Character spawns beside the anchor. Carries `agent_id` and `agent_type`, nothing else. **Not once per agent** — a background subagent resumed with `SendMessage` emits a second one ~20 ms after that call's `PreToolUse`. Creation stays idempotent for that reason, and for a **known** `agent_id` this event is the *revival* path: it returns a dormant character to `active` **in place**, emitting `dormancyChanged(isDormant: false)` and nothing else. No second character, no second seat, no re-spawn walk — the one visible change is the `sleep` badge coming down. |
| `PreToolUse` | Open a call keyed by `tool_use_id`. Character enters/keeps working. |
| `PostToolUse` | Close that `tool_use_id`. |
| `PostToolUseFailure` | Close that `tool_use_id`, flagged failed. Fires *instead of* `PostToolUse`, never alongside it; the message is in `error`, not `tool_response`. |
| `PostToolBatch` | Close every `tool_use_id` in `tool_calls[]`. A primary close path, not a sweep — see below. |
| `SubagentStop` | Agent enters `.reporting` → walks to anchor → delivers → **returns to its seat, stands up and goes `dormant`**, wearing the `sleep` badge. Emits `reportDelivered` and then `dormancyChanged(isDormant: true)`. **`dormancyChanged` is the one turn boundary the delta stream carries**, so it is what ends the seated posture — the `Z` tab and the body now say one thing instead of a tab sitting over a body that disagrees with it [ADR-005 §3]. It does **not** depart: this is a turn boundary, not a death, and the agent can be resumed. Its open calls are abandoned (`.agentStopped`) and its permission-gate mark is disarmed — the turn completed, so nothing is pending — which emits `gateChanged(isGated: false)` ahead of the report beat when a gate was open. See "`SubagentStop` is a turn boundary, not a death" below. |
| `Stop` | Main agent pauses. **Not** "turn over" — it fires once per assistant message stream, several times in one user turn when async subagents wake the main thread. Never treat it as end-of-session or as a reap trigger. It **disarms** that agent's permission-gate mark (below): the turn completed, so it emits `gateChanged(isGated: false)` — and only when there was a gate to close. **No `Stop` in the corpus closes one**: every captured gate ends at the approving close, at the answering `UserPromptSubmit`, or at the reaper, so all 26 of them still emit nothing. The path is ADR-001 (d) rule 2's second half and is kept for the same reason that rule is. That is not the turn boundary §3 wants: it says nothing about the turn, it releases a body that was being held still [ADR-005 §7]. **It needs no dormancy of its own** — checked, not assumed: `Stop` sets no lifecycle and emits nothing but that gate clear, and the main agent departs only on `SessionEnd` and the idle sweep, so it already stays in the room across a turn boundary, which is the whole of what dormancy buys a subagent. Marking it dormant would also be the weaker claim, since `Stop` fires once per assistant message stream and several times in one user turn. **This is the one place ADR-005 asks for something the model does not have.** §3 closes the seated posture on `Stop` for the main agent; a scene fed only deltas cannot see it, so what ships seats the main character at its session's first event and stands it up only when it leaves. That is a blind spot, not a fiction — the room declines to draw a boundary it was not told about — and closing it means emitting a `turnEnded(agent:)` delta here, on the same footing as `dormancyChanged`: a change, never a repeat, replayed by `ProjectRegistry` across a project switch. Not done; a second module is a second concern. |
| `PermissionRequest` | **An agent-level marker.** Records for that agent: a permission gate is open, plus the set of `tool_use_id`s it held open at that instant. No join by name, no join by recency, no `tool_use_id` read from the event — it carries none. Emits **`gateChanged(isGated: true)`**, a change and never a repeat, and does not clear the attention badge. It used to emit nothing at all, on the grounds that a marker is not a fact about the room; the *marked set* is not and still never leaves the model, but *being stopped at a gate* is — it is the only answer this app has to "is any agent stuck", and the body holds still for all of it [ADR-005 §7]. Nine gates open across the seventeen captures and they are long: measured from this delta to its clear, 7.8 / 11.5 / 31.8 / 31.8 / 36.7 / 55.4 / 247.6 s, plus two that no event in their stream ever closes and only the reaper ends. See "The interactively denied tool call" below. |
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

**The badge is the whole representation of the *notification*.** There is no
body state for "waiting on a human" — the pack ships none, and the six body
states are fixed. A character blocked at a permission gate keeps whatever body
its posture says: seated, because it is in a turn, at its desk. [I1/I2]

What it does **not** keep is its motion. Since ADR-005 §7 an agent with an open
permission-gate mark holds one still frame and plays no phrase — see "the
ambient loop is keyed by badge class" below. That is a different channel and a
different fact: the gate mark arms on `PermissionRequest` and names its agent,
the badge is raised by a `Notification` 6.0 s later that names nobody. For those
six seconds the stillness is the only thing the room says about a blocked agent,
so the two compose rather than duplicate — the bubble says *the room needs you*,
the stillness says *and this one is getting nothing done meanwhile*. Neither
depends on the other.

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

There is **one** badge anchor and there are four things that can want it. The
order is **attention > sleep > open tool badge > closing beat**, and the
comparisons are argued separately because they are different kinds of question.

**The order is about which fact gets the anchor, not about which picture is
drawn there.** Three of the four ranks draw the pack's speech bubble; `sleep`
draws a small dark tab instead, for the reason recorded under "`SubagentStop` is
a turn boundary" — at `1x` a bubble's *presence* is the loudest signal the room
has, and spending it on an agent that has stopped inverted the one distinction
the room exists to make. Nothing about the ranking moved.

The fourth rank is `ADR-003`'s and it is the existing order with one entry
appended at the bottom — nothing above it moves. A beat is a glyph about work
that has *finished*, so everything that is about now outranks it, and each of the
three does more strongly than it outranks a live tool badge. It does not merely
lose the slot to them: a rising attention or a `dormancyChanged(true)` **cancels**
a beat outright, so answering the prompt or waking the agent does not bring a
stale glyph back. See "The closing beat" below.

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

### The one request on this port that is not a hook — M7d

`ListenerHeartbeat` POSTs to `127.0.0.1:<bound>/_liveness` once a second. It is
the app asking itself whether it is still answering, and it is the **only**
source of the pilot lamp. See `docs/ADR-004-liveness-lamp.md`.

It is recognised on the **request target**, in `HTTPRequest.parse`, which is the
first token of the first line — so a probe is identified before anything else on
the connection has been looked at, and the cost on the hot path is one token
comparison on a string the parser had already built. [I5] Measured:
`LivenessTests.aRunningHeartbeatDoesNotCostTheSessionLatency` puts the listener's
p99 at 0.164 ms over 2000 requests with the heartbeat running beside it, against
a 5 ms budget.

**It is not an event and it never becomes one.** `handle` returns before
`HookEventDecoder` is reached, so a probe cannot create a session, an agent, or
tool state, and it does not appear in `unhandled` — which would otherwise be the
worst outcome, since that counter exists to notice the hook surface growing and
a steady drip of our own traffic is exactly what would blind it. It is counted on
its own axis, `IngestCounters.probes`, and is deliberately outside `requests` and
`malformed` for the same reason.

A hook POST goes to `/hook` and can never be mistaken for one: the match is on
the whole target, not a prefix
(`LivenessTests.onlyTheExactProbeTargetCounts`).

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
   gated call closes normally), or a `Stop` (the turn completed). Also
   `SubagentStop`, which is a `Stop` read for a subagent.

   Arming and disarming each emit `gateChanged` — a change, never a repeat —
   and nothing else about the mark leaves the model. That delta is what holds a
   blocked character still [ADR-005 §7]; the *marked set* still drives deadlines
   and nothing else, and is still never drawn from, because nothing in the event
   names the gated call.
3. **Shorten.** A `UserPromptSubmit` for that same agent while the mark is still
   set pulls every still-open marked call's deadline in to `now + G`, and spends
   the mark — so it disarms, by rule 2, and the character moves again at the
   moment the human answered rather than 60 s later when the reaper catches up.
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

**Since it drives a delta, the *stream* has to balance too, and that is a
second obligation rather than the same one.** A scene told `gateChanged(true)`
and never told anything else holds a character still forever, which is I4's
character-that-types-forever with the sign flipped — and it would be frozen by a
fact the model itself had already dropped. So every path that clears the mark
emits the clear: a marked call closing (the approve path) or being abandoned
(the reaper), `Stop`, `SubagentStop`, and the `UserPromptSubmit` that answers the
dialog. Departure is the one exception and needs no clear, because the
`agentDeparted` beside it removes the character the fact was about — exactly the
division `dormancyChanged` already makes. Checked over all seventeen captures by
`PermissionGateTests.everyGateThatOpensIsClosedOrItsCharacterLeaves`, which
walks the delta stream rather than the model: nine gates open, nine close, and
the two in `concurrent-permission-gates` that outlive their streams are closed
by the sweeps.

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
| magnifier | `Read`, `Glob`, `Grep`, `ToolSearch` |
| terminal | `Bash`, `BashOutput`, `KillShell` |
| globe | `WebSearch`, `WebFetch` |
| checklist | `TodoWrite`, `Agent`, `SendMessage` |
| plug | `mcp__*` (any) |
| question mark | anything unmapped — and `Monitor`, permanently, see below |

Unmapped tools get the question mark and are logged. Never invent a badge for a
tool you do not recognise — the question mark is honest, a guess is not. [I1]

### The table is filled from the captures, not from imagination — M6d

A live capture logged `unmapped tools: Monitor×1, SendMessage×2, ToolSearch×5`.
Five uses of one tool in one session is an ordinary tool, not an exotic one, and
a room that answers "?" for it is telling the user less than it could.

So the table was reviewed against **every distinct `tool_name` in `fixtures/`**,
walked rather than remembered. There are six: `Bash` (45 calls), `Read` (19),
`Agent` (10), `ToolSearch` (6), `SendMessage` (2), `Monitor` (1).
`everyToolInEveryFixtureIsEitherMappedOrDeliberatelyNot` now does that walk on
every run and fails on a tool that is in neither the table nor the list of
deliberate question marks, so a future capture cannot introduce one quietly.

**There are seven badges and no more are coming** — four of them are authored and
no further art packs will be bought [04-ART-DIRECTION, M5c]. So the only question
a new tool can raise is *does it belong in a bucket that exists*, never *what
glyph does it need*.

- **`ToolSearch` → magnifier.** It queries the tool catalogue by name or keyword
  and hands back schemas. It reads no file, but neither does `Glob`, which is in
  that bucket for matching *names* while `Grep` is there for matching *contents*:
  the bucket is retrieval, not the filesystem. Not `globe`, which is the network;
  `ToolSearch` never leaves the process.
- **`SendMessage` → checklist.** On the strength of the capture rather than a
  reading of the name. This document already records that a `SendMessage`
  `PreToolUse` is followed ~20 ms later by a `SubagentStart` — twice in
  `fixtures/four-subagents.jsonl`, at 25 ms and 26 ms — which is the same event
  `Agent` produces and the reason `SubagentStart` is not once per agent. The
  model already treats `SendMessage` as dispatch, and any other badge would have
  the glyph disagree with the character waking up beside it in the same batch.
- **`Monitor` stays the question mark, and that is the answer rather than a
  deferral.** It is the one tool in the capture with two disjoint substrates and
  a name that does not say which: a `command`, which runs in the same shell
  environment as `Bash`, or a `ws` WebSocket. Badges are keyed by name alone, so
  `terminal` would claim a shell for a call that may be a socket and `globe` the
  reverse. It is 1 of the 83 calls in `fixtures/`, so a bucket would be right
  rarely and wrong rarely — and when those two are that close, the glyph that
  asserts only "we do not recognise this" wins. [I1] If `Monitor` ever splits
  into two tool names, each half has an honest home and this line goes.

Two near misses left alone on purpose, in the same spirit as the hand mirror and
the monitor in `04-ART-DIRECTION.md`: `ToolSearch` is not `globe` merely for
having "search" in common with `WebSearch`, and `Monitor` is not `terminal`
merely for usually carrying a shell command.

**Multiple open calls:** display the badge for the *lowest-ordinal* tool in the
table above, plus a small `×N`. Deterministic ordering means the badge is
stable while calls interleave; most-recent-wins would flicker. [I3]

**This rule never sees a lingering call**, and that is worth stating now that
one can linger. `ADR-003`'s closing beat exists *only* while an agent's open set
is empty, so the count during a beat is zero and the `×N` — drawn only above one
— is suppressed with no new rule. The lowest-ordinal selection is not modified,
not extended, and not read in a new situation: the glyph a beat carries is
literally the last value the rule above returned for a non-empty set. Had the
rule instead been "every closed call lingers", the badge would flip from
`terminal` to `magnifier` at the moment work *stopped*, because `magnifier` is
the lower ordinal — a badge change caused by nothing happening, which is the
flicker the ordering exists to prevent, coming back through a side door.

**Three badges are not in this table.** None is a tool. The first two live under
`badges.states` rather than `badges.map` and outrank everything; the third is a
tool glyph the slot keeps for a moment after its call ended, and it is outranked
by everything. While any of them is up the `×N` is suppressed.

| Badge | Raised by | Cleared by |
|---|---|---|
| attention | `Notification` | the badged agent's next consumed event |
| sleep | `SubagentStop` (`dormancyChanged`) | the same agent's next consumed event, which revives it |
| **closing beat** — the tool glyph that was on screen | the close that empties an agent's open-call set, and no other close | `D` = 500 ms elapsing; or immediately by a `callOpened`, a rising attention, `dormancyChanged(true)`, departure, project switch, scene rebuild or `SessionEnd` |

The first two are cleared by the same rule because they are the same kind of
fact: a statement about an agent that stopped, which that agent's next event
refutes. The order between them, and against the tool badge, is under
"Precedence in the badge slot" above.

### The closing beat — `ADR-003`, accepted 2026-08-09

> When an agent's open-call set becomes empty **by a real close**, the badge that
> was on screen at that instant remains for `D` and then clears. The `×N` is
> suppressed for the whole beat. **The body stops moving at the close and
> asserts no ongoing work for any frame of the beat** — one still frame, no
> ambient phrase. Nothing else ever lingers.

That middle sentence read "the body goes idle at the close and is idle for every
frame of the beat" until ADR-005, which moved the posture off the open-call set:
the body during a beat is now seated and **still** rather than standing, which
asserts less rather than more, and the ongoing-work claim lives wholly in the
motion. ADR-003 §6 condition 1 carries the argument and is the ratified text.

It exists because three of the six tool classes were structurally unobservable:
across a measured 224 s session, `magnifier` had 16 calls totalling 0.11 s and
landed on **zero** sampled frames, `checklist` 5 calls and 0.07 s and zero
frames, `document` 10 calls and one frame. The badge system was drawing exactly
what it was told — predicted frames matched observed on all six classes — and
what it was told was almost nothing.

Four things about it are rules rather than details:

- **Only on the transition to zero.** A close into a still-occupied set gets
  nothing: the slot is occupied and the character is visibly working anyway.
- **`.callAbandoned` arms no beat**, even when it empties the set. An abandon is
  the reaper closing our blind spot rather than a completed action, and it fires
  up to fifteen minutes after the fact — a `magnifier` beat at t+900 saying
  "just did a read" about a call we lost track of is fiction. [I1] The scene
  splits the two close paths for this reason and no other.
- **The body carries tense; the badge carries kind.** `agent is working ⟺
  !openCalls.isEmpty` is unchanged and the ambient loop still ends with the
  call, to the frame — it is a statement about the **motion**, which is where
  ADR-005 left it. A still character under a `magnifier` bubble reads "not
  working; the last thing was a read", which is true. Letting the body claim
  ongoing work for the beat would assert an agent still reading, which is false,
  and `ADR-003` §6 declares itself void — not degraded — if an implementation
  does it. The precedent is already in the room: the attention badge has no body
  state at all.
- **It is scene-side.** `WorldModel` knows nothing about it. The call really
  closed; holding it open in the true layer would be fiction in the one place
  that may not have any, would lie to the reaper, and would break the replay
  harness's no-orphaned-state property.

`D` = 500 ms, derived rather than tasted: the floor is the room's own 8 fps
animation grain and its shortest complete gesture (`working` is 3 frames =
375 ms), and the ceiling is that "just now" has to still be true. 500 ms is the
first value on the 125 ms grid above 375 ms, and 2.7% of the measured 18.5 s
mean gap between an agent's calls, so it cannot make an intermittent agent read
as continuously busy. It lives in `SceneDirector.closingBeatDuration` with the
derivation attached.

**What it measurably bought**, replaying the same 224 s capture through the same
offscreen renderer, badge-frames per class at the rig's 1 s sampling:

| class | before | after |
|---|---:|---:|
| terminal | 103 | 114 |
| plug | 100 | 102 |
| globe | 12 | 18 |
| document | 1 | 5 |
| **magnifier** | **0** | **10** |
| **checklist** | **0** | **2** |

Frames showing three or more distinct glyphs at once went from 10 to 27. The
only pixels that differ between a before and after render of the same instant
are inside the badge band: 1384 of 288 000 at t=33 s, two `magnifier` bubbles,
and not one pixel of any body.

**It adds badge changes, and only where there were none.** Over the same
capture, drawn badge changes go from 108 to 128. All twenty are pairs belonging
to the eleven calls whose open and close landed inside one 1/60 frame — the
badge was suppressed before it was ever emitted, so those calls previously
produced *zero* badge changes rather than two. (`ADR-003` §3 item 2 says the beat
"adds no badge changes; it moves one", which is true only of a call that spanned
a frame.) The flicker bound is unaffected: such a call changes the open-call set
twice, so two badge changes is inside its allowance, and the rule "a character's
badge changes no more often than its open-call set does" still holds for every
character in every fixture.

**What it does not do**, because overstating it is the failure mode here. It
takes the badge channel from *unobservable* to *observable*, not to
*glanceable* — there is no value of `D` that makes a 6 ms call catchable by a
random one-second glance without lying, and `ADR-003` §9 rejects a longer one on
exactly that ground. It touches no body, no costume, no pose and no station, so
a room where every character sits identically still has every character sitting
identically. And agents spend 84% of a session in a state the hook stream does
not describe at all; nothing here changes what the room can know.

**Body state while working is a seated pose in every case**, and *which* seated
pose is a function of the **badge class** — the one the lowest-ordinal rule above
has already computed — never of `tool_name` directly. The scene looks the state
up in `characters.poses.working` keyed by the badge's manifest key, falling
through to the table's required `default` and then to `working` itself, so the
lookup is total for any badge and for a manifest carrying no table at all.
[ADR-002 §5a and §8 item 7, implemented]

**The pose follows the body, not the badge**, and `ADR-003` is when that stopped
being a distinction without a difference. A lingering beat glyph must never
select a seated working pose: the lookup above is reached only from `working`,
the body is `idle` for every frame of a beat, so the beat cannot reach it. The
table ships empty, so nothing is visible either way today — which is exactly why
the rule is written down before somebody fills it in.

This paragraph used to read "the sitting pose, regardless of tool", and **the
property it was there to protect is unchanged: a tool name that appears tomorrow
still needs no new art.** What changed is why. It holds because both tables are
*total*, not because the answer is constant — an unrecognised tool is the
question mark, the question mark falls to the default pose, and the default pose
is art we already own. Nothing above needs editing when a new tool ships, and
nothing needs drawing.

**Every badge class still resolves to the same *pose*, and that is a fact about
the manifest rather than about the code.** `characters.poses.working` ships
empty: `04-ART-DIRECTION.md` measured the pack's only candidate for a second
seated pose at 96 differing pixels out of 288 000 for a four-agent room — the
legs, which every desk covers — so no table was written. The behaviour is decided
by the lookup, not by the sentence: fill the table in the manifest and the room
changes with no code change.

**What is no longer true is that every working character sits identically.** The
pose is the same; the *motion over it* is not. See "The ambient loop is keyed by
badge class too — M7c" below.

### The ambient loop is keyed by badge class too — M7c

The pose answers *what shape a working character is in*. It has one answer,
permanently, and the section above is why. The ambient loop answers a different
question — *how that shape moves* — and it has six, because the seated art holds
two positions and a schedule over two positions is something we can write.

Measured off the six shipped premades rather than read off a row name: of the
pack's 20 pose rows exactly two are seated, both are 3 frames per direction, and
in **every** frame of both, **frames 0 and 1 are the same position** (0–32 px
apart, an eye blink; literally identical on variant 10) while **frame 2 lifts the
whole upper body 2 px** (530–770 px of a ~950–1160 px body). So there is one
seated gesture in this pack: a two-position bob, `settled` and `raised`.

`SpriteRoomScene/AmbientMotion.swift` gives each badge class a **phrase** over
those two positions, on the manifest's own 8 fps grid and using no other rate:

| class | phrase | period | raised |
|---|---|---:|---:|
| `terminal` | `S R` | 250 ms | 50% |
| `document` | `S S S R` | 500 ms | 25% |
| `plug` | `S R R R` | 500 ms | 75% |
| `magnifier` | `S S S S S S R R` | 1000 ms | 25% |
| `globe` | `S S S S R R R R` | 1000 ms | 50% |
| `checklist` | `S S R R R R R R` | 1000 ms | 75% |
| `question_mark` | — the shipped loop, `0 1 2` | 375 ms | 33% |

Four rules, and each is one of this document's existing rules read on a new
layer rather than a new rule:

- **Keyed on the badge class, never on `tool_name`** — §5a, the same reason the
  pose is. The mapping is total, so a tool name that appears tomorrow needs no
  new art and no new phrase.
- **`question_mark` gets no phrase**, and plays the shipped loop unchanged. An
  unmapped tool — `Monitor`, permanently — moves the way a character has always
  moved. Guessing a motion for it would be the question mark's own argument
  abandoned on a larger surface than a glyph. [I1]
- **An agent holding calls of two classes plays the lowest-ordinal one** — the
  same value the badge already computed, so nothing new decides it, and because
  the selection is order-independent the gait cannot flicker as parallel calls
  interleave. [I3] The phase is not reset by the swap: every phrase is on the
  same 125 ms grid, so a class change lands on a step boundary and the body
  continues into the new schedule rather than restarting.
- **Only a body with an open call plays one.** [I2] `walk`, `deliver`, `spawn`
  and `depart` are untouched — each of them *is* a real event being told, so it
  plays as authored whatever the open-call set says. `idle` holds one frame, and
  since ADR-005 so does a **seated** body whose open-call set is empty: the
  posture says *in a turn*, the motion says *running something*, and they are
  different questions. An ADR-003 closing beat cannot reach this channel because
  the open-call set is empty for every frame of it by definition.
- **And a body at a permission gate plays none, even holding calls** — ADR-005
  §7, the third and last thing that stops the body and the only one that takes
  motion *away*. A gated `Bash` is an open call, so this channel played
  `terminal` over it — `S R`, 250 ms, the busiest row in the table above — and
  the one agent in the room that could not proceed read as the hardest-working
  one. Measured on `fixtures/concurrent-permission-gates.jsonl` at t=20 s, two
  subagents blocked since t=6.45 and t=7.92: **3 760 px changed every 125 ms
  before, 0 after** (`spriteroom --render`, 720x400, t=20.00 / 20.125 / 20.25). The badge layer never had this bug (see "attention outranks
  every tool badge", reason 2: a call parked at a gate *is not running*); this
  is that sentence applied to the body. It needs no carve-out from I2, because
  removing motion needs no licence, and no art, because a gated agent returns
  the same one-element sequence `idle` already does. The fact arrives as
  `gateChanged`; it is **not** keyed on the attention badge, which lands 6.0 s
  later and can be raised on an agent with no gate at all.

### The posture is keyed by the turn — ADR-005

The section above answers *how a working character moves*. This one answers
*where the character is*, and the two were one question until ADR-005 separated
them.

> **A character is seated from any event this app consumes for that agent until
> that agent's turn ends. It stands only when it has no turn in progress.**

`working` is the seated pose at the desk and `idle` is a **standing** pose out in
the walkway, so the choice between them asserts whether the agent is at its
workstation. Keying it on the open-call set — which is what shipped from M0 to
ADR-005 — put that assertion on the timescale of a syscall: the median tool call
in `fixtures/` is 23 ms and the median gap between two calls of one turn is
2.35 s, so a character sat down for milliseconds and stood in the walkway for
seconds, twice per call, and the room asserted that an agent got up 1.3 s after a
`Read`. Nothing said that happened. [I1]

Seated opens on `UserPromptSubmit` (main), `SubagentStart` (subagent) and any
`PreToolUse`. Seated closes on `SubagentStop` (`dormancyChanged`), `SessionEnd`,
departure and the idle sweep — and on `Stop` for the main agent, **which the
model does not emit**; see the `Stop` row above for what that costs and what
would close it. There is no timer, no hold constant and no minimum duration: the
state is an interval between two real events, the same shape dormancy already is.

What the room says afterwards:

| picture | means | channel |
|---|---|---|
| seated, **moving** | a tool call is open, of this badge class | motion |
| seated, still | in a turn; between calls, thinking | posture |
| standing, still | no turn in progress — finished, or not started | posture |
| standing + `Z` tab | turn over, subagent, still assigned | posture + badge, agreeing |
| walking | spawn, report, depart, eviction | unchanged |

Measured over all 17 fixtures, deltas batched a frame at a time as the scene
receives them: posture changes **95 → 40**, and the shortest interval between two
posture changes of one character **0.017 s → 8.196 s**. The motion budget is
untouched — a still seated character moves 0 px/s, exactly as a standing one did.

**A motion asserts exactly what the badge asserts and nothing more** — *this
agent's lowest-ordinal open call is of this class* — because it is keyed on the
same value. That the shapes are evocative (`terminal` buzzes, `magnifier` mostly
sits still) is a bonus and is not a claim: the room is not asserting that
anybody typed.

**What it cannot do, and the number is the same one ADR-003 measured.** A motion
is only as visible as the call is long, and there is no closing beat for the
body — ADR-003 §2 makes the body idle for every frame of the badge's beat and
`CLAUDE.md`'s I2 clause requires the body be truthful for every frame. Over the
M7a capture, per class, calls lasting at least one phrase bar:

| class | calls | total open s | median s | ≥250 ms |
|---|---:|---:|---:|---:|
| terminal | 18 | 102.75 | 0.054 | 3 |
| plug | 4 | 100.06 | 25.016 | 4 |
| globe | 8 | 13.19 | 1.764 | 8 |
| document | 10 | 0.75 | 0.074 | **0** |
| magnifier | 16 | 0.11 | 0.006 | **0** |
| checklist | 5 | 0.07 | 0.010 | **0** |

15 of 61 calls last long enough for the body to complete anything. So this
channel separates `terminal`, `plug` and `globe` — the classes an agent
*dwells* in — and a `Read` is as invisible in motion as it already was in
pixels. That is I2 working, not a gap in it.

### One seated pose is all the pack has, and that is now closed — M6g

The sentence above says *what* ships. This says *why nothing more can*, because
the emptiness kept being read as a backlog. It is not one. Every pose row in
Modern Interiors was cut and rendered, not read off its name, and the result is a
single measurement that decides all of them at once:

> **Of the pack's 20 pose rows, exactly two are seated, and both are the same
> sit.** A character is bottom-aligned in its 32 × 64 frame, so the last pixel
> row is the floor. `sit_a` (row 4) and `sit_b` (row 5) never reach it, in any
> frame of any direction of any cast variant — their feet are on a chair.
> **Every other row reaches it in at least one frame**, because standing is what
> those rows are.

`sit_b` was already refused on pixels; it is refused again here on meaning, and
the second reason is the stronger one because it does not depend on how much of
it a desk hides. It is a **cross-legged floor sit** — the bare `Bodies/` sheet
extends the legs forward in row 4 and folds them under in row 5 — and no event
means *sit on the ground*. A pose table that gave `terminal` the floor sit and
`magnifier` the chair sit would be asserting a difference in posture that no
payload contains, on a character who is visibly on an office chair. [I1]

The rows never previously examined all fail the same way. `pick_up` (9), `lift`
(11), `throw` (12) and `push_cart` (8) are ordinary four-direction rows whose
side blocks are near-mirrors, so any of them **can** be cut `right`/`left` only
and satisfy §7's facings clause exactly — and every one of them is a person
standing up. That is the hole
`ThemeContractTests.everyNamedPoseStateIsSeatedRatherThanMerelySideOn` closes:
side-on is necessary and it was the only thing being checked.

**`phone` is refused three times over, and the third refusal is the one that
outlives the art.** Rows 6 and 7 are the pack's phone and reading rows. Neither
is seated — every frame stands on the floor row — and neither has a side view at
all: measured against the `base` row's known directions, whose side views score
0.85–1.05 on self-mirror asymmetry and whose front and back score 0.21–0.24, all
12 frames of row 6 score 0.39–0.47 and all 12 of row 7 score 0.22–0.37. They are
front views, twelve of them, with no direction blocks. But suppose the art were
perfect. **The pose keys on the badge class, not on the tool** [ADR-002 §5a], and
`checklist` is `TodoWrite`, `Agent` *and* `SendMessage` — so a phone bought for
"messaging another agent" is a phone drawn for `TodoWrite`, which is not a call
by anybody's reading. Keying the pose on `SendMessage` alone is not available:
it is exactly the totality property §5a exists to preserve, and losing it means a
tool name that appears tomorrow needs new art. So the earlier refusal of `phone`
for `WebFetch` was right, and it was right for a reason that survives being
re-argued with a better tool.

### Nothing is held, and this is now a measurement rather than an inference

`04-ART-DIRECTION.md` retired the held-prop model on the grounds that the sprites
carry no per-frame hand anchors. That reasoning is about *placing* a prop and it
is not a claim about the download, so the download was checked.

**The generator's held layers are real and are registered frame for frame.** Not
inferred from the sheet dimensions — proved by pixels: `Book_32x32_01`'s art is
**96.1%** identical to what premade 06 already carries, and 0 of its 3936 opaque
pixels fall outside the character's silhouette on the pose it belongs to. There
is no anchor to solve. Composite the sheet and every frame lands.

**And the inventory it unlocks is empty for this room.**

| Layer | Files | Pose rows carrying art |
|---|---:|---|
| `Books/32x32` | 6 | **row 7 only** — standing, front-facing |
| `Smartphones/32x32` | 5 | **row 6 only** — standing, front-facing |
| `Accessories/32x32` | 84 in 19 families | every row, and **not one is held** — hats, glasses, beards, masks, gloves, a backpack |

**There is no held-object art for the seated pose. Zero files, zero frames.** The
two objects the generator ships exist for the two rows this section has already
refused, which is not a coincidence — they are the rows *about* holding
something.

The near miss is worth recording so nobody finds it again. `Smartphones` is a
24 × 6 sheet rather than the full 56 × 20, and read naively its content sits on
"row 4", which is the sit row; composited there it looks almost plausible. It is
off by two. The sheet is y-offset a whole two rows, and the premade's own baked
phone settles it: sheet row 4 against premade row 6 is **95.9%** identical, and
against premade row 4 it is 16.9%. Placed on the seat it would also **strobe** —
it covers 2 of the 3 frames of the seated `right` block and none of `down` — and
it would move 30.4 pixels per frame, about **122 of 288 000** for a four-agent
room, which is the same order as the 96 that was judged invisible. A book placed
the same way changes 205 px per frame and draws a slab across a side-view
character's chin, 8% of it floating clear of the body.

So the third layer stays retired, and **no manifest key is proposed for it**. A
contract for art that does not exist is speculative generality, and the condition
for writing one is easy to state: **held art keyed to the `sit` row, side-on,
with a frame for every frame of the loop.** Until a sheet like that exists, the
honest held object is no held object — which is the `question_mark` answer
applied to a layer instead of a glyph, and it is always true.

### The costume layer, which is a different layer and a different question

The paragraph above stays true and it was answering the wrong folder. `Books` and
`Smartphones` are the generator's two *held* layers, so they are the two that
inherit the `sit` row's problem. The generator also ships four layers that are
**worn** — `Outfits` (132 files), `Hairstyles` (200), `Accessories` (84),
`Eyes` (7) — every one of them at the premade sheet's exact 1792×1312 geometry.
Nobody had looked at those, because the question had always been phrased as "can
the character hold something".

The claim was checked before anything was built on it, in the terms the last one
failed on:

> **An outfit composited onto a premade's `sit` row lands on the torso, covers
> the premade's own garment, and leaves the head alone.** Over all six cast
> variants and both seated directions: outfit ink 168–412 px per frame against a
> 952–1171 px body, of which **0 px fall outside the body's silhouette** for 26
> of the 33 families and 4–16 px for the rest. There is no offset to solve — the
> sheets are the premade sheets, and `Body_32x32_01`'s bare seated frame is
> 904 px, every one of them inside premade 06's 952.

Two consequences, and the second is the honest limitation:

- **The desk hides almost none of it.** The desk is a 32 px sprite placed 28 px
  to the character's right, so it overlaps four columns of a 32 px body:
  `office`, `briefing`, `broadcast` and `stage` hide **12 px of 952**, 1%.
  `mission_control` hides 136 (14%) and `library` 396 (42%), because their
  surfaces are wider and taller. So an outfit is 244–400 visible pixels in four
  of six themes — a quarter of the character, contiguous, and the largest single
  region of it.
- **It is a value-and-hue channel, not a silhouette one.** Silhouette gain is
  0–16 px. M0's finding that this cast cannot be told apart by outline is not
  repaired by an outfit; what an outfit changes is the *value* of the torso, and
  a white coat against a dark uniform is a large value step in the biggest patch
  of the sprite. Anything that needs silhouette has to come from a hat — the
  measured winners on the seated frames are snapback **+156 px**, beanie **+132**
  and detective hat **+128** per frame, against a bare 952 — or from an outfit
  with a hood, of which the pack has one.

**What it may claim, and the two tiers that decide.** A costume can say
something: a lab coat says *this agent tests things*. Whether that is fiction
depends entirely on how the costume was reached, so the wardrobe has two tiers
and they are not the same rule.

| Tier | Key | May it assert? | Why |
|---|---|---|---|
| `characters.costumes.roles` | the **exact** `agent_type` string | **Yes** | The user named the agent `test-engineer`. Translating a name the user chose is what the nameplate already does. Nothing is inferred at any arrow. |
| `characters.costumes.assignable` | rendezvous over `agent_type` | **No** | An `agent_type` nobody anticipated is arbitrary text and licenses no claim about the work. "Different clothes" may say only *these are different agents*. |

`Costume.asserts` records which kind a costume is, and
`CostumeContractTests.noAssertingCostumeIsInThePoolTheHashDrawsFrom` is what
keeps a hard hat out of the hash's range. It is `question_mark`'s discipline
applied to a wardrobe: **the honest costume for something we do not recognise is
a costume that claims nothing.**

The selection is total and lives in `ThemeSelector.costume(agentID:agentType:in:)`:

```
costume(agent) =
    nil                            if agent_id is absent   — the main thread
    nil                            if agent_type is absent or ""
    roles[agent_type]              if the wardrobe translates that exact name
    rendezvous(agent_type, pool)   otherwise
    nil                            if the pool is empty
```

It is on the **agent** volatility band [ADR-002 §6], decided at spawn from
`agent_id` and `agent_type`, carried on `SpriteIntent.spawnCharacter`, and stored
in a `let`. There is no `setCostume` and there must not be one: a character that
changed clothes because a later `agentAppeared` carried a type we did not have
the first time would be changing *who it is* under the user's eye, which is M5's
argument for the always-on nameplate suffix applied to a second channel. (The
suffix itself no longer ships — the plate is one row — but the argument for
deciding identity once, at spawn, is what outlived it and it is what binds
here.)

**Exact match, no case folding, no trimming.** `agent_type` is the user's own
string, and this app does not invent normalisations of those — the same decision
`ThemeSelector.theme(for:stored:manifest:)` makes about `cwd`. A wardrobe that
wants `Explore` and `explore` to agree lists both.

**There is no hair layer and there must not be one.** The 200 hairstyle sheets
register exactly as well. The cast's hair is the channel M0 measured as actually
separating the six variants, and a costume that overwrote it would spend a proven
identity channel to buy an unproven one. The same caution applies to a hooded
outfit, which covers the head as a side effect: it is the strongest silhouette in
the set and the only one that costs a variant its hair.

**`characters.costumes` ships empty**, so every lookup is `nil`, no layer node is
built, and the character drawn is the one this app has always drawn. The mechanism
is inert until art exists, and `CostumeContractTests` asserts the empty state is a
legal one rather than skipping past it — the same shape as
`characters.poses.working`, and written this way *because* of it.

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

### What a subagent was dispatched to do — M7e

The same `PostToolUse` that carries the link carries a second fact about the
child, and until M7e the model decoded it and threw it away.

**The `Agent` tool's `PreToolUse` carries `tool_input.description`: a real 3–5
word summary of the job, written at dispatch.** Ten of them are in `fixtures/` —
`Touch file s1`, `Read three.txt sleep`, `Read delta/epsilon, sleep, reread
alpha`, `Touch a file via bash` — alongside `tool_input.subagent_type`. So a
character can say what it is *for* without anything being inferred: the room
would be repeating a string the payload gave it. [I1]

It reaches the child by the route the parent link already takes, because it is
the same route:

```
PreToolUse   tool_name == "Agent"  →  OpenCall(tool_use_id).dispatchedTask
PostToolUse  tool_response.agentId →  agentTasked(agent: child, task:)
```

- **The description belongs to the dispatching `tool_use_id`, not to an agent.**
  The child's `agent_id` does not exist anywhere in the payload until the
  `PostToolUse`. So the string is held against the call that carried it and
  associated at link time — the same instant, the same event, the same join key
  as `agentLinked`. [I3]
- **It is retroactive by construction**, exactly as the link is: `SubagentStart`
  fires *before* the `PostToolUse`, so a character appears and learns its task a
  moment later. `agentTasked` is therefore its own delta rather than a field on
  `agentAppeared`, and a task learned before its character exists waits in the
  same pending record the parent link waits in.
- **`agentTasked` is emitted at most once per agent** and is `nil` far more
  often than not. Three ordinary absences: the **main thread**, which has no
  dispatching `Agent` call and **must never be given a task** — its absence is
  what makes it the main thread; a subagent whose dispatch this app never saw,
  because it attached mid-session; and a `SendMessage` resume, whose
  `tool_input` carries `summary`, `content` and `recipient` and no
  `description` at all. In every one of them the rendering is to **say nothing**
  — the same fallback an unlinked subagent takes when it anchors to the main
  agent. [I1]
- **The string is carried whole.** Shortening `Move the badge beside the head`
  to `move badge` is a judgement about a plate's width, so it belongs to the
  layer that knows the width. Doing it in the model would bury the real value
  where nothing could test it.

**Reading `tool_input` is restricted to `tool_name == "Agent"`, and that is a
correctness rule before it is an optimisation.** `description` is not one tool's
field: **37 of the corpus's 45 `Bash` calls carry one**, and so does its single
`Monitor` call. On a `Bash` it describes a shell command, not an assignment, so
letting it reach a nameplate would have the room assert that somebody was sent
to do it. Only `Agent`'s `description` means *what this agent is tasked with*.

That restriction is also what keeps the decode off the hot path. **The hook POST
blocks the user's session** and `tool_input` is unbounded — a 5.5 MB `Edit`
produces a 5.7 MB POST — so this is the only branch that opens a nested
container inside it, on a tool that appears 10 times in the corpus's 83 calls.
Every other `PreToolUse` never looks at `tool_input` at all. [I5]

**It adds no open state, which is the whole of its answer to [I4].** The
description lives on the `OpenCall` — the model's only store keyed by
`tool_use_id`, and one every close path already empties: the three closes, the
deadline sweep, `SubagentStop`, `SessionEnd` and the idle sweep, all through
`WorldModel.removeCall`. A side table `tool_use_id → description` would have
been new state with its own reaping obligation, and it is exactly the shape "a
character that types forever" takes in a map. A dispatch abandoned by the reaper
therefore loses its description with its call and the child is linked with no
task, which is the fallback and not a bug. Pending links are held in
`SessionState`, so `SessionEnd` and the 30-minute sweep take them too.

**The nameplate draws it, and the nameplate is nothing else.**
`SceneDirector.taskLine(_:)` shortens the description to the plate's ten glyphs
— drop the function words, join what is left, clip mid-word, and **end in `…`
unless every word survived** — and `NameplateText.headline` is the ladder that
puts it on the band: the task if there is one, else the `agent_type`, else the
name. The task went to the band because in this corpus the type is where the
room's agents *agree* — nine of the ten dispatches are `general-purpose` — and
the task is where they differ.

> **The plate was three rows when this section was written and it is one row
> now.** The maintainer, at the running app: *"the nameplates are still wrong,
> they take up too much space, should just have the summary of what they are
> doing in one or 2 words. and that's it."* So the `agent_type` row and the
> `agent_id` discriminator row are gone, and 63 × 29 px became **63 × 11**. The
> type is still the ladder's second rung — an agent whose dispatch we never saw
> shows it — but it is drawn only when there is no task above it, and the
> discriminator is not produced at all.

The ten real descriptions render as `TOUCH FIL…` (twice), `READ ONE…`,
`READ TWO…`, `READ THRE…`, `READ FOUR…`, `TOUCH FIL…`, `READ ALPH…`,
`READ BETA…` and `READ DELT…`. Ten glyphs is two short words, so the two
`Touch file s1`/`s2` dispatches in `concurrent-permission-gates` collapse onto
one line — and with the discriminator row gone **those two characters now carry
identical plates**. That is a real loss of S4 and the price of the instruction
above; `everySimultaneousPlateCollisionInTheCorpusIsListed` enumerates every
colliding pair in `fixtures/`, and that is the only one. A wider line would not
buy it back: `TOUCH FILE S1` needs thirteen glyphs and the seat pitch cannot
afford them.

An agent with no task shows its `agent_type` on the same one row: no empty row
and no placeholder, because a slot shown empty invites the viewer to guess what
was in it. [I1] Because `agentTasked` lands after the character is seated, the
scene learns it through `SpriteIntent.setNameplate`, which redraws the plate
texture; the plate does not change shape, so the update is one line being
replaced rather than a plate growing under a character already on screen.

`ProjectRegistry` stores and replays it, because a task learned while a project
was off screen must survive the switch — the same reason it replays
`agentLinked` and `dormancyChanged`.

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

**A dormant character wears a small dark `Z` tab over an otherwise ordinary idle
character, in its own seat, under its own plate.** Nothing else about it moves —
and since the idle body holds one frame, *nothing about it moves at all*.

**The tab is not a speech bubble, and that is the whole of the decision.** It was
one until M7: the pack's blue `Z` bubble, drawn in the same anchor at the same
size as the six tool badges. At `1x` — which is every frame this app renders,
`RoomCamera.comfortablePopulation` being empty — that made *finished* and
*working* the same picture. Measured against a working badge, the `Z` bubble
occupied **84%** of the slot's pixels in a silhouette that is a strict **subset**
of every tool bubble (IoU 0.792, 100% contained), at the same value. A fresh
reading of a real frame counted six bubbles as six busy agents when all six were
`Z`, zero agents were working, and the one character with **no** badge was the
only live one: the badge was marking the dead and its absence was marking the
living.

So the slot now draws two families, and the split is what a glance reads:

- **a white speech bubble means a tool call** — open, closed inside a closing
  beat, or parked at a gate under the attention glyph. Nothing else puts one
  there;
- **a dark tab means a turn ended.** It is `SceneBitmaps.dormancyTab`: the room's
  own lettering, the `×N` chip's construction, 9x11 px against a bubble's 24x34.

The pack's `sleep` art stays declared in `badges.states.sleep` and
`TextureStore.sleepTexture()` stays with it — the fact is unchanged and the
manifest is where it is recorded — but the scene no longer draws it. The one
residue is a dormant agent raising attention, which takes the slot ahead of
dormancy and so does put a bubble over an agent with nothing running; that
precedence is argued below and is not disturbed here.

#### It keeps its seat, but not ahead of a working agent

The room has seven seats and this decision, taken alone, spent all seven of them
on agents that had finished. Seats were released on `agentDeparted` and on
nothing else, and a dormant subagent departs only at `SessionEnd` or the
30-minute idle sweep — so over one ordinary session the seven filled with
sleepers and stayed that way. A strictly serial ten-subagent run, one worker at
a time, drew the main agent and six characters **all wearing the `Z`**, the
oldest of them finished three minutes earlier, over a plate reading `+4 MORE`;
and the single agent that was actually working at that instant was inside that
`+4` and off screen. That is S5 failing at the plainest session shape there is.

Nothing above is retracted. *Stays visible* and *outranks a working agent for a
seat* are separable claims and only the second was doing damage:

- **A live agent with no seat takes one from the longest-dormant character that
  has one.** The evicted character walks out and is carried by the overflow
  count in the same frame — the room's existing sentence about an agent it
  cannot seat: *this one exists, it is counted, it is not drawn.* It has **not**
  departed: it is still in the population, still revivable in place, and still
  leaves only on the two paths that genuinely mean gone. [I1]
- **Lazily, only under pressure.** Freeing the seat on `dormancyChanged(true)`
  would empty a room the moment its last subagent stopped, leaving the main
  agent alone under `+6` and six empty desks. A quiet room keeps showing its
  sleepers, which is what this decision is for.
- **The revival path is unchanged and now also brings a character back on
  screen.** A revived agent is live, so it outranks the sleepers that took its
  place and is seated again by the same rule.
- **Still no deadline.** The dormancy clock added for this orders evictions and
  nothing else. No amount of elapsed dormancy removes a character by itself,
  which is the paragraph above held exactly.

The rule lives in `SceneDirector.settleSeats`; it is scene-side seating policy
and no part of it reaches the model.

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
