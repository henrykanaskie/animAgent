# ADR-001 — The interactively denied tool call

**Status: ACCEPTED, 2026-08-07** — accepted by the maintainer and implemented in
the same change. Recommendation **(d)** below is the rule that ships; (a), (b)
and (c) remain recorded as rejected and are not implemented.

It changes no close path. `PostToolUse`, `PostToolUseFailure` and
`PostToolBatch` are untouched; what this changed is a *deadline*, which is
tool-keyed policy that already lived in `Reaper`, plus the per-agent marker
state rule 1 needs. See `docs/03-EVENT-MODEL.md` for the shipped contract.

Author: `ingest-engineer`, M6. Written against Claude Code 2.1.224 and the
fixtures as captured at M0c. Every number below is measured from `fixtures/`;
the commands that produce them are in the appendix.

---

## The problem

Click "No" on a permission prompt and **nothing ever closes that tool call.**

`fixtures/permission-prompt.jsonl`, verified line by line:
`toolu_0199hyfQtR1Hf3i3feHZvivV` gets a `PreToolUse`, then no `PostToolUse`, no
`PostToolUseFailure`, no mention in the following `PostToolBatch` (which lists
only the later, approved call), and its turn produces no `Stop`. The Esc-cancel
path behaves identically.

`03-EVENT-MODEL.md` used to say "Every declined permission prompt is that case"
about the `PostToolBatch` path. That is true of the **headless auto-deny** in
`fixtures/tool-failure.jsonl` and **false of every interactive denial**, which
is what a real user hits.

`Bash` carries the 15-minute deadline, rightly — M4 made that case, and a
shorter one abandons real long-running commands mid-run. So today, clicking
"No" on a `Bash` prompt leaves that character typing for **fifteen minutes**.

The replay says it out loud:

```
── permission-prompt.jsonl ─────────────────────────────────
  [   2.056] callOpened       576fc2a1/main Bash(toolu_0199hyfQtR1Hf3i3feHZvivV)
  [   8.090] attentionChanged 576fc2a1/main permission_prompt
  [  57.460] attentionChanged 576fc2a1/main cleared
  ...
  [ 103.461] callAbandoned    576fc2a1/main Bash(toolu_0199hyfQtR1Hf3i3feHZvivV) sessionEnded
```

The call survives from t=2 to t=103, closed only because the session ended. Had
the session continued, it would have survived to t=902.

**It is reapable, so this is not an I4 violation.** The duration is the problem,
not the existence. That framing decides the shape of the answer: **this wants a
deadline change, not a new close path.** A deadline is already tool-keyed
policy that lives in the `Reaper`; the three close paths are verified,
load-bearing, and out of bounds.

## What M6 already changed, and what it did not

The attention badge is wired now, and it **outranks the tool badge**. So while
the dialog is up, the character shows "needs you" rather than a `terminal`
glyph. That is a real improvement to the *visible* symptom and it costs nothing
here.

It does not fix this. After the denial the badge clears on the user's next
prompt, and the character reverts to a working body with a `terminal` badge for
the rest of the fifteen minutes. **The residual is the window from the click to
the deadline**, and it is the whole subject of this ADR.

---

## The three recorded options, measured

### (b) "The next `UserPromptSubmit` closes stragglers" — REJECTED, with data

This is the clean-looking one and it is **refuted by a real capture**, not by
argument.

M4 established that a subagent's result arrives at the main thread as a
*synthetic* `UserPromptSubmit`. In `fixtures/three-subagents.jsonl` two tool
calls are genuinely still running when one arrives:

| Call | Agent | Ran for | Synthetic prompts it survived |
|---|---|---|---|
| `toolu_017StzPCoy…` (`Bash`) | subagent `a3b4487…` | **8.05 s** | 1 |
| `toolu_01NDyNkE17…` (`Bash`) | subagent `a894ded…` | **15.05 s** | 2 |

Rule (b) closes both. Both were working. That is an **early reap, which is
fiction** — precisely the failure M4 corrected when it lengthened `Agent`'s
deadline, and it fails in the direction this project cares about most.

Two attempted rescues, both of which also fail:

- *Scope it to the previous `prompt_id`.* Does not help: the close for
  `toolu_017StzPCoy…` carries the **new** `prompt_id` (`417fd15b…`), not the
  opener's (`558b59f7…`). The synthetic prompt re-stamps everything after it.
- *Scope it to the main thread.* Removes the two counterexamples above, since
  both are subagent calls — but M4 observed `Agent` running **synchronously**,
  where the parent's `Agent` call stays open for the child's entire life. The
  child's report *is* the synthetic prompt. So a main-thread-scoped rule closes
  a synchronous `Agent` call at the exact moment its child reports, which is
  when the parent is most obviously still working. Derived from two documented
  facts rather than captured in one file, and flagged as such.

And the doc's own warning stands: distinguishing synthetic from real by reading
the prompt text is a `01-PRD.md` non-goal ("Reading or displaying
prompt/response *content*"), and it would also be the first thing in this app
to touch the user's words.

### (c) "Consume `PermissionRequest` and pair by tool name" — REJECTED; the rule stays as written

The pairing rule should **not** be narrowed. It is right, and
`PermissionRequest` is a worse join key than the rule's authors could have
known:

- `parallel-tools` proves the general case: five concurrent calls close in a
  different order from the one they opened in.
- `PermissionRequest` offers `tool_name` + `tool_input` and nothing else. That
  pair is **not even unique**. Two `Read`s of the same path, or two identical
  `Bash` invocations, in one batch are indistinguishable — and a wrong join
  closes the wrong call, which surfaces as a character stuck idle while it is
  working. That is the nastier direction, because it looks like nothing is
  wrong.

### (a) "A short deadline for a call sitting at a permission gate" — the right family, but not as written

The brief asks two sharp questions. Answering both:

**Is marking different enough from pairing to be legitimate? Yes.** The pairing
rule governs one operation: choosing which open call a close applies to. Its
purpose is to prevent closing the wrong call. A marker that says "*this agent*
has a call at a permission gate" performs no join at all — it uses `session_id`
and the presence or absence of `agent_id`, which are the sanctioned identity
keys, and it names no `tool_use_id`. It cannot close the wrong call because it
closes nothing. `03-EVENT-MODEL.md` already describes `PermissionRequest` in
exactly those terms: "a *this agent is blocked on a human* signal, not a close
signal." Consuming it as that signal is reading it as what the doc says it is.

**Is "at most one permission prompt open at a time" safe? No — it is untested.**
Six `PermissionRequest`s were captured across all of M0c. Every one is a lone
call in its own turn; none overlaps another. That is not evidence for the
general case, it is evidence that the general case was never exercised. Claude
Code batches parallel tool calls and there is no capture of a batch where two
of them need permission. **Nothing may assume it**, and the recommendation below
does not.

**Why (a) alone still does not work.** Arming a shorter deadline at
`PermissionRequest` cannot distinguish approve from deny — and on the approve
path the tool then runs for its natural duration. A shortened deadline would
reap an *approved* five-minute build at the gate deadline. That is the same
early-reap fiction, moved onto the more common path. Arming alone is not
enough; something has to say which way the human answered.

---

## (d) Recommendation — mark on `PermissionRequest`, act on `UserPromptSubmit`, change only the deadline

Each of (a) and (b) fixes the other's flaw. (a) has a reliable arming signal and
no way to tell approve from deny; (b) has a discriminator and no way to know
whether it is looking at a real prompt or a synthetic one. Conditioning (b) on
(a) removes both problems.

**The rule:**

1. **Consume `PermissionRequest` as an agent-level marker.** On arrival, record
   for that agent: *a permission gate is open, and these are the `tool_use_id`s
   this agent had open at that instant.* No join by name, no join by recency, no
   `tool_use_id` read from the event — it does not carry one. The marked set is
   simply the agent's open-call set, which we already hold.
2. **The mark is disarmed** by any close of any call in the set (approve: the
   gated call closes normally), or by `Stop` (the turn completed).
3. **If a `UserPromptSubmit` for that same agent arrives while the mark is still
   set**, every call still open from the marked set has its deadline pulled in
   to `now + G`. **Shortened, not closed.** The close paths are untouched; the
   reaper still does the closing, still emits `.callAbandoned`, and the
   character still just returns to idle.

**Why this is the discriminator the data supports.** A denial ends the turn with
no close and no `Stop`, and the very next thing in the stream is the user typing
again — that is exactly the fixture. An approval closes the call, which disarms
the mark before any prompt can act on it.

**Why the synthetic-`UserPromptSubmit` hazard is defused rather than ignored.**
For a synthetic prompt to trigger the shortening, the same agent must be sitting
at a permission gate at that moment. The two captured counterexamples are
subagent calls with no gate anywhere near them — untouched. The synchronous
`Agent` case is structurally excluded: a main thread blocked inside a
synchronous `Agent` call is not simultaneously raising a permission prompt.

**G = 60 s, and the number has data behind it.** The only thing G must survive
is the gap between a synthetic `UserPromptSubmit` and a genuinely-running call's
close. That gap is measured: **8.05 s and 15.05 s**, the two straddles in
`three-subagents`. 60 s is four times the largest observed. It reduces the worst
case from **900 s to 60 s — 15×** — while leaving four times the observed
head-room. It is a number to revisit with more captures, and it is recorded as
such rather than as a constant of nature.

### What it costs

- One more consumed event, so `PermissionRequest` stops being counted as
  unhandled. The unhandled counter's job is to notice the hook surface growing;
  losing a name from it is a small real loss.
- Per-agent state that is not a call: an armed flag and a set of ids. It must be
  cleared on `SessionEnd` and on agent departure like everything else, and it is
  one more thing to reap.
- It marks **all** of the agent's open calls, not the gated one, because nothing
  names the gated one. See the first risk below.
- Complexity. This is three rules where the project currently has one. That is
  the strongest argument against it and it should be weighed honestly: a reader
  six months from now has to hold "marked", "disarmed" and "shortened" in their
  head to reason about a deadline.

### What it could get wrong

1. **A main-thread parallel batch mixing a gated call with a genuinely long
   sibling.** The sibling is marked too, so if a `UserPromptSubmit` lands while
   the mark is set, it is reaped 60 s later rather than at its own deadline.
   Early reap, i.e. fiction. Narrow — it needs a batch where one call is gated
   and another legitimately runs past 60 s after the user's next prompt — but
   real, and it is the recommendation's one genuine hazard.
2. **A queued prompt during a long approved call.** If the TUI emits
   `UserPromptSubmit` when the user *types* rather than when the turn picks the
   message up, a user who types ahead during an approved five-minute `Bash`
   would arm nothing (the mark is disarmed on close, not before) — unless a
   *second* gate opened. Believed safe; **unverified**, and it is on the
   confidence list below.
3. **`PermissionRequest` for a subagent is unobserved.** Every captured one is
   main-thread. If it carries `agent_id` the rule works unchanged; if it does
   not, a subagent's gate would mark the main thread instead, and the wrong
   agent's calls would be shortened. **Unverified.**

   *As shipped:* attribution goes through the ordinary identity rule and nothing
   else, and it is asked in exactly one place —
   `WorldModel.gateOwner(of:)` — whose doc comment names this risk. It returns
   an optional `AgentRef` and its one caller already handles `nil`, so if the
   capture says subagent gates carry no `agent_id`, the correction is a new body
   for that one function (most plausibly: mark nothing when attribution is
   unknown, since marking the wrong agent is the failure being avoided). No
   workaround was invented for a fact we do not have. [I1]
4. **`PermissionRequest` might stop firing, or start firing for things that are
   not gates.** The whole mechanism rests on one unhandled-until-now event
   observed six times.

### What would have to be true for me to be confident

Four captures, none of which needs new tooling — `tools/pty-capture/ptydrive.py`
already drives an interactive session and answers a dialog:

1. **A denial with a parallel main-thread batch.** Two `Bash` calls in one
   assistant turn, one denied and one long-running. Settles risk 1 and settles
   whether two `PermissionRequest`s can be outstanding at once.
2. **A subagent permission gate.** Settles risk 3 — does `PermissionRequest`
   carry `agent_id`?
3. **A queued prompt during a long approved call.** Settles risk 2 — when does
   `UserPromptSubmit` fire relative to the user's keystroke?
4. **A denial in a session that then keeps working**, rather than one that ends
   40 s later. `permission-prompt.jsonl` ends before the deadline could have
   mattered; a capture where it does is what would prove the fix.

`permission-prompt.jsonl` should join the required fixture set when this is
implemented, because it is the fixture that would prove it. Note that it does
**not** replay to zero open calls without the reaper today, by nature, exactly
like `killed-session` — and under this recommendation it still would not. What
would change is the number: 900 s becomes 60 s.

*It joined the set in this change*, in `docs/03-EVENT-MODEL.md` and in
`Fixtures.required`. All four captures above remain outstanding; none of them
blocks the rule, and each would settle a risk rather than change the design.

---

## As implemented — 2026-08-07

Everything below is where the three rules actually live, so that a reader
holding this document can find them without a search.

| | |
|---|---|
| `HookEvent.Kind.permissionRequest` | Decodes the event. **Carries no payload** — deliberately, so that `tool_name` is not even in reach of a future join. |
| `WorldModel.AgentState.permissionGate` | The mark: `Set<ToolUseID>?`, `nil` when disarmed. Held *inside* the agent's state, which is what makes `SessionEnd`, departure and the idle sweep clear it by construction rather than by three pieces of housekeeping. [I4] |
| `WorldModel.gateOwner(of:)` | Rule 1's attribution, and the seam for risk 3. |
| `WorldModel.armPermissionGate(ref:)` | Rule 1. Emits no delta. |
| `WorldModel.removeCall(_:ref:)` | Rule 2's first half. The one point at which a call leaves an open set, whichever path asked — which is why the disarm is there and **not** in any of the three close paths. |
| `WorldModel.disarmPermissionGate(ref:)` on `.stop` | Rule 2's second half. `Stop` still emits nothing. |
| `WorldModel.answerPermissionGate(ref:at:)` on `.userPromptSubmit` | Rule 3. Rewrites deadlines; closes nothing, emits nothing. |
| `Reaper.permissionGateGraceInterval` | **G = 60 s**, with the measurement that produced it. |
| `Reaper.shortenedDeadline(_:answeredAt:)` | `min(existing, now + G)`. |

Two decisions the recommendation above did not spell out, taken here and
recorded rather than left in the code alone:

- **Rule 3 pulls in only; it never pushes a deadline out.** "Pulled in to
  `now + G`" is read as `min(existing, now + G)`, so a marked `Read` keeps its
  own 30 s rather than being granted 60. A rule that exists to shorten
  deadlines must not be able to lengthen one.
- **A second `PermissionRequest` re-marks with the set as it stands then.** This
  document is explicit that "at most one gate outstanding" is untested and must
  not be assumed; taking the later snapshot is the conservative reading of an
  agent that is blocked on something.

`PermissionRequest` is consumed but **not yet registered** in
`HookInstaller.events`, so in a normal install it does not arrive and this rule
cannot fire. That is deliberate: no capture records which matcher shape this
event answers to, and this project's rule is that a registration shape is
captured rather than guessed — a wrong one is a hook that silently never fires.
It is the one step left, and it is one line in two files once the capture lands.

---

## The alternatives, and why I did not recommend them

**Do nothing; leave it to the reaper.** Legitimate, and cheapest, and I do not
recommend it: fifteen minutes of a character typing after a two-second
interaction is the signature bug of this project on the most ordinary
interaction there is. M6's badge work narrows the *visible* symptom during the
wait but not after the answer.

**Shorten `Bash`'s deadline globally.** The one-line fix, and I recommend
against it. `Bash` is `npm test`, `swift build`, `cargo build` — commands that
legitimately run for many minutes. Shortening it trades fiction on the denial
path for fiction on the long-build path, which is at least as common, and it
directly reverses the reasoning M4 used to lengthen `Agent`. **If the maintainer
wants a one-line change anyway**, the least-bad version is not a global shorten
but rule 1 + a fixed gate deadline applied only to calls marked at a
`PermissionRequest` — which is this recommendation minus the discriminator, and
it pays for that simplicity by reaping approved long calls early.

**Wait for `PermissionDenied`.** The name exists in 2.1.224's event array and
would settle this outright. It has **never fired** — registered over both HTTP
and `command` delivery, tested against both denial paths a user has. The
condition that emits it is unknown. Not a plan.

---

## Appendix — reproducing the numbers

```
./.build/debug/spriteroom-replay fixtures/permission-prompt.jsonl
```

shows the orphaned `Bash` closing only at `SessionEnd`. The straddle table came
from walking `fixtures/three-subagents.jsonl` and, for every call, counting the
`UserPromptSubmit`s between its `PreToolUse` and its close:

| Call | Tool | Agent | Duration | Prompts straddled |
|---|---|---|---|---|
| `toolu_017StzPCoy…` | `Bash` | `a3b448736697956e7` | 8.051 s | 1 |
| `toolu_01NDyNkE17…` | `Bash` | `a894ded5b0c4b18de` | 15.049 s | 2 |

No call in any other fixture straddles a prompt, and no *main-thread* call in
any fixture does — which is why the main-thread-scoped variant of (b) has to be
refuted by reasoning from M4's synchronous `Agent` rather than by a fixture.
