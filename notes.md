# Build notes

An append-only log. One entry per completed step: what we found, and how that
changed the plan. The point is the delta — which assumptions the work overturned
and what moved downstream as a result.

---

## 2026-08-07 — Scaffold

**Found.** The repo had the five instruction docs and two of the seven agent
definitions, and nothing else. No package, no source tree, no `docs/`
directory — while every doc cross-referenced `docs/03-EVENT-MODEL.md` and
`.claude/agents/`. The layout in `CLAUDE.md` was aspirational.

**Changed.**

- Docs moved to `docs/`, agent definitions to `.claude/agents/`, `CLAUDE.md` to
  the root. The cross-references in the docs now resolve.
- Wrote the five missing team members: `ingest-engineer`, `test-engineer`,
  `ui-engineer`, `build-verifier`, each derived from the invariants they are
  responsible for rather than from a generic role description.
- `Package.swift` with the `SpriteRoomCore` / `SpriteRoomScene` / `SpriteRoomApp`
  split, plus a `spriteroom-replay` executable for the harness M1 needs. Swift 6
  language mode on every target, since strict concurrency is an architectural
  requirement here, not a preference.
- `CLAUDE.md` claims the Core-imports-no-UI boundary "is checked." It was not.
  `Tests/SpriteRoomCoreTests/ImportBoundaryTests.swift` now actually checks it.
- `assets/` gitignored — the LimeZu licence permits use but not redistribution.

`swift build` and `swift test` green, no warnings.

---

## 2026-08-07 — Art packs supplied (twice)

**Found.** `assets/` initially held only Modern Office. A first drop added the
**free** Modern Interiors pack — 1% of the full asset, four characters, and a
licence reading "YOU CAN'T USE THE ASSET IN COMMERCIAL PROJECTS." A second drop
added the **full paid** Modern Interiors at `assets/moderninteriors-win/`.

**Changed.**

- The licence conflict the free pack created is resolved. The full pack permits
  commercial use and editing, matching the Office pack, so
  `04-ART-DIRECTION.md`'s "licence terms are identical" claim holds again. One
  asymmetry survives: Office says credits are *appreciated*, Interiors says
  credits are **required**. The About-panel credit to `limezu.itch.io` is
  therefore mandatory, not a courtesy.
- `assets/Modern tiles_Free/` is now redundant and is a live hazard — one file
  from it in the manifest silently makes the build non-commercial. Art-director
  instructed to build nothing against it. **Recommend deleting it**; left in
  place pending the user's call.
- Badges became sourceable: `4_User_Interface_Elements/` ships UI sheets. But
  **sheets only, no singles**, which contradicts `04-ART-DIRECTION.md`'s "build
  from the singles, not the sheets" — that rule exists because the pack's
  interior sheets have uneven grids and we have no slicer. The UI grid appears
  uniform, so a narrow slicer for this one sheet is the resolution.
- The plan to export the cast from the Windows-only generator under a VM is
  **obsolete**: `0_Premade_Characters/` ships 20 premade sheets per size. The
  task became selection-for-distinct-silhouette rather than asset generation.
- Character frame geometry is still open. The 32× premade sheets are 1792×1312,
  and 1312 divides evenly by neither 32 nor 64, so the doc's assumed grid is
  wrong. Being resolved against the pack's own animation guide rather than
  guessed.

---

## 2026-08-07 — M0a, hook payload ground truth

91 events captured from real headless sessions, isolated at project scope in a
sandbox so the developer's own `~/.claude/settings.json` was never touched. Every
captured `cwd` is the sandbox — verified independently.

**The load-bearing claim held.** `agent_id` is present on subagent events and
*absent as a key* — not null — on main-thread events, without exception across
all 91. The whole identity model rests on this. The capture also produced two
distinct `Explore` subagents with different `agent_id`s in one session, which is
exactly the case that breaks any scheme keyed on `agent_type`.

**What reality contradicted, and what changed:**

- **`SessionStart` never fires.** Not once, in five headless runs. The event
  model had it creating the session and the main agent — so a model that waits
  for it starts empty and stays empty forever. Session and main-agent creation
  are now specified as **lazy on first event of any kind**. This is the change
  most likely to have cost a day of debugging at M1.
- **`PostToolBatch` is a primary close path, not a safety net.** A tool call
  refused at the permission gate emits `PreToolUse` and then *neither*
  `PostToolUse` nor `PostToolUseFailure`. Its only close is the following
  `PostToolBatch`. Handling only `PostToolUse` leaks an open call on **every
  declined permission prompt** — the exact "character that types forever" bug I4
  exists to prevent. Promoted to a mandatory third close path.
- **The tool is named `Agent`, not `Task`.** `Task` is the model-facing name and
  never appears in a payload. Fixed in the deadline table and the badge mapping.
- **Subagents launch asynchronously.** The `Agent` call's own
  `PreToolUse`/`PostToolUse` pair closes in ~16 ms while the subagent runs for
  minutes. So the 15-minute deadline was meaningless, and — more importantly —
  the reporting walk must never be timed off the spawning call. A subagent's
  life is `SubagentStart` → `SubagentStop`, keyed by `agent_id`. The
  parent→child link is `tool_response.agentId`; there is no `parent_agent_id`.
- **`Stop` is not "turn over."** It fires once per assistant message stream,
  four times in one turn in the `three-subagents` capture. Never a reap trigger.
- **`PostToolUseFailure` replaces `PostToolUse`** rather than accompanying it,
  and its field is `error`, not `tool_response`.
- All three event names the docs marked speculative — `SubagentStart`,
  `PostToolUseFailure`, `PostToolBatch` — are **real**.

**Architecture confirmed, not revised.** HTTP hooks are native
(`{"type": "http", "url": ...}`), so `02-ARCHITECTURE.md`'s in-process listener
design stands as written. And I5 is now empirical rather than theoretical: HTTP
hooks have no `async` field, and a listener that holds for 3 s was measured
adding 3 s to every tool call in the session.

**Known gaps, carried forward honestly:**

- No `tool-failure` fixture. `PostToolUseFailure` and the permission-denied
  orphan were both observed and quoted in `FINDINGS-M0.md`, but neither was
  persisted as fixture data. Since the permission-denied leak is a real
  correctness bug, this fixture should exist before M1 exits.
- `SessionStart` in *interactive* mode is unverified — a TUI could not be driven
  from a non-tty shell. Kept in the doc, marked unverified.
- `Notification`, `PermissionRequest`, `PermissionDenied` never fired in headless
  capture. Marked unverified rather than deleted: absence of observation is not
  evidence of absence.
- `unknown-events` is 5 real + 7 synthetic. Necessarily so — Claude Code cannot
  be made to emit an event it does not have. Synthetic lines are flagged
  `"_synthetic": true`.

---

## 2026-08-07 — `tool-failure` fixture, closing M0a's gap

Captured myself rather than spending the one agent slot on it.

**Found.** Both non-`PostToolUse` close paths, in one 8-event session:

- `Read` of a missing file → `PreToolUse` → **`PostToolUseFailure`**. No
  `PostToolUse` for that `tool_use_id` ever arrives.
- `Bash` refused at the permission gate → `PreToolUse` → **nothing**. Neither
  close event fires. The call's only close is its appearance in the `tool_calls[]`
  of the following `PostToolBatch`.

**And one thing nobody had noticed:** `PostToolBatch` *re-reports* the `Read`
call that `PostToolUseFailure` had already closed. So the two close paths
overlap rather than partition. Closing must therefore be idempotent — an
already-closed `tool_use_id` must be a no-op and must not emit a second
`.callClosed`. A duplicate close would drive the scene's open-call count
negative and surface much later as a character stuck idle while it is working.
That is a nastier bug than the leak it sits next to, because it fails in the
opposite direction and looks like nothing is wrong.

**Changed.**

- `fixtures/tool-failure.jsonl` — 8 real events. Required coverage is now six
  fixtures, not five; `03-EVENT-MODEL.md` updated to match.
- Added the idempotency rule to the close-path section of `03-EVENT-MODEL.md`.
- Wrote the acceptance condition into both the doc and `fixtures/README.md`:
  this fixture must replay to zero open calls **without the deadline sweep
  firing**. If M1 needs the reaper to drain it, the close paths are wrong and
  the reaper is hiding it.

M0a's gap list is now empty. The remaining unverified items (`SessionStart`
interactive, `Notification`, `PermissionRequest`/`PermissionDenied`) all need an
interactive TTY session, which cannot be driven from this harness. They stay
marked unverified in the doc rather than being guessed at.

---

## 2026-08-07 — M0b, art ground truth

`04-ART-DIRECTION.md` was written from store pages. Measured against the files,
**eleven of its claims were wrong** and eight held. The corrections are in the
doc; these are the ones that changed the plan.

**Two headline findings.**

*Six of the seven tool badges cannot be sourced.* The pack assumed to supply
them — Modern User Interface — was never purchased. Modern Interiors'
`4_User_Interface_Elements` turns out to be an **emote** set: hearts, `!`, `?`,
sleep-Z, moons, weapons. No document, magnifier, terminal, globe, checklist or
plug anywhere in it. Only `question_mark` exists as real art, and a genuine red
`!` badge for `Notification` turned up as a bonus. The other six ship as
placeholders with provenance recorded in the manifest, so M2 is unblocked and
M5 has an explicit shopping list. This is the one thing that needs a purchase
decision.

*The silhouette rule is refuted, and that is the more interesting failure.*
`04-ART-DIRECTION.md` and `art-director.md` both assert "silhouette carries
identity at 1x" — flatten two variants to black and you should still tell them
apart. Measured: of 20 premades, four fail I7 saturation outright; of the 16
that qualify, the best possible 6-subset differs by only **88px in 2048, 7.3% of
combined outline**, and several premades are silhouette-*identical* at distance
zero (01≡02, 05≡11≡14≡20). No selection fixes this — the bodies are identical by
construction, since the generator varies clothing and hair colour over a shared
frame.

The rule was kept, not weakened, and the consequence recorded instead: **the
nameplate is now a primary identity channel rather than decoration.** That
promotes an unresolved dependency into a blocker — no font ships with either
pack, so a licence-clean pixel font must be sourced before S4 ("six agents,
every character individually identifiable") can pass. Filed as its own task.

**Measurements that replaced assumptions.** Character canvas is **32×64**, not
32×32. Direction order is `right, up, left, down`, proved by exact mirror-pairing
of the horizontal blocks. `sit` is confirmed side-view only — all four direction
blocks mirror-pair, so no back-view sit exists anywhere and the side-view room
layout is the design, not a compromise. `gift` **does** exist, so `deliver`
needed no redesign. `read a book` does **not** exist, so that state is dropped —
six body states, not seven.

The 32× set is complete: 5330 shadowless singles at all three sizes with zero
filename differences. The buyer report of content missing at 32 and 48 is
refuted.

**Changed downstream.**

- `05-MILESTONES.md` M2 said "all seven animation states play." Now six, named
  explicitly, with a nameplate-legibility criterion added — since a room whose
  characters differ only in hue now fails S4 by construction.
- `.gitignore` switched from `assets/` to `assets/*` plus a negation for
  `assets/manifest.json`. Git cannot re-include a file inside a wholly-ignored
  directory, so the obvious spelling would have silently done nothing. The
  manifest holds filenames and numbers, no artwork, so tracking it redistributes
  nothing — and without it a fresh clone cannot build the scene at all.
- The blanket rule "build from singles, not sheets" is refuted as stated. Floors,
  characters and badges ship **only** as sheets; taken literally the rule leaves
  the room with no floor. Narrowed to where singles exist.
- The Windows-VM character generator is obsolete — 20 premades ship per size.

**Lint passes on real art, and it earned it.** Room max saturation 0.183 against
a 0.25 ceiling; weakest character saturation 0.598 against 0.55; value contrast
0.472 against 0.40. It **failed first** at 0.386 contrast, and the fix was
lightening the room band rather than lowering the threshold. The lint was also
verified to actually fail — four injected violations produce four named errors
and exit 1 — which caught a real bug in it: it had been silently skipping
manifest paths outside `assets/`.

**Left alone deliberately.** `assets/Modern tiles_Free/` is still on disk. Its
licence forbids commercial use *and* forbids editing sprites for commercial
projects, so a single file from it in the manifest would quietly make the whole
build non-commercial. Nothing references it and no script reads it. Deleting
someone else's files is not mine to do unasked — recommended, not done.

---

## 2026-08-07 — M1, ingest and world model

All seven exit criteria pass, verified independently rather than taken on
report: clean `.build` from scratch with zero warnings, 43 tests green, all six
fixtures replaying to zero open calls, no `@unchecked Sendable` anywhere, and
`SpriteRoomCore` importing only `Foundation`, `Network` and `os`.

**Listener p99 is 0.112 ms** against a 5 ms budget — about 45× under. Measured
with a blocking keep-alive loopback client, one request in flight, which is the
shape of a session actually blocking on a hook response. That matters more than
the headroom: S2 caps *added* latency at 10 ms and this is the component that
spends it.

`tool-failure` replays to zero open calls **without the deadline sweep firing**,
which was the condition I set when capturing it. The close paths are genuinely
right rather than the reaper quietly covering a leak. `killed-session` is the
only fixture with an orphan at end of stream, and it abandons cleanly on the
sweep — I4 demonstrated rather than asserted.

**One real contradiction surfaced, between two documents I had both signed off.**
`03-EVENT-MODEL.md` said a session is created lazily on "the first event of any
kind"; `fixtures/README.md` said unhandled events "change nothing". Both cannot
hold, and the fixtures prove it: the synthetic unknown events in
`unknown-events.jsonl` arrive *after* that session's `SessionEnd`, so creating
state from an unhandled event resurrects a dead session — and
`SubagentHeartbeat` carries an `agent_id`, so it would spawn a character out of
an event we do not understand. [I1]

Resolved toward the fixture, which is ground truth: unhandled events are counted
and refresh the liveness timer, but never create a session, an agent, or tool
state. Session creation is lazy on the first **consumed** event. This still
fully satisfies the original intent, which was that nothing waits for
`SessionStart`.

**That resolution has a product cost, and it is worth naming.** Since
`UserPromptSubmit` is not in the consume table, the main character now appears at
the session's first *tool call* — and a turn that produces no tool call draws no
character at all. For a product whose one sentence is "you glance at the notch
and know what your agents are doing," an agent that is thinking but invisible is
a real hole. The honest fix is to consume `UserPromptSubmit`: the event genuinely
happened, and I2 already licenses drawing an idle character. The dishonest fix
would be to weaken the unhandled rule, which is why the agent escalated rather
than picking one. Recorded in the doc and filed as a task — it is not blocking
M2 or M3, and it belongs with M4's ingest work.

**Design calls the agent made, all of which I agree with.** `Notification` and
`Stop` emit no delta, because no delta type exists for either and inventing one
is fiction — `Stop`'s idleness already falls out of an empty open-call set.
`SubagentStop` for an unknown agent is a no-op rather than spawning a character
just to walk it off screen. Time is a *parameter* (`ingest(_:at:)`,
`sweep(at:)`) rather than an injected clock object — stronger, since the actor
never reads wall time, and it avoids a shared mutable clock that strict
concurrency would have wanted an escape hatch for. A `PostToolBatch`-only close
records outcome `.reconciled`: we know the call ended, we do not know it
succeeded, and claiming more would be fiction.

**The one assumption still untested against reality:** HTTP framing is
`Content-Length` only, no chunked encoding. Ordinary JSON clients always set it,
and a differently-framed body degrades to counted-malformed while still
answering `202`, so the failure mode stays harmless. M4 exercises this live.

**Deferred to M2:** the parent→child link (`tool_response.agentId` on the `Agent`
tool's `PostToolUse`). `SubagentStart` arrives *before* that `PostToolUse` in
`three-subagents`, so the link must be applied retroactively. No M1 criterion
needs it, and the doc already says an unlinked subagent anchors to the main
agent.

---

## 2026-08-07 — M2, the room on screen

All seven criteria pass, verified from a clean rebuild: no warnings, 135 tests,
`RoomCamera` importing only `Foundation`, no `@unchecked Sendable`, `.nearest`
applied in exactly one place. And for the first milestone with pixels, verified
by *looking* — the screenshots are in the scratchpad, not just asserted.

**The most valuable finding is an engine detail that nearly invalidated the
evidence.** `SKRenderer.update(atTime:)` does not evaluate the `SKAction` tree
at all. An `SKAction`-driven character is therefore frozen at spawn in any
offscreen render — every screenshot would have shown a room of motionless
figures while the tests passed. Animation was rewritten onto an explicit clock
(`Character.advance(to:)`), driven by `SKScene.update(_:)` in the window and by a
simulated clock offscreen. Side benefit: the choreography became deterministic
and unit-testable, which is what made the collision tests below possible at all.

**I sent this milestone back once, and was wrong about why.** I flagged the
delivery frame because the reporting subagent's nameplate appeared to collide
with the anchor's. The plates were not intersecting — they were on different
rows. What painted over `MAIN` was the walker's **body**: accumulated z put an
aisle character above a seated character's nameplate. The right fix was
therefore structural rather than positional, and it is stronger than what I
asked for: nameplates and badges now occupy a z band above every body, so no
body can occlude any identity in any arrangement. The rect test I asked for
would not have caught the original defect; the layering invariant test does.

Suppressing the walker's plate was considered and rejected, correctly — in a
cast M0 proved is not separable by silhouette, an unidentifiable character is
the same failure as an illegible one, just quieter, and it would fire exactly
when the room is dramatising something and you are looking at it.

**The requested test then caught a second collision nobody had seen:** two
subagents reporting within a second of each other both walk to the same delivery
point. Two agents stopping near-simultaneously is common, so the delivery point
became a row of slots at 80px pitch — slots rather than a queue, because a
queued character stands about waiting and nothing in the data says it waited.
[I1]

There is an honest correction inside that: the first version of the test stepped
a second of scene time per delta batch, which compresses the event stream against
the animation clock and manufactures coincidences that cannot happen in a real
replay. The criterion says *at real time*, so the test now runs the same fixed
1/60 step as the offscreen harness — 2,900+ frames, every pair checked each
frame. The compressed run was not wrong to be alarming, though; it is why the
slots exist.

**Residual, not half-built:** plate-plate collision is now impossible for
`three-subagents` and for concurrent reports, but not structurally impossible in
general — two characters walking the same row in opposite directions can still
cross. The general answer is label collision avoidance, which is a real feature
and was correctly flagged rather than started.

**Desk-vs-character depth is now a decision rather than an accident.** Desks had
been pinned at a fixed z while characters computed theirs from row, so the
character always won by default. Desks now take the same row-depth function plus
a half: at 32px the only cue that a character is sitting *at* a desk rather than
beside one is whether the desk's near edge crosses the body. Aisle characters
are a row nearer the camera, so anyone walking past is still in front of the
furniture — which is what the walkway is for.

**Two findings handed to the art-director, not acted on.** Accent hues do not
separate the cast: measuring the most-saturated pixel of each of the six
variants, all six land inside a **30° arc**, and 07 and 17 are hue-identical.
`04-ART-DIRECTION.md` claims one accent hue per variant "chosen for mutual
separation"; the generator in fact dresses one body in variations of one warm
palette. So accent colour is a weak second glance, and the nameplate *text* is
doing all of the identity work. The manifest should carry an explicit
`accent_hex` per variant chosen for separation rather than sampled from the art.
Separately, `room.props.identified` is `false`, so no single among the 339 can
honestly be called a desk — desks are hatched placeholders, and the manifest
needs a role mapping before real furniture can be placed. Sampling and
documenting rather than inventing a palette or guessing a filename was the right
call. [I1]

**Judgment calls worth keeping:** floor and wall tiles are chosen by
*measurement* — load all 141 builder tiles, keep the fully-opaque single-colour
ones, take the darker as floor — so no filename appears in the code and a
re-slice does not break the room. Characters walk in from one seat-pitch out
rather than the room edge, because at the edge the whole entrance happens off
camera. `×N` counts total open calls, not calls of the badged tool.

**The nameplate font is written, not sourced.** A 5×7 bitmap typeface embedded
as a constant, authored as `#`/`.` strings. An antialiased system font beside
nearest-filtered pixel art is the fastest way to make the scene look broken. It
is one constant and one call site, so the sourced-font blocker stands unchanged
and this does not pre-empt it.

**Deferred to M4:** the parent→child link. `tool_response.agentId` is not decoded
by Core and no delta carries it, so exposing it means touching Core — out of
scope for the scene. Every reporting subagent currently anchors to the main
agent, which is the documented fallback. [I1]

**Not provable here:** `screencapture -l` fails with "could not create image from
window" because this terminal has no Screen Recording permission. The window does
open and its render loop runs, and the window shots come from the live `SKView`,
but that is in-process capture, not OS-level proof the pixels reached the
display. M3 or a human glance settles it.
