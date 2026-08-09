# ADR-002 — Themed rooms, stations, and what the room may claim

**Status: ACCEPTED, 2026-08-08**, by the maintainer, and being implemented.
Nothing was implemented when this was written; §8 is the spec the
implementation follows, and §15 lists the documents this makes wrong until they
are edited. An art-director agent is inventorying the theme sets in
parallel; this document is written so that **whatever set they confirm**, the
mechanism is unchanged and the only thing their report decides is how many
themes are in the pool.

Author: `planner`. Written against Claude Code 2.1.224, `assets/manifest.json`
as generated at M5c, and the code as committed at `004b587`.

It changes **no invariant**. It lifts one half of one `01-PRD.md` non-goal —
and edits that document in this same change rather than leaving it contradicting
the product. It contradicts one paragraph of `04-ART-DIRECTION.md`, named and
argued in §5 rather than quietly overwritten. It adds **one persisted file**,
which `02-ARCHITECTURE.md` currently and correctly says does not exist; that is
a real architectural change and §3d states it as one.

This document supersedes an earlier draft of itself. The draft treated theme
selection as two layered mechanisms with the second one optional. That is a menu,
not a decision, and an implementer handed it would have shipped the half that
satisfies none of what was asked. There is one mechanism here.

---

## What was asked

1. ~~The room should be **bigger from the start** — less zoomed in.~~
   **Shipped** at `004b587`. Out of scope here, and §0 is only about what it did
   to everything else.
2. A **cooler environment than a classroom** — themed; engineering, a rocket
   ship.
3. The theme should be **related to what the project is**.
4. **Uniqueness, and relation to what the agent is actually doing**, changing
   **dynamically depending on the task and project in hand**.
5. The characters should be **"more designed for what they are doing"**.

And the standing instruction the rest of this is written under: *"I'm trusting
you to figure out solutions to the problems you encounter."*

## The short answer

| Ask | Answer |
|---|---|
| 2 | Yes. 24 themed prop sets are on disk. There is **no rocket ship** and none will be bought; an engineering/control-room feel is a *composition* of Conference Hall + Office + Basement, not a pack, and the inventory settles whether it composes. |
| 3 | **Only the user can make this true.** The theme is a per-project preference with a deterministic default derived from `cwd`. The default relates to *which* project you are in; only the user's pick relates to *what* it is. We never read the project's files — §3b, and it is refused rather than deferred. |
| 4 | Split by volatility. **Project** → the theme. **Agent** → the station, from `agent_type`. **Tool call** → the badge and the seated pose. There is no fourth layer for "the task", because the task is not observable to us and its only proxy is already on screen. §6. |
| 5 | Partly, and the parts are unequal. The **station** — the furniture the character works at — carries almost all of it and costs art we already own. The **pose** carries a little, if the inventory finds a second usable seated pose. **No new poses are promised.** §5. |

The three things in the request that **cannot be honestly satisfied** are listed
in §14 rather than designed around.

---

## 0. What `004b587` shipped, and why it raises the stakes here

`RoomCamera.comfortablePopulation` is now empty by default and read as an
allow-list, so **the room draws at `1x` at every population**. The ladder is
untouched and still integer [I6]; only the preference changed.

That was right, and it makes this ADR load-bearing rather than decorative.
Arithmetic, from `RoomLayout`'s own constants:

- The room is `25 × 9` tiles = **800 × 288 px**. The panel frames **720 × 400**.
- So at `1x` the panel shows nearly the full width and **appreciably more than
  the room's nominal height**.
- `wallRows` is 2, so the wall the room actually *has* is `wallBaseY = 224` up to
  288 — **64 px**. Everything above that, out to the top of the panel, is
  `drawnRows`' painted extension: real tiles, so no void shows, and nothing on
  them.
- M5 measured the content band at **132 px of a 400 px panel**. The other 268 px
  was flat floor and flat wall.

**These four numbers were `25 × 6`, `800 × 192`, `wallBaseY = 128` and "more
than twice" until the composition change.** The room grew from 4 floor rows to
7 — converting wall, which no pack we own can decorate, into floor that objects
and a second row of seats can stand on. Recorded rather than silently corrected
because the paragraph below still turns on the ratio, and the ratio moved: the
panel no longer shows anywhere near twice the room's height, so "the room is
shorter than its window" is a weaker claim than it was, not a false one.

Measured after the change: **~250 px of 400 (63%)** carries characters or
furniture, against 113 px (28%) before. Wall is down to 84 px (21%). The
remaining ~32% is foreground reserve the report choreography needs and only a
redesign of that beat could free.

Two consequences the implementer must hold:

**The dressing is now the product, not the polish.** Before `004b587` a busy
room pulled in and the empty bands mostly went away. They no longer do, at any
population. Pulling back permanently is an improvement only if there is
something back there; otherwise it is a smaller version of the same empty room.

**M5's foreground rule has lost half its job and gained importance.** The
foreground row was placed *strictly below the content band* precisely so it
would be out of frame at the tightest zoom — I7's "remove the detail that
competes with characters" answered geometrically. There is no tightest zoom any
more: `1x` is the only scale in practice, so **the foreground row is now
permanently on screen**. The geometric protection is inert; the palette
protection (I7, low saturation, low contrast) and the no-motion rule (§9) are
all that is left, and they now have to hold on their own.

---

## 1. What I1 governs, and what it does not — resolving (a)

I1 says: *every visible behavior traces to a real hook event. If the data does
not say it happened, the room does not show it.*

The word is **behavior**. The room already contains a great deal that traces to
no event at all: a desk, a chair, four plants, two boards, a floor, a wall.
Nobody decided from the payload that these agents work in an office. That
furniture is not an I1 violation and never was, because it asserts nothing about
the data — it is the surface the assertions are drawn on.

This project has drawn that line twice already, in the same direction:

- **M5c, authored badges.** "I1 forbids the room asserting *data* the hooks did
  not give us. It says nothing about who drew the pixels." Four glyphs were
  authored here and ship as final art.
- **M5, assigned accent hues.** "The accent is not a pixel of the sprite. It is
  the nameplate border, which the *scene* draws. Assigning it claims nothing
  about the artwork." Six hues were invented outright and the lint enforces their
  separation.

So the rule this ADR works under, stated so it can be argued with:

> **Scenery may vary. Scenery may not assert.**
>
> Changing what the room is made of is free. Making the room's contents encode a
> claim about the project, the task, or the code is fiction, whatever the pixels
> look like.

The maintainer's own example is exactly the failure: *a room that looks like a
rocket lab because we guessed the project is aerospace.* The problem is not the
rocket. It is the **because**. The same rocket, chosen by the user, is true by
construction. The same rocket, assigned by a stable hash of `cwd`, asserts only
"this is a different project from that one", which is true.

The residual — that a *viewer* may read meaning into an arbitrary assignment —
is real, is the main risk of the default, and is risk 2 in §11.

---

## 2. The signals we actually hold

### 2a. The inventory

**Received and used today:** `cwd`, `session_id`, `agent_id` (present ⇒ subagent;
**absent ⇒ main thread**), `agent_type`, `hook_event_name`, `tool_name`,
`tool_use_id`, `tool_response.agentId`, `notification_type`, `reason`.

**Received, held, deliberately unused:** `permission_mode`,
`permission_suggestions`, `effort`, the `error` string on `PostToolUseFailure`,
and `tool_input` — which `HookEvent.Kind.permissionRequest` does not even decode,
on purpose, so that a future join cannot reach it (ADR-001). `tool_input` carries
the user's `Bash` command line. **It is content. Nothing in this ADR may reach
for it.**

**Derived, and therefore just as real:** population per project; each agent's
open-call set; the observed multiset of tool names over time; the count of agents
per `agent_type`; gate/attention state; project liveness.

**Never received:** anything from `SessionStart` — `source`, `model`. Not "rare":
**unreachable over HTTP** in 2.1.224, proven at M0c by registering a `command`
hook alongside and watching it receive the event in all 8 sessions while the HTTP
endpoint received none. `session_title` does not exist at all; an early draft of
the event model invented it. Nothing may be built on any of it.

**Not available at any price under the current non-goals:** the prompt, the
response, the task, what the code does, its language, its framework, its git
state.

Two facts about the fields we do hold that the mechanism has to survive:
`agent_type` **can be the empty string** (M0c), and it is otherwise **arbitrary
text** — an agent name a user typed. And a subagent that departed on
`SubagentStop` **can come back** via `SendMessage` (M4), so nothing may treat an
`agent_id` as retired.

### 2b. Derived from real data vs. invented

The distinction the rest of this document turns on:

- **Derived** — a pure, total function of a datum we hold, whose output claims
  nothing the datum does not establish. `hash(cwd) → theme` is derived: it claims
  "project X", and project X is exactly what `cwd` is.
- **Invented** — output asserting a fact about the world we were not given.
  `cwd` contains "rocket" ⇒ aerospace ⇒ rocket lab is invented at the second
  arrow. So is *any* domain inference from a directory name, a file listing, or a
  tool mix.

The test is: **can the room be wrong?** A hashed theme cannot be wrong, because
it says nothing falsifiable. A guessed theme can be wrong, and will be, silently,
for as long as the user keeps that project.

### 2c. The table

Every visual dimension, the exact datum behind it, the fallback when that datum
is absent, and — the column this ADR is really about — **how often it may
change**. `question_mark` is the precedent for the fallback column: the honest
answer for something we do not recognise is a generic, not a guess.

| Visual dimension | Driven by | Fallback when absent | Volatility — changes when |
|---|---|---|---|
| **Room theme** | The user's stored choice for this exact `cwd`. Absent ⇒ rendezvous hash of `cwd` over the assignable pool. | `defaultThemeId` from the manifest — the Office the room ships today. Also the fallback for an unknown stored theme id and for an unreadable preference file. | **Project.** The user picks, or the selected project changes. **Never with activity.** |
| **Room geometry** (seat pitch, aisle, delivery slots, wall line, foreground line) | Theme-independent. Identical in every theme. | — | Never. |
| **Seats occupied** | Population — agents that exist because a *consumed* event created them. | Seat 0 is always framed even when empty, so an off-screen report is still visible. Unchanged. | `agentAppeared` / `agentDeparted`. |
| **Station** — desk, chair and at most one adjacent floor prop at one seat | `agent_id` **absent** ⇒ `station.main`. Present with non-empty `agent_type` ⇒ rendezvous hash of `agent_type` over the theme's numbered stations. | `station.default`, for a subagent whose `agent_type` is absent **or empty**. | **Agent.** Decided at spawn, never rewritten. §6 rule 2. |
| **Backdrop props** (wall line) and **foreground props** | The theme. A fixed, ordered list. | The Office boards and plants. | Never. |
| **Character variant** (which premade) | Main = variant 0; subagents take the lowest unused. Unchanged, and §13 says why it is not keyed on `agent_type`. | Wrap by index. Unchanged. | At spawn. Unchanged. |
| **Body: idle vs working** | `!openCalls.isEmpty`. Unchanged. [I2/I3] | idle | Any change to the open-call set. |
| **Body: which seated pose while working** | The **badge class** already computed by the lowest-ordinal rule — *not* `tool_name` directly. | `poses.working.default`, which is what `question_mark` resolves to and therefore what every unmapped tool gets. | **Tool call.** Exactly when the badge changes; never independently. §6 rule 3. |
| **Body: walk / deliver / spawn / depart** | `SubagentStart`, `SubagentStop`, `SessionEnd`. Unchanged. | — | Unchanged. |
| **Badge** | `tool_name` → mapping table; lowest ordinal plus `×N`. Unchanged. | `question_mark`. Unchanged. | Unchanged. |
| **Attention badge** | ADR-001's permission-gate marker. Unchanged; still outranks every tool badge and suppresses `×N`. | Main thread when no agent is marked. Unchanged. | Unchanged. |
| **Nameplate** | `agent_type` + last three alphanumerics of `agent_id`. Unchanged. | `MAIN` for the main thread — the identity rule, not an exception. | At spawn. Unchanged. |
| **Accent hue** | Assigned per variant, 60° apart, lint-enforced. Unchanged. | Sampling, for an older manifest. Unchanged. | Never. |
| **Camera scale** | `1x` at every population, since `004b587`. | `1x` floor. [I6] | Viewport change only. |

Four rows are new — **room theme**, **station**, **backdrop/foreground**, **which
seated pose**. Everything else is listed so the implementers can see it is
untouched.

**`permission_mode` appears nowhere, and that is a decision.** We hold it, and it
is tempting — "this agent is in plan mode" is genuinely something the agent is
doing. It is left out because it is a per-event field that can change inside a
session, so it belongs to the *tool-call* volatility band, and we have no art
that asserts it without inventing a vocabulary. If it is ever drawn it should be
a badge, not scenery. Recorded so nobody thinks it was overlooked.

---

## 3. Theme selection — resolving (b)

### 3a. The PRD non-goal is overridden, and the PRD is corrected in this change

`01-PRD.md` lists **"Customisation, theming, user-supplied sprites"** as an
explicit v1 non-goal. The maintainer is overriding the theming half. That is a
product decision and it is theirs to make. What is not acceptable is a PRD that
contradicts the product, so `01-PRD.md` is edited **in this same change** to
record the override, to point here, and to keep the halves that are *not*
overridden: **user-supplied sprites and user-authored themes remain non-goals.**
The user picks from a fixed list; they do not add to it.

### 3b. Reading the project's files — refused, and the promise it protects

Deriving a theme by inspecting `cwd` — a directory listing, `package.json`,
`Cargo.toml`, `.git/config`, file extensions, a Dockerfile — is the **only**
mechanism that could genuinely make the theme *related to what the project is*
without asking the user. It is refused. The reasoning is not close, and this is
the paragraph to argue with if you want to overturn this ADR.

The sentence at stake is `01-PRD.md`'s, and it is quoted rather than paraphrased:

> Reading or displaying prompt/response *content*. This is a status surface, not
> a transcript. **It also keeps the app from ever holding your source code.**

Four reasons, in the order they should be weighed:

1. **The stated reason is the whole promise, and a language detector breaks it.**
   The non-goal's justification is not "we do not read transcripts"; it is "the
   app never holds your source code". A detector that opens `package.json` holds
   your source code. It holds *less* of it than a transcript viewer would, and
   less-of-it is not what the sentence says.
2. **Its value is that it is categorical.** "This app never opens a file under
   your project directory" is a claim a user can verify in ten seconds with
   `fs_usage` and then stop thinking about. "This app only reads *some* files,
   for a good reason" needs an audit, and it invites the next reason. The
   promise's worth is almost entirely in being unqualified.
3. **It is the wrong shape of thing to add to this app.** Ingest is a `202` and a
   queue [I5]; the model is live state that dies with the app. A filesystem
   scanner is a new I/O surface, a new latency source, a new macOS TCC prompt
   (this is a background `.accessory` process with a status item — a Files &
   Folders prompt from it is exactly the moment a user uninstalls), and a new
   failure mode, bought for a guess.
4. **And it would still be a guess.** A repo full of Swift is not a project
   *about* Swift. The step from "detected TypeScript" to "this room should look
   like a broadcast studio" is invented at the second arrow no matter how good
   the detector is. It buys a violated promise and *still* fails §2b's test: that
   room can be wrong.

**Proposed as a named invariant, for the maintainer to promote into `CLAUDE.md`
if they agree** — it cannot be added from this ADR's scope:

> **I9 — The app never reads the project.** It never opens, stats, lists or
> watches any path under a `cwd` it has been told about. `cwd` is a routing key
> and a display string. Nothing else.

If the maintainer declines the invariant, the refusal above still stands as this
ADR's decision. The invariant only makes it enforceable by someone other than
the author of the next patch.

The cheaper cousin — **keyword inference from the `cwd` string itself** — is
refused for reason 4 alone, and it is the maintainer's own named example of
fiction. `~/code/rocket` is a directory named by a human for reasons of their
own.

### 3c. The decision

**The room theme is a per-project preference with a deterministic default.** One
mechanism, two inputs, stated as a single function:

```
theme(cwd) =
    stored[cwd]                      if stored[cwd] names a theme in the manifest
    rendezvous(cwd, assignablePool)  otherwise
    manifest.room.defaultThemeId     if the pool is empty
```

The user changes `stored[cwd]` from the menu bar. Nothing else writes it. Nothing
else reads the theme.

**Why this is one mechanism and not two options.** The derived default is not an
alternative to the user's choice; it is *the value the preference has before the
user has expressed one*, which every preference needs and which this one cannot
get from anywhere else. Ship only the default and request 3 is never satisfied
for anybody and there is no escape from a bad draw. Ship only the picker and the
first-run room — §3f, the common case, the one the maintainer sees most — has
nothing to draw. Neither half is useful alone, which is why neither is optional.

Four things about the default are load-bearing, and each is a real footgun:

- **Not Swift's `Hasher`.** `hashValue` is seeded per process. Using it gives the
  same project a different room on every launch — precisely the requirement being
  violated — and it looks like a bug in the scene rather than in the hash. Use a
  pinned function: **FNV-1a 64 over the UTF-8 bytes**, one screen of code, and
  **pin a test vector**, so a refactor that changes the mapping turns a test red
  rather than silently redecorating every user's rooms.
- **Append-stable selection.** `hash(cwd) % themeCount` renumbers everything the
  day a theme is added. Select by **rendezvous**: take the theme maximising
  `fnv1a64(cwd + "\u{1}" + themeId)`, ties broken by the lexicographically
  smaller `themeId`. Adding a theme moves about one project in N instead of
  nearly all of them. The tie-break is not decoration — without it a 64-bit
  collision makes the room depend on dictionary iteration order.
- **Keyed on `cwd` exactly as received.** That is already the project bucket. A
  path differing by a trailing slash or a symlink is already a different project
  everywhere else in this app; the theme inherits that behaviour and does not
  invent a normalisation of its own.
- **The pool is the *assignable* themes, not all of them.** §3e.

### 3d. The preference file — the first thing this app has ever persisted

This is the honest cost and it must not be buried. `02-ARCHITECTURE.md` says, in
a paragraph that was *already corrected once* for describing a config file that
did not exist:

> **Nothing else is persisted, and this paragraph used to claim otherwise.** …
> If a preference ever does need to survive a launch, add it deliberately; do not
> assume this file already exists because a document once said it did.

**This is that deliberate addition.** It is an architectural change, not an
implementation detail, and it is specified here completely so that nobody has to
decide anything at the keyboard:

- **Path.** `~/Library/Application Support/SpriteRoom/themes.json`. That
  directory already exists — it is where `settings-backup.json` goes — so no new
  location is introduced.
- **Format.** `{"schema": 1, "themes": {"<cwd>": "<themeId>"}}`. Keys are the
  exact `cwd` strings the events carried. Nothing else in the file.
- **Owner.** `SpriteRoomApp`, beside `HookInstaller`. **Not** `SpriteRoomCore`
  and **not** the scene. `SpriteRoomCore` gains no file I/O and keeps its
  headless testability; the data flow in `02-ARCHITECTURE.md` stays
  one-directional, with the theme entering the scene the same way the selected
  project does.
- **When it is read.** Once, at launch, before the first project is displayed.
  Never again.
- **When it is written.** Only when the user picks a theme from the menu. Write
  to a sibling temp file and `rename` over the target, so a crash mid-write
  cannot leave a truncated file. **Never on a hook event path** — no disk I/O
  anywhere downstream of ingest, ever [I5].
- **Every failure degrades to the default and none is fatal.** File missing,
  unreadable, not JSON, wrong `schema`, `themes` not an object — all mean "no
  stored choices", the app launches, and every project takes its derived theme.
  A file that fails to parse is renamed once to `themes.json.bad` and a fresh one
  is started, so a corrupt file cannot wedge the picker forever and the user's
  bytes are still on disk if they want them.
- **An entry naming a theme the manifest does not have** — a removed theme, an
  older manifest — falls back to the derived default *for that project only*, and
  the entry is left in the file, because the theme may come back.
- **No eviction.** Entries are a few dozen bytes and a project you have not
  opened in a year is exactly the one whose choice you would be annoyed to lose.
- **Write failures are counted, not surfaced.** A read-only home directory means
  the picker works for this launch and forgets on the next. That is a degradation
  the user can live with; a modal dialog about a desk skin is not.

Two things this file is **not**: it is not a general preferences store — schema 1
holds themes and nothing else, and the next preference is a new ADR, not a new
key; and it is not a config file a user is expected to hand-edit.

### 3e. Which themes the default may draw from

Because an arbitrary assignment can still be *read* as meaningful, each theme in
the manifest carries an `assignable` flag, and the derived default draws only
from `assignable: true`. The picker lists everything.

The intent, for the art-director to apply to whatever they confirm: themes that
read as "a place where work happens" are assignable — Office, Conference Hall,
Basement, Museum, TV & Film Studio, Art, Classroom & Library, Japanese Interiors.
Themes that read as a **claim about the work** are choosable but not assignable —
Hospital, Jail, Shooting Range, Grocery, Ice Cream Shop, Gym, and the three
seasonal sets. A user who picks Jail has said something about their project; a
hash that picks Jail has said it *for* them.

This is a judgment call, it is the softest paragraph in this document, and the
maintainer should overrule it freely — it is one boolean per theme in the
manifest. The mechanism does not depend on it.

### 3f. First run, and the empty project

A project with one `UserPromptSubmit` and nothing else still has to look like
something. It does, and by construction rather than by a special case:

**The theme is resolved when the project bucket is created — on its first
*consumed* event — from `cwd` alone.** It takes no input that accumulates: not
population, not tool history, not time. So the room is fully dressed on the very
first frame it is ever drawn, and the empty-project case is the same code path as
the busy one. The main character sits at `station.main`, which every theme is
required to bind (§7), with an idle body, no badge, and the theme's backdrop and
foreground already placed.

The one thing that is *not* dressed on the first frame is the seats of subagents
that do not exist. That is unchanged, correct, and the reason seat 0 is always
framed.

---

## 4. Stations — what varies per agent

A **station** is the desk, the chair, and at most one adjacent floor-standing
prop at one seat. It is where request 4's "uniqueness, and relation to what the
agent is actually doing" is actually met, because `agent_type` is the one datum
that says what an agent *is*.

**Selection, total by construction:**

```
station(agent) =
    "main"                                   if agent_id is absent
    "default"                                if agent_type is absent or ""
    rendezvous(agent_type, theme.numberedStations)   otherwise
```

`"main"` and `"default"` are separate bindings that every theme must declare.
They are not the same thing: `"main"` says *this is the main thread*, which is
the identity rule; `"default"` says *this is a subagent whose type we were not
told*, which is the `question_mark` of furniture.

**Four `general-purpose` subagents get four identical desks. That is deliberate,
and it is the interesting decision in this section.**

We *could* honestly vary the station per `agent_id` — it would assert nothing
false, exactly as the `cwd` hash asserts nothing false. It is refused because it
would spend the station's only meaning on decoration. Keyed on `agent_type`,
**"same desk" means "same kind of worker"** — a rule a user learns in one glance
and can then read off the room. Keyed on `agent_id`, the desks are all different
and none of them means anything. Four identical desks is *truthful thinness*:
those four agents genuinely are the same kind of thing, and the channels that
separate them are the ones M5 built and S4 proved — the `TYPE:XXX` nameplate, the
accent hue, and the seat. Manufacturing furniture differences between identical
agents is decoration pretending to be information, which is the failure mode I1
exists to prevent wearing a friendlier face.

The same reasoning kills keying the **character variant** on `agent_type`, for an
additional and harder reason — see §13; it would regress S4.

---

## 5. Characters — what request 5 can honestly mean

`04-ART-DIRECTION.md` and `03-EVENT-MODEL.md` both say: **body state while
working is the sitting pose, regardless of tool**, because "the tool identity
lives entirely in the badge… this is what lets a new tool name appear tomorrow
without new art."

Request 5 pushes directly on that, so it is answered directly.

### 5a. What that paragraph protects, and how to keep it

It protects **extensibility**, not truth. A pose that varied with the tool would
not be fiction — `tool_name` is real data, and the badge above the same head
already asserts exactly the same thing. The stated worry is that a new tool name
arrives and there is no art for it.

That worry is fully answerable, and the answer is one word: **key the pose on the
badge class, not on the tool name.** The badge mapping is already **total** —
every unmapped tool gets `question_mark`. So a tool nobody has heard of maps to
`question_mark` maps to the default seated pose, forever, with no new art. The
property the paragraph exists to preserve is preserved exactly.

**Proposed replacement for that paragraph**, for `04-ART-DIRECTION.md`'s owner to
apply (outside this change's scope):

> Body state while working is a **seated** pose in every case. Which seated pose
> is a function of the badge class, and the badge mapping is total, so a tool
> name that appears tomorrow still needs no new art. Every working pose is
> side-view, right and left only.

### 5b. What art exists, and what is therefore promised

The pack ships `idle`, `idle_anim`, `walk`, `run`, `sit`/`sit2`/`sit3`, `phone`,
`gift`, plus `sleep`, `push cart`, `pick up`, `lift`, `throw`, `hit`, `punch`,
`stab`, `grab gun`, `gun idle`, `shoot`, `hurt`. Six body states are in the
manifest. `working` is **one** seated pose today: `04-ART-DIRECTION.md` row 4,
`sit`. **No further packs will ever be bought.**

So the honest reading of "more designed for what they are doing", in descending
order of confidence:

1. **The station carries almost all of it.** A character at an engineering bench,
   a library carrel, a studio desk or a conference table reads as doing different
   work without one new frame of animation. This is where the value is, it costs
   art we already own, and it is keyed on `agent_type` — genuinely what the agent
   *is*.
2. **The pose carries a little, and how much is a fact the inventory settles.**
   `04-ART-DIRECTION.md` measured **two** sit rows, both side-view in all four
   direction blocks; the brief names three. The mechanism does not care: the
   pose table is **manifest data** (§7), so if the inventory confirms one usable
   seated pose, every badge class maps to it and this half is inert with no code
   path to delete. If it confirms two or three, they are assigned to badge classes
   by a table in the manifest, collapsing aggressively exactly as the badge table
   does — same reason, a user cannot read seven poses at `1x`.
3. **Nothing else is promised.** There is no "designing" pose, no "reviewing"
   pose, no "planning" pose. `read` was dropped at M0 because the animation does
   not exist. `phone` is not confirmed seated and must not be assumed into a
   desk. Authoring a character animation is permitted in principle — M5c settled
   that authoring pixels is not an I1 violation — but it is a different order of
   work from a 10 × 12 badge glyph: six variants × two directions × N frames,
   matched to a generator's hand. **Out of scope and not recommended.**

Two hard constraints on anything proposed here, both measurements rather than
opinions:

- **Every working pose is side-view.** All four direction blocks in both sit rows
  are mirrors, so no front- or back-facing sitting sprite exists at any size. A
  theme whose seating implies a character facing the camera is asking for art
  that was never drawn.
- **Every seated character faces right**, because the desk is placed to its right
  and the chair role was chosen at M5 for a backrest on the left. **A theme whose
  chair does not satisfy this is not a theme** — it is the hard filter in §7 and
  the biggest risk in §11.

---

## 6. Dynamism without flicker — resolving (c)

The precedent is the badge: **deterministic lowest-ordinal selection, because
most-recent-wins flickers** [I3]. The discipline this ADR adds is one level up
from that:

> **Every visual dimension is assigned to exactly one volatility band — project,
> agent, or tool call — and may only change on that band's own event.** Nothing
> is driven by a signal that would need a timer to be watchable.

That is stronger than hysteresis, and it is why no new hysteresis constant
appears anywhere below. A dimension driven by the badge inherits the badge's
debounce, which is already tested. A dimension driven by the project changes only
when the user does something. There is no dimension in the middle, and §6 rule 1
is the decision to keep it that way.

**Rule 1 — the room does not change with activity. At all.**

This is the largest single decision in this ADR and the one most likely to
disappoint, because it is the literal words of request 4 that it declines. Three
reasons:

- The nearest honest proxy for "what the task is" is the observed tool mix. That
  is real data, and it is **already on screen**, per agent, above each head, at
  higher fidelity and with no lag. Re-encoding it in the scenery adds a second
  channel that says less, later.
- Any scenery driven by a tool mix needs hysteresis measured in *minutes* to
  avoid re-decorating every few seconds — and hysteresis that long means the room
  asserts a **past** state as present. A room that re-decorates constantly is
  worse than a static one; a room that re-decorates slowly is quietly stale. Both
  are worse than a room that does not claim to know.
- It breaks the one property the theme must have: **a project looks the same
  every time you glance at it.** A room that looks different on Tuesday is not a
  place the user recognises, and recognising the place is the whole reason to
  have one.

**Rule 2 — the station is decided at spawn and never rewritten.** M5's reasoning
for the always-on nameplate suffix applies verbatim: rewriting a character's
appearance while it is on screen changes its *identity* under the user's eye, at
exactly the moment the room got busy and they are looking at it, and it would
churn as the visible set changes on every arrival, departure and report walk.

**Rule 3 — the seated pose changes exactly when the badge changes, and never
independently.** No dwell timer, no smoothing, no minimum hold. The temptation is
to add one, because a body swapping pose is louder than a 24 × 34 glyph swapping.
It is refused: a dwell makes the pose and the badge disagree for the dwell's
duration, which is the body asserting a tool class that has ended while the badge
above it says otherwise. **If it proves visually noisy in a real room, the fix is
fewer distinct poses, not a timer** — collapse two badge classes onto one pose in
the manifest and the noise goes away without anything lying.

**Rule 4 — a theme change is a rebuild, not a transition.** Themes change on
project switch and on user pick, both of which are discontinuities the user just
caused. No cross-fade, no prop animating in. The room is simply the other room.
Stations are recomputed from the same inputs by the same function, so every agent
lands on the corresponding station of the new theme; that is a rebuild, not a
rule-2 rewrite.

**Rule 5 — the same test the badge has.** M4 established that the badge-change
count must equal the open-call-change count, and it caught a real spurious change
with it (`setBadge(.none)` at spawn). The pose gets the identical assertion over
`three-subagents` **at real time** (the fixed 1/60 step, not a step-per-batch):
**pose changes ≤ badge changes**, per character, over the whole replay. And the
room gets the strongest form of the same idea: **zero prop-node rebuilds across
an entire fixture replay**, since no fixture contains a project switch or a user
pick.

---

## 7. The theme contract

So the inventory produces something the scene can consume, and so a theme that
cannot be honest cannot be added. A **theme** is a named set of role bindings in
`assets/manifest.json`, under `room.themes`:

| Key | Count | Constraint |
|---|---|---|
| `floor`, `wall` | 1 each | Selected by **measurement**, as today — load the builder tiles, keep the fully-opaque single-colour ones. No filename in `Sources/`. |
| `station.main` | 1 | The main thread's seat. Distinguishing it is honest: `agent_id`'s absence is the identity rule. |
| `station.default` | 1 | A subagent of unknown or empty type. |
| `station.<n>` | ≥ 1 | Numbered subagent stations. The rendezvous pool for `agent_type`. |
| `backdrop[]` | ≥ 1 | Floor-standing, placed on the wall line. |
| `foreground[]` | ≥ 1 | Floor-standing, placed on the foreground line. |
| `assignable` | bool | Whether the derived default may pick this theme. §3e. |

A **station** is itself `{ desk, chair, prop? }`, where `chair` must be
**side view with the backrest on the left** so a person on it faces right, and
`prop` is an optional floor-standing item placed adjacent to the seat.

Three named placement points, all theme-independent, all already derivable from
`RoomLayout`: the **seat point** (`seatPosition` / `deskPosition`), the **wall
line** (`wallBaseY = 224`, and 128 before the room grew to 9 tiles), and the
**foreground line** (strictly below the content band, as M5 placed it).

Inherited rules, none of them negotiable:

- **Nothing enters `assets/manifest.json` until it has been located in the
  downloaded files.** Mechanically enforced — `build-manifest.py` re-stats every
  path and the lint fails on any declared asset it cannot load.
- **Every prop carries its measured `content_box`** and is placed by putting that
  box's bottom-centre on a named point. The singles are neither bottom-aligned
  nor centred: the desk's baseline is row 87 and the plant's row 75 in canvases
  of identical size. A fixed offset is right for one file and 12 px into the floor
  for the next.
- **Nothing is placed on a surface the art carries no datum for.** This is the
  monitor decision and it stands. A desk-top prop requires the `desk` binding to
  carry a *measured* `surface_y`; without one, floor-standing only. The same rule
  bars **wall-mounted** props: a poster needs a declared `mount_y`, and until the
  art carries one, the wall band is dressed by tall floor-standing props only. An
  eyeballed offset dressed as data is the failure mode. [I1]
- **Everything goes through the desaturating import pass and the I7 lint.** Room
  under 0.25 saturation; characters keep the saturation and the darkest values.
  **If a theme fails, the theme is wrong, not the threshold** — M0's contrast
  check failed at 0.386 and the fix was lightening the room. That precedent is
  binding, and with 24 candidate sets it will be tested.
- **`provenance: "pack"`.** No theme prop is authored. The authored-art path
  exists for badge glyphs and is not opened here.

And one new binding, for §5:

| Key | Constraint |
|---|---|
| `characters.poses.working` | A map from badge id to a seated state name, plus a **required** `default`. Total by construction. Every named state must exist in `characters.states` with `right` and `left` frames and no others. |

---

## 8. The implementation, specified

Nothing below is a choice. If an implementer finds a decision left to them here,
that is a defect in this document and they should hand it back.

**`SpriteRoomScene`** — pure, no SpriteKit types in the signatures, unit-tested
the way `RoomCamera` is:

1. `fnv1a64(_ bytes: some Sequence<UInt8>) -> UInt64`. Offset basis
   `0xcbf29ce484222325`, prime `0x100000001b3`. One pinned test vector.
2. `rendezvous(key: String, over ids: [String]) -> String?` — argmax of
   `fnv1a64(key + "\u{1}" + id)`, ties to the lexicographically smaller `id`,
   `nil` for an empty pool.
3. `ThemeSelector.theme(for cwd: String, stored: [String: String], manifest:
   Manifest) -> String` — the function in §3c, in that order, with the
   manifest's `defaultThemeId` as the final floor.
4. `ThemeSelector.station(agentID: String?, agentType: String?, in theme: Theme)
   -> String` — the function in §4. Empty and absent `agent_type` take the same
   branch.
5. `RoomScene` takes a `themeId` at build time and reads its bindings from the
   manifest. **No filename and no theme name appears in `Sources/`** except
   `defaultThemeId`'s key. Changing theme rebuilds the prop nodes; it does not
   touch characters' seats, plates, variants or badges.
6. `SceneDirector` stores the station id in the presentation record beside
   `variant`, `seat` and `nameplate`, and never rewrites it.
7. The pose is looked up from `characters.poses.working` by the badge class the
   director already computes, at the moment it already computes it. No new
   trigger, no new timer, no new state.

**`SpriteRoomApp`**:

8. `ThemeStore` — reads `themes.json` once at launch, exposes `[cwd: themeId]`,
   writes atomically on a user pick. All failure modes per §3d.
9. `ProjectSelector` gains a **Room ▸** submenu listing every theme in the
   manifest, with the current one checked, enabled only when a project is
   selected. It writes through `ThemeStore` and tells `RoomHost` to rebuild. The
   precedent for a menu item that *writes* something is the hooks toggle,
   justified there on the grounds that it does not touch a running agent; a theme
   picker does not touch one either. The panel stays a pure display surface and
   keeps `ignoresMouseEvents`; **nothing about I8 moves.**

**`SpriteRoomCore`**: unchanged. No new delta, no new field, no file I/O.

**Tests, each of which must be seen red before it is believed:**

- The pinned FNV-1a vector.
- Two resolutions of the same `cwd` with the same manifest give the same theme —
  and across a simulated process restart, which is what catches `Hasher`.
- Adding a theme to the pool moves at most a small fraction of a corpus of
  synthetic `cwd`s. (Rendezvous, not modulo.)
- Empty `agent_type` and absent `agent_type` resolve to the same station; absent
  `agent_id` resolves to `station.main` regardless of type.
- Every theme in the manifest binds every required key, and every named pose
  state exists with exactly `right` and `left` frames. Art-gated per
  `CLAUDE.md`'s rule, with a visible skip.
- A `themes.json` that is missing / truncated / wrong-schema / naming an unknown
  theme each yield the derived default and no throw.
- **Pose changes ≤ badge changes**, per character, over `three-subagents` at real
  time. (§6 rule 5.)
- **Zero prop-node rebuilds** across every fixture replay. (§6 rule 1, mechanically.)
- The existing delta-stream tests are byte-identical, since Core does not change.

---

## 9. What is explicitly out

Drawn so the implementers do not have to guess.

- **Reading anything under `cwd`.** No directory listing, no manifest file, no
  git metadata, no extensions, no stat. §3b.
- **Prompt or response content**, in any form. Unchanged PRD non-goal, and the
  reason the whole theme is derived from a path rather than from meaning.
- **`tool_input`.** It is in the `PermissionRequest` payload and it is the user's
  command line. ADR-001 deliberately declines to decode it. Nothing here reaches
  for it.
- **Keyword inference from the `cwd` string.** §3b.
- **Theme, backdrop or foreground varying with tool activity.** §6 rule 1.
- **Animated props.** ~~`3_Animated_objects/` exists and stays out.~~
  **Amended 2026-08-08 — see §14b.** The reasoning below stands and is the
  reason the exception is one prop rather than a category; the flat prohibition
  does not.

  In this product **motion means an agent is working** — it is the one signal a
  glance actually reads. Scenery that moves on its own competes with the only
  thing the room is for. This is I7's "the room is the low-contrast layer"
  applied to the time axis, and it is a firmer line than the saturation one. It
  matters more since `004b587`, because the foreground row is now always on
  screen (§0).
- **Wall-mounted and desk-top props**, until the manifest carries a measured
  mount or surface datum. §7.
- **New character poses beyond what the pack ships.** §5b.
- **User-supplied sprites and user-authored themes.** Still a PRD non-goal.
- **A second preference in `themes.json`.** Schema 1 holds themes. The next
  preference is a new ADR.
- **More than one room on screen**, or a per-agent room. One project, one room.
- **A theming *engine*.** `CLAUDE.md`: "No speculative generality. No plugin
  systems, no theming engine." A theme is manifest data plus a selection
  function. If the implementation grows a registry, a protocol and a loader, it
  has gone wrong.
- **Touching the camera.** `004b587` settled it. [I6]

---

## 10. What it costs

- **The first persisted preference this app has ever had.** §3d. One file, one
  new failure surface, and a paragraph of `02-ARCHITECTURE.md` that has been
  wrong once already about exactly this.
- **A second decision surface for the user.** Today the only thing they own is
  which project is displayed. Every menu item is something to maintain, explain
  and get wrong — and a picker nobody finds means request 3 is never satisfied
  for that user (risk 4).
- **A great deal more art through the lint.** Up to 24 theme sets against one,
  and I7 is a gate that has genuinely failed before.
- **More textures resident and more nodes on screen** than the room has ever
  drawn. Unmeasured. Probably fine; not verified.
- **`04-ART-DIRECTION.md` loses a clean rule.** "The body is always the sitting
  pose" is simpler than "the body is a seated pose chosen by badge class". The
  simplicity was worth something and it is being spent.
- **Complexity in the scene.** One layout and one prop set becomes one layout and
  N prop sets with a selection function, a fallback, and a stability guarantee.

---

## 11. What it could get wrong

1. **The side-view chair filter may kill most of the 24 themes.** Modern
   Interiors' seating was drawn for a top-down-ish interior, not for a side-view
   sit row, and the Office chair was *selected* at M5 precisely because its
   backrest is on the left. If most theme sets have no such chair, the pool
   collapses to three or four and most of the "uniqueness" this ADR promises
   evaporates. **This is the single biggest risk and it is unverified.** The
   inventory settles it; nothing else here should be built until it does.
2. **A hashed theme is read as a claim.** The mechanism asserts nothing, but a
   user who sees a museum may conclude we think their project is a museum. It is
   the honest residual of the default, it is why the picker is not optional, and
   it is why §3e keeps the assignable pool neutral.
3. **`agent_type` is a thin hash key in practice.** Most sessions are a main
   thread plus `general-purpose` subagents, so most rooms will show one station
   repeated. §4 argues that is truthful rather than a defect — worth knowing
   before someone reports it as a bug.
4. **Nobody finds the picker.** The whole of request 3 lives behind a submenu of
   a status item. If it is not discovered, every user's experience of this
   feature is the arbitrary default. No mitigation is proposed; the alternative
   is a modal prompt about a desk skin, which is worse.
5. **A moved or renamed project gets a new room.** Truthful — it is a different
   bucket everywhere else in the app too — and surprising. The picker is the
   escape hatch. A stored entry for the old path is left behind and harmless.
6. **The pose flickers in a way `three-subagents` does not show.** The fixture is
   what we have. Rule 5's test is the guard and rule 3's answer (fewer poses) is
   the fix that does not lie.
7. **The pinned hash gets refactored.** A well-meaning cleanup to Swift's
   `Hasher` redecorates every room on every launch and looks like a rendering
   bug. Only the pinned vector prevents it.
8. **`themes.json` is the thin end of a config file.** The app has gone eight
   milestones without one. The counter is §9's rule that the next preference
   needs its own ADR, and it is a rule about people, so it will hold exactly as
   long as someone enforces it.

---

## 12. What would have to be true for me to be confident

None of these needs new tooling, and none is a design change:

1. **The inventory names at least three themes** with a side-view chair whose
   backrest is on the left, at least one floor-standing backdrop prop tall enough
   to read against the wall band, at least one foreground prop, and a pass through
   `lint-palette.py` after the import pass. **Below three, the honest answer is
   that this ships as one alternative theme plus a picker, not as a system** —
   and the mechanism is unchanged either way.
2. **The inventory settles the seated-pose count** — how many *distinct*,
   *side-view*, *seated* poses exist at 32×64 in the sheets we ship. If it is
   one, §5b item 2 is inert and nothing else moves.
3. **A screenshot at `1x` of a dressed themed room with six agents**, showing
   that the 268 px the content band does not occupy is no longer flat. §0 is
   currently an argument, not a picture, and it is the premise of the whole
   change.
4. **Pose changes ≤ badge changes** over `three-subagents` at real time, per
   character.
5. **A pinned hash vector, plus two launches of the same `cwd` producing the same
   theme.** Stability is the requirement most easily lost by accident.
6. **The lint passing over every theme in the pool**, with its numbers recorded
   the way M0's were, so a theme that only just passes is visible.

---

## 13. Alternatives considered and rejected

**Infer the theme from the project's files.** §3b. Rejected: it crosses a
categorical promise, adds an I/O surface and a TCC prompt to an app that has
neither, and buys an inference that is still a guess. **This is the only rejected
option that could have satisfied request 3 automatically, and rejecting it is why
§14 exists.**

**Infer the theme from words in the `cwd` string.** Rejected: the maintainer's
own example of fiction. A domain claim derived from a name chosen for other
reasons.

**Drive the theme from the observed tool mix.** Genuinely derived from real data,
and rejected anyway: it destroys stability, duplicates the badge with more lag
and less precision, and cannot avoid either flicker or staleness. §6 rule 1.

**Drive the theme from the tool mix with a long hysteresis window.** The
sophisticated version of the above, and it is worse, not better: a window long
enough to stop flicker is long enough that the room asserts a past state as
present. Rejected on the same grounds ADR-001 rejected a badge timeout — a
constant with nothing behind it.

**A derived theme with no user override.** Rejected: request 3 is then never
satisfied for anyone, and a user dealt a room they dislike has no recourse for
the life of the project.

**A user-picked theme with no derived default.** Rejected: the first-run room —
the most common room there is, and the one the maintainer sees most — would have
nothing to draw, and "pick a theme" is not a thing to ask of someone who opened a
panel to glance at it.

**Store the preference in `~/.claude/settings.json`, beside the hook block.**
Rejected: that file is the user's, we already promise to restore it byte for
byte, and putting our preferences in it makes that promise harder to keep for the
sake of avoiding one file in a directory we already own.

**Let the theme follow `agent_type` — an `Explore` room, a `security-reviewer`
room.** Rejected: there is one room per project and several agent types in it at
once. That is the *station's* job, and it is how request 4's per-agent uniqueness
is actually met.

**Vary the station per `agent_id`, so identical agents get different desks.**
Rejected in §4: it would assert nothing false, and it would spend the station's
only meaning — "same desk means same kind of worker" — on variety.

**Key the character variant on `agent_type`, so an `Explore` always looks the
same.** Tempting, cheap, and rejected on **S4**. Variants are currently claimed
lowest-unused precisely so two characters on screen together never wear the same
body; M0 refuted silhouette (best six-variant subset differs by 7.3% of outline)
and M2 refuted accent hue (all six inside a 30° arc). A type-keyed variant puts
two visually identical characters in the room the moment two agents of different
types collide on the same hash, and S4 is the criterion M5 spent a milestone
rescuing.

**Author new poses.** Not rejected on principle — M5c settled that authoring is
permitted — but out of scope and not recommended. §5b item 3.

**Do nothing.** The honest baseline. The room works, S4 passes, every milestone
is clean. What this buys is a room that is a *place* rather than a diagram —
which, for a product whose one sentence is "you glance at the notch and know what
your agents are doing", is worth something and is not measurable. Since `004b587`
it also buys the 268 px of flat floor and wall that the wide view now shows at
every population, which *is* measurable and is not currently earning its space.

---

## 14. What cannot be honestly satisfied

Stated plainly, because designing around these would ship something that quietly
lies.

1. **"Themed related to what the project is" — not automatically. Ever.** What
   the project is about is not observable to this app: the prompt and response are
   a non-goal, and the filesystem is refused in §3b. The derived default relates
   to *which* project you are in, not *what* it is, and this document should not
   be read as claiming otherwise. **Only the user's pick makes request 3 true,
   and only for the projects they pick for.**
2. **"Changing dynamically with the task" — no.** We do not know the task. The
   nearest real proxy is the tool mix, which is already on the badge above each
   head, faster and more precisely than any scenery could restate it. The room
   changes with the *project*; the character changes with the *tool call*; there
   is nothing in between and inventing something would be fiction with a slow
   fade on it.
3. **"A rocket ship" — there is no rocket ship**, in any pack we own, and no
   further packs will be bought. An engineering or control-room *feel* may be
   composable from Conference Hall + Office + Basement, and the inventory will say
   whether it composes into something that reads at `1x`. If it does not, the
   answer is that it does not, not a room with a rocket-shaped prop in it.
4. **"Characters more designed for what they are doing" — bounded by the pack.**
   Stations, yes, and they are the good half. Poses, at most two or three seated
   variants and possibly one. No bespoke pose per activity, at any price we are
   willing to pay.

---

## 14a. Amendment, 2026-08-08 — the manifest that shipped

Two divergences between §7 as written and `assets/manifest.json` as built, found
by the implementer of §8 items 8–9 rather than by review. Both resolved here so
the ADR and the artifact agree; §7's prose above is superseded on these points.

**Key path.** §7 specified `room.themes` and `room.defaultThemeId`. What shipped
is top-level **`themes.sets.<id>`** with **`themes.default`**. The shipped shape
wins, and it is the better one: `room` stays byte-for-byte the contract the
scene already loads — it *is* the resolved default theme — and every theme,
including that default, carries the same shape beside it. A reader learns one
loader, not two. Nothing has to be reshaped and no existing reader breaks.

**`assignable`.** §3e's split between what the hash may pick and what the user
may choose had nothing to read: the flag was absent from every theme. It is now
emitted per theme, defaulting to `true`, and all six current themes carry it as
`true` because all six are neutral workplaces. The flag exists so the first
theme that would read as a claim about the work — a jail, a hospital — can be
offered to a user who wants it without ever being *assigned* to somebody by a
hash. That is the difference between the user saying "make mine the jail" and
the app deciding a project looks like one, and only the second is fiction. [I1]

Neither change touches the mechanism in §3c or the spec in §8.

---

## 14b. Amendment, 2026-08-08 — one animated prop, and the rule that admits it

§9 banned animated props outright. The maintainer asked for them, and the ban is
replaced by a rule rather than lifted, because §9's reasoning was right about
*why* motion is dangerous here and wrong only about whether it can ever be
afforded.

**The rule: a prop may idle on its own loop and may never take input from the
delta stream.** A clock that swings is scenery. A clock that swings *faster when
the agent is busy* is scenery asserting something, and that is the fiction §9
exists to prevent [I1]. `loop` is always `true` and has no other value; nothing
in the animation path reads a delta, and there is no code path by which it
could.

**One prop ships**, `pendulum_clock` in `library`: 4 frames at 5 fps, 64 moving
pixels of 2096, and 192 of 288,000 on the panel between consecutive frames. The
budget is deliberately that small, because §9's argument is correct that motion
out-competes everything else a glance reads.

Three candidates were refused on measurements, and the refusals are the useful
part:

- `control_room_screens` **fails the lint** — `mission_control` 0.427 → 0.363
  against a 0.40 floor — and cannot be drawn regardless: its content box is
  120 px wide while the scene places `board` at four points 96 px apart, so
  copies clip each other at any canvas size. The canvas widening approved for it
  is reverted.
- `control_room_server` composes cleanly and would spend 0.019 of the 0.027
  margin §14a's rework deliberately bought.
- `old_tv` is a TV meant to stand *on* furniture; the back row is a floor line,
  so it would hang at chest height over nothing. It moves **31.5%** — and it
  **would have passed the lint**, because the lint said nothing about motion.

  Two corrections to that sentence, both worth keeping visible. The figure was
  written here as 27.9%, and before that as 10.4%; the true number is 364 moving
  pixels of 1156 visible. **Three passes at one measurement, two of them wrong**,
  which is why the importer now generates it and the lint recomputes and
  cross-checks rather than trusting either.

  And the gap it named is **closed**. `scripts/lint-palette.py` has a fourth
  threshold: pixels changed per second on the panel, summed over animated props
  and multiplied by the copies the room draws, against a ceiling measured as the
  quietest *looping* character animation any shipped variant plays. Characters
  set the number, which is what I7 says everywhere else — the room is the quiet
  layer, and now that holds on the time axis too. `old_tv` fails it at **9.49×**.

**The slot is `board`, and the reason given here was wrong.** This said `plant`
repeats three times in the back row *and seven in the permanently-visible
foreground*, so `board` was the only role that could afford motion. The
foreground row was removed at `4e7b43d`, two commits before the budget was
written, and the budget's placement census had not noticed — it priced `plant`
at ten copies when the room draws **three**. `plant` is the *cheaper* slot, not
the dearer one. Corrected at M6e; see `scripts/preview-theme.py`.

What survives is the budget itself, which is the rule: **any role may carry
motion if it fits, and no role may carry motion because of what it is.** `board`
carries the clock today because `library`'s board is the prop that reads as a
clock, not because of a cost argument that turns out to have been arithmetic on
a demolished row. `board` is still every theme's identity object and dark
anchor, so `library` gives up its chalkboard for this — that trade is real and
unchanged, and it is one line to revert.

The lesson is the one the `prop_origin` bug already taught and this repeated
inside the fix for it: the census was cross-checked against `render()`, which
transcribed the *same* dead layout, so the two agreed with each other and with
nothing the scene draws. A transcription checked against a transcription is not
a check.

---

## 14c. Amendment, 2026-08-09 — the stations that shipped

§4 and §7 specified the station and left three things to whoever filled it in.
All three had to be decided to put art on screen, so all three are settled here
rather than in a commit message. Nothing below changes the selection function in
§4 except by adding the tier §4 did not have.

**A second tier, and it is the one §4 was missing.** §4's selection was
`rendezvous(agent_type, numberedStations)` and nothing else, which means *every*
station the room can show is reached by a hash. That is fine for a station that
says nothing and wrong for one that says anything, and §5b item 1 is explicit
that the station is where "relation to what the agent is actually doing" is
supposed to be met — so a station that may not mean anything cannot meet it. The
wardrobe had already solved this and the solution is copied verbatim:

```
station(agent) =
    "main"                                   if agent_id is absent
    "default"                                if agent_type is absent or ""
    roles[agent_type]                        if the manifest names that exact string
    rendezvous(agent_type, assignable)       otherwise
    "default"                                if the pool is empty
```

`roles` is keyed on the **exact** `agent_type` a session produced, so a station
reached through it is the room repeating a name the user chose — the licence the
nameplate has always run on — and it may assert. `assignable` is the hash's
range; arbitrary text licenses no claim, so every member of it carries
`asserts: false` and says only *this is a different agent from that one*. It is
`question_mark`'s answer, furnished. [I1]

`assignable` also replaces §7's "the ids that are numbers" convention. A pool the
hash may reach has to be **stated**, for the reason the wardrobe's is: the naming
habit and the guarantee were the same fact, so renaming a station changed what
the hash could say. The numeric convention survives only as the fallback for a
manifest that predates the list.

**Which agent types the asserting tier is keyed on, and the mistake it is
avoiding.** `characters.costumes.roles` is keyed almost entirely on *this
repository's own invented subagent names* — `test-engineer`, `scene-engineer`,
`art-director`. No user outside this repo runs any of them, so the expressive
half of the wardrobe is addressed to an audience of one. `fixtures/` contains
exactly three `agent_type` values across all 17 captures: `general-purpose`
(165), `Explore` (23) and the empty string (17). The station `roles` table names
those first and this repo's own names second, and
`StationContractTests.everyAgentTypeTheFixturesContainIsTranslatedOrDeliberatelyNot`
reads `fixtures/` rather than a list, so the day a capture carries a fourth type
the suite says so. The empty string is deliberately **not** in `roles`: it takes
the `default` branch before `roles` is consulted, because an agent we cannot name
may not be given a meaning.

**Declared once, under `room.props.stations`, and inherited by every theme.** §7
made stations a per-theme binding, on the reasonable assumption that a station
would be themed art. It cannot be. Only one object in either pack — Modern Office
single 104 — is a chair drawn side-on with its backrest on the left, which is
what the pack's one-directional seated pose requires, so `chair` is not a
variable in any theme; and `04-ART-DIRECTION.md` measured that the desk is 5.7×
to 16.6× the chair's visible area but that every desk in the pack desaturates to
the same pale slab. Six copies of one block would have been six places for it to
drift. A theme that declares its own `props.stations` still overrides the whole
block for itself, all-or-nothing, so §7's per-theme contract is intact and
unused.

**A station overrides the prop, not the furniture.** Every station that ships
declares only `prop`; `desk` and `chair` fall back to the theme's own
`props.roles`, per theme, at decode. That keeps a station from dragging the
Office desk into the library, and it puts the whole of the separation in the one
channel the art we own can actually separate. It is less than §7 allows and it is
what §7 allows *and* the pack supports.

**Two geometric limits, both derived and both now asserted by a test that needs
no art on disk.** A station prop stands one tile to the character's left on a 96px
seat pitch, between the neighbouring desk and the character's own 32px body, so
its content box may be **at most 32px wide** — the same wall the 120px
`control_room_screens` hit at M6c, where widening the canvas was never what was
in the way. A station *desk* is drawn in front of the body, so it may be at most
**44px tall**, which is how far the shortest cast variant's head sits above its
own feet.

**What this does not fix, stated so nobody reports it as new.** Two themes ship a
`props.roles.desk` that would fail both limits — `library`'s is 56×70 and
`mission_control`'s 44×36 — and `library`'s consequently draws over the face of
whoever sits at it. That predates stations, it is drawn at every seat by
`buildRoom()` whether anyone is sitting there or not, and it is theme art rather
than station art. It is recorded in `notes.md` and in `04-ART-DIRECTION.md`
rather than worked around here.

---

## 15. If accepted, these documents are wrong until edited

Out of this change's scope, listed so nothing rots:

- **`04-ART-DIRECTION.md`** — "Body state while working is the sitting pose,
  regardless of tool." Replacement text is in §5a. Also needs §7's theme role
  vocabulary and the side-view chair constraint.
- **`03-EVENT-MODEL.md`** — carries the same sentence at the end of the
  tool→badge section. Same replacement.
- **`02-ARCHITECTURE.md`** — the Configuration section. It currently states,
  correctly and emphatically, that nothing but `settings-backup.json` is
  persisted. §3d changes that, and the paragraph should be edited to name
  `themes.json` rather than softened.
- **`05-MILESTONES.md`** — this is an M6-sized body of work across three agents
  and has no milestone.
- **`CLAUDE.md`** — only if the maintainer promotes I9. §3b.
- **`01-PRD.md`** — edited in **this** change. Not deferred.

The precedent is `CLAUDE.md`'s done-rule 5, and the reason it is spelled out here
is the final verification pass: every defect that pass found was in the one
artefact nobody's tests touch.
