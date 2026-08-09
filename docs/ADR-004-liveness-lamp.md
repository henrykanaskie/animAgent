# ADR-004 — the pilot lamp

**Status: IMPLEMENTED at M7d, and §3's clause is the maintainer's to accept or
reject.** The code ships; the sentence proposed for `CLAUDE.md`'s I2 does not,
because an agent does not get to amend the constitution on its own say-so. If
the maintainer disagrees that §3 is a *clarification* of I2 rather than a change
to it, that disagreement is the whole decision and the lamp should come out —
`SceneBinding.showLiveness` is the only wire and removing it removes the feature.

Author: `implementer`, M7d. Written against Claude Code 2.1.224 and the code as
committed at `b3a492b`. Every number is either measured in this change or is a
constant already in the repo, and the derivations are shown.

---

## 0. The defect

M7c stopped the idle body animating, so that movement in the room means an open
tool call and nothing else. That was right, and the measurement behind it is not
in dispute: an idle character had been moving **196,404 px** over eight frames
against a working character's **181,080** — the motion channel was carrying the
busy/idle signal *backwards*.

The cost was recorded deliberately rather than bodged around:

> **A room where nobody is working is now a room where nothing moves at all.**

That is the truth about such a room. It is also, at a glance, exactly what a
room draws when the listener has died, when the session ended, when the hooks
were never installed, or when the panel has stopped updating. The user cannot
tell *my agents are idle* from *this app is broken*, and looking harder at the
characters cannot help, because the characters are correct.

The product's one sentence is "you glance at the notch and know what your agents
are doing". A surface that cannot distinguish "nothing to report" from "not
reporting" fails that sentence in the most expensive way available: quietly.

## 1. The rule

> **The panel draws one 9 px indicator, pinned to the bottom-left of the frame,
> whose ink is present if and only if a request POSTed to this app's own hook
> port completed within the last two seconds. It contracts for 125 ms on each
> such completion. It says nothing else, about anything.**

Three pictures, differing by **extent** and drawn in the nameplate's two
colours:

| phase | ink core | says |
|---|---|---|
| `lit` | 5×5 | a round trip completed within `hold` |
| `wink` | 3×3 | …and within 125 ms — this is the pulse |
| `dark` | none | none did; the listener is not answering |

`hold` = 2.0 s, `wink` = 0.125 s, and the beat is attempted every 1.0 s.

## 2. Why it is not fiction — the crux

**A blinking light on a timer would be fiction, and it is the obvious
implementation.** It would keep blinking with the listener dead, the queue
wedged and the hooks uninstalled: a visible behaviour tracing to nothing, which
is I1, and "filling dead air with invented activity", which is I2's own phrase
for it. Any design in which the indicator's motion comes from `Date()` is that
design, however it is dressed.

So the signal is **earned**. `Liveness.beats` moves for exactly one reason:
`ListenerHeartbeat` opened a loopback connection to the port the listener
actually bound, POSTed to `/_liveness`, and read back `HTTP/1.1 202`. Kill the
listener and every subsequent round trip fails, `beats` stops, and the lamp is
dark within `hold`.

**The negative is a test, not an argument.**
`LivenessTests.theHeartbeatStopsWhenTheListenerStops` binds a listener, waits for
beats, stops the listener, and asserts that `beats` and `lastBeatAt` do not move
across twenty further intervals — while `lastFailureAt` *does*, which is the
difference between "stopped counting" and "stopped looking".
`LivenessLampTests.timeAloneCanOnlyEverDarkenIt` walks 1000 instants and asserts
no phase ever re-lights on the clock alone.

**Why a self-POST rather than reading `NWListener`'s state.** Cheaper, and
weaker. A listener can report `.ready` while its accept path is wedged, while
the process is out of descriptors, or while the loopback route has been taken
out from under it. The question the user needs answered is not "does an object
say it is ready" but *if Claude Code posted a hook right now, would it land* —
and the only honest way to answer that is to post one. The probe is deliberately
built on a raw socket rather than on `Network.framework`, which is what
`HookListener` uses: a probe that shares its transport with the thing it probes
can be brought down by the same fault and still report success from a cached
state.

**What it does *not* claim.** Not that the hooks are installed, not that Claude
Code is running, not that the user's sessions point at this port, not that the
app is "healthy". A lit lamp means the listener answers. That is a smaller claim
than anyone would like and it is the only one the evidence supports. [I1]

## 3. I2 — the carve-out, stated as explicitly as ADR-003 stated its own

> **I2 — Ambient only inside an open tool call.** A character idles unless it has
> at least one open tool call. Inside one, it runs an ambient loop for as long as
> the call lasts. Never fill dead air with invented activity.

ADR-003 §7 had to answer the same shape of question about the badge slot, and
the answer it gave is the model for this one: I2 governs a **character**, the
badge is not a character, and the badge had already been governed separately
twice before anybody noticed the ambiguity. It then insisted — correctly — that
the ambiguity be closed *in the text*, and proposed a clause.

This lamp needs the same treatment one layer further out, because it is not even
in the room:

> **I2 — Ambient only inside an open tool call.** […] Never fill dead air with
> invented activity. **This governs a character. The panel may additionally show
> one indicator that is about the app itself — not seated, not named, not at a
> station, drawn in the room's lettering rather than in the cast's art —
> provided every frame of it traces to a fact about this process that was
> measured rather than assumed, and provided it says nothing about any agent.**

**That clause makes I2 stronger, not weaker**, in the way ADR-003's did: it names
the exact conditions under which anything may move outside a tool call, and the
conditions are severe. Each is checked, and each is checkable:

1. **Not a character.** A 9 px square of chrome pinned to the frame, in the
   nameplate's plate and ink, in a corner no seat, station, aisle or delivery row
   reaches. It has no body state, no pose, no nameplate, no badge anchor and no
   costume, and it is not in `RoomScene`'s node graph for the room — it hangs off
   the camera.
2. **Traces to a measured fact.** `Liveness` and nothing else, and `Liveness`
   moves only on a completed round trip. `LivenessLamp.phase` is pure with time
   as a parameter, the discipline `WorldModel.sweep(at:)` and
   `SceneDirector.apply(_:at:)` already keep.
3. **Says nothing about any agent.** It does not change with population, with
   open calls, or with which project is on screen. A room with six working agents
   and a room with none draw an identical lamp. **This is the load-bearing one**,
   and it is what stops the lamp becoming a second, quieter activity channel
   competing with the cast — which would reopen the exact defect M7c closed.

**If condition 3 is ever dropped — if somebody makes the lamp beat on real hook
traffic as well, so that it flickers faster when the room is busy — this ADR is
void**, not degraded. That version is a second motion channel keyed to activity,
in the corner of the eye, next to a cast whose motion is the signal the product
exists to deliver; and it is one line to write.

**The precedent this sets, named rather than left implicit.** "The panel may
carry a bounded fact the room does not" is a general licence, and the next
request will be for a second indicator, or a bigger one, or one with no measured
fact behind it. The clause above is written to make the conditions explicit for
exactly that reason. There is **one** such indicator and there is no slot for a
second — the same answer this project has twice given about a second badge
anchor.

## 4. The numbers

**`interval` = 1.0 s.** Taken from `LiveDriver.sweepInterval`, which is already
the rate at which this app decides it is time to look at the world, rather than
chosen. A second cadence at some other rate would be a second answer to a
question that has one.

**`wink` = 0.125 s.** One animation frame on the manifest's own 8 fps grid,
which is ADR-003 §4's Floor B taken rather than re-tasted. A change shorter than
one animation frame is briefer than anything else this room draws.

**`hold` = 2.0 s = two intervals.** One interval would make a single dropped beat
— a scheduler hiccup, a machine coming back from sleep — draw a dead listener,
which is a false alarm on the one indicator whose whole value is that it does not
cry wolf. Two tolerates exactly one miss and no more. The asymmetry is ADR-003's
polarity argument read here: `lit` is the positive assertion, so a *late*
darkening is the fiction and an early one is only a miss, and two intervals is
the smallest value that survives a hiccup.

**The wink contracts rather than extinguishes, and that is the whole reason there
are three pictures instead of two.** If the pulse were an off-frame, "no ink"
would mean *either* the pulse *or* a dead listener, and a glance landing inside
a 125 ms wink would read as "broken" — the exact confusion this feature exists to
remove, moved from the room into the indicator. With a contraction the rule is
total:

> Any ink inside the lamp means a request landed within the last `hold`. No ink
> means none did.

**Extent, not value.** That is the dormancy tab's finding re-used rather than
re-derived: extent is what *there is something there* is read from at a glance;
value is what it is read from once you have already looked. A lamp that pulsed by
changing brightness would ask a viewer to resolve two greys in a 9 px square on a
720×400 panel, which nothing in this project has shown a person can do at `1x`.

**Motion: 32 px/s, placed, for the whole room, at any population.** 16 changed
pixels per transition, two transitions per beat, one beat a second.
`04-ART-DIRECTION.md`'s 1461 px/s prop ceiling is **not** inherited: it rests on
"an idling character is the quietest thing the cast can legitimately be", an
idling character now moves 0, and that document marks the ceiling REVISIT WITH
DATA. The ceiling that governs here is a **working** character — `magnifier`'s
1000 ms ambient bar, on the order of 1300 px/s — because the only thing the lamp
must never do is mask the busy/idle distinction. 32 is 2.5% of 1300, and because
it is the *same* 32 whether the room is empty or full, it is a constant added to
both sides of that comparison and cannot change its sign. **Nothing about the
accepted prop set is repriced.**

## 5. Where it lives, and why not lower

- **`SpriteRoomCore/Ingest/Liveness.swift`** — `Liveness`, a value; and
  `ListenerHeartbeat`, which produces it. Core, beside the listener it probes,
  because it is ingest and because it must be testable without a screen. It
  imports `Darwin` and `Foundation`; the import-boundary test is unaffected.
- **`HookListener`** recognises the probe on the request target and returns
  before the decoder. **This is the only change to the hot path** and it is one
  token comparison on a string the parser had already built. [I5]
- **`SpriteRoomScene/LivenessLamp.swift`** — the pictures, the phase function and
  the node. It attaches to the scene's camera, so it does not touch `RoomScene`
  and cannot be reached by a `SpriteIntent`. That is deliberate on both counts:
  the lamp is not a consequence of a delta and must not be able to become one.
- **`SceneBinding.showLiveness(_:at:)`** — the one wire, called from
  `RoomHost.consume` every frame including frames with no deltas, because the
  wink ends by the clock passing an instant and an idle app is exactly the case
  where no delta will ever arrive to end it.

**`WorldModel` knows nothing about any of this**, for ADR-003's reason applied to
a different layer: the model's job is to be true about the *session*, the lamp is
about the *process*, and putting the second in the first would lie to the reaper
and break the replay harness's no-orphaned-state property.

## 6. `--render` draws no lamp, and that is I1 rather than an optimisation

A fixture replay has no bound port. Nothing is receiving. A lamp in that picture
could only be reporting on a listener that does not exist, so `SceneBinding`
builds one only when it is handed a non-`nil` `Liveness` — which the offscreen
renderer never does. When you cannot represent something truthfully, show
nothing.

The distinction this preserves is worth naming: **no lamp** means *this run has
nothing to answer for*; a **dark** lamp means *we asked and nothing answered*.
They are different statements and they draw differently.

It also keeps `scripts/lint-palette.py`'s scene comparison honest. That harness
diffs its own composition against `spriteroom --render` pixel for pixel with an
empty known-defect register, so a lamp drawn in a listener-less render would fail
the I7 gate — correctly, because it would be a pixel the room could not account
for. All six themes still agree with the scene at zero differing pixels.

## 7. The evidence

`spriteroom --liveness-demo DIR --for 6` binds a *real* ephemeral listener (port
0, never the user's 8787), starts the *real* heartbeat, and renders the real
`RoomScene` through the real `SKRenderer` on wall time, one frame every 125 ms.
Halfway through it calls `stopListenerOnly()` — the listener dies, the heartbeat
keeps beating against a port nothing is on, and the lamp goes dark on its own.
The harness never touches the heartbeat, the `Liveness` or the lamp. That is the
difference between demonstrating a signal and demonstrating a variable.

Measured, on the empty room — the exact picture that could not be told from a
crash:

| t (s) | lamp | beats | |
|---:|---|---:|---|
| 0.00 | dark | 0 | nothing proved yet |
| 0.13–1.01 | lit | 1 | first round trip landed |
| 1.13 | **wink** | 2 | the pulse |
| 1.26–2.01 | lit | 2 | |
| 2.13 | **wink** | 3 | |
| 2.25–3.00 | lit | 3 | |
| **3.00** | | | **listener stopped** |
| 3.13–4.01 | lit | 3 | inside `hold`; one miss is tolerated |
| 4.13–5.88 | **dark** | 3 | and it stays dark |

Pixel differences between those frames, measured on the 720×400 renders:
lit↔wink **16 px**, lit↔dark **25 px**, all of them inside `x∈[6,10] y∈[389,393]`
— the lamp's own 9×9 box in the bottom-left corner, and not one pixel anywhere
else in the frame.

## 8. What it cannot do

**It cannot detect a frozen renderer in a single frame.** If the panel stops
drawing, the last frame stays on screen, lamp and all, and a still picture of a
lit lamp is what a healthy idle room looks like at that instant. The wink closes
this over *time* rather than at an instant: a live app contracts the core twice a
second, so one second of watching separates a live panel from a frozen one. No
version of this could do better, because a frozen panel by definition shows a
frame that was true when it was drawn.

**A single frame can be ambiguous in the other direction only if the reader
ignores extent.** There is no phase in which a live app draws an empty lamp, so
the 12.5% duty-cycle problem that an on/off blink would have had does not exist.
That is the whole reason the wink is a contraction.

**It is chrome, and the room is a window into a room.** A pinned indicator is a
small break in that fiction, taken knowingly: the alternative — a fixture in the
room, a wall lamp, a clock — would have to come from the manifest, would be
theme-dependent, and would be a *thing in the room* asserting a fact about the
process, which is a worse category error than an obvious piece of chrome.

**The bottom-left corner is not guaranteed empty.** A report from the outermost
left seat can put a nameplate under the lamp for the length of a walk, and the
lamp draws over it, costing a few pixels of a plate that is still legible. A
corner the room cannot reach does not exist at `1x`, where the frame is cropped
to the content on every axis.

## 9. Alternatives rejected

**Leave it alone.** The strongest rejected option and the one to fall back to if
§3 is refused. Rejected because the current state is not neutral: the room is
*silent in the same way whether it is working correctly or not at all*, and the
one sentence this product is judged on is about answering a glance.

**A timer-driven pulse.** The obvious implementation, and the fiction. §2.

**Read `NWListener.state` and draw a static "connected" mark.** Honest, cheap,
and motionless — so it cannot distinguish a live panel from a frozen one, and it
is a weaker fact than a completed round trip. §2.

**Beat the lamp on real hook traffic instead of, or as well as, the probe.**
Tempting, because it needs no extra traffic at all. Rejected twice over: an idle
room produces no hook traffic, which is precisely the case this exists for, so it
does not work; and a lamp whose rate tracks activity is a second motion channel
competing with the cast, which is §3 condition 3 and the reason this ADR would be
void.

**Put the indicator in the room as a prop** — a wall clock, a desk lamp, a
blinking server rack. Rejected on three counts: it needs manifest art, and no
further packs are being bought; it would be theme-dependent, so six themes would
need six of them; and a thing standing in the room asserting a fact about the
*process* is a worse category error than chrome that is obviously chrome.

**Make the whole room dim or desaturate when the listener is down.** Rejected: it
is a large, ambiguous change to a picture whose colour relationships are the
subject of I7 and a lint, to carry one bit.

**Show the ingest counters as text.** Rejected. `01-PRD.md` lists metrics as an
explicit non-goal, and a request counter in the corner is a dashboard.

## 10. What would make me more confident

1. **A watched capture at `1x` by somebody who does not know the design**, asked
   only "is this app working?" over an idle room. That is the perception check
   and nothing here substitutes for it.
2. **A real session left idle for an hour**, to see that the lamp neither drifts
   nor accumulates and that `probes` and `beats` stay equal.
3. **A panel reveal landing inside a wink**, with a human's eyes.
4. **The frozen-renderer case, induced deliberately** — SIGSTOP the app and look
   at the panel — to check that a person actually reads a lamp that has stopped
   winking as "stopped" rather than as "idle".

## 11. Documents this makes wrong until edited

Edited in this change: `docs/02-ARCHITECTURE.md` (the data-flow diagram and the
concurrency list), `docs/03-EVENT-MODEL.md` ("The one request on this port that is
not a hook"), `docs/04-ART-DIRECTION.md` ("The pilot lamp does not inherit this
ceiling").

**Not edited, and deliberately:** `CLAUDE.md`'s I2. §3 proposes the clause; the
maintainer accepts or rejects it. Note that ADR-003's own proposed I2 clause is
also still unapplied, so the invariant currently carries neither carve-out while
the repository behaves as though it carried both. That is a real inconsistency
and it is the maintainer's to resolve in one edit rather than two.

`05-MILESTONES.md` is owned by another agent in this tree and no milestone covers
this.
