# 04 — Art direction

Revised after selecting the source art, then **corrected at M0 against the
files**. Two LimeZu packs are on disk and a third was assumed and is not:

- **Modern Interiors** (`assets/moderninteriors-win/`) — characters, the
  character generator, base interiors, and an emote set. Present.
- **Modern Office (Revamped)** — desks, chairs, monitors. The room. Present.
- **Modern User Interface** — assumed to be the badge icon set. **Not
  purchased, not on disk.** Six of the seven tool badges depend on it and are
  placeholders until it arrives. See `docs/FINDINGS-M0.md`.

Licence terms for the two packs we use are equivalent in substance — commercial
and non-commercial use permitted, editing permitted, redistribution forbidden —
but **not identical in wording, and the difference matters**: Modern Office says
credits are *appreciated*; Modern Interiors says **credits required
(`limezu.itch.io`)**. The stricter term governs. Two consequences that are not
negotiable: `assets/` is gitignored or the repo is private, and the credit line
ships in an About panel.

A third folder, `assets/Modern tiles_Free/`, is the free sampler of Modern
Interiors. Its licence forbids commercial use **and forbids editing the sprites
for a commercial project**. Nothing in it may enter the manifest, and the import
script must never read it — one non-commercial file contaminates the build.
Delete the folder.

---

## The rule that governs this whole document

**Nothing enters `assets/manifest.json` until it has been located in the
downloaded files.**

Multiple buyers have reported sprites visible in the packs' promotional images
that do not exist in the download — chairs, sofas, a back-view sitting pose.
Specifying a scene around a pose that does not ship is a failure discovered at
M2, when it is expensive.

The rule is now enforced mechanically rather than by care: `assets/manifest.json`
is **generated** by `scripts/build-manifest.py`, which walks the filesystem and
re-stats every path before writing. A path that is not on disk cannot appear in
the manifest, and the palette lint fails on any declared asset it cannot load.

Frame counts, canvas sizes, and pose names below were claims to verify. They
have been verified at M0 and the wrong ones are corrected. Where a claim could
not be checked because the source is absent, it says so.

---

## Three layers

The previous version of this document specified a generic `working` loop with a
12×12 prop overlaid on the character. **That model is dead.** The character
sprites have no documented per-frame hand anchors, and the pack author has
confirmed every outfit was drawn frame by frame — so there is no cheap way to
place a held object correctly across outfits and frames.

Replaced by three independent layers that never fight each other:

| Layer | Source | Carries |
|---|---|---|
| **Body** | Modern Interiors premade character sheets | what the agent is *doing* |
| **Badge** | emote bubble, floating above the head | *which tool* is running |
| **Room** | Modern Office tileset | the setting and the anchor desk |

Nothing is held. Delete every reference to a held prop.

The badge layer was assumed to come from a Modern User Interface pack. It does
not — that pack is not on disk, and one badge comes from Modern Interiors'
emote set while six are placeholders. The layering is unaffected: the badge is
an independent sprite above the head, and where it comes from is a sourcing
question, not a design one.

Placement is by measurement, not eyeball. A character is bottom-aligned in its
32×64 frame and its head starts partway down, so the manifest records
`head_top_px` per variant and the badge anchors its bubble tail to that point.

## Canvas

Every figure below is measured, not assumed.

- Packs ship at 16×16, 32×32, and 48×48. **Use the 32× set.** M0 checked the
  completeness worry and it is unfounded: the Modern Interiors *shadowless*
  singles — the variant this document tells you to prefer — number 5330 at all
  three sizes with zero filename differences. The default shadowed singles do
  vary (16×: 5381, 32×: 5470, 48×: 5296), but 32× is the **fullest** of the
  three, not the thinnest. Characters (20 premades) and the UI sheet ship at
  all three sizes.
- **Character sprites are 32×64 at the 32× set, not 32×32.** They are twice as
  tall as they are wide: a premade sheet is 1792×1312 = 56 columns of 32px by
  20 rows of 64px, plus 32px of unused trailing padding. Anything that assumed
  a square character canvas is wrong.
- Room tiles are **two different shapes** and the manifest keeps them apart:
  Room Builder floor and wall tiles are a true 32×32; the Modern Office object
  singles are **64×96** — a fixed 2×3-tile canvas with the object padded into
  it, bottom-aligned. Do not assume a single is one tile.
- Badges: 24×34, taken from the emote artwork's own bounds. Not a round number
  because it is derived from the art rather than imposed on it.
- Integer render scale only: `3x`, `2x`, `1x`. [I6] `1x` is the floor.
- `.nearest` filtering on every texture. No mipmaps.

**Build from the singles where singles exist — but they do not always exist.**
Modern Office ships 339 object singles and Modern Interiors ships 5330
shadowless ones, and for those the rule stands: the combined theme sheets have
uneven grids and off-grid sprites and you have no auto-slicer.

Three things ship **only** as sheets, and the original blanket rule would have
left the room with no floor, no characters, and no badges:

| Sheet | Grid | Verdict |
|---|---|---|
| `Room_Builder_Office` | exact 32px, no off-grid content | safe to slice — this is floors and walls, and there is no singles alternative |
| Premade character sheets | exact 56×20 of 32×64 | safe to slice |
| `UI_32x32.png` | divides exactly into 18×16 cells, but the artwork is **not cell-aligned** | slice by measured bounds, never by the nominal grid |

The UI case is the one to be careful with. The speech-bubble emotes sit at a
+4px x offset and are 28–34px tall, so they hang across the cell boundary below
them; cutting on the grid clips every one. `scripts/process-assets.py` cuts them
by connected-component bounding box, which is reproducible. Do not eyeball
offsets — if a future sheet resists this, stop and report rather than guessing.

## Body states

**Four** states are sourced directly. Two are composed. One was dropped because
the animation does not exist. None are invented.

Every sheet row is 4 direction blocks laid out **right, up, left, down**. That
order is measured, not assumed: blocks 0 and 2 are pixel-exact mirrors of each
other, and of the remaining two, one shows no skin or eyes in the head band
(back) and the other shows two eyes and a mouth (front).

| State | Source row | Frames per direction | Notes |
|---|---|---|---|
| `idle` | row 1 `idle` | 6 | standing, not at a desk. 4 directions. |
| `working` | row 4 `sit` | 3 | side-view sitting. The desk pose. **Right and left only** — see below. |
| `walk` | row 2 `walk` | 6 | the full pack ships a real walk cycle. The old note about slowing a `run` down does not apply — that was the free sampler. |
| `deliver` | row 10 `gift` | 10 | a handing-over animation. Exactly the `SubagentStop` beat. Does not loop. |

Composed, not sourced:

- **`spawn`** — walk in from the room edge using `walk`. There is no spawn
  animation and inventing one is not worth the cost.
- **`depart`** — the same in reverse.

Dropped:

- **`read`** — there is **no `read a book` animation** in Modern Interiors. The
  guide sheet has 20 pose rows and none of them is reading; the `Books/` folder
  holds six static props for the character generator, not a loop. This document
  already called `read` optional flavour, so it goes. Read-class tools are
  distinguished by the magnifier badge, which is the layer that carries tool
  identity anyway.

Not represented as a body animation, on purpose:

- **`attention`** (`Notification`) — no suitable body animation exists. Use the
  badge alone. A state shown by badge only is honest; a body animation
  repurposed from `punch` or `shoot` would be fiction. [I1] The badge itself is
  now sourced: the red `!` emote bubble.

That is **six** body states in the manifest — `idle`, `working`, `walk`,
`deliver`, `spawn`, `depart` — where this document previously implied seven.
`docs/05-MILESTONES.md` M2 says "all seven animation states play" and should be
read as six until someone sources a reading pose.

Frame rate 8 fps throughout.

The pack also ships `sleep`, `phone`, `push cart`, `pick up`, `lift`, `throw`,
`hit`, `punch`, `stab`, `grab gun`, `gun idle`, `shoot` and `hurt`. None of them
has an event that licenses it. They stay unimported. [I1]

## Sitting is side-view only — confirmed

This was a buyer report. It is now a measurement.

Both sit rows hold 12 frames in 4 blocks of 3. In an ordinary pose row, blocks 0
and 2 are mirrors (the two side views) and blocks 1 and 3 are front and back. In
the sit rows, **blocks 1 and 3 are also exact mirrors of each other** — meaning
all four blocks are side views and the front and back slots were filled with
side art. There is no front-facing and no back-facing sitting pose in the pack,
at any of the three sizes.

**Design the room so desks are viewed from the side.** Do not lay out an office
that requires characters facing away from the camera, and do not put a
back-view desk in the manifest — that sprite does not exist. The side-view
layout is the design, not a compromise to fix later.

The manifest therefore declares `working` with `right` and `left` frames only.
A scene that asks for `working` facing up or down is asking for art that was
never drawn, and should be treated as a bug in the scene.

## Tool → badge mapping

Collapse aggressively. A user cannot distinguish twelve icons at `2x`.

| Badge | Tools |
|---|---|
| document | `Edit`, `Write`, `NotebookEdit` |
| magnifier | `Read`, `Glob`, `Grep` |
| terminal | `Bash`, `BashOutput`, `KillShell` |
| globe | `WebSearch`, `WebFetch` |
| checklist | `TodoWrite`, `Task` |
| plug | `mcp__*` (any) |
| question mark | anything unmapped |

**Six of these seven have no icon.** M0 checked every pack on disk. Modern
Interiors' `4_User_Interface_Elements` is an *emote* set — hearts, `?`, `!`,
sleep `Z`, music notes, moons, a sun, coins, weapons — not an application icon
set. There is no document, no magnifier, no terminal, no globe, no checklist and
no plug anywhere in it. The standalone **Modern User Interface** pack this
document assumed would supply them has not been purchased.

| Badge | Status |
|---|---|
| question mark | **sourced** — blue `?` emote bubble |
| document, magnifier, terminal, globe, checklist, plug | **placeholder**, drawn by `scripts/generate-placeholders.py` |
| attention (`Notification`) | **sourced** — red `!` emote bubble |

The placeholders reuse the pack's speech-bubble frame, so the silhouette does
not change when a real icon replaces one, and the swap is a manifest edit.

Do not substitute a nearby emote for a missing badge. The pack has a cog and a
hammer, and neither of them is a terminal; picking one because it is *sort of*
tool-shaped is the same failure as inventing a badge for an unknown tool.
Unmapped tools get the question mark and are logged — never guess. [I1]

**Multiple open calls:** show the badge for the *lowest-ordinal* tool in the
table, plus a small `×N`. Deterministic ordering keeps the badge stable while
calls interleave; most-recent-wins flickers. [I3]

## The palette rule is now a build step [I7]

I7 was written assuming we authored both the room and the characters. We do
not — the room is a purchased tileset with its own palette, and the characters
come from a generator.

So the rule becomes a **preprocessing pass**, not an authoring instruction:

1. Room tiles are desaturated and value-compressed at asset-import time, by
   `scripts/process-assets.py`, into `assets/processed/`. Both packs' licences
   permit editing.
2. Character sprites pass through untouched. This is not laziness — I7 assigns
   the characters the saturation and the dark values, so running the room
   transform over them would destroy exactly the contrast the lint protects.
3. Badges also pass through untouched. A badge floats above the room rather
   than being part of it, so the room saturation ceiling does not bind it.
4. `scripts/lint-palette.py` runs over `assets/manifest.json` after processing.
   Thresholds unchanged: room under 25% saturation, every character carrying
   something above 55%, at least 40% value contrast between a character's
   darkest pixel and the mean room value.

Measured at M0, after the pass: room max saturation **0.183** against the 0.25
ceiling, room mean value **0.785**, room darkest value **0.659**, weakest
character accent **0.598**, weakest value contrast **0.472**. All pass.

Two numbers in that pass are set by measurement and should not be nudged by
taste. The room's value band is `[0.55, 0.92]`. The **floor** exists so the room
can never own the darkest pixel on screen — with a floor of 0.55 and the
characters' darkest pixel at 0.314, it cannot. The floor was originally 0.45,
which produced a room mean of 0.70 and **failed** the contrast check at 0.386.
The fix was to lighten the room, because I7 says the room is the low-contrast
layer; it does not say the threshold is negotiable. If this lint fails, the art
is wrong.

Do the pass in a script committed to the repo, not by hand in an image editor.
Hand-edited assets cannot be regenerated when the pack updates. The import is
idempotent and verified so — three consecutive runs produce byte-identical
output.

**Shadows.** Confirmed, with a wrinkle. The Office pack's default art bakes an
opaque grey shadow at exactly `RGB(167,151,150)` — established by differencing
the default sheet against the supplied shadowless sheet, 16560 pixels. Modern
Interiors supplies a full shadowless singles set and that is what to prefer
there. Modern Office does **not**: its 339 singles exist in one variant only,
and 225 of them carry the baked shadow, so preferring shadowless is impossible
and the import strips instead. The strip is a flood-fill inward from
transparency through shadow-coloured pixels, not a colour replace, because that
colour is also used as legitimate fill in a few tiles. Measured against ground
truth: 99.4% of shadow removed, 176 legitimate pixels lost, all of them single
pixels on a silhouette edge and invisible at `1x`.

## Character distinctness — the rule survives, but this art cannot satisfy it

**No VM is needed and no generator has to run.** The pack ships **20 premade
characters** at all three sizes, fully animated. Separately, the "generator" is
not an application at all: `CHARACTER_GENERATOR.txt` describes stacking body,
eyes, outfit, hairstyle and accessory layers in any editor that supports layers.
The Windows-only tool named in `THIRD-PARTY TOOLS.txt` is a third-party
convenience, not a dependency. Casting is now a **selection** problem, which is
the pleasant version of this problem.

So the cast is selected, and it was selected by measurement:

- Four premades (01, 02, 03, 05) peak below 0.55 saturation and **fail I7
  outright**. They are excluded — the lint would reject them.
- Of the 16 that qualify, the 6 with the largest minimum pairwise silhouette
  distance are **06, 07, 09, 10, 17, 19**.

Now the uncomfortable part. **This art does not carry identity in silhouette,
and no selection fixes that.** Flattened to solid black, the best available
6-subset differs by only 88 pixels of 2048 at its closest pair — 7.3% of the
two outlines combined. Several premades are silhouette-*identical*: 01 and 02
match exactly, as do 05, 11, 14 and 20. They are the same body with different
hair colour, because that is how a generator cast is built.

The rule stays, because it is right about what reads at `1x`:

- Prefer variants that differ in *outline*, not only in colour. The selection
  above does exactly this, and it is worth doing even at 7%.
- Verify by flattening two variants to solid black. If you cannot tell them
  apart, they are the same character in different colours.
- One accent hue per variant, and that hue appears nowhere in the processed
  room. This holds by construction: the room is clamped under 0.18 saturation
  and every selected character carries something above 0.55.

But the rule can no longer be the *only* thing carrying identity, because the
source art will not let it. **The nameplate is now load-bearing, not
decoration** — see Typography. If a six-agent room proves unreadable at the
resulting zoom [S4], the honest fixes are a stronger nameplate or a
per-character accent that reads at `1x`, not a demand for silhouettes this pack
cannot supply. Commissioning custom bodies is the only way to satisfy the rule
as originally written, and that is an M5-or-later decision with a real cost.

## Typography

Confirmed: **no font ships with either pack** — no `.ttf`, no `.otf`, nothing
font-shaped anywhere in the files. The previews use Arial Bold. Source a pixel
font for nameplates. Arial at 8pt beside this art looks exactly as wrong as it
sounds.

This is no longer a finishing touch. Since silhouette cannot separate the cast
(see above), the nameplate is a primary identity channel and needs to be legible
at `1x`. Choose the font on that basis and check it at `1x` before adopting it.

## Placeholders

Mostly discharged. Characters, room and one badge are real art as of M0. What
remains a placeholder:

- **Six tool badges** — document, magnifier, terminal, globe, checklist, plug.
  Blocked on the Modern User Interface pack. `scripts/generate-placeholders.py`
  draws them at the real badge canvas inside the real bubble frame, so the swap
  is a manifest edit with no code change and no layout change.
- A **fallback character set**, generated only on `--characters`. Not in the
  manifest. It exists so that a missing pack degrades to something that renders
  rather than to a crash.

The original instruction stands for anything else that goes missing: flat-colour
blocks at the correct dimensions and the correct palette split, and make them
look like placeholders. A placeholder that could pass for final art will survive
to M5.

## Scripts

| Script | Does |
|---|---|
| `scripts/pnglite.py` | minimal PNG decode/encode, stdlib only. No pip anywhere in this pipeline. |
| `scripts/process-assets.py` | the import pass — room recolour, shadow strip, character slicing, badge cutting. Idempotent. |
| `scripts/generate-placeholders.py` | draws what no pack supplies. |
| `scripts/build-manifest.py` | generates `assets/manifest.json` from disk, re-stating every path. |
| `scripts/lint-palette.py` | the I7 gate. Non-zero exit names the file and the value. |

Order: process → placeholders → manifest → lint.
