# ADR-006 — the desk says the work

**Status: PROPOSED.** Author: `planner`, task #71. Written against Claude Code
2.1.224, `assets/manifest.json` and `fixtures/` as committed, and the code as
committed at `005cf5f`. Every number below is measured from `fixtures/`, from the
shipped art, or from a render of the shipped `SKRenderer`; the derivations are
shown rather than asserted.

It proposes **one amendment to `CLAUDE.md`'s identity model** (§6) and **no change
to any invariant** — I1, I2 and I3 are argued in §6 rather than in passing,
because the whole question is whether they are being touched.

It is **stacked on ADR-005** and degrades cleanly if ADR-005 is rejected (§5d).

---

## 0. The brief, and the one place I think it is wrong

The maintainer redefined the product mid-session:

> "I just want the sprites to have an actual representation of what they're
> doing… if the agent is coding, it should have a laptop on the desk… it feels
> like an actual workspace, not just they're sitting at a desk."

The standing brief for this ADR states the structural finding as a dilemma:

> **STATIONS** are furniture-scale and read at `1x` — but are keyed to
> `agent_type` and stored in a `let` never rewritten. **RIGHT SIZE, WRONG KEY.**
> **HELD OBJECTS** are keyed per open tool call — the correct data — but are
> 12×10 px inside a ~20×16 px torso. **RIGHT KEY, WRONG SIZE.**
> …My proposal: bind DESK FURNITURE to a WORK KIND.

The two measurements are correct and I re-derived both. **The conclusion is one
step too far, and the ADR is better for not taking it.**

Binding the *existing* station to a work kind means making
`SceneDirector.Presentation.station` mutable. That `let` is load-bearing: it is
what makes `noPropNodeIsEverRebuiltAcrossAnyFixtureReplay` true, it is ADR-002 §6
rule 2's enforcement, and it is the reason a room does not rearrange itself while
you are looking at it. The brief asks me to say what replaces the guarantee it
gave.

**Nothing has to replace it, because the station does not have to move.** A
station is three pieces — desk, chair, and one floor-standing prop to the
character's left — and the room has a **fourth place that is empty in every
theme and at every seat: the top of the desk.** That surface is 24 px above the
floor in four themes and 36 px in two, it is 32 px wide, it is unoccupied by
anything in any theme, and — §2c proves this from the cast's own pixels — an
object standing on its right-hand half **cannot cover a character's head at any
height whatsoever.**

So the proposal is:

> **Add a second furniture slot, on the desk surface, keyed to the work.
> Leave the station exactly as it is, `let` and all.**

Two slots, two keys, two tenses:

| slot | where | keyed to | tense | changes |
|---|---|---|---|---|
| **station** (desk, chair, floor prop) | seat, and one tile left | `agent_type` | *what kind of worker this is* | never, per agent |
| **desk-top object** | on the desk, right half | **work kind** (§1) | *what kind of work this has been* | at most once per 4 s (§4) |
| badge | above the head | open-call set | *what it is doing right now* | per call [ADR-003] |

The badge already answers "right now" correctly and at machine scale. The
station answers "what kind of worker" and answers it from a field that is
`general-purpose` for **8 of the 10 real dispatches in `fixtures/`**. The missing
answer is the middle one, and it is missing because nothing was keyed to it —
not because the room had no room for it.

*(A correction while I am here: `notes.md`'s M7e entry says "nine of the ten real
`Agent` dispatches are `general-purpose`". Counted from `tool_input.subagent_type`
over all 17 fixtures it is **eight** — six across `concurrent-permission-gates`,
`four-subagents` and `subagent-permission`, plus one in `three-subagents`; the
other two are `Explore`. The argument is unaffected and the number should be
right.)*

---

## 1. The vocabulary

**Four kinds and an abstention.** Closed set, no extension point, no plugin.

| kind | the room draws | the claim | evidence class |
|---|---|---|---|
| `authoring` | an open laptop on the desk | this agent has been **changing files** | `Edit`, `Write`, `NotebookEdit` |
| `research` | a stack of papers on the desk | this agent has been **looking things up** and changing nothing | `Read`, `Glob`, `Grep`, `ToolSearch`, `WebSearch`, `WebFetch` |
| `running` | a desk monitor with a lit screen | this agent has been **executing commands** | `Bash`, `BashOutput`, `KillShell` |
| `coordinating` | an upright pad or clipboard on the desk | this agent has been **dispatching and tracking work** | `TodoWrite`, `Agent`, `SendMessage` |
| *(none)* | **the bare desk, exactly as today** | nothing | everything else, and any weak signal (§3) |

### 1a. Why four, and not seven

Three independent ceilings land on the same number, which is why I trust it.

**The silhouette ceiling.** I7 says silhouette and value contrast are what read at
small sizes, not detail, and the camera drops to `1x` from four agents — which is
exactly when the room is worth reading. Four kinds is four silhouette families in
a ≤ 28 px box: a **wedge** (laptop, lid up), a **low flat slab** (paper stack), an
**upright rectangle on a stalk** (monitor), a **thin upright board** (pad). A fifth
would have to be discriminated by what is drawn *inside* one of those four
outlines, and I7 says that is the channel that does not survive.

**The evidence ceiling.** Each of the four is decided by **tool name alone**. No
kind in this table requires reading a command string, a file path, a prompt, or
any other argument. That property is what makes §3's fallback safe and §6's
constitutional ask small, and every candidate I dropped had to be dropped to keep
it.

**The maintainer's own seven collapse onto four.** Their list was: coding,
planning, verifying, research, writing, visual design, running/building. Two of
those pairs were already the same picture in their own telling — *"if it's
verifying, it should have like a computer"* and *"running/building"* are one
object — and the room should not pretend to a distinction the person asking for it
did not draw.

### 1b. What I dropped, and why — including the one they asked for by name

**`verifying`, folded into `running`.** Separating "ran the tests" from "ran a
script" requires matching the **Bash command string** — the single most sensitive
field in the payload and the one §6 refuses to read. The reward for reading it
would be a second box-with-a-screen, distinguished from the first by interior
detail, which is the channel I7 says is gone at `1x`. It fails the silhouette
ceiling and the evidence ceiling at once. `running` is true of both and
unmistakable.

**`writing` (prose, docs), folded into `authoring`.** The only separator is a file
extension — `.md` against `.swift` — and the honest depiction of both is the same
object, because both are *a person changing a file at a laptop*. A second object
would be a claim about the *content* of the file, from its name.

**`visual design` — the painter — dropped outright, and this is the one the
maintainer asked for by name.** Two independent refusals, either sufficient:

- **There is no art and none is composable.** Six body states ship — `idle`,
  `working`, `walk`, `deliver`, `spawn`, `depart` — and the manifest's own
  `unsourceable_states` already records `read` as having no animation in the pack.
  A painter is a *pose*, and the pose is the thing this art cannot be made to do
  without authoring a whole animation row.
- **The evidence is bad even if the art existed.** An agent editing `.tsx` and
  `.css` is doing `authoring`. That the authoring is *design* is a story told
  about a file extension. I1 says the room shows the fact, and the fact is that a
  file changed.

§7 states the honest substitute rather than softening this.

### 1c. The mapping is a function of something the scene already receives

`WorldDelta.callOpened(agent:call:)` carries the whole `OpenCall`, and `OpenCall`
carries `toolName`. The scene already switches on it — `ToolBadge.badge(forTool:)`
— and **that switch's six classes are already almost exactly this vocabulary:**

| `ToolBadge` | `WorkKind` |
|---|---|
| `.document` | `authoring` |
| `.magnifier` | `research` |
| `.globe` | `research` |
| `.terminal` | `running` |
| `.checklist` | `coordinating` |
| `.plug` | *abstains* |
| `.questionMark` | *abstains* |

So `WorkKind.init?(badge:)` is a **total function of a value the scene already
holds**, in exactly the shape `HeldObject.init?(badge:)` already has — including
its I1 discipline, that `questionMark` maps to nothing rather than to a guess.
`.plug` abstains for the same reason `Monitor` gets a question mark: an `mcp__*`
tool's substrate is unknown by name, and furniture is a much bigger surface on
which to be wrong than a badge.

**The observed half of this design therefore reads no new payload field at all.**
That is the most important sentence in this document and §6 is built on it.

### 1d. Two kinds the maintainer will notice are already shipping, badly

The brief's inventory found that `checklist` + held `clipboard` already fire on an
open `Agent` dispatch, so *"the main agent holds instructions while dispatching"*
already ships and nobody noticed. I verified it: `ToolBadge` maps `Agent` →
`.checklist` and `HeldObject.init?(badge:)` maps `.checklist` → `.clipboard`.

It is unnoticed for the reason ADR-005 §9 item 6 gives: the held object is ~90 px
inside a 20×16 torso and the badge is a bubble that fires for the length of one
tool call. Under this ADR the same fact — *this one is dispatching* — additionally
lands on a 24×42 object on the desk that persists for as long as it is true. That
is the whole thesis in one example: **the fact was already in the room, in the two
channels too small and too fast to carry it.**

---

## 2. Where it goes, measured

### 2a. The gap the brief named, confirmed

`content_box` measures a prop's ink footprint, not the plane you may stand
something on. For a side-view desk those are usually the same number and
**sometimes are not**: `library` binds *"wooden school desk with an open book on
the top"*, whose box top is 8 px above its slab.

### 2b. The measurement is mechanical, and I ran it

> **The desk surface is the topmost row inside the desk's `content_box` carrying
> an unbroken horizontal run of ink at least 80% of the box width.**

Run over the default desk role and all six themes:

| theme | `content_box` | slab row | **surface height above floor** | box-top height |
|---|---|---:|---:|---:|
| *(room default)* | x0 y64 32×24 | 64 | **24** | 24 |
| `briefing` | x0 y64 32×24 | 64 | **24** | 24 |
| `broadcast` | x0 y64 32×24 | 64 | **24** | 24 |
| `office` | x0 y64 32×24 | 64 | **24** | 24 |
| `stage` | x0 y64 32×24 | 64 | **24** | 24 |
| `library` | x16 y34 32×44 | **42** | **36** | 44 |
| `mission_control` | x12 y40 40×36 | 40 | **36** | 36 |

**The rule discriminates the case it exists for**: `library` answers 36, not 44 —
it finds the slab under the book — while every bare-topped desk answers its own
box top. Two distinct values across seven desks, both plausible, none eyeballed.

This belongs in `scripts/build-manifest.py` beside the code that already writes
`content_box`, as one new key per desk role (`surface_y`, or a `surface` box if
the x-range is ever needed). It is not a judgement and it is not art-direction; it
is the same measurement the generator already performs, one row higher.

### 2c. The head-clearance question is already answered, by a function that ships

`RoomScene.SeatedHead` measures, from the cast's own seated frames, how tall a
surface at a given near edge may stand before it covers a head pixel. I re-ran its
algorithm in Python over all **18** shipped seated right-facing frames (six
variants × three frames). The suffix-minimised clearance, in scene px above the
feet, by canvas column:

```
columns  0…25 : 16      columns 26…27 : 18
columns 28…29 : 26      columns 30…31 : 28      column ≥ 32 : unbounded
```

The character canvas is 32 px wide and seat-centred, so column 32 is
`nearEdgeX = +16`. Therefore:

> **An object whose near edge falls at or beyond +16 scene px from the seat centre
> is entirely outside the character's own canvas and cannot cover a head pixel at
> any height.**

And the geometry fits with room to spare. `RoomLayout.deskPosition` puts the desk
bottom-centre at `seat + 28`, so a 32 px desk occupies **+12 … +44**; the next
seat's station prop starts at **+48** [ADR-002 §7]. An object placed with its left
edge at **+16** and width **W ≤ 28** sits inside the desk's own footprint, beyond
the character's canvas, and short of the neighbour.

**That is the entire placement rule**, and it needs no new constant: *left edge at
`seat + 16`, bottom edge at `deskSurfaceY`, `W ≤ 28`, drawn one depth step in
front of the desk it stands on.*

### 2d. The art exists, and the inventory needs one correction

Rendered from `assets/processed/room/32x32/singles/` at 3× and inspected. Ink
bounding boxes:

| candidate | singles | size | slot |
|---|---|---|---|
| open laptop, lid up, ¾ | **135, 137, 138, 140** | 26×40 | `authoring` |
| laptop / small screen, front | 136, **139** | 24×32 | `authoring` |
| paper stack, small | **153** | 24×22 | `research` |
| paper stack, medium / tall | 154, 155 | 32×30, 32×42 | `research` (over budget at 32) |
| desk monitor, lit screen | **130–134** | 30×30, 32×28 | `running` |
| pad / standing book | **179** | 24×42 | `coordinating` |
| desk lamp, articulated | 141–146 | ~24×30 | unassigned; a real candidate for the theme, not for a kind |

Four kinds, four objects, all inside the ≤ 28 px width budget except the two large
paper stacks, all already in `assets/processed/`, all from the pack the app already
credits. **No pack needs buying and, if the art-director accepts these bindings,
no pixel needs authoring.**

> **Wrong about `running`, corrected during implementation rather than in this
> proposal.** This table's ink boxes were measured *by bounding box*; step 4's
> own re-check measured every single in the 130–134 band *row by row* against
> the same 28 px bound and none of the five clears it — the tightest is
> 30 px, two over. So the fourth object is not a pack single after all, and
> "no pixel needs authoring" is false of `running` specifically. §1's table and
> the two paragraphs above keep the record straight: `laptop`, `papers` and
> `pad` are declared, unbound, exactly as proposed; `running`'s desk-top role
> is **authored** — `Sources/SpriteRoomScene/DeskMonitorArt.swift`, in the
> shape `HeldObjectArt` already established and licensed (that file's own doc
> comment and ADR-005 §0) — rather than bound to 130–134, and it carries no
> `assets/manifest.json` entry, because there is no source PNG for one to name.
> `docs/04-ART-DIRECTION.md`'s "Prop roles" section has the full account and
> the palette/silhouette numbers; `DeskMonitorArtTests` is where they are
> checked, since `scripts/lint-palette.py` reads the manifest and cannot see an
> object the manifest does not name.

**One correction to the brief's inventory, offered because it changes a build
estimate.** "Workbench singles 85–101 exist but are unidentified" — I rendered all
seventeen. **None of them is a workbench.** 85 is a low bench; 86–96 are flat floor
rugs and mats; 97 is a small framed picture; 98, 99 and 100 are the three plants
the manifest already binds to `main`, `plant` and `n01`; 101 is a rucksack. There
is no work surface in that band and nothing there needs identifying for this
feature. **The desk-scale object band is 120–179**, and the table above is what it
holds.

---

## 3. The fallback rule, as arithmetic

> **Wrong is worse than generic.** A laptop on the desk of an agent that is not
> changing files is the room lying, which is what I1 exists to prevent. The bare
> desk is always available and is always true.

Each agent carries a **tally**, `[WorkKind: Int]`, scoped to one turn (§4a).

1. **The opening claim.** When a turn opens, if the agent has a dispatch task
   (`AgentSnapshot.task`, which already ships), it is classified by a closed
   keyword lexicon into at most one kind, and that kind is seeded with
   **exactly one vote**. The lexicon is total and **abstains on ambiguity**: a
   description matching keywords of two kinds contributes nothing, as does one
   matching none.

   *Why one vote and not more.* The description is **inference about intent
   written before the agent acted**. One real observed tool call is worth exactly
   as much, so it gets exactly as much. This is what makes the maintainer's
   honest case work: an agent **told to plan** that is in fact editing files needs
   **two** edits to tie its own brief and **three** to beat it, which happens
   inside the first second of real work.

2. **The observations.** Every `PreToolUse` adds one vote to
   `WorkKind.init?(badge:)`. Unmapped and `mcp__*` tools add nothing — abstention,
   never a guess. [I1]

3. **The candidate** is the kind with the most votes. Ties are broken **in favour
   of the incumbent**; with no incumbent a tie yields no candidate. No recency, no
   ordering dependence, no most-recent-wins — the three properties ADR-003 §5
   protects, kept for the same reasons.

4. **The gate. This is the numeric definition of "weak".**

   > A candidate is adopted only if
   > **`votes[top] ≥ 3`** **and** **`votes[top] ≥ 2 × votes[runner-up]`**.
   > Otherwise the desk is bare.

   - **`≥ 3`** because the opening claim is worth 1 and a single stray call is
     worth 1. Three means *either* the brief agreed with two real calls *or*
     three real calls agreed with each other. **No single event, and no pair of
     events, can furnish a desk.**
   - **`≥ 2×`** because a 2:1 majority is the smallest ratio a tie-plus-one cannot
     reach. An agent that read three files and edited three files clears neither
     kind and gets the bare desk — **which is the true picture: it is doing
     several things, and the room has one object to say so with.**

### 3a. What the two numbers buy, measured over the whole corpus

Replayed over all 17 fixtures, counting every time the drawn object would change:

| rule | station-object changes, 17 fixtures |
|---|---:|
| argmax, no gate, no dwell floor | **32** |
| **+ the margin gate (`≥ 3`, `≥ 2×`)** | **5** |
| **+ the 4 s dwell floor (§4)** | **5** |

**27 agents appear across the corpus. Five ever earn an object; twenty-two keep
the bare desk.** The gate refuses 84% of the corpus, and the five it admits are:

```
four-subagents    MAIN → coordinating     ab7894b769… → running
three-subagents   MAIN → coordinating     a894ded5b0… → research
parallel-tools    MAIN → running
```

Both `MAIN → coordinating` results are the maintainer's own example — *"if it's
the main task and giving instructions"* — arrived at from `Agent` and `SendMessage`
calls with no new data and no lexicon involved at all.

**The dwell floor buys nothing on this corpus (5 → 5), and I want that read as
honest rather than as reassuring.** It is a guard against a workload the fixtures
do not contain, not a fix for one they do. §9 item 2 is the measurement that would
price it.

### 3b. The evidence base for the observed half is thin, and the brief did not say so

Full `PreToolUse` census over all 17 fixtures:

| tool | calls |
|---|---:|
| `Bash` | 37 |
| `Read` | 19 |
| `Agent` | 10 |
| `ToolSearch` | 6 |
| `SendMessage` | 2 |
| `Monitor` | 1 |

**Zero `Edit`. Zero `Write`. Zero `Grep`. Zero `Glob`. Zero `WebSearch`/`WebFetch`.**
Every file path in the corpus — twelve of them — is a `.txt` or `.sh` under one
scratch directory. The captures were built at M0 to exercise ingest, and they
exercise `sleep`, `touch` and `read a text file`.

So: **`authoring` — the kind the maintainer asked for first, the laptop — cannot
fire once anywhere in the committed corpus, and no threshold in this document has
been tuned against a session that writes code.** That is the largest weakness here,
it is not fixable by argument, and it is why §8's build order opens with a capture
rather than with a feature.

---

## 4. Stability — why this is an ADR

A desk that rearranges itself mid-turn is the flicker I3 exists to prevent and
would be worse than a static wrong desk. Three mechanisms hold it still, and each
is measured rather than chosen.

### 4a. The tally is scoped to a turn

Opened by `UserPromptSubmit` (main) / `SubagentStart` (subagent) / any
`PreToolUse`; cleared by `Stop` / `SubagentStop` / `SessionEnd` / departure / the
idle sweep. **These are ADR-005's turn boundaries exactly** — not a second answer
to a question that has one.

The scoping matters because votes only accumulate. An unscoped tally makes a
long-lived agent *more* rigid the longer it runs: `research` at 40 votes would need
80 `authoring` votes to be corrected, so an agent that read for five minutes and
then coded for twenty would keep a paper stack. Per-turn, the desk reflects **this**
turn's work, and a turn is exactly the unit of "what I asked it to do".

### 4b. The drawn object is *re-derived* at a turn boundary, never *cleared*

When a turn ends the tally resets and **the object stays on the desk.** It is
replaced only when the next turn's tally clears the gate with a *different* kind.

This is the tense argument and it is the reason this channel is the right one:

> **The badge is present tense — "a call of this class is open" — and it goes out
> when the call closes. The station is dispositional — "this is the desk this
> agent works at" — and it is as true between turns as during one.**

Clearing on `Stop` would rearrange the furniture every time an agent finished
something, which is a furniture change carrying no news. ADR-005 measured the
standing intervals those events open: median 9.6 s, minimum 4.2 s. The room would
spend all of them redecorating.

### 4c. The dwell floor: `S = 4 s`

> **A character's desk-top object may be set from nothing to a kind the moment the
> gate is first met. Once set, it may change only at an instant at least `S` after
> it was last set.**

The asymmetry is deliberate: appearing is the room *learning* something and costs
nothing to watch; changing is the room *correcting itself* and is the loud event.

**`S = 4 s`, and it is not a new number.** ADR-005 measured every standing interval
in the corpus and found the minimum at **4.226 s**, with none under 4 s at all —
the room's demonstrated human-scale floor. `S` is the largest whole second not
exceeding it. Nothing on a character may then change faster than the slowest
channel already changes, and the number was taken rather than tasted, in the shape
ADR-004 §4 took `LiveDriver.sweepInterval` and the 8 fps grid.

**Why a number is needed at all, when §3's gate already supplies hysteresis.**
Because tool calls are machine-scale. ADR-005's headline finding — median call
0.023 s, 71% under 375 ms — means an entire vote sequence can land inside a
quarter of a second: two `Read`s adopt `research` at t = 0.05 s and six `Edit`s
flip it to `authoring` at t = 0.2 s. The gate bounds *how many* changes; only a
clock bounds *how fast*. This is ADR-005's sentence applied to a different
channel: **the counts are honest and the clock is what keeps them glanceable.**

**And this is not the fiction ADR-004 §2 rejects.** There, the objection was to a
signal whose *content* came from `Date()`. Here the content is the tally and the
clock only *delays* a change that real events have already earned. Delaying a true
change is not asserting a false one; ADR-003 §8 item 4 already establishes
wall-clock expiry inside `SceneDirector`, with time injected as a parameter and
never observed, and this uses that same seam.

### 4d. What replaces the `let`'s guarantee — nothing, because the `let` stays

`Presentation.station` remains `let`. `RoomScene.stationFurniture` is untouched.
`noPropNodeIsEverRebuiltAcrossAnyFixtureReplay` and ADR-002 §6 rules 1–4 all hold
unchanged, because **not one of the three pieces they govern is what moves.**

The new slot's guarantee is its own and it is a number: **5 changes over 17
fixtures against 32 for the naive rule**, with a hard floor of one change per 4 s
per character. If ADR-005 lands, the two mutable things on a character — posture
and desk object — are then bounded by the *same* 4-second floor, derived from the
same measurement.

---

## 5. Where it lives, and what it costs

### 5a. In `SceneDirector`, and not an inch lower

**A work kind is an inference. `WorldModel`'s job is to be true.**

That is ADR-003 §13's argument applied to a new value, and it is the same reason
ADR-004 §5 keeps `Liveness` out of the model. Putting a classifier in
`SpriteRoomCore/Model/` would put a guess in the layer the reaper and the replay
harness trust, and would make the fixture-replay "no orphaned state" property mean
less than it means today.

So: **no new `WorldDelta` case, no change to `WorldModel`, no change to `Reaper`,
and no change to the ingest hot path.** [I5]

`SceneDirector.Presentation` gains a tally, a drawn kind and a `lastSetAt`, in the
shape it already carries `closingBeat: (badge, until)`. The tally is per-agent
state inside the presentation, so it is reaped by every path that already removes
a presentation — departure, `SessionEnd`, project switch, scene rebuild. It adds
no open state and no new reaping obligation. [I4]

### 5b. The one new intent

A new case, "SpriteIntent.setDeskObject(agent:kind:)", emitted only when the
drawn kind actually changes — the discipline `setNameplate` already follows.
(Quoted rather than backticked: `DocumentedSymbolTests` reads a backticked
identifier as a claim that the symbol exists, and this one is proposed. It takes
backticks in the change that writes it.) `RoomScene`
gains one node per seated character, parented like the station's own furniture and
hidden rather than destroyed, so ADR-002 §6 rule 1 is honoured by construction.

### 5c. `--render` draws it, and `scripts/lint-palette.py` will notice

Unlike ADR-004's lamp, this **is** a thing in the room and it **is** about an
agent, so it draws in fixture replay like any other furniture. That means the
palette lint's scene-versus-composition diff will see it, and any binding chosen
in §8 step 3 must clear I7's room ceiling — these are pack singles already
processed by `scripts/process-assets.py`, so they should, but "should" is why the
lint exists.

### 5d. If ADR-005 is rejected

The subagent turn boundaries this needs already exist as deltas
(`agentAppeared(.spawning)`, `dormancyChanged`, `reportDelivered`). **The main
agent's do not**: there is no delta for `Stop` or `UserPromptSubmit` today, which
is ADR-005 §8's "26 `Stop` events draw nothing at all".

Without ADR-005, the honest degradation is: **subagents get per-turn tallies; the
main agent gets one tally for its whole life.** That costs less than it sounds,
because the main agent's kind is stable in practice — it dispatches, tracks and
messages — and both `MAIN` results in §3a are `coordinating`. This ADR does not
require ADR-005; it is simply better with it, and it needs no turn delta of its
own either way.

---

## 6. The constitutional line

`CLAUDE.md`'s identity model says:

> Do not invent an identity scheme on top of these. Do not hash the transcript
> path. If attribution is ambiguous, the character does not appear.

And `ThemeSelector`'s doc comment states the principle that paragraph has been
read as: `theme(cwd)` *"does not say what the project is about, and nothing here
may ever be taught to."*

### 6a. The amendment is smaller than the brief expected, and that is the finding

The maintainer's authorisation was broad:

> "I think it needs to be able to see a little bit into what the request and
> prompt is, and I think that is okay. I am okay with that."

**This design does not need most of it, and declines what it does not need.**

- The **observed** signal reads `toolName` off `OpenCall` — which the scene already
  receives and already keys the badge from. **No new field.**
- The **inferred** signal reads `tool_input.description` on an `Agent` dispatch and
  on no other tool — which `WorldModel` already decodes, already carries as
  `AgentSnapshot.task`, and which `SceneDirector.taskLine(_:)` **already draws on
  the nameplate**, shortened, at M7e. **No new field.**

So the app already reads dispatch task text and already draws it. The genuinely
new act is **classifying** that string rather than only echoing it — and
classifying is strictly less exposing than echoing, because its output is one of
five closed values instead of ten glyphs of the user's own words.

**The brief expected me to ask for file paths, and I am not asking.** Paths were
wanted to separate frontend work from other work — but `visual design` is the kind
§1b drops, and code-versus-prose is the distinction §1b folds. With those two gone
there is nothing left for a path to decide. **The one field most likely to leak
something a user cares about is the one this design has no use for.**

### 6b. The text I propose

Added to `CLAUDE.md`'s **Identity model** section, after the existing four bullets:

> **Beyond identity: what an agent is doing.** The four fields above answer *which
> character this is*. Two further payload fields answer *what kind of work it has
> been doing*, and only these two are admitted for that purpose:
>
> - **`tool_name`** on `PreToolUse` — already the badge's key.
> - **`tool_input.description`**, on an `Agent` dispatch and on no other tool —
>   already the nameplate's text.
>
> The room may **classify** these two into a closed, total vocabulary whose
> unmatched case is *say nothing*. It may **echo** them only where a shipped
> feature already does. **No other field of `tool_input` is read for display** —
> not `prompt`, not `command`, not `file_path`, not `content`, not `query`, not
> `pattern`.
>
> Text from a payload is never written to disk, never sent anywhere, and never
> drawn except as an existing feature already draws it. A derived work kind
> chooses one furniture slot and nothing else: it may not choose a variant, a
> costume, a seat, an accent hue, a nameplate or a theme. If the classification is
> ambiguous, the room shows the plain desk — the same answer the identity model
> already gives when attribution is ambiguous.

### 6c. What the app must never do with this text, stated as checkable rules

1. **Never drawn verbatim**, except the nameplate's already-ratified shortened
   `description` [M7e]. The work kind's own output is one of five enum values.
   *Checkable:* no code path passes a payload string to `PixelFont` except
   `SceneDirector.taskLine(_:)` and the nameplate's `agent_type`.
2. **Never written to disk.** The shipped app persists exactly two things:
   `ThemeStore` (`cwd` → theme id) and the hooks block in `~/.claude/settings.json`.
   Neither may gain a field for this. *Checkable:* a test that `ThemeStore`'s
   encoded form contains no task text.
3. **Never sent anywhere.** The app has one socket, inbound, on loopback. No
   network egress may be added for this, ever.
4. **Never used for identity or for the theme.** `theme(for:)`, `station(...)`,
   `costume(...)` and the variant assignment keep their present inputs. *Checkable:*
   their signatures do not gain a `WorkKind`.
5. **The lexicon is closed, total, and abstains.** No regex over free text beyond a
   fixed keyword list; two matching kinds means no kind. *Checkable:* a test that
   every description in `fixtures/` classifies to a kind or to `nil`, and that the
   ambiguous ones give `nil`.
6. **The classifier never sees more than the field.** `tool_input.description` is
   read only on `tool_name == "Agent"`, which is already the model's rule and
   already the reason `aHugeToolInputIsNeverWalked` passes in 4.9 ms on a 5.5 MB
   payload. [I5]

### 6d. The privacy cost this ADR actually creates is in the *capture*, not the app

§8 step 0 asks for a capture of a real working session, because §3b shows the
committed corpus cannot tune this. **A real capture writes the maintainer's real
prompts, real commands and real file paths verbatim into `fixtures/`, which is
tracked in git.** That is a much larger disclosure than anything the runtime does,
it is created by this ADR's evidence requirement, and it should be named rather
than discovered later.

The mitigation is procedural, not technical: capture into an untracked directory,
commit **numbers** rather than payloads, and if a fixture must be committed, commit
a synthesised one built to the same shape. Nothing in this ADR requires a real
session to be checked in.

### 6e. The invariants, one by one

- **I1 — No fiction.** Every vote traces to a `PreToolUse` this app consumed; the
  opening claim traces to a string the payload carried. The gate exists so that a
  weak signal draws *nothing*, which is I1's own instruction for the case where
  truthful representation is not available. **Honoured.**
- **I2 — Ambient only inside an open tool call.** **Untouched, and this needs no
  carve-out.** I2 governs motion on a character. A desk-top object is furniture: it
  has no body state, no pose, no ambient loop, and it moves 0 px/s in every frame
  of its life. Stations have been per-agent since ADR-002 and needed no clause for
  the same reason. **This ADR proposes no change to I2 and no third carve-out from
  it** — a point worth making explicitly, since ADR-003's and ADR-004's proposed
  clauses are both still unapplied and ADR-005 proposes a fourth.
- **I3 — State keyed by `tool_use_id`.** The tally is a **counter over closes and
  opens**, not a current-tool-per-agent. It is fed by `callOpened` and is
  indifferent to how many calls are open at once, which is exactly what I3 asks
  for. **Honoured, and note that this is why the tally counts opens rather than
  reading "the current tool".**
- **I6 — Integer scales.** Unaffected; the object is drawn at 1:1 scene pixels like
  every other prop.
- **I7 — Palette separation.** §5c. The bindings are pack singles already run
  through the import processing, and the lint checks them.
- **I8 — No focus.** Unaffected. No interaction is proposed.

---

## 7. What this art cannot do, stated plainly

The maintainer asked for four pictures. **Two of them cannot be delivered and I am
not going to dress up a substitute as the thing.**

**1. "If you're saying this subagent should be designing the UI, it should be kind
of like a painter." — Not deliverable.** There is no painter pose in any of the
three packs, none is composable from the six shipped body states, and a pose is
what the request is. The `apron` costume ships and is already bound to
`art-director` and `designer` via `characters.costumes.roles` — but M7c measured a
costume at **0.00% silhouette difference**, so at `1x` an aproned character and a
plain one are the same picture. **The honest substitute is: a design agent gets a
laptop, like every other agent that changes files, and the room does not claim to
know that the file was a stylesheet.** A held palette *is* drawable at
`HeldObject`'s price — but ADR-005 §8 item 4 prices that channel at 12×10 px inside
a 20×16 torso and ranks it last of everything considered, and I agree with that
ranking.

**2. "…or to be talking to the subagent." — Not deliverable.** No addressing
gesture exists: no character in this art can turn to face another. The one
inter-character choreography the room has is the `SubagentStop` report walk, and
it is licensed by that event alone. **The honest substitute already ships and is
being improved rather than invented:** the dispatching agent gets `coordinating` —
a pad on its desk — for as long as it has been dispatching, on top of the
`checklist` badge and held `clipboard` that already fire during the dispatch call
itself (§1d).

**3. "If the agent is coding, it should have a laptop on the desk." —
Deliverable**, §2, and it is the cheapest of the four.

**4. "If I'm asking it to plan something, it should be holding a clipboard and
writing on a clipboard." — Half deliverable.** The clipboard is deliverable, on the
desk (single 179, or the held clipboard that already ships). ***Writing* on it is
not**: that is a pose, and `working` is the only seated animation in the art.

---

## 8. Build order — cheapest first, each step independently shippable

**Step 0 — capture a real working session. Not shippable; blocks steps 3–5.**
Owner: `test-engineer`. No art. §3b is the argument: the committed corpus contains
zero `Edit`, zero `Write` and zero `Grep`, so `authoring` — the kind the maintainer
asked for first — cannot fire once anywhere in it, and none of §3's thresholds has
been tested against a session that writes code. **Capture into an untracked
directory and commit numbers, not payloads** (§6d). Steps 1 and 2 do not wait on
this.

**Step 1 — the desk-surface anchor. Cheapest of all, and it draws nothing.**
Owners: `art-director` (sanity-check the seven measured values), then
`scene-engineer` (`RoomLayout.deskSurfacePosition(seat:surfaceHeightAboveFloor:)`
— backticked now that this step has shipped it; the depth rule stays out of
this step, since there is nothing yet to depth-sort against the desk it stands
on, and is deferred to the step that draws an object here).
One generator rule (§2b), one manifest key per desk role, one placement function.
Ships as a pure measurement with **no visible change**, and it is verifiable on its
own: a test asserting the anchor lands on the slab for all six themes, `library`
answering 36 rather than 44. Independently useful — anything the room ever puts on
a desk needs it.

**Step 2 — the work-kind model, with no art.** Owner: `scene-engineer`. `WorkKind`,
`WorkKind.init?(badge:)`, the lexicon, the tally, the gate, the dwell floor, and a
line in `spriteroom-replay` printing each agent's adopted kind. **Draws nothing**
and touches no invariant. Ships behind the replay harness, where it can be
regression-tested against §3a's table: 5 adoptions, 0 later changes, 22 of 27
agents on the bare desk. No `SpriteRoomCore` change at all (§5a).

**Step 3 — the first object: `authoring`, the laptop.** Owner: `art-director` picks
between 26×40 (135/137/138/140) and 24×32 (136/139) and binds it; `scene-engineer`
draws it at the step-1 anchor. **This is the maintainer's headline request and it
is one manifest binding plus one node.** Needs step 0 to be meaningful — otherwise
it ships a picture nothing in the corpus can produce.

**Step 4 — `research`, `running`, `coordinating`.** Owner: `art-director` for three
more bindings (153; 130–134; 179), `scene-engineer` for nothing new. Independently
shippable one at a time and in any order; each one that lands makes one more kind
visible and each one that does not leaves a bare desk, which is already the
fallback.

> **`running` did not bind to 130–134 — §2d's correction above.** It is authored
> (`DeskMonitorArt`) rather than bound, so its step is one file of art plus its
> own tests instead of one manifest entry, and it does not touch
> `assets/manifest.json` at all. The other two bindings in this step (153, 179)
> are unaffected and still just a manifest entry each.

**Step 5 — re-measure.** Owner: `test-engineer`. Re-run §3a's table over the step-0
capture, and answer §9 items 1 and 2. If the gate turns out to refuse almost
everything on real work, **the honest response is §10's first alternative, not a
lower threshold.**

Everything before step 3 needs no art-director involvement at all. Steps 3 and 4
need bindings and an I7 check, and no authored pixels.

---

## 9. What would make me confident

1. **A real coding session captured and replayed** (step 0), with the per-agent
   adopted kind printed beside a human's own description of what each agent was
   doing. That is the accuracy measurement and nothing in this document
   substitutes for it. **§3b is why this is item 1 and not item 4.**
2. **The change count and the bare-desk rate on that capture.** If `authoring`
   fires for 5% of agents, the gate is too tight and the feature is decoration; if
   the object changes more than once a minute per character, `S` is too small.
   Both are read off the same replay.
3. **A watched capture at `1x` with four or more agents**, by somebody who does not
   know the design, asked only "what is each of these doing?". The camera renders
   `1x` from four agents and that is when the room matters; a 24×32 object that
   only reads at `2x` is worth nothing then. The shipped station props are the
   existing evidence that furniture *does* read at `1x` — in
   `four-subagents-mission_control-720x400-t020.00.png`, five agents at `1x`, the
   twin-monitor stands are the most legible per-agent difference in the frame —
   but a desk-top object is smaller than a floor stand and inherits nothing.
4. **The `library` anchor looked at by eye.** It is the *one* desk whose surface
   is not its box top: its art has a book drawn on it, so the box top is 44 and
   the surface is 36, and the rule has to return the desk rather than the book.

   **This item originally named `mission_control` alongside it and that was
   wrong.** Implementing step 1 measured all seven: `mission_control`'s surface
   *is* its box top, because its bare equipment table's own top row already
   clears the 80% run threshold. Both are still 36 px and both are still drawn
   behind the body, which is what made them look like one case — they are two,
   and only one of them exercises the rule.
5. **A session where the description and the tools disagree**, deliberately
   constructed: dispatch an agent to "plan the refactor" and have it edit six
   files. The desk must end on `authoring`. This is the maintainer's own honest
   case and it should be a fixture.
6. **`spriteroom-replay --all` unchanged** — 17 fixtures, zero orphaned state. This
   document touches no close path and that must stay true.

---

## 10. Alternatives rejected

**Leave it alone.** The strongest rejected option in most ADRs; not here. The
maintainer has watched the shipped app and said what it is missing, and the
missing thing is real: **8 of 10 dispatches in the corpus are `general-purpose`, so
the one furniture channel the room has is spent on a field with almost no
information in it.** That is not honesty purchased at a cost.

**Rekey the existing station to the work kind — the brief's own proposal.**
Rejected in favour of §0's second slot. It makes `Presentation.station` mutable,
which destroys ADR-002 §6 rule 2 and `noPropNodeIsEverRebuiltAcrossAnyFixtureReplay`;
it deletes `agent_type` from the room, which is the fact the station currently
carries and the *only* place `agent_type` appears besides the nameplate's second
row; and it buys nothing the empty desk surface does not already offer for free.
**If the maintainer prefers the rekey, note that it is strictly more expensive and
strictly less truthful, and that the two facts then compete for one slot.**

**Put the work kind on the held object.** Rejected on ADR-005 §8 item 4's
measurement, unchanged: 12×10 px inside a 20×16 torso, 0.00% silhouette difference,
the weakest channel the room owns — and it is already keyed per open call, so it
already says something *truer and more current* than a work kind would. Overwriting
it would be a downgrade.

**Put the work kind on the badge.** Rejected. The badge's proposition is present
tense with a cardinality attached [ADR-003 §1], and a work kind is dispositional. A
dispositional claim in a present-tense slot is the exact error ADR-003 spent a
document refusing.

**Key the work kind to the current tool call rather than to a tally.** Rejected by
ADR-005's headline measurement: median call **0.023 s**, 71% under 375 ms. A
furniture-scale object keyed to a call would appear and vanish inside a single
rendered frame, which is the strobe with a bigger sprite. **This is the argument
the brief said transfers directly, and it does.**

**Read file paths and add a `frontend` / `design` kind.** Rejected on two grounds
and the first is sufficient: **there is no art for it** (§1b, §7). The second is
that it is the only part of the design that would need the payload field most
likely to embarrass someone, for a claim about intent that a file extension does
not support.

**Read the `Bash` command string to separate `verifying` from `running`.**
Rejected: §1b's silhouette ceiling and §6's field list. Two boxes with screens is
not a distinction at `1x`.

**A longer, richer vocabulary — eight or ten kinds.** Rejected on the maintainer's
own instruction: *"abstract, not necessarily super niche"*. Small and unmistakable
beats complete and mushy, and §1a gives three independent ceilings that all land
at four.

**A lower gate — adopt on the first matching call.** Rejected: it is 32 changes
against 5 over the corpus (§3a), it lets one stray `Read` furnish a desk, and it
puts the room's largest per-agent object on the timescale of a syscall.

**Put the tally in `WorldModel`.** The tempting implementation — everything
downstream gets it for free. Rejected hardest, for ADR-003 §13's reasons applied to
a new value: it puts an **inference** in the layer whose whole job is to be true,
where the reaper and the replay harness trust it. §5a.

---

## 11. Documents this makes wrong until edited

Out of scope for this change; listed so nothing rots.

- **`CLAUDE.md` — the Identity model.** §6b's addition. This is the only
  constitutional text this ADR proposes changing, and it is an **amendment**, not a
  clarification: the section as written admits four fields and this admits two more
  for a different purpose. If the maintainer disagrees that the two are admissible,
  that disagreement is the whole decision and the ADR should be rejected rather
  than trimmed. **I2 is untouched** (§6e) and this ADR adds no carve-out to it.
- **`docs/03-EVENT-MODEL.md`** — the tool→badge section gains a sentence saying the
  same six classes now also feed a work kind, and a note that `tool_input.description`
  is read for classification as well as for the nameplate.
- **`docs/04-ART-DIRECTION.md`** — "Nothing is on the desk" wherever it says so; the
  desk-surface anchor and the ≤ 28 px width budget; the four bindings; and the
  standing statement that stations are chosen once, which stays true and now needs
  the second slot named beside it.
- **`docs/02-ARCHITECTURE.md`** — `SceneDirector` gains a second time-dependent
  value beside the closing beat. Line 18 and line 74 were already due an edit from
  ADR-003 §14; this does not add a new one, it adds a second reason for the same one.
- **`assets/manifest.json` and `scripts/build-manifest.py`** — the new desk-surface
  key. Owned by the art-director; not touched here.
- **`docs/05-MILESTONES.md`** — no milestone covers this.
- **`docs/ADR-002-themed-rooms.md` §4/§7** — the station's geometry paragraph
  describes three pieces. It becomes four, and §7's "at most one floor-standing
  prop beside the seat" needs the desk-top slot named so the next reader does not
  conclude the surface is reserved.

Nothing in `Sources/` or `Tests/` was touched by this change. Two other agents are
live in those trees.
