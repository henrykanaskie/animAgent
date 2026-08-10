# ADR-005 — posture carries the turn

**Status: ACCEPTED** 2026-08-09, and implemented in the same change (task #64).
The maintainer accepted §6's amendment to I2 and §5's restatement of ADR-003 §6
condition 1; both are applied in `CLAUDE.md` and `docs/ADR-003-badge-dwell.md`.
**§7 was deliberately held back from that change** — it needs a delta in
`SpriteRoomCore`, and a second module is a second concern — and was built in
task #65; see the note at the head of §7 for what shipped, what was re-measured
and the one claim it makes that turned out to need paying for.
Author: `planner`, task #63/#64. Written against Claude Code 2.1.224,
`fixtures/` as committed, and the scene as committed at HEAD.

**Three claims in this document were found wrong while implementing it, and they
are corrected in place below rather than left for the next reader to trip over.**
Two are measurements and one is a fact about the model:

- **§3's closers are not all available to the scene.** `Stop` emits **no delta**
  and neither does a second `UserPromptSubmit` — see the correction under §3 —
  so the main agent's turn end is not implementable in `SpriteRoomScene` at all.
  What shipped seats the main character at its session's first event and stands
  it up only when it leaves. Every number §3 gives for the main agent is
  therefore a number about a `turnEnded` delta that does not exist yet.
- **§1's 4 924 px is not the posture swap.** It is the whole-frame change between
  two *different instants*, and 3 128 px of it is the badge bubble coming down.
  Measured at one instant with only the rule changed, the posture swap is
  **528 px** — see the correction under §1.
- **§9 item 6's original claim that every frame renders at `1x`** was already
  corrected on disk before implementation began.

The measured result — the shortest posture dwell going from one frame to
**8.196 s**, and corpus posture changes from 95 to 40 — is in the corrections
under §3 and in `PostureTests.thePostureChannelIsOnTheTimescaleOfAGlance`.

It proposes **one change to I2's first sentence** and argues that at length in §6,
because the whole question is whether it is a change or a reading. It makes
`docs/03-EVENT-MODEL.md`, `docs/04-ART-DIRECTION.md` and `ADR-003 §6` wrong in
named places; §12 lists them.

---

## 0. The premise the whole document rests on: authoring art is not fiction

`BodyState.swift` says `read` was dropped "because Modern Interiors has no
`read a book` animation" and that filling the gap would be fiction under I1.

**The first half is true and the conclusion does not follow, and that error has
been quietly limiting this project.** I1 governs what *triggers* a visible
behaviour — every behaviour must trace to a real hook event. It says nothing
whatever about who drew the pixels. This repository already authors art in code
and has done since M5c: `scripts/generate-art.py` draws four of the seven badges,
`SceneBitmaps` draws every nameplate and the `×N` chip and `dormancyTab` pixel by
pixel, `PixelFont.standard` is authored outright, and `HeldObject.swift` draws all
six carried objects by hand from an ASCII grid — with the rule written down in its
own doc comment:

> **Authoring is precedented and is not an I1 violation.** I1 forbids the room
> asserting *data* the hooks did not give us; it says nothing about who drew the
> pixels.

So "the pack has no such animation" is a reason we **cannot reuse one**. It is not
a reason we **cannot make one**. `BodyState`'s comment conflates the two and
should be corrected in the same change (§12).

**Having established that, this ADR then recommends almost no new art**, and that
is not a retreat from the premise. It is the result of applying it: once you are
allowed to ask *what should the room draw*, rather than *what did the pack ship*,
the two highest-value moments in the room turn out to be things the room already
owns and is currently drawing **wrong**.

## 1. The defect, which is the maintainer's own report

> "i noticed the sprites also would be doing something for like 1 second then
> stopping, then resuming, then stopping etc.. can that be fixed please"

`SceneDirector.swift:261`:

    var body: BodyState { openCalls.isEmpty ? .idle : .working }

`working` is the seated pose at the desk. `idle` is a **standing** pose. So the
character stands up and sits down on every tool-call boundary. Measured over all
17 fixtures, pairing by `tool_use_id`:

| | |
|---|---:|
| seated stints long enough to render at all (≥ 1/60 s) | 33 |
| median seated stint | **0.071 s** |
| seated stints under 0.5 s | 19 of 33 |
| median gap between them | 2.35 s |

**And the posture swap is the loudest thing the body does.** Rendered at 720×400
through the shipped offscreen renderer, `single-agent-simple` at t=8.0 (seated,
`Bash` open) against t=10.0 (standing, between calls):

| transition | pixels changed on one character |
|---|---:|
| one 8 fps step of the seated ambient loop | 1 384 |
| **seated → standing** | **4 924** |

So the room's largest body event is **3.6× the loudest thing a working character
legitimately does**, it fires twice per tool call, and for the median call the
two fire 71 ms apart. Look at the two frames side by side and it is worse than the
arithmetic: in the standing frame the character has stepped out from behind its
desk and into the walkway. **The room is asserting that the agent got up and left
its workstation, 1.3 seconds after a `Read`, and will sit back down 1.4 seconds
later.** No event says that happened. That is an I1 violation on the body channel,
and it has been shipping.

> **CORRECTION (task #64, on implementing this).** *The 4 924 px number is real
> and it is not the posture swap.* It is the change between `t=8.0` and
> `t=10.0` of the same build — two different instants — so it carries three
> things at once: the badge bubble coming down, the seated loop's phase, and the
> pose. Rendering the same fixture at the same instant under the old rule and
> the new one, with nothing else different, the pose alone is **528 px** at
> `2x`; the bubble accounts for **3 128** of the 4 924 (it is what remains of
> that transition after the fix), and one step of the seated ambient loop is
> **1 384**, reproduced exactly. So the honest arithmetic is the reverse of the
> claim: **the posture swap is 0.38× an ambient step, not 3.6×.** The head is
> the largest block of a character and it does not move between the two poses,
> and the desk covers what does.
>
> **This changes the size of the defect and not its nature, and the ADR is
> accepted on the half that survives.** The standing pose is a *front-facing
> figure standing in the walkway* where the seated pose is a side view at a
> desk — legible in a 4× crop, and asserting something no event said — and it
> was being drawn for the 2.35 s median gap between two calls of one turn. The
> case for the fix is I1 and the 3 ms dwell, both untouched. The case from
> amplitude is withdrawn.

**This is I2's strobe protection failing on a channel nobody checked it on.**
`01-PRD.md` says a 3 ms call "simply never gets an ambient loop", and that is true
— of the *loop*. It is not true of the *posture*, which snaps on the same edge with
no minimum duration and 3.6× the amplitude. `AmbientMotion` closed the loop half at
M7c. The posture half was never closed.

## 2. Why no hold, no dwell and no number can fix it — proved, not asserted

The obvious fix is ADR-003's shape: hold the seated pose for `H` after the last
call closes. **There is no value of `H` that works, and this is a proof rather
than a judgement.**

Split the 40 measured idle gaps by whether a real turn-boundary event
(`Stop`, `SubagentStop`, `SessionEnd`) falls inside them:

| class | n | median | max |
|---|---:|---:|---:|
| gap **inside** a turn — the agent is thinking, and will call again | 37 | 2.02 s | **26.38 s** |
| gap **straddling** a turn boundary — the agent genuinely finished | 3 | 30.47 s | 32.71 s |

The straddling minimum is **14.99 s**. The inside maximum is **26.38 s**. The two
distributions **overlap on [14.99, 26.38]**, and both examples are in the same
fixture (`four-subagents.jsonl`, agents `ab69ae01f` and `aae859812`). So:

- any `H` > 26.38 s holds a genuinely finished agent seated for half a minute,
  which breaks S5 — the criterion the product exists for;
- any `H` < 14.99 s leaves the 26.38 s inside-turn gap stuttering;
- **and no `H` classifies both correctly, because a timer cannot separate two
  overlapping distributions.**

The manager anticipated this ("a fixed hold that is both long enough to bridge and
short enough to be honest may not exist"). It does not exist, and this is the
number that says so.

**The event separates them perfectly, by construction.** That is the whole design.

## 3. The rule

> **A character is seated from any event this app consumes for that agent until
> that agent's turn ends. It stands only when it has no turn in progress.**
>
> **Motion over the seated pose is unchanged, to the frame: a character animates
> if and only if it holds an open tool call, keyed on the badge class exactly as
> `AmbientMotion` already keys it.**

Seated is opened by: `UserPromptSubmit` (main), `SubagentStart` (subagent), or any
`PreToolUse` — an agent doing something is in a turn, and this is also the revival
path for a resumed subagent.

Seated is closed by, and only by: `Stop` (main), `SubagentStop` (subagent),
`SessionEnd`, departure, and the 30-minute idle sweep. Every one of them is an
event or a sweep the model already has, already reaps, and already emits.

> **CORRECTION (task #64, on implementing this).** *The last clause is false for
> two of the five, and one of them is `Stop`.* The scene consumes `WorldDelta`
> values, not hook events, and:
>
> - **`Stop` emits no delta at all.** `WorldModel`'s `case .stop:` disarms the
>   permission-gate mark and returns; its own comment says "it changes no visible
>   state, so `Stop` still emits nothing", and `03-EVENT-MODEL.md`'s `Stop` row
>   says "Still emits nothing". `spriteroom-replay fixtures/denial-then-work.jsonl`
>   prints twenty deltas for twenty-eight events and not one of them comes from
>   any of that capture's three `Stop`s.
> - **A second `UserPromptSubmit` emits no delta either.** The first one creates
>   the session and its main agent (`agentAppeared`); every one after that reaches
>   an agent that already exists, and `ensureAgent` emits nothing for a live
>   agent.
>
> `SubagentStop` **does** arrive, as `dormancyChanged(isDormant: true)`, and
> `SessionEnd`, the idle sweep and eviction all arrive as `agentDeparted` or as a
> rebuild. So four of the five closers are available and the fifth is the main
> agent's.
>
> **What shipped, therefore:** the main character sits down at its session's
> first event and stands up only when it leaves. That is a blind spot rather
> than a fiction — the room declines to draw a boundary it was not told about,
> which is I1's own instruction — but it means the `denial-then-work` 1 → 6 and
> `idle-notification` 0 → 2 rows of the table below, the 26 `Stop`s of §8's
> bonus, and §4's "standing, still = turn over" row for the main agent are all
> **contingent on a `turnEnded(agent:)` delta that does not exist**. Adding it is
> a `SpriteRoomCore` change of the same shape and size as §7's `gateChanged`, and
> it was held back for the same reason: a second module is a second concern.
>
> **The measured result of what did ship**, over all 17 fixtures, deltas batched
> at 1/60 as the scene actually receives them
> (`PostureTests.thePostureChannelIsOnTheTimescaleOfAGlance`, which prints the
> per-fixture table):
>
> | | before | after |
> |---|---:|---:|
> | posture changes, whole corpus | 95 | **40** |
> | shortest posture dwell | **0.017 s** (one frame) | **8.196 s** |
>
> The counts are lower than the table below on both sides because they are
> counted after frame batching rather than on the raw event stream, and because
> the main agent's boundaries are missing from the "after" column. The dwell is
> the number the maintainer's complaint was about, and it moved by a factor of
> 482.

**Nothing is invented and no number is introduced.** There is no `H`, no timer, no
minimum duration and no queue. The state is an interval between two real events,
which is the same shape `dormancyChanged` already is — and for subagents it is
*literally* that fact, so a dormant character is a standing character and the `Z`
tab now sits over a body that agrees with it instead of over one that does not.

### What it does to the picture, measured

Posture changes over the whole corpus, today against proposed:

| fixture | now | proposed |
|---|---:|---:|
| `four-subagents` | 56 | **24** |
| `three-subagents` | 24 | **14** |
| `single-agent-simple` | 6 | **2** |
| `killed-session` | 5 | **1** |
| `tool-failure` | 4 | **2** |
| `interactive-session` | 4 | **2** |
| `denial-then-work` | 1 | 6 |
| `idle-notification` | 0 | 2 |
| `permission-prompt` | 1 | 2 |
| **total** | **126** | **77** |

**Four rows go up and they are not regressions, they are the fix's other half.**
`denial-then-work` has four prompts and three `Stop`s and almost no tool calls, so
today its character stands motionless for 157 s through three complete turns of
real work. Under the rule it sits down when the user prompts and stands when the
turn ends: six posture changes carrying six real events, against one carrying
none. `idle-notification` goes 0 → 2 for the same reason — **a turn that used no
tool is currently invisible on the body**, which is the M4 defect ("an agent that
was thinking was invisible") half-fixed and never finished.

### And the dwell, which is the number that matters

The complaint is not about *how many* posture changes there are. It is about how
fast they come. Under the rule, every standing interval in the corpus —
turn-end to that agent's next consumed event, n=13:

| | |
|---|---:|
| minimum | **4.226 s** |
| median | 9.603 s |
| maximum | 67.88 s |
| under 1 s | **0** |
| under 4 s | **0** |

Against today's seated stints: minimum 0.003 s, median 0.071 s, 19 of 33 under
half a second.

**The minimum posture dwell goes from 3 ms to 4.2 seconds — three orders of
magnitude — with no hold, no constant and nothing to tune.** That is the whole
result, and the reason it comes for free is one sentence:

> **Tool calls are machine-scale events and turn boundaries are human-scale
> events. Keying the posture to the call put the loudest channel in the room on
> the timescale of a syscall. Keying it to the turn puts it on the timescale of a
> glance.**

## 4. What the room then says, and why it says more rather than less

| picture | means | channel |
|---|---|---|
| seated, **moving** | a tool call is open, of this badge class | motion — unchanged |
| seated, still | in a turn; between calls, thinking | posture |
| standing, still | turn over — waiting on the human | posture |
| standing + `Z` tab | turn over, subagent, still assigned | posture + badge, now agreeing |
| walking | spawn, report, depart, eviction | unchanged |
| bubble | tool kind, attention, or a closing beat | unchanged |

Today the top two rows are the *same picture* half the time and the third fires
for 71 ms at a stretch. Under the rule each row is a distinct, seconds-long state.

**The busy/idle signal does not move, and this is the load-bearing check.** M7c
established that motion is the only channel that survives `1x` and that an idle
body holds one frame (`AmbientMotion.idleSequence = [0]`), so an idle character
moves **0 px/s**. A seated-still character also moves 0 px/s. The proposal
therefore changes **which still frame is drawn in dead air and nothing else about
the motion budget**: `04-ART-DIRECTION.md`'s 1461 px/s ceiling, the six phrases,
the lint and every prop price are untouched, and "something in the frame is moving
means somebody is working" holds exactly as well after as before.

**What it costs, stated plainly.** A viewer who has learned that *seated* means
*executing* is misled about a still seated character. The mitigation is that
nothing else on that character asserts execution — no motion, no held object, no
bubble — and that the picture they are being asked to read instead ("at their
desk, not running anything") is the true one. §9 keeps this as the main risk.

## 5. The held object and the closing beat both get better, and one rule must change

**The held object.** `Character.heldObject` guards on `currentState == .working`.
Under the rule a seated-and-still character *is* `.working` by state name, so the
guard would put a book in the hands of an agent with no open call — which is
false. **The guard must move to the fact rather than the state name:** the hands
are full if and only if the open-call set is non-empty *and* the badge slot is
showing a tool. That is one line and it is a strengthening — it stops the hands
depending on a state whose meaning this ADR is changing.

**ADR-003's condition 1 must be restated, and this is the one place this document
weakens a ratified ADR.** ADR-003 §6 says the beat is legal *if and only if* "the
body is idle for the whole beat" and declares itself **void** — not degraded — if
an implementation holds the body in `working`. Under this rule the body during a
beat is seated and still, which is `working` by name.

The property ADR-003 was protecting is stated in its own next clause: *"so nothing
on screen claims ongoing work."* That property is **better** satisfied here, not
worse, because the ongoing-work claim has been moved wholly into the motion
channel and the motion stops at the close, to the frame — which is exactly what
ADR-003 §2 demanded and could only get by borrowing the posture channel to say it.
So the condition should be rewritten in terms of the property:

> 1. **The body asserts no ongoing work for any frame of the beat** — it holds a
>    single still frame and plays no ambient phrase — so nothing on screen claims
>    the work is continuing.

**This is a real amendment to a ratified ADR and it is the maintainer's to accept
or reject.** If it is rejected, this ADR falls with it, because there is no
version of turn-scoped posture in which a closing beat sits over a standing body.

**It also removes a contradiction the manager named.** Today the badge holds
500 ms after the close specifically so the event is seeable, while the body has
already stood up on the same frame — two channels disagreeing about the same
instant. Afterwards they agree: the badge lingers over a character that has not
moved.

## 6. I2 — this one is an amendment, and calling it a clarification would be dishonest

> **I2 — Ambient only inside an open tool call.** A character idles unless it has
> at least one open tool call. Inside one, it runs an ambient loop for as long as
> the call lasts. Never fill dead air with invented activity.

ADR-003 and ADR-004 both argued that I2 governs the **body** and that their slot
was not the body, so both were clarifications. **This ADR is in the body and
cannot make that move.** Sentence by sentence:

- *"A character idles unless it has at least one open tool call."* **Contradicted
  on the state name, honoured on the substance.** The character does not *idle* by
  `BodyState`; it holds a still seated frame. It runs no ambient loop, moves
  0 px/s, and holds nothing.
- *"Inside one, it runs an ambient loop for as long as the call lasts."*
  **Untouched, to the frame.** This is the sentence that does the work and this ADR
  does not go near it.
- *"Never fill dead air with invented activity."* **Honoured.** The dead air holds
  a still frame. A still frame is not activity, and the posture is not invented —
  it traces to `UserPromptSubmit` / `SubagentStart` / `Stop` / `SubagentStop`,
  every one a real hook event this app already consumes.

The proposed text:

> **I2 — Ambient only inside an open tool call.** A character runs an ambient
> loop if and only if it holds at least one open tool call, and runs it for as
> long as the call lasts. Never fill dead air with invented activity.
> **This governs motion. A character's *posture* — seated at its station, or
> standing — is governed separately: it traces to the turn boundaries the hook
> stream carries, it holds a single still frame in either case, and it may never
> move a pixel that an open call has not licensed [ADR-005].**

**That clause makes I2 stronger where it counts and weaker where it did not.** It
turns the first sentence from a statement about a state name into an *iff* about
motion, which is what the invariant was always defending — M7c's whole finding was
that an idle body moving 196 404 px against a working body's 181 080 was carrying
the signal backwards, and the fix was to stop the *motion*, not to choose a pose.

**The precedent this sets, named rather than left implicit.** "Posture may carry a
fact the open-call set does not" is a general licence and the next request will be
for a pose keyed to something with no event behind it. The clause is written to
make the conditions explicit: a turn boundary in the stream, a still frame, and no
pixel of motion. §8 adds the admission rule that a future body *animation* has to
clear on top of that.

## 7. The second moment: a blocked character stops moving

**BUILT** (task #65), as specified and with no rule changed. The measurements
below reproduced exactly: 3 760 px every 125 ms at t=20 with a 250 ms period,
t=20.00 and t=20.25 pixel-identical. Afterwards t=20.00, 20.125, 20.25, 25.00
and 30.00 are all pixel-identical to each other — **0 px/frame** — and the
ungated fixtures render byte-identically to before (`three-subagents` at t=10,
20, 30, 40).

What shipped, and the three places it differs from the sketch below:

- `WorldDelta.gateChanged(agent:isGated:)` exists, on `dormancyChanged`'s
  footing, replayed by `ProjectRegistry` across a project switch. `PermissionRequest`
  emits the raise; the *five* clears are a marked call closing, a marked call
  being abandoned, `Stop`, `SubagentStop`, and the `UserPromptSubmit` that
  answers the dialog.
- The scene carries it on **its own intent**, `SpriteIntent.setGated`, rather
  than on the badge selection: the gate stops the motion, and motion is neither
  the posture nor the slot. `AmbientMotion.sequence` gained the third condition
  §7 asks for and no new body state, exactly as predicted.
- **"It reaps for free" was true of the mark and not of the delta**, which is the
  one claim below that had to be paid for rather than inherited. See the
  correction under the last bullet.

Two numbers in this section were re-derived and one is different. The gate
lifetimes measured *as the shipped delta stream draws them* — raise to clear,
over all seventeen captures — are **7.8, 11.5, 31.8, 31.8, 36.7, 55.4 and
247.6 s, plus two that no event in their stream closes at all**, and there are
**nine** gates rather than eight. The conclusion is unchanged and the shape is
the same: this is a long, glanceable, frequently-wrong state.

Ranked second, and it is the answer to "whether any agent is stuck".

**Today the room asserts the opposite of the truth here.** `Character.ambientBadge`
reads `currentBadge.badge` rather than `.drawn.badge`, deliberately and with an
argument attached, so a `Bash` parked at a permission gate keeps playing the
`terminal` phrase — `S R`, 250 ms period, the busiest schedule in the table.
Measured on `fixtures/concurrent-permission-gates.jsonl` at t=20 s, two subagents
blocked on a human since t=6.45 and t=7.92: **3 760 pixels change every 125 ms,
with a 250 ms period** (t=20.00 and t=20.25 are pixel-identical). The badge layer
correctly refuses to draw `terminal` over a gated call — ADR-003 §1 says in as many
words that a gated `Bash` "is not running", so drawing `terminal` over it "asserts
work that is not happening". **The body asserts it anyway, in the one channel this
project measured as the only one that survives `1x`.**

The rule:

> **While an agent has an open permission-gate mark, its body holds the `settled`
> position and plays no phrase.**

- **It is an INTERVAL, not a point**, and a long one: measured gate lifetimes are
  **9.43, 13.52, 34.05, 36.60, 37.76 and 248.78 s**, plus two that never close in
  their stream at all. That is glanceable by any standard the project has.
- **It needs no carve-out from anything.** It removes motion; nothing needs a
  licence to move less. It is strictly more I2-compliant than what ships.
- **It needs no art.** `AmbientMotion` already returns a sequence of positions; a
  gated agent returns `[settled]`, the same one-element shape `idleSequence` has.
  Zero new pixels, zero manifest keys, zero lint exposure.
- **It reads at `1x`,** because it is the motion channel, which is the only one
  that does.
- **It composites correctly with the attention bubble** rather than duplicating
  it: the bubble says *the room needs you*, the stillness says *and this one is not
  getting anything done meanwhile*. The bubble arrives **6.0 s after** the gate
  opens (measured, four occurrences) — so for those six seconds the stillness is
  the *only* signal there is, and today there is none.
- **It reaps for free.** The mark is per-agent state inside `AgentState`, already
  cleared by `SessionEnd`, departure, the idle sweep, `Stop`, `SubagentStop` and
  any close of a marked call. [I4]

  > **CORRECTION (task #65, on implementing this).** *True of the mark, and not
  > of the delta, and the difference is the whole of what a new delta costs.*
  > Every path listed does clear the mark by construction, and
  > `PermissionGateTests.nothingIsMarkedOnceEveryFixtureHasFinished` already
  > checked it. But the scene does not hold the mark; it holds whatever the last
  > `gateChanged` told it. A clear that happens inside the model without emitting
  > one leaves a character still forever, frozen by a fact the model has already
  > dropped — I4's character that types forever with the sign flipped. So each of
  > the five gate-ending paths emits the clear explicitly, and **departure
  > deliberately does not**, because the `agentDeparted` beside it removes the
  > character the fact was about; that is the same division `dormancyChanged`
  > makes. The obligation is checked on the *stream* rather than on the model, by
  > `everyGateThatOpensIsClosedOrItsCharacterLeaves` over all seventeen captures
  > and by `noCharacterIsLeftGatedOnceTheReaperHasHadItsSay` over the four gated
  > ones after the idle sweep. Nine gates open, nine close.
  >
  > One thing found while checking it, recorded because it was not the expected
  > answer: **no capture ends a gate by departure**. `SessionEnd` and the idle
  > sweep abandon the agent's open calls first, and abandoning a *marked* call
  > disarms through the same `removeCall` every other close path uses — so the
  > clear always beats the departure to the stream. The departure ending is
  > reachable only for a gate whose marked set is empty, which is legal and which
  > no capture contains.

**The one cost, stated.** `PermissionRequest` currently emits no delta at all
(`03-EVENT-MODEL.md`, "An agent-level marker, and nothing else… Emits no delta").
This needs a `gateChanged(agent:isGated:)` delta on the same footing as
`dormancyChanged` — a `Bool`, a change never a repeat — and `ProjectRegistry` must
replay it across a project switch as it replays the other three. That is the only
model-side change in this document.

*Built as described.* The doc line quoted above is corrected in the same change,
along with the `Stop` and `SubagentStop` rows and the ambient-loop section. The
`ProjectRegistry` replay is the one with the widest window to be wrong in — two
of the nine gates outlive their streams — and it is pinned by
`aGatedCharacterIsStillGatedAfterAProjectSwitch`.

## 8. The other candidates, ranked, with the ones I think are bad ideas named

**3. The failure beat — `PostToolUseFailure`.** The scene reads `CallOutcome`
**nowhere**: `grep -rn "outcome\|AbandonReason\|reconciled" Sources/SpriteRoomScene/`
returns nothing. The model decodes the fact, puts it on the delta, and the whole
scene layer discards it. That is a genuine gap and it should be closed **eventually**.

It is ranked third and not first, against the maintainer's instinct, on two
grounds. First, the evidence base is **one event in the entire corpus** — one
`PostToolUseFailure` in 17 fixtures against 75 `PreToolUse` and 9
`PermissionRequest`. Designing a body one-shot on n=1 is the thing this project
refuses to do everywhere else. Second, and more important: **a failed tool call is
not stuck.** The agent gets the error and immediately carries on; the state has no
duration. *Stuck* is the permission gate, it lasts 9 to 249 seconds, and §7
delivers it with no art at all. The maintainer's ranking put failure and denial
together; the data separates them, and the denial half is the valuable one.

When it is done: it is a POINT, so it wants a **badge state**, not a body state —
an eighth entry under `badges.states` beside `attention` and `sleep`, authored in
`SceneBitmaps` in the `dormancyTab` construction. **That is the art-director
handoff and it is the only one in this document.** Note the trap: `dormancyTab` is
drawn by the scene, so `scripts/lint-palette.py` — which reads the *manifest* —
cannot see it, and `HeldObjectArtTests` had to measure the palette floor itself.
Any new authored glyph inherits that obligation.

**4. Pickup and put-down — the maintainer's favourite, and I recommend against
it.** Three independent refutations, any one of which is sufficient:

- **Rate.** 71% of calls (49 of 69) are shorter than 375 ms, which is the shortest
  complete gesture the room can draw on the 8 fps grid. The median call is 23 ms.
  For the majority of calls the pickup would still be playing when the put-down
  fires — **both would land inside a single 1/60 s frame** — so the design needs a
  queue. `BodyState.loopsByDefault`'s own doc comment says what the queue costs:
  the current design exists so "a 3 ms `Read` and a four-minute `Bash` both render
  with no queue and no minimum duration". A pickup gives that back.
- **Anchor.** There is **one** hand anchor — `x 14…17, y 52…55`, one constant,
  because on the seated pose the hands do not move across the three frames. There
  is no per-frame table, so a pickup cannot be a hand rising to meet an object; it
  can only be the object appearing in place with some scale or alpha ramp. That is
  a *transition*, not a pickup, and calling it one is the kind of thing `04-ART-
  DIRECTION.md` correctly refuses elsewhere as "an eyeballed offset dressed as
  data".
- **Size.** The object is 12×10 px inside a 20×16 px torso at `1x`, in the channel
  `HeldObject.swift` itself prices as "you can see they are holding *something*",
  and `AmbientMotion` prices at 0.00% silhouette difference. It is the weakest
  channel the room owns, and a beat on it is worth the least per pixel of work of
  anything considered here.

If the maintainer still wants it after that, the honest version is a **two-frame
appear on the 125 ms grid**, admitted only for calls known to outlast it — and
under §3 there is no longer a posture change to hang it on, so it would be its own
beat with its own arming rule. I would spend the effort on §7 instead.

**The admission rule I would like written down, because it is what stops this
list growing.** A body one-shot may be admitted only if **its duration is shorter
than the 99th-percentile inter-arrival time of its own trigger, per agent,
measured on `fixtures/`.** `deliver` passes: 28 `SubagentStop`s, never twice
within 4 s for one agent, 1.25 s of animation. Pickup fails by three orders of
magnitude. That is a mechanical test a future ADR can run rather than argue, and
it is the generalisation of the collision problem this document was asked to solve:
**the resolution of a one-shot colliding with the next event is not to queue it and
not to restart it — it is to not have admitted it.**

**5. Decoration, named as such so nobody mistakes it for work.** A distinct glyph
for `idle_prompt` versus `permission_prompt` (both currently draw one bubble; both
mean "this session wants you", which is what the glyph asserts, so this is a real
but small gain). A beat on `agentLinked`. A beat on `setOverflow`. A visible
`reconciled` outcome. Anything on `callAbandoned` — and that one is not merely
decoration but actively wrong: an abandon fires up to 15 minutes after the fact and
`03-EVENT-MODEL.md` already rules that it "does not display an error", for the same
reason ADR-003 refuses to arm a beat from one.

**A bonus of §3 worth naming, because it is a moment nobody asked for.** There are
**26 `Stop` events** in the corpus and today they draw **nothing at all** — the
main agent's turn ending is completely invisible, while a subagent's gets the whole
report walk. Under §3 every one of them stands a character up, for a median of
9.6 seconds. That is a real, frequent, previously-silent event acquiring a visible
beat, for free, as a side effect of the fix the maintainer asked for.

## 9. What this could get wrong

1. **Semantic drift on the biggest channel.** A user who learned "seated =
   executing" is misled by a still seated character. Mitigated only by the fact
   that nothing else on that character asserts execution, and by §4's table being
   learnable in one glance. This is the largest risk and there is no measurement in
   this document that closes it — §10 item 1 is what would.
2. **It amends a ratified ADR.** §5 rewrites ADR-003 §6 condition 1. If the
   maintainer reads that as gutting ADR-003 rather than restating it, this ADR
   should be rejected rather than amended.
3. **`Stop` is not reliably a turn end for the main thread** —
   `03-EVENT-MODEL.md` says it fires once per assistant message stream, several
   times in one user turn. The measurement says this does not bite: the shortest
   standing interval in the whole corpus is 4.23 s. But the corpus has 26 `Stop`s
   and a workload with heavy async subagent traffic could produce a short one, and
   the guard against it is §10 item 2 rather than anything in the design.
4. **Four fixtures get *more* posture changes** (§3). I argue they are the fix's
   other half; a maintainer who disagrees is disagreeing with seating a character
   that has a prompt and no tool call, which is a separable decision and could be
   dropped — at the cost of leaving M4's "an agent that was thinking was invisible"
   half-fixed.
5. **§7 needs the first new `WorldDelta` this document proposes**, and every new
   delta is a new reaping obligation. It is answered structurally — the mark lives
   inside `AgentState` — but it is the one place this change reaches into
   `SpriteRoomCore`.

   *This was the right thing to worry about and the structural answer was not
   sufficient.* See the correction in §7: the mark reaps by construction, the
   **delta stream** does not, and the five clears are emitted explicitly for that
   reason. Built and checked on the stream (task #65).
6. **The camera runs at `2x` up to three agents and `1x` from four.**
   `RoomCamera.defaultComfortablePopulation` is `[2: 3]`, so
   `scale(forPopulation:)` returns `2` for a room of one to three characters and
   drops to `minimumScale` only when a fourth arrives. An earlier draft of this
   section claimed the table shipped `[:]` and that every frame renders at `1x`;
   that was wrong, and it came from a stale doc comment in `AmbientMotion.swift`
   which has since been corrected. The correct reading is narrower but not
   weaker: a beat that only reads at `2x` is worth **nothing once the room is
   busy** — which is precisely the moment a person most needs to read it — rather
   than worth nothing outright. That is why §8 ranks the held-object beat last
   and §3 and §7 first. Both of those are posture and motion, which are the two
   channels measured to survive `1x`; costumes (0.00% silhouette), held objects
   (~90 px inside a torso) and stations (a pale slab) are the three measured not to.

## 10. What would make me confident

1. **A watched capture at `1x` by somebody who does not know the design**, asked
   only "how many of these are working, and is any of them stuck?" over
   `four-subagents`, before and after. That is the S5 measurement and nothing in
   this document substitutes for it.
2. **The shortest `Stop`-to-next-event interval over a real live session** with
   async subagents, to check risk 3 against a workload the fixtures do not contain.
3. **A live capture of a permission gate at `1x`**, watching whether a person
   reads a still character beside two moving ones as "that one is blocked".
4. **The posture-change count re-measured on the shipped renderer** rather than on
   the event stream, since a change that lands inside one frame draws nothing.
5. **`spriteroom-replay` over all 17 fixtures** with zero open calls after the
   sweep, unchanged — this document touches no close path and that must stay true.

## 11. Alternatives rejected

**Leave it alone.** The strongest rejected option in most ADRs; not here. The
maintainer has watched the shipped app and reported the defect, the posture swap
is 3.6× the loudest legitimate body event, and the standing pose asserts the agent
left its desk. This is not honesty purchased at a cost.

**Hold the seated pose for `H` after the last close.** The obvious fix. Refuted by
measurement in §2: the inside-turn and straddling gap distributions overlap on
[14.99, 26.38] s, so no threshold classifies both.

**Hold the call open in `WorldModel` for a minimum duration.** Rejected for
ADR-003 §13's reasons, unchanged: fiction in the layer whose job is to be true, it
lies to the reaper, it breaks the replay harness's no-orphaned-state property, and
it falsifies `agent is working ⟺ !openCalls.isEmpty`, which `03-EVENT-MODEL.md`
states as an equivalence.

**Make the *idle* pose a seated one and leave the rule alone** — i.e. draw
`BodyState.idle` seated. Tempting and nearly free. Rejected because it destroys the
distinction rather than fixing it: a departed-but-not-yet-departed agent, a dormant
one and a thinking one would all draw the same picture, and the `Z` tab would be the
only thing separating "finished" from "working", which is the exact inversion M7
found and fixed.

**A pickup/put-down one-shot.** §8 item 4.

**A body animation for "waiting on a human".** Rejected on the grounds
`03-EVENT-MODEL.md` already gives and this ADR does not disturb: no such animation
exists and repurposing `punch` or `phone` would be fiction. §7 gets the same fact
by *removing* motion, which needs no art and no licence.

**A second badge anchor for a failure glyph.** Rejected for the third time in this
repository, on the same ground: the manifest carries exactly one badge anchor and a
second position would be an eyeballed offset dressed as data.

## 12. Documents this makes wrong until edited

**All of these were edited in the change that accepted this ADR (task #64),
except the last, which is another agent's.**

- **`CLAUDE.md` — I2.** §6's amendment. This is an amendment, not a clarification,
  and if the maintainer disagrees with §6 that disagreement is the whole decision.
  Note that ADR-003's and ADR-004's proposed I2 clauses are *both* still unapplied
  while the repository behaves as though it carried them; this would be the third,
  and they want one edit rather than three.
- **`docs/ADR-003-badge-dwell.md` §6 condition 1 and §2** — "the body is idle for
  the whole beat" becomes "the body asserts no ongoing work for any frame of the
  beat". §5 above.
- **`docs/03-EVENT-MODEL.md`** — "The ambient loop is keyed by badge class too"
  gains the posture rule; the `Stop` row gains "stands the main character up"; the
  `PermissionRequest` row gains `gateChanged`; the closing-beat section's "the body
  goes idle at the close" is restated.

  The `PermissionRequest` half was done in task #65, with the `Stop` and
  `SubagentStop` rows, the attention-badge section, the ambient-loop section and
  the reaping section. The `Stop` row's "stands the main character up" is still
  outstanding and still waiting on `turnEnded`.
- **`docs/04-ART-DIRECTION.md`** — "Body states": `idle` is no longer what a
  character between two tool calls draws. The motion-budget section is *untouched*
  and should say so explicitly, since this change moves 0 px/s in dead air.
- **`Sources/SpriteRoomScene/BodyState.swift`** — the doc comment's claim that
  authoring a missing animation "would be fiction under I1" is wrong and §0 is the
  correction. Code rather than docs, so listed here rather than above, but it is the
  sentence that has been limiting this project and it should not survive this change.
- **`docs/01-PRD.md`** — the strobe paragraph should say the protection is on the
  motion channel and that the posture channel was unprotected until now.
- **`docs/05-MILESTONES.md`** — no milestone covers this. Owned by another agent.
