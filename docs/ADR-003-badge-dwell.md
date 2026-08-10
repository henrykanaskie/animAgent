**Status: ACCEPTED, 2026-08-09**, by the maintainer, after §12's load-bearing
unknown was measured. See §0 below — it came back at the maximum.
implementer would follow if the maintainer accepts; §14 lists the documents this
makes wrong until they are edited.

Author: `planner`, M7a. Written against Claude Code 2.1.224, `assets/manifest.json`
as generated at M6h, and the code as committed at M7a. Every number below comes
either from the M7a instrumented capture or from a constant already in the repo;
the derivations are shown rather than asserted.

It changes **no invariant**, and §7 argues that at length rather than in passing,
because the whole question is whether it does. It proposes a **clarifying clause**
to I2 that does not change I2's meaning. It changes one sentence of `01-PRD.md`'s
strobe paragraph and one paragraph of `03-EVENT-MODEL.md`'s badge section.

---

## 0. The unknown §12 named, measured

§12 says the projected gain rests on **how many closes land in an already-empty
set**, because only those produce a beat — and that if the number is small the
honest response is to accept the measurement rather than raise `D`.

Counted over the 224 s capture, by replaying every `PreToolUse` against all
three close paths and asking whether the agent's set was empty afterwards:

| class | closes | → empty | share |
|---|---:|---:|---:|
| terminal | 18 | 18 | 100% |
| magnifier | 16 | 16 | 100% |
| document | 10 | 10 | 100% |
| globe | 8 | 8 | 100% |
| checklist | 5 | 5 | 100% |
| plug | 4 | 4 | 100% |
| **total** | **61** | **61** | **100%** |

**Every close empties the set.** The beat fires on all of them, so the projected
effect is not "roughly right" — it is the ceiling. The 16 `magnifier` calls that
landed on zero frames all become beats.

It also says something the capture was not designed to show: in this session **no
agent ever held two calls at once**. That is a property of this workload — five
subagents each working sequentially — not of the product; `fixtures/parallel-tools`
holds five concurrent calls on one agent and is the case I3 exists for. So the
100% is an upper bound on a real session shaped like this one, and a session with
genuine intra-agent parallelism would see fewer beats and need none of them,
because a busy agent is already visibly busy. **That is the rule working, not a
gap in it:** the beat exists precisely for the agent whose set keeps emptying.

---

## The measurement

A 224-second session, six agents, sampled every second with ground truth beside
every frame:

| badge class | calls | total open s | median s | agent-frames on screen |
|---|---:|---:|---:|---:|
| terminal | 18 | 102.75 | 0.054 | 103 |
| plug | 4 | 100.06 | 25.016 | 100 |
| globe | 8 | 13.19 | 1.764 | 12 |
| document | 10 | 0.75 | 0.074 | 1 |
| magnifier | 16 | 0.11 | 0.006 | 0 |
| checklist | 5 | 0.07 | 0.010 | 0 |

**The first thing this proves is that the room is correct.** At a 1 s sample
interval the expected frame count for a class is its total open seconds. Predicted
against observed: 103/103, 100/100, 13/12, 1/1, 0/0, 0/0 — every row within one
frame, on six independent rows. The badge system draws exactly what it is told, the
sampler is unbiased, and there is no bug here to find. Thirty-one calls across three
badge classes produced **one frame between them** because they were open for 0.93
seconds in total.

Two more numbers from the same capture, because the rest of this document leans on
them:

- **Occupancy.** 6 agents × 224 s = 1344 agent-seconds. 216.93 s of those have a
  call open: **16.1%**. For 83.9% of its life a character in that room correctly
  had nothing to show.
- **Spacing.** 1127.07 agent-seconds with nothing open, across 61 calls, is a
  **mean gap of 18.5 s** per call. The distribution is not in the capture and §12
  asks for it.

**Re-measuring faster does not rescue this, and that is arithmetic rather than a
guess.** A 6 ms call at the room's 60 Hz render rate spans 0 or 1 frames, and one
frame is 16.7 ms of exposure. Sampled at 60 Hz the sixteen `magnifier` calls would
resolve to roughly six single-frame flashes. That is not an instrument artefact
being corrected; it is the strobe, measured. The 1 s sampler and the 60 Hz renderer
agree.

## What the badge means today, stated so it can be argued with

From `03-EVENT-MODEL.md` and `ToolBadge.swift`, the badge slot currently asserts:

> This agent holds N open tool calls, of which this glyph is the lowest-ordinal
> class.

Present tense, about a set, with a cardinality attached. Every existing rule in that
slot is built on it: the lowest-ordinal choice exists so the claim is stable while
the set changes; the `×N` annotates the set's size; attention outranks the tool
badge on the explicit grounds that a gated `Bash` **is not running**, so drawing
`terminal` over it "asserts work that is not happening".

That last one matters more than it looks. The project has already refused to leave
a tool badge up over a call that was open but not executing. This ADR proposes
leaving one up over a call that is not even open. The bar was set by us, recently,
in the same slot.

---

## 1. Dramatisation or assertion — the crux

The case to test: *a badge that lingers 400 ms after a 6 ms `Read` still says "a
`Read` happened", and that is true.* The precedent offered is the `SubagentStop`
walk, which `03-EVENT-MODEL.md` licenses in as many words: "The walk is a
*dramatisation of that fact*, which is allowed."

**They are not the same, and the difference is not the length of the depiction.**

The walk depicts a **completed event**. "This subagent reported" becomes true at an
instant and stays true forever after. The walk spends 1.25 s of `deliver` frames
plus travel on an event that occupied no time at all, and nobody reading the room
concludes the subagent spent two seconds walking, because the room's tempo is
understood as the tempo of *telling*. The proposition's truth value does not decay
while it is being told.

The badge is a **state indicator**. Its proposition is "holds an open call of class
X", which becomes false at the close. Holding the glyph past the close is not
spending time on a true thing; it is continuing to make a claim after the claim
stopped being true. The `×N` is the proof that this is the badge's real semantics
and not an over-reading: a count of *something* is drawn beside it, and a count is
only ever about now.

So on the shipped semantics, **a lingering badge is an assertion and it is false.**
The walk does not license it. If that is where the analysis stops, this ADR
recommends against and §13's first alternative is the answer.

It does not stop there, because the badge's semantics are ours and can be changed
— and there is one specific change that makes the lingering glyph true rather than
merely defensible.

### The move that makes it true

The room has two channels over one character: the **body**, which is what I2
governs, and the **badge**, which I2 never mentions. Today both are read from the
same fact — `body = openCalls.isEmpty ? .idle : .working` and the badge from the
same set — so they say the same thing twice and either one can stand for the pair.

Split them:

> **The body carries tense. The badge carries kind.**

The body goes idle at the instant the last call closes, unchanged, exactly as I2
requires. The badge slot then shows, for a short beat, *what the work that just
stopped was*. The composite on screen is a character in the `idle` loop with a
`magnifier` bubble — and that composite does not assert ongoing work. It reads as
"not working; the last thing was a read", which is what happened.

This is the same shape as two decisions already in the room and it is worth naming
both, because they are what make it precedent rather than invention:

- **The attention badge is the whole representation of waiting**, with no body
  state, precisely because the pack has no animation for it and repurposing one
  would be fiction. The badge already carries a fact the body does not.
- **The `sleep` badge sits over an idle body** and means "finished a turn". A
  viewer already sees a badge over an idle character and correctly reads it as a
  statement about that character rather than as a claim that it is working.

**So: dramatisation, conditionally, and the condition is the whole argument.** A
badge-only dwell over a body that has already gone idle is a dramatisation of a
completed event, in the walk's family. A dwell that also holds the body in
`working` is an assertion of a present tense that has ended, it is an I1 violation,
and §13 rejects it explicitly. The two are not variants of one idea; they are the
two sides of the line, and this ADR's recommendation is entirely a bet that the
line is where I have just drawn it.

**The honest weakness.** A viewer who has learned the current meaning reads the
badge and not the body, and for the length of the beat they are misled. Nothing in
the design prevents that; only the beat's shortness bounds it. §6 puts a number on
how long, and §11 keeps it as the recommendation's main risk.

---

## 2. What persists: the badge, never the body

Decided above and restated here as the rule an implementer follows.

**Persisting:** the badge glyph, alone, in the badge slot.

**Not persisting, and not negotiable:**

- **The body's motion.** The ambient loop ends with the call, to the frame. I2 is
  honoured to the letter, and §7 is therefore a clarification.

  This read *"`Presentation.body` stays `openCalls.isEmpty ? .idle : .working`"*
  until ADR-005, which is the same claim written in terms of an expression that
  no longer exists. The body state is now keyed on the turn and the *motion* is
  keyed on the open-call set — `AmbientMotion.sequence(for:state:openCalls:
  frameCount:)` returns a single held frame for an empty set — so the sentence
  that mattered is unchanged and the implementation detail under it moved.
- **The `×N`.** It annotates the open set. See §5.
- **The working pose.** `characters.poses.working` is keyed by badge class
  [ADR-002 §5a], and the open-call set is empty during the beat, so the pose
  lookup is not reached — `SceneDirector.body(for:badge:)` guards on the set
  rather than on the state name, for the reason ADR-005 §5 gives. The table ships
  empty so nothing is visible either way today, but the rule must be stated
  before it is filled: **the pose follows the work, not the badge.** A lingering
  `magnifier` must never select a seated working pose.

---

## 3. The rule: the closing beat

> **When an agent's open-call set becomes empty by a real close, the badge that was
> on screen at that instant remains for `D` and then clears. The `×N` is suppressed
> for the whole beat. Nothing else ever lingers.**

Dwell exists **only on the transition to zero**. A call that closes while its agent
still holds others gets no beat — it never needed one, because the slot is occupied
and the character is visibly working anyway. This is the entire mechanism, and its
simplicity is the argument for it:

1. **It introduces no new selection rule.** The lingering badge is literally the
   last value `BadgeSelection.select` returned for a non-empty set. Lowest-ordinal
   is untouched.
2. **It cannot flicker.** The badge sequence over a character's life is exactly
   what it is today with the final transition to `none` delayed by `D`. It adds no
   badge changes; it moves one. `ADR-002 §12` item 4's "pose changes ≤ badge
   changes" property is unaffected for the same reason.
3. **It targets the measured failure exactly.** The sixteen invisible `magnifier`
   calls are calls on an agent that had nothing else open — read, then think. That
   is the shape the beat covers.
4. **It is trivially reapable.** One optional `(badge, expiry)` per character, in
   the scene, cleared by expiry, by any call opening, by departure, and by rebuild.

### The beat begins only on a real close

`.callAbandoned` must **not** start a beat. An abandoned call is the reaper closing
our blind spot, not a completed action, and it fires up to 15 minutes after the
fact. A `magnifier` beat at t+900 saying "just did a read" about a call we lost
track of is fiction of the plainest kind [I1]. `SceneDirector.apply` currently folds
`.callClosed` and `.callAbandoned` into one case; the beat is the first thing that
needs them separated, and the comment there already says an abandoned call is our
blind spot rather than the user's failure.

Likewise no beat from `SessionEnd` (the character is leaving) or `SubagentStop`
(dormancy takes the slot; see below).

### What cancels a beat

Immediately, in all cases:

- a `.callOpened` — the normal rule resumes and the open set decides the glyph;
- `attentionChanged` raising — attention outranks it for the same three reasons it
  outranks a live tool badge, and more strongly here: it is beating a glyph about
  something that has finished;
- `dormancyChanged(true)` — the `Z` is a fact about now and the beat is not;
- departure, project switch, scene rebuild, `SessionEnd`.

The slot's precedence becomes **attention > sleep > open tool badge > closing
beat**, which is the existing order with one entry appended at the bottom. Nothing
above it moves.

---

## 4. The number

`D = 500 ms`. Not a taste; four constants already in the repo bound it, and the
binding one is the room's own animation.

**Floor A — one rendered frame.** 1/60 s = 16.7 ms. Necessary and useless alone;
this is the value at which the strobe lives.

**Floor B — the room's animation grain.** `assets/manifest.json` runs every
character state at **8 fps**: 125 ms per animation frame. A badge whose life is not
a whole number of these is shorter than the smallest unit of change the room draws.

**Floor C — the room's shortest complete gesture, and this is the binding one.**
The `working` state is **3 frames at 8 fps = 375 ms** per ambient loop; `idle` is 6
frames = 750 ms. A badge on screen for less than 375 ms is up for less time than
one complete gesture of the character wearing it. That is the honest floor: below
it, the room is drawing something briefer than anything else it draws.

**Floor D — S1, corroborating.** `01-PRD.md` S1 accepts up to 250 ms between the
hook firing and the call appearing, which is the project's own ruling that 250 ms
of *absence* passes unnoticed. A badge present for less than that is inside the
room's admitted noise floor. Weaker than C — latency tolerance is not a perception
threshold — so it is offered as corroboration, not proof.

**500 ms is the first value on B's grid above C**: four animation frames, 1⅓
working loops, twice S1's budget, thirty render frames.

**Ceiling A — spacing.** 500 ms is 2.7% of the measured 18.5 s mean gap between
calls, so it cannot make an intermittent agent read as continuously busy. The
merging failure mode — dwell longer than the gap between calls — is three orders of
magnitude away in this workload. The *short* tail of that distribution is not in the
capture; §12 item 2 asks for it, and a burst of calls 200 ms apart is genuinely
continuous work, so merging it is not a lie anyway.

**Ceiling B — the reaper.** The live sweep runs at 1 s (`LiveDriver.sweepInterval`).
`D` under a second never interacts with a deadline, an abandon, or the idle sweep.

**Ceiling C — the panel.** `revealDuration` is 0.22 s and a retracted panel renders
nothing. A beat is therefore at most `D` of stale exposure to someone who opens the
panel into one, and §11 keeps that.

**Ceiling D — truth.** "Just did a read" has to still be true. 500 ms is recent by
any reading; five seconds is arguable; thirty is a lie. This ceiling has no number
behind it and is stated as the soft one, but it is the reason the answer is not
"make it long enough to see easily".

Note the shape: **the floor comes from perception and the ceiling from truth, and
they are squeezing from opposite directions.** The band is roughly [375 ms, 2 s] and
500 ms is at its bottom on purpose — every millisecond above the floor is bought
from honesty, so the right value is the smallest one that clears it.

### What 500 ms actually buys

Predicted frames = (total open s + beats × D) / 1 s sample. Taking the upper bound
where every call closes to an empty set:

| class | today | upper bound at D = 500 ms |
|---|---:|---:|
| magnifier | 0 | 8 |
| checklist | 0 | 3 |
| document | 1 | 6 |
| globe | 12 | 17 |
| terminal | 103 | 112 |
| plug | 100 | 102 |

The three dark classes go from **1 frame of 224 to about 17**, i.e. from 0.4% of the
run to 7.6% — slightly above where `globe`, the marginal-but-observed class, already
sits. Badge occupancy across the room rises from 16.1% to at most 18.4% of
agent-time.

**These are upper bounds and I want them read as upper bounds.** Every call that
closes into a still-occupied set gets nothing, and the number of transitions to
empty is not in the capture. It is the single most load-bearing unknown in this
document and §12 item 2 is about getting it.

**It is a modest number and overstating it would be the failure mode here.** This
takes the badge channel from *unobservable* to *observable*. It does not take it to
*glanceable*, and §9 says why nothing could.

---

## 5. Overlap, the `×N`, and the flicker rule

The question posed was: does a closed-but-lingering call still count toward `×N`?

**Under the closing-beat rule the question dissolves, and that is a point in the
rule's favour rather than a dodge.** A beat exists only while the open set is empty,
so the count during a beat is zero, and `×N` is drawn only above one. The
lowest-ordinal-plus-`×N` rule is **not modified, not extended, and not read in a new
situation.** It never sees a lingering call.

Stated as the three properties that rule exists to protect, each checked:

1. **Determinism.** The badge is a pure function of the open set. It becomes a pure
   function of (open set, last-closed badge, now) — still pure, with time injected
   rather than observed, which is `WorldModel.sweep(at:)` and
   `ProjectRegistry.absorb(_:at:)`'s existing discipline and is what keeps it
   testable without waiting.
2. **No most-recent-wins.** Nothing in the beat consults recency across a set. The
   remembered glyph is the one already computed by lowest ordinal.
3. **Change count.** The number of badge changes per character is unchanged; one of
   them moves later by `D`.

**Had the rule been "every closed call lingers", all three would break**, and it is
worth recording why, because it is the obvious design and it is wrong. `Read` opens,
`Bash` opens, `Read` closes, `Bash` closes: with per-call lingering the slot would
show `terminal` while both ran and then flip to `magnifier` at the moment work
stopped, because `magnifier` is the lower ordinal — a badge change caused by nothing
happening. Give each lingering entry its own expiry and you get two flips instead of
one. That is the flicker the ordinal rule was written to prevent, reintroduced
through a side door. If the maintainer prefers per-call lingering, this is the
consequence to price in.

---

## 6. Whether it can lie, and for how long

**Name the failure mode:** an agent has finished work and is idle, and it wears a
badge implying it is still working.

**How long:** at most `D` = 500 ms, once per transition to idle, and never
cumulatively — a beat cannot be extended, only cancelled. Worst case for a user
opening the panel into a beat is the same 500 ms. There is no path by which a beat
outlives its character, survives a rebuild, or stacks.

**Why it is not an I1 violation, stated as the conditions rather than as a
conclusion.** It is not a violation *if and only if* all of these hold, and if any
one is dropped in implementation it becomes one:

1. **The body asserts no ongoing work for any frame of the beat** — it holds a
   single still frame and plays no ambient phrase — so nothing on screen claims
   the work is continuing.
2. The beat is bounded and short enough that "just now" is true.
3. The beat traces to a real event — a real close of a real call — and to no other.
   Abandons are excluded for exactly this reason (§3).
4. Nothing in the slot carries a present-tense *quantity*: the `×N` is suppressed.
5. The room is never *quieter* than the truth as a consequence: the beat only ever
   adds a glyph after work, never removes one during it.

Condition 1 is the load-bearing one. **If an implementer finds it inconvenient and
lets the body claim ongoing work for the beat, this ADR is void** — not
"degraded", void. That version is the lie in the PRD's list, and the ADR that
permits it would have to argue against I1 rather than within it.

**Condition 1 was restated by ADR-005 §5, and this is what changed and what did
not.** It used to read *"the body is idle for the whole beat"*, and it declared
this ADR void if an implementation held the body in `working`. That named a
**state** where it meant a **property**, and the property is the one written in
its own next clause: *so nothing on screen claims ongoing work*. The two came
apart when ADR-005 moved the posture off the open-call set: during a beat the
character is now seated and **still**, which is `working` by state name and
asserts strictly *less* than the standing pose it used to draw — the standing
pose said the agent had left its desk, which no event ever said. The
ongoing-work claim now lives wholly in the motion channel, and the motion stops
at the close, to the frame, which is exactly what §2 below demanded and could
only get by borrowing the posture channel to say it.

So the condition is unchanged in force and stronger in effect: it is now checked
in the frames the body plays rather than in the name of the state it is in
(`ClosingBeatTests.theBodyAssertsNoOngoingWorkForEveryFrameOfTheBeat`). A
by-product is that the badge no longer lingers over a character that stood up on
the same frame the glyph was held for — two channels that used to disagree about
one instant now agree.

**What I cannot defend.** A viewer whose learned reading of the badge is "working
now" is misled for up to 500 ms per idle transition, regardless of what the body
does. That is a real cost and the only mitigation is the number's size. I do not
claim it is zero.

---

## 7. I2 — clarification, not amendment, and the distinction is load-bearing

**This section quotes I2 as it read in 2026-08 and reasons against that text.**
ADR-005 has since amended the first sentence — it is an *iff* about motion now,
and posture is governed separately — so read what follows as the argument that
was made rather than as the current invariant. Nothing in the conclusion moves:
I2 was never about the badge slot, and it still is not.

> **I2 — Ambient only inside an open tool call.** A character idles unless it has at
> least one open tool call. Inside one, it runs an ambient loop for as long as the
> call lasts. Never fill dead air with invented activity.

Read the three sentences against the proposal:

- *"A character idles unless it has at least one open tool call."* Satisfied
  exactly. The body idles the instant the set empties.
- *"Inside one, it runs an ambient loop for as long as the call lasts."* Satisfied
  exactly. The loop ends with the call.
- *"Never fill dead air with invented activity."* The beat is not invented — it
  traces to a `PostToolUse` — and it is not activity: the character is visibly
  doing nothing.

I2 governs the **ambient loop** and the **body**. It does not mention the badge, and
the badge has already been governed separately twice: the attention badge exists
with **no body state at all**, and the `sleep` badge sits over an idle body. Neither
needed an ADR against I2, because I2 was never about the badge slot.

**So this is a clarification.** `CLAUDE.md` says an invariant may not be broken
without an ADR, and this document is the ADR that says it is not being broken — the
distinction matters because the two produce different repositories. An amendment
would weaken the sentence that keeps the strobe out of the body forever; a
clarification leaves it at full strength and writes down what it was always about.

**But the ambiguity is real and should be closed in the text, not in this file
only.** Someone will read I2 as covering the badge, correctly notice that a beat
outlives its call, and either implement fiction on the strength of this ADR or
refuse a legitimate change. §14 proposes one clause:

> **I2 — Ambient only inside an open tool call.** A character idles unless it has at
> least one open tool call. Inside one, it runs an ambient loop for as long as the
> call lasts. Never fill dead air with invented activity. **This governs the body.
> The badge slot is governed separately and may carry a fact the body does not — an
> attention or sleep state, or a bounded beat after a call closes — provided the
> body is truthful for every frame of it.**

That clause makes I2 stronger, not weaker: it names the condition under which the
badge may diverge, and the condition is that the body may not.

**`01-PRD.md`'s strobe paragraph stays true and needs one sentence added.** "A 3 ms
call simply never gets an ambient loop" remains exactly correct and remains the
rule. What changes is that the badge is now the channel that carries the short call,
so the paragraph should say the strobe protection is on the body and the badge
answers for the short call in a different way. Text in §14.

---

## 8. The implementation, specified

Small, and deliberately in one module.

1. **`SceneDirector.Presentation` gains one field**: `closingBeat: (badge:
   ToolBadge, until: Date)?`. Nothing in `SpriteRoomCore` changes. `WorldModel`,
   `Reaper`, `WorldDelta` and the replay harness are untouched, so "no orphaned
   state at the end of the run" means what it meant.
2. **`SceneDirector.apply` takes the instant**: `apply(_ deltas: [WorldDelta], at
   now: Date)`. Time injected, never observed — the `ProjectRegistry` pattern.
3. **`SceneDirector` gains `tick(at:)`**, or `apply` is called every frame with an
   empty delta array. `RoomHost.consume(_:at:)` **already runs every frame including
   frames with no deltas at all, and already takes a clock**, for the ageing logic;
   its one change is that `binding.apply` stops being guarded by `!deltas.isEmpty`.
   The precedent is four lines above the guard.
4. **Expiry is wall-clock, never accumulated frames.** A retracted panel stops
   rendering, so a frame-counting beat would freeze while hidden and be presented
   stale on reveal. Comparing against `Date` means a beat that expired while the
   panel was down is already gone when it comes up. This is the one detail that is
   cheap to get wrong and expensive to notice.
5. **`.callClosed` and `.callAbandoned` are split** in `apply`. Only the former can
   arm a beat, and only when it empties the set.
6. **`BadgeSelection` gains the beat as its lowest-precedence source**, below the
   open set, with `count: 0` so the existing `×N` suppression applies with no new
   rule. `isAttention` and `isSleeping` are unchanged and both still win.
7. **`D` is a named constant with this document's derivation in its doc comment**,
   in the shape `Reaper.permissionGateGraceInterval` already uses — the number and where
   it came from, in the file, so the next person can re-derive rather than re-taste.

Tests, in `SpriteRoomSceneTests`, all with injected time:

- A 6 ms call on an idle agent produces a badge for `D` and then none.
- The body asserts no ongoing work for every frame of the beat — it plays a
  single held frame, no posture change is emitted, and the working-pose lookup is
  not reached. (This read "the body is `.idle` for every frame"; ADR-005 §5
  restated it, and §6 condition 1 above carries the argument.)
- A call closing into a non-empty set arms no beat.
- `.callAbandoned` arms no beat, including when it empties the set.
- Badge-change count per character over `fixtures/three-subagents.jsonl` is equal to
  today's, not greater.
- A call opening mid-beat cancels it and the open set decides the glyph.
- Attention and dormancy each cancel a beat.
- A beat armed before a rebuild does not survive it.

---

## 9. What this does not fix, stated before anyone hopes otherwise

**It does not answer the maintainer's complaint.** "Every character sits identically
with the same speech bubble" is two problems. The badge half is what this document
addresses, and it addresses it by making three glyphs appear at all. The *sitting
identically* half is costume, station and pose, and this change touches none of them
by construction — the body is unchanged, that is the entire point of §2, and a room
where every character sits identically will still have every character sitting
identically afterwards.

**It does not deliver S5's untested half, and no dwell could.** To be caught by a
random one-second glance with any reliability, a 6 ms call would need a beat on the
order of seconds; sixteen such beats in a 224 s run on an agent that is genuinely
idle 84% of the time would make that agent look continuously busy. **There is no
value of `D` that makes a fast tool glanceable without lying**, and the argument is
the same squeeze as §4's: perception pushes up, truth pushes down, and for a
6 ms call the two bands do not overlap at the glance timescale. The beat serves the
person *watching* the room. For the person glancing at it, the panel is usually
retracted while these calls fire and every beat has expired before the reveal
finishes.

**It does not change what the room can know.** The deepest finding in the
measurement is not about badges: agents spend **84% of their time in a state the
hook stream does not describe**, and that state is the model choosing what to do
next. The user wants to see deliberation. There is no event for it, there will not
be one, and no amount of smearing 0.11 s of reading across the gap is that.

I raise that last point against my own recommendation deliberately. If the beat is
read as "making the room look busier", it is on the wrong side of I1 whatever the
mechanism. It is defensible only as "the badge channel is now non-empty for the
classes that fire", and that is all it should ever be claimed to do.

---

## 10. What it costs

- One optional field and one `Date` comparison per character per frame, in a scene
  that already runs a full render at 60 Hz. Nothing measurable.
- `RoomHost.consume` loses a guard, so `SceneDirector.apply` runs every frame
  instead of only on frames with deltas. It is a dictionary walk over at most the
  room's population.
- `SceneDirector` stops being a pure function of deltas and becomes a function of
  deltas and time. That is a real architectural change, `02-ARCHITECTURE.md` says
  the old thing in two places, and §14 names them rather than letting it rot.
- The ground-truth rig cannot verify a 500 ms beat at a 1 s sample interval. §12
  item 1.

## 11. What it could get wrong

1. **It satisfies the instrument and not the maintainer.** The rig's numbers go up,
   `magnifier` appears in the table, and the room still looks like six characters
   sitting still — because §9 says it will. This is the biggest risk in the
   recommendation and it is a risk of *false success*, which is worse than failure
   because it is harder to notice.
2. **The semantic drift is unmitigated.** §6's last paragraph. A user who reads the
   badge and not the body is misled for up to 500 ms.
3. **Condition 1 gets dropped in implementation.** Holding the body for the beat is
   one line, it makes the effect much more visible, and it is the lie. §6 says the
   ADR is void if it happens; that only works if somebody is looking.
4. **The empty-transition count could be small.** If most fast calls close into a
   set that is still occupied, the beat buys far less than §4's upper bound —
   possibly close to nothing. This is measurable before implementing and §12 asks
   for it first.
5. **The floor rests on the room's animation grain, not on a perception measurement
   of a 24×34 badge at `1x`.** Floors A–D are all internal constants. None of them
   is "a person could read this glyph". That is the softest joint in §4 and the only
   way to close it is to look at one.
6. **A precedent is set.** "The badge may carry a bounded fact the body does not"
   is a general licence, and the next request will be for a longer beat, or a beat
   on the body, or a beat for something with no event behind it at all. §7's clause
   is written to make the condition explicit for exactly that reason.

## 12. What would have to be true for me to be confident

In this order, and the first two are cheap and should precede any code:

1. **The rig samples at ≤ 250 ms with ground truth.** At 1 s a 500 ms beat is
   unfalsifiable — half of them are invisible to the instrument by construction.
   Either resample at 4× or report aggregate badge-seconds, which is a fair
   statistic at any interval; preferably both.
2. **The empty-transition count from the existing capture.** How many of the 61
   calls closed into a set that was already empty? That number, not 61, is what `D`
   multiplies, and it decides whether §4's table is roughly right or wildly
   optimistic. It is a re-analysis of data already on disk.
3. **The short tail of the gap distribution.** How many consecutive calls on one
   agent are less than 1 s apart? It is the merge risk stated as a number, and the
   mean of 18.5 s says nothing about it.
4. **A watched capture at `1x`.** A person who does not know the workload, looking
   at an agent whose only tools are `Read` and `Grep`, saying what it is doing.
   That is the perception measurement §11 item 5 asks for, and it is also the only
   check on whether 500 ms was enough.
5. **Badge changes per character unchanged** over `three-subagents` at real time.
   The beat must move a change, never add one.
6. **A capture of a panel reveal landing inside a beat**, to see the ≤ 500 ms stale
   exposure with a human's eyes rather than as an argument.

If (2) comes back small, the honest response is §13's first alternative rather than
a longer `D`.

---

## 13. Alternatives considered and rejected

**Leave it alone; accept that the badge shows only long tools.** The strongest
rejected option, and the one I would recommend if §2's body split cannot be
enforced or if §12 item 2 comes back small. Rejected because the current state is
not neutral: seven glyphs exist, four of them authored by hand at M5c against a
closed art budget, and three of the six tool classes are structurally
unobservable — 0 for 21 calls, 1 for 31 across all three. That is not honesty
purchased at a cost; it is a channel that was built and cannot fire. The truthful
alternative — show nothing — is already what ships and it demonstrably leaves the
badge slot empty or `terminal` for almost the whole run. **This option remains
live and the maintainer should reject this ADR into it if unconvinced by §1.**

**Linger the body as well as the badge.** Rejected, and it is the version of this
idea that must be rejected loudest because it is the one that would actually be
visible. It asserts a present tense that has ended, it is "the lie" from
`01-PRD.md`'s failure modes, it breaks I2's second sentence outright, and it would
need an ADR arguing *against* I1 rather than within it. It is also what the strobe
rule exists to prevent: sub-frame calls producing ambient animation is precisely
what a body dwell reintroduces, with a timer bolted on so it looks deliberate.

**Hold the call open in `WorldModel` for a minimum duration.** The tempting
implementation — one line in the model, everything downstream free. Rejected
hardest of all. It puts fiction in the layer whose whole job is to be true, it makes
the body work (so it is the previous alternative with extra steps), it breaks the
replay harness's "no orphaned state" property, it lies to every consumer including
the reaper, and it would make `agent is working ⟺ !openCalls.isEmpty` false — a
line `03-EVENT-MODEL.md` states as an equivalence. This is the reason the beat lives
in `SceneDirector` and not an inch lower.

**A per-agent recent-activity indicator that is not the badge.** A pip or tick near
the nameplate, firing on each close. Rejected on three counts: the manifest carries
**exactly one badge anchor**, and this project has twice refused a second position
as "an eyeballed offset dressed as data"; it needs art, and no further packs are
being bought [04-ART-DIRECTION, M5c]; and it carries strictly less — a pip says
*something happened*, the badge says *what*, and "what" is the entire complaint.
Noted as the cleanest option if the maintainer rejects §1's argument but still wants
something, because it never touches the badge's present tense.

**Show a count of completed calls rather than the last one's kind.** Rejected on
three counts, the third fatal. It answers "how much" when the question is "what". It
collides with the existing `×N` in the same slot with an incompatible meaning, and
two numbers in one anchor is worse than none. And it is a **metric** — `01-PRD.md`
lists "Metrics: token counts, cost, duration charts" as an explicit non-goal, and a
call counter is the first one through the door. The room is a status surface; a
tally of what has finished is a dashboard.

**Batch — a badge for the batch a `PostToolBatch` describes.** Rejected on
mechanism, not on principle. `PostToolBatch` is a **close** path: it arrives after
the calls in it have finished, so a batch badge could only ever go up once the work
was over, which is a longer and more retrospective version of the thing §1 is
worried about. Its span is seconds to minutes, so "recently" stops being true well
inside it. And a batch of mixed kinds still needs one glyph, which is the
lowest-ordinal rule over a much longer window — more smearing, for a claim that has
decayed further. The one thing it has going for it is that "this turn used these
tools" is unambiguously true; that is not enough to buy a badge that lights up after
the fact.

**A longer `D` — two to five seconds.** Rejected by §4's ceiling D and §9. It is the
only change that would make fast tools genuinely visible at a glance, and that is
exactly why it is the lie: an agent idle 84% of the time, firing sixteen `Read`s,
would wear a near-continuous badge. If the maintainer wants glanceability, the
honest answer is that the data does not support it, not a bigger number.

---

## 14. If accepted, these documents are wrong until edited

Out of this change's scope, listed so nothing rots. Three agents are live in the
tree; none of these is touched here.

- **`CLAUDE.md`** — **I2**, the clarifying clause in §7. This is the only invariant
  text this ADR proposes changing, and it changes what I2 *says* without changing
  what it *means*. If the maintainer disagrees that it is a clarification, that
  disagreement is the whole decision and the ADR should be rejected rather than
  amended.

  **Applied, in the shape ADR-005 left it.** The clause is in `CLAUDE.md` as a
  bullet under "This governs motion", reading *"provided the body asserts no
  ongoing work for any frame of it"* — §6 condition 1's wording rather than
  §7's earlier "provided the body is truthful for every frame". The two say the
  same thing; the later one says it in terms of the property rather than of a
  state name, which is the distinction ADR-005 §5 turned out to need.
- **`01-PRD.md`** — the strobe failure mode. "Handled by I2/I3: state has duration,
  so a 3 ms call simply never gets an ambient loop" stays, with an addition:
  *"That protection is on the **body**, and it is why the badge channel was empty
  for three of six tool classes across a measured 224 s run. `ADR-003` adds a
  bounded beat to the badge slot after a call closes; the body rule is unchanged."*
  S5's second half should also be marked as what it is — the untested half, and now
  the measured-failing half.
- **`03-EVENT-MODEL.md`** — the tool→badge section. "Multiple open calls: display
  the badge for the lowest-ordinal tool… plus a small `×N`" is unchanged and should
  gain a sentence saying the rule never sees a lingering call. The two-row table of
  badges "not in this table" gains a third row: *closing beat, raised by the close
  that empties an agent's open set, cleared by `D` elapsing or by anything that
  cancels it.* The precedence section gains the fourth rank.
- **`02-ARCHITECTURE.md`** — two places. Line 18's "`SceneDirector` translates
  deltas into sprite intents" and line 74's "maps deltas to intents" both become
  deltas *and the passage of time*, in the shape line 103 already uses for
  `ProjectRegistry` — by parameter, never by a clock it owns.
- **`04-ART-DIRECTION.md`** — only if it states that the badge is present while a
  call is open. Not verified; the implementer should grep before assuming it is
  clean.
- **`05-MILESTONES.md`** — no milestone covers this.

`ToolBadge.swift`'s `BadgeSelection` doc comments carry the badge-slot argument in
full and are the real specification of the precedence order. They are code rather
than docs, so they are not listed above, but they are wrong in the same way and
must be updated in the implementing change.
