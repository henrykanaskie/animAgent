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
