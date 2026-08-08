# 04 — Art direction

Revised after selecting the source art, **corrected at M0 against the files**,
and corrected again at **M5b when the third pack was bought**. All three LimeZu
packs are now on disk:

- **Modern Interiors** (`assets/moderninteriors-win/`) — characters, the
  character generator, base interiors, and an emote set. Present.
- **Modern Office (Revamped)** — desks, chairs, monitors. The room. Present.
- **Modern User Interface** (`assets/modernuserinterface-win/`) — **purchased at
  M5b.** It is a real application-icon set and it supplied `document` and
  `checklist`. It does **not** contain a magnifier, a globe, a plug or a
  console.

**No further packs will be bought.** That is a decision, taken at M5c, and it
closes the search rather than pausing it. The consequence is recorded here
because it changes what this document is about: **the badge layer is
deliberately mixed provenance.** Two packs supply it — Modern Interiors gives
every badge its speech bubble and gives `question_mark` and `attention` whole,
Modern User Interface is partially mined for `document` and `checklist` — and
the remaining four glyphs, `magnifier`, `terminal`, `globe` and `plug`, are
**authored here**, on the pack's own grid and in the pack's own palette. They
are final art, not scaffolding, and the manifest says `provenance: "authored"`
so nobody has to guess which is which.

Licence terms for the three packs are equivalent in substance — commercial and
non-commercial use permitted, editing permitted, resale and redistribution
forbidden — but **not identical in wording, and the differences matter**:

- Modern Office says credits are *appreciated*.
- Modern Interiors says **credits required (`limezu.itch.io`)**.
- Modern User Interface says **credits required**, and adds a clause neither
  other pack carries: **every permission it grants is "except NFT minting"**.
  It is the only licence term in this project that restricts a *use* rather
  than a distribution, and it travels with the art — anything built out of
  these badges inherits it.

The strictest term governs on each axis. Three consequences that are not
negotiable: `assets/` is gitignored or the repo is private, the credit line
ships in an About panel, and nothing here is minted.

**One credit line still covers all three packs**, because all three are by the
same author and both "credits required" licences name the same destination.
`assets/manifest.json` carries it as `credit.text` — "Pixel art by LimeZu —
limezu.itch.io" — with `credit.packs` listing all three and
`credit.restrictions` recording the NFT clause, so the About panel needs no
change and the term is not lost.

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

The badge layer draws from **two** packs as of M5b. The frame — a 24×34 speech
bubble — is Modern Interiors' own empty emote bubble; the glyph inside it is
either a Modern Interiors emote (`question_mark`, `attention`, cut whole), a
Modern User Interface icon dropped into that frame (`document`, `checklist`),
or, for the four badges no pack draws, a glyph generated here and dropped into
the same frame the same way (M5c — see below). **All seven share one frame**,
and as of M5c that is a fact about the files rather than an intention. The
layering is unaffected: the badge is still one independent sprite above the
head, on one canvas, on one anchor.

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
| `UI_32x32.png` (Modern Interiors) | divides exactly into 18×16 cells, but the artwork is **not cell-aligned** | slice by measured bounds, never by the nominal grid |
| `Modern_UI_Style_1_32x32.png` | divides exactly into 61×43 cells, and every icon is **wholly inside one cell** — but at no fixed offset within it | cell coordinate to find it, bounding box inside that cell to cut it |

The Modern Interiors UI case is the one to be careful with. The speech-bubble
emotes sit at a +4px x offset and are 28–34px tall, so they hang across the cell
boundary below them; cutting on the grid clips every one.
`scripts/process-assets.py` cuts them by connected-component bounding box, which
is reproducible. Do not eyeball offsets — if a future sheet resists this, stop
and report rather than guessing.

**Modern User Interface is better behaved, and was verified rather than
assumed** (M5 found the emote sheet was not cell-aligned, so this was checked
first and not taken on trust). All three of its sheets divide exactly into 32px
cells — 61×43, 49×34 and 51×51 — and 85% of its connected components fit inside
a single cell, the rest being panels, bars and frames that were never
candidates. But the icons are **padded into their cells at no consistent
offset**: of the flat icon block, some start at (8,8), some at (8,10), some at
(4,10), some at (6,8). So the cut is still two steps — the 32px cell locates the
icon and is what makes the coordinate reviewable, and the bounding box inside
that cell is what makes the cut correct. Taking the cell whole would centre
nothing; assuming a fixed pad would clip.

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

**All seven are final art. Three come from a pack and four were drawn here.**
Corrected at M5b, which replaced the claim that six were blocked on buying
Modern User Interface; corrected again at M5c, when the four that no pack draws
stopped being placeholders and were authored.

| Badge | Status | Source |
|---|---|---|
| document | **sourced** — M5b | Modern UI `Style_1` cell (28,22), a page with a pencil across its corner |
| checklist | **sourced** — M5b | Modern UI `Style_1` cell (31,18), a bulleted list |
| question mark | **sourced** — M0b | Modern Interiors emote sheet, blue `?` bubble |
| attention (`Notification`) | **sourced** — M0b | Modern Interiors emote sheet, red `!` bubble |
| magnifier, terminal, globe, plug | **authored** — M5c | drawn by `scripts/generate-art.py` on the pack's 2× design grid, in the pack's four-colour icon palette, inside the pack's own bubble — see below |

The two new badges are **composited, not drawn**: the Modern UI icon is dropped
into Modern Interiors' own *empty* speech bubble at `UI_32x32.png` (164,16,24,34).
That bubble is not a lookalike of the `question_mark` badge's frame — it is the
same 692-pixel component with no glyph in it, proved by differencing the two,
which leaves exactly the `?` and nothing else. So a composited badge cannot have
a different silhouette from one cut whole, and the canvas and anchor did not
move. Both licences permit editing, and the composite is done by
`scripts/process-assets.py`, so it survives a pack update.

The exact coordinates live in `MUI_BADGE_ICONS` in that script and are copied
into every manifest entry — sheet, cell, bounding box inside the cell, frame
rect. Anyone can reopen the same file and disagree.

### The four that stay placeholders, and what was actually searched

M5b rendered and inspected **every 32px cell of all three Modern UI sheets** —
337 distinct alpha masks on Style 1, 283 on Style 2, plus the 28 components that
straddle cell boundaries, plus the gamepad sheet. The pack's entire vocabulary
is 41 flat application glyphs (lock, unlock, 3×3 grid, back chevron, person,
cog, home, list, trash, check, cross, plus, minus, four arrows, sort, refresh,
swap, fast-forward, mail, play, back, up/down triangles, funnel, question mark,
trophy, info, pause, plinth, speaker, mute, sliders, play-in-box, twitter,
facebook, discord, edit, cart), a media strip (monitor, monitor-with-cursor,
phone, image, dropdown, speech bubbles, checkbox, music, mute) and an RPG item
set (gifts, stars, jars, backpacks, hearts, coins, a hand mirror, a closed book,
a gear, a phone-in-hand). All three size sets are the same artwork: the 16× and
48× sheets are exact 0.5× and 1.5× of the 32× ones.

None of it is a magnifier, a globe or a plug. A filename search across all 52726
PNGs in the three packs for `globe|plug|socket|world|search|magnif|terminal|
console|map` returns one hit, `animated_Christmas_snowball_globe` — a snow globe.

The near misses were left alone deliberately, and are named here so nobody
"finds" them again:

- The **hand mirror** at `Style_1` cell (14,9) is a circle on a handle and would
  read as a magnifier at `1x`. It is a mirror, from a fantasy inventory set.
- The **monitor** at `Style_1` cell (19,3) is the only screen in the pack, and
  it sits inside the media strip beside monitor-with-cursor, phone, image and
  speaker — so the pack's own semantics for it are *display*, not *shell*.
  Rejected on that ground and **not** on legibility, which was measured rather
  than asserted: composited into the badge frame it scores glyph IoU 0.31
  against `document` and 0.43 against `checklist`, no worse than pairs already
  shipping.

This is the same call M5 made when it left the cog and the hammer alone rather
than calling them a document and a terminal, and the reasoning has not changed:
picking an icon because it is *sort of* tool-shaped is the same failure as
inventing a badge for an unknown tool. Unmapped tools get the question mark and
are logged — never guess. [I1]

### The four badges no pack draws are authored — M5c

Two things changed at M5c and they belong together.

**First, the frame.** M5b measured that the four unsourceable badges did *not*
reuse the pack's bubble: their frame was a hand-made lookalike with a heavier,
darker border, which is why they read louder than the real badges beside them.
M5b called that harmless on the grounds that a placeholder should be
conspicuous. That was right for a scaffold and wrong here, because — see the
next paragraph — these are not scaffolding. At the `1x` floor the badge row was
speaking two visual languages, four shouting beside four talking, which is I7
failing on the badge layer.

**Second, and it is the bigger change: no further art packs will be bought.** So
calling these four "placeholders" was a claim about a roadmap that does not
exist. M5b's search is finished and its conclusion is not "keep looking", it is
"draw them". They are now **authored final art**: `provenance: "authored"` in
the manifest, a third value beside `pack`, with `authored_because`, `searched`
and `drawn_by` recording how we got here. `placeholder` keeps its meaning
elsewhere — the fallback character set is still one.

**Authoring is not an I1 violation.** I1 forbids the room asserting *data* the
hooks did not give us. It says nothing about who drew the pixels. `PixelFont.standard`
is the precedent: written here rather than sourced, licence-clean by
construction, and M5 closed the "source a pixel font" blocker by keeping it.
What I1 still forbids, and this change does not touch, is inventing a badge for
a tool that is not in the mapping table. Unmapped tools still get the question
mark.

#### How they are drawn

- **The pack's bubble, not a lookalike.** `scripts/process-assets.py` writes the
  empty bubble out to `assets/processed/badges/32x32/_bubble_frame.png` — the
  same 692-pixel component `question_mark` is cut from — and
  `scripts/generate-art.py` composites into those pixels with the same
  centre-the-bounding-box arithmetic the pack composites use. An authored badge
  and a pack badge are now the same construction.
- **The pack's grid.** Dump `document` or `checklist` pixel by pixel and every
  feature is a 2×2 block: the Modern UI 32× sheet is a 2× scale-up of a 16px
  design. A glyph drawn at 1px line weight beside them reads as a different hand
  immediately. So every authored glyph is designed on a half-resolution grid and
  doubled, and the designs are literal ASCII grids in `DESIGN` — reviewable, and
  editable without an image editor. The bubble interior is 20×24, so a design is
  at most 10×12 cells, which forces the simple silhouette that survives `1x`.
- **The pack's palette.** Differencing the two composited badges against the
  empty bubble recovers their ink exactly: four colours, saturation 0.252–0.345,
  value 0.420–0.694. Those four are used verbatim. A palette is a set of
  numbers, not artwork; the manifest is where provenance is claimed. An interim
  draft used a deliberately off-hue slate ramp so a reviewer could spot which
  four were ours — the right instinct for a placeholder and the wrong one for
  final art, whose job is not to announce itself.

The old ink was outside the pack's band in both directions: a 0.610-saturation
globe, higher than variant 06's most saturated pixel (0.598), and a 0.078-value
terminal screen, **darker than the darkest character pixel on screen at 0.314**,
which is the one thing I7 says a non-character layer may never be.

#### Distinguishability, measured before and after

Pairwise IoU of the glyph ink with each state's own bubble subtracted. The
closest pair in the set was `terminal` vs `plug` at **0.56** — both ours, both a
centred blob of the same footprint. `terminal` is now a wide window with a `>_`
prompt and `plug` a narrow two-pin stack, and that pair is **0.16**.

The closest pair in the whole set is now **0.37**, `checklist` vs `terminal`,
one pack and one authored; the closest pack-only pair, `checklist` vs
`question_mark`, is **0.36** and unchanged by any of this. Twelve of the
twenty-one pairs improved, the largest by 0.40; the three that got worse did so
by 0.07 or less and none of them is near the top of the table.

The acceptance test that is not a number is the room shot: at `1x`, above a
character's head, a viewer should not be able to point at which four we drew.

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

   **Re-derived at M5c over every badge, the four authored ones included**, rather
   than inherited from M5b — which checked only the two composited badges and
   drew two conclusions from them that do not survive the wider measurement.
   The exemption holds, but it holds for a narrower reason than M5b claimed:

   - **No badge owns the darkest pixel on screen.** Every badge bottoms out at
     value **0.337**, which is the bubble's own darkest border step, against
     the characters' darkest pixel at **0.314**. This is the axis I7 actually
     protects, and it holds for all eight badges. **It did not hold before
     M5c**: the old placeholder terminal reached value 0.078 and the other
     three 0.180, so the four badges with no source art were the darkest thing
     in the room. That is the strongest reason the retone was not cosmetic.
   - **On saturation the honest statement is narrower.** The six badges we draw
     or composite top out at **0.384** — again the bubble's border, with glyph
     ink at 0.345 and below. But the two emotes cut whole from the pack are
     `question_mark` at **0.710** and `attention` at **0.770**, which is above
     the peak saturation of three of the six cast variants (06 at 0.598, 17 at
     0.621, 19 at 0.748) though below the most saturated character pixel on
     screen (variant 09, **1.000**). M5b's "the badges top out at 0.34
     saturation" was true of the two it measured and false of the set. Those
     two are pack art, they are bright rather than heavy (value 0.82–1.00), and
     repainting real art to satisfy a sentence would be the wrong repair — so
     the sentence is corrected instead.
   - **M5b also claimed the badges "would pass the room's saturation ceiling
     anyway". They would not.** Every badge is over 0.25, the frame alone
     putting it there. The exemption is load-bearing, not decorative.

   If a future badge is ever the darkest thing on screen, this exemption is the
   wrong answer and the badge is.
4. `scripts/lint-palette.py` runs over `assets/manifest.json` after processing.
   Thresholds unchanged: room under 25% saturation, every character carrying
   something above 55%, at least 40% value contrast between a character's
   darkest pixel and the mean room value. **Added at M5, not a relaxation:** the
   assigned accents must each clear 45% saturation and value 0.60, and no pair
   may be within 40° of hue.

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
  room. This holds for the room by construction — it is clamped under 0.18
  saturation — but **it did not hold between the variants, and at M5 the source
  of the hue changed** (below).

But the rule can no longer be the *only* thing carrying identity, because the
source art will not let it. **The nameplate is now load-bearing, not
decoration** — see Typography.

### Accent hue is assigned, not sampled — corrected at M5

Until M5 the scene took each variant's accent by sampling the most saturated
pixel of its own art. M2 measured what that produces: **all six selected
premades land inside a 30° arc of hue, 07 and 17 are hue-identical, and 07/19
differ by 3.5°.** The generator dresses one body in variations of one warm
palette, so there is no sixth hue in the art to find. The sentence "one accent
hue per variant, chosen for mutual separation" was therefore false as written —
it described an intention, not the files.

The manifest now carries `characters.variants.<id>.accent_hex`, **six hues 60°
apart**, assigned in manifest order. Two things make this not a violation of the
verify-before-you-write rule:

- The accent is not a pixel of the sprite. It is the nameplate border, which the
  *scene* draws. Assigning it claims nothing about the artwork.
- `scripts/lint-palette.py` now checks it: every variant must declare one, each
  must clear 45% saturation and value 0.60, and **no pair may be closer than
  40° in hue**. Measured on the shipped set the closest pair is 59.7°. The
  sentence is enforced now instead of asserted.

`TextureStore` keeps the sampling path as the fallback for a manifest without
the field, so an older manifest still renders — with the weak channel it always
had.

### Same-typed agents: the nameplate carries a discriminator — M5

M4 watched three `general-purpose` subagents dispatched together render three
identical `GENERAL-P…` plates. With silhouette refuted here at M0 and accent hue
refuted at M2, they were separable only by seat position — which is S4 failing
for the most ordinary case there is.

The plate for a subagent is now `TYPE:XXX`, where `XXX` is the **last three
alphanumerics of `agent_id`**. `agent_id` is the only field that actually
distinguishes two subagents of one type, and it is data we already hold — so
this is not an invented label. [I1] The main agent has no `agent_id` and so has
no suffix, which is the identity rule rather than an exception.

Two calls worth recording, both made at M5:

- **Always on, never conditional on a clash.** Showing the suffix only while two
  visible agents share a type would rewrite a plate that is already on screen —
  changing a character's *identity* under the user's eye, at exactly the moment
  the room got busy and they are looking at it — and would flicker as the
  visible set changed on every arrival, departure and report walk.
- **8 + 1 + 3 = 12 glyphs**, up from a 10-glyph plate. Three discriminator
  characters rather than two because two hex characters collide across six
  agents about 5.5% of the time and three about 0.4%, and a collision here is
  precisely the failure S4 names. The separator earns its glyph: without it
  `GENERAL3F` reads as one word. `:` because no `agent_type` contains one, while
  `-` appears inside `general-purpose` itself.

Twelve glyphs is 77 px of plate against 96 px of seat pitch and 80 px of
delivery-slot pitch, so neighbours' plates still cannot touch.

Commissioning custom bodies remains the only way to satisfy the silhouette rule
as originally written, and it is still a real cost. Nothing here needs it.

## Typography

Confirmed: **no font ships with either pack** — no `.ttf`, no `.otf`, nothing
font-shaped anywhere in the files. The previews use Arial Bold, and Arial at 8pt
beside this art looks exactly as wrong as it sounds.

M2 wrote a 5×7 bitmap typeface as a constant (`PixelFont.standard`) rather than
sourcing one, and left "source a pixel font" standing as a blocker.

**At M5 that blocker is closed, and the answer is that the font we wrote is the
one to keep.** Judged at `1x` in a six-agent room, which is the size and the
crowd it has to survive: every glyph is on the pixel grid by construction, `0`
carries a slash so it cannot be read as `O`, no two glyphs render identically
(there is a test), and the plates separate six characters at the `1x` floor. A
sourced `.ttf` would have to be hinted or rendered at exactly the right size to
match that, would reintroduce antialiasing next to nearest-filtered art, and
would add a licence to audit. A font authored here is licence-clean *by
construction* — which was the only thing sourcing one was ever going to buy.

It stays one constant and one call site, so replacing it is still local if
anyone disagrees.

## Prop roles — added at M5

The Modern Office singles are named by **index only**. There is nothing to look
up: `00_Modern_Office_Singles.ase` holds one unnamed layer and 339 unnamed
frames, with no slices and no tags, and the two `Office_Design_*.aseprite` files
are the same. So `room.props.identified` was `false` and the room drew hatched
placeholder desks, which was the correct answer while nothing had been checked.

At M5 five roles were identified the only way this pack allows — by rendering
every single onto a contact sheet and looking at it. The role map records the
index so anyone can reopen the same file and disagree:

| Role | Single | What it is |
|---|---|---|
| `desk` | 34 | plain desk, top slab plus two legs |
| `chair` | 104 | office chair, side view, backrest on the left — a person on it faces right, which is the only way this pack's sit animation faces |
| `plant` | 99 | small potted plant, floor standing |
| `board` | 171 | presentation board on a stand, floor standing |

**Placement is by measurement.** The singles are 64×96 canvases with the object
dropped in wherever it sat on the source sheet: they are neither bottom-aligned
nor centred, and the desk's baseline is row 87 while the plant's is row 75 in
canvases of identical size. So each role carries its measured `content_box`, and
the scene puts that box's bottom-centre on a named point. A fixed offset would
have been right for one file and 12 px into the floor for the next.

**The other 334 singles stay unidentified**, and stay out of the role map. A
role nothing draws is an invitation for the scene to guess. Monitors (121–133)
and laptops (139–140) are identifiable too and were deliberately *not* added: a
monitor has to stand on a desk's surface and the art carries no datum for where
that surface is, so placing one would be an eyeballed offset dressed up as
data. [I1]

`SceneBitmaps.placeholderDesk` survives as the fallback for a manifest with no
`desk` role, so the room still draws against an older manifest.

## Composition — corrected at M5

The camera used to fit the room's **nominal** box, `rows × tile` = 192 px. In the
720×400 panel that had two consequences, both wrong for a surface whose whole
job is a glance:

- the ~132 px strip where characters, nameplates and badges actually live sat in
  the middle third, with a flat band of wall above and a flat band of floor
  below;
- **`3x` was unreachable at any population**, because 192 × 3 = 576 does not fit
  in 400. The top rung of the I6 ladder was dead code in the product.

The camera now fits a **content band**, derived from the manifest rather than
written down: from the bottom of the lowest nameplate (a character standing in
the aisle) to the top of the tallest badge. One agent working now fills the
panel at `3x`, which is the case a glance surface exists for.

Two smaller calls in the same pass:

- Vertical slack is biased *upwards*. The band's bottom is reserved for an aisle
  character and most of the time nobody is there, so centring the band spends
  the difference on empty foreground floor. The bias is clamped by the slack the
  scale actually left, so it can never crop a plate or a badge.
- The room is furnished: a desk and a chair at every seat, boards and plants
  alternating along the back wall, and a row of plants in front of the walkway.
  Everything went through the same desaturating import pass as the floor, so I7
  still binds it.
- **Decoration is placed outside the content band on purpose.** The foreground
  row sits strictly below the band, which means it is *out of frame* at the
  tightest fitting scale and only appears as the camera pulls back. That is I7's
  "a background detail competes with the characters at exactly the zoom where
  they are hardest to read" answered geometrically rather than by taste: at
  `3x`, where the characters are biggest and there is no spare room, the
  decoration is not on screen at all; at `1x`, where there is nothing else in
  the foreground, it is.

**Residual, stated rather than papered over.** At the `1x` floor — six agents —
the band is 132 px of a 400 px panel and the bands above and below are still
large. That is forced: with six characters the room is 640 px wide, which only
fits at `1x`, and `1x` makes the band a third of the panel's height. The only
real fixes are a panel whose height tracks the scale (which would make the
drop-down jump as agents come and go) or a fractional zoom (which I6 forbids).

## Placeholders

**Discharged for the badge layer.** Characters, room, furniture and all seven
tool badges are final art as of M5c — three cut from packs, four authored here.
The four that were placeholders through M5b are not any more, and the reason is
not that we found them: no further packs will be bought, so they were drawn.
See the badge section above.

What is still genuinely a placeholder:

- A **fallback character set**, generated only on `--characters`. Not in the
  manifest. It exists so that a missing pack degrades to something that renders
  rather than to a crash.
- `SceneBitmaps.placeholderDesk`, now reached only if a manifest declares no
  `desk` role.

The original instruction stands for anything that goes missing *while something
is genuinely pending*: flat-colour blocks at the correct dimensions and the
correct palette split, and make them look like placeholders. A placeholder that
could pass for final art will survive to M5.

**M5c drew the line that instruction was missing.** Being conspicuous is what
gets a placeholder replaced — it is worth paying for while a replacement is
coming. When nothing is coming, conspicuous buys nothing and costs the user a
badge row that reads as two families every time they glance at the notch. So the
rule is: **if it is waiting, make it loud; if it is permanent, either draw it
properly or say plainly that it is scaffolding for good.** Which of those a
thing is belongs in the manifest, where a reviewer and a test can both read it,
not in how ugly it looks.

## Themed rooms — added after M5c

The maintainer asked for "a cooler environment than a classroom", suggesting
**engineering, rocket ship, classroom**. Two of those are buildable. One is not,
and it is worth saying flatly before anything else:

> **There is no rocket ship, spacecraft, launch pad, capsule, airlock, console
> bank or star field in any pack we own.** All 24 Theme Sorter sets, both Room
> Builder sheets, the 8 Home Designs and the animated-objects set were listed and
> the 24 sets were rendered and looked at. The nearest thing to a spacecraft
> interior in 5330 themed sprites is a shooting-range target on a mast. No
> further packs will be bought, so this is not a scheduling problem — it is the
> shape of what we have. What *is* buildable is a control room, and `mission_control`
> below is that room, assembled out of a hospital and a jail. (It was a
> basement and a shooting range through M6; that version did not read, and
> the M6b section says why.)

### The inventory, and why it had to be rendered

The Theme Sorter sets are named by index only, exactly like the Office singles:
the `.ase` files hold unnamed frames with no slices and no tags. So there is
nothing to look up and no auto-slicer, and the only way to find out what single
164 of set 14 is, is to render it and look. `scripts/contact-sheet.py` does that
and is committed so the work is not repeated from zero.

| # | Set | Files | What is actually in it |
|---|---|---:|---|
| 2 | Living Room | 122 | sofas, wardrobes, side tables, **good large plants (13–18)**, floor lamps (79–88) |
| 3 | Bathroom | 158 | not surveyed |
| 4 | Bedroom | 555 | not surveyed |
| 5 | Classroom & Library | 75 | school desks/chairs (1–30), **chalkboards (27–30, 36, 39)**, globes (34–35), world map (31), **tall bookcases (55–75)**. Note 50–51 have a character baked in — unusable [I1] |
| 6 | Music & Sport | 249 | upright pianos (1–24), grand pianos (28–33), **drum kits (37–42)**, amp cabinets (43–44), guitars (45–59), harps, **mic stands (61–65)**, balls |
| 7 | Art | 46 | paint pots (1–20), bonsai (21), paint-strewn benches (22–29), **easels (34–40)**, framed pictures (41–46) |
| 8 | Gym | 209 | not surveyed |
| 9 | Fishing | 77 | not surveyed |
| 10 | Birthday Party | 29 | not surveyed |
| 11 | Halloween | 240 | not surveyed |
| 12 | Kitchen | 408 | not surveyed |
| 13 | Conference Hall | 68 | **stage curtains (1–24)**, lecterns with screens (29–32), **flip charts (50–52)**, status kiosk (41), fire extinguisher, framed banners, light pools (66–68) |
| 14 | Basement | 240 | mattresses (4–60), crates (64–66), **pool tables (76–81)**, workbenches (85–101), stools (103–156), **flat-screen monitors (163–166)**, tool trays, cables, consoles (167–182), doors |
| 15 | Christmas | 123 | not surveyed |
| 16 | Grocery Store | 483 | not surveyed |
| 18 | Jail | 344 | surveyed at M6b for tall dark equipment only: **two screens stacked on a pedestal (146)** — a surveillance monitor post, and the darkest-in-source prop found anywhere (median value 0.314, the pack's own ink). Cell doors, bunks, barred windows otherwise |
| 19 | Hospital | 532 | surveyed at M6b: **console bench with two wall screens on brackets (315)**, **grey equipment tables (127, 130)**, machines on wheels with screens and button panels (332), supply racks (58, 62), IV stands, beds, lockers. The most control-room-shaped set in the download, and its name is why nobody looked |
| 20 | Japanese Interiors | 131 | not surveyed |
| 21 | Clothing Store | 494 | not surveyed |
| 22 | Museum | 451 | ticket booths, turnstiles, stanchions, **display plinths with vases**, floor spotlights, **framed paintings** |
| 23 | TV & Film Studio | 80 | **film cameras on tripods (1–7)**, **softbox lights on stands (8–11)**, green screens (12–27, unusable — see below), armchairs, ring lights, boom mics, wall monitors (41–47), **director's chairs (54–74)** |
| 24 | Ice Cream Shop | 102 | not surveyed |
| 25 | Shooting Range | 28 | booth counters (1–8), **console terminals (11–14)**, target masts (15–18), rails, **rack units with LED strips (23–28)** |
| 26 | Condominium | 86 | not surveyed |

There is no set 17 in the download. Ten sets were surveyed in full at M6, two
more partially at M6b, and the rest
listed by count; the ten cover every theme below with room to spare, and
rendering the other 3300 sprites would have bought nothing this task needed.

**Green screens cannot ship.** Set 23's singles 12–27 are the most saturated art
in any pack we own. They pass the lint only because the import transform clamps
saturation, which turns them into flat pale-green rectangles — a green screen
that is not green is a rectangle. They are excluded by omission, not by a filter.

### The five themes, and the default

Each theme fills the same four placement slots. **The slot names are not object
nouns.** The scene places a work surface at each seat, a seat, a standing object
on the back wall, and a repeated accent along the back wall and the foreground
walkway, and it looks them up as `desk`, `chair`, `board` and `plant`. Those are
the Office room's words and they are now the interface; a theme filling `plant`
with a stage curtain is the slot doing its job. Renaming them to
`surface`/`seat`/`backdrop`/`accent` would say what they mean and is the right
change the next time the scene is opened — it is a scene change, so it is not in
this one.

| Theme | `desk` | `board` | `plant` | Floor | Reads as |
|---|---|---|---|---|---|
| `office` (default) | Office 34 | Office 171 chart board | Office 99 potted plant | Office builder | the room as it shipped |
| `mission_control` | Hospital 127 equipment table | Jail 146 two-screen monitor post | Hospital 315 console bench under two wall screens | fine square grid, cool | a screen wall over a console row |
| `broadcast` | Office 34 | TV Studio 8 softbox on a tripod | TV Studio 1 film camera on a tripod | pale diagonal | tripods, and nothing else has tripods |
| `library` | Classroom 26 desk with an open book | Classroom 39 green chalkboard | Classroom 57 tall bookcase | wood plank | the classroom that was asked for |
| `stage` | Office 34 | Music 37 drum kit | Music 62 mic stand | herringbone | the only theme whose back wall is not a rectangle |
| `briefing` | Office 34 | Conference 50 flip chart | Conference 1 hanging curtain | large block tile | a hall rather than a workspace |

`chair` is Office single 104 in **every** theme, and that is a finding rather
than laziness: the pack's seated pose faces right and only right, so the chair
must be a side view with its backrest on the left. Office 104 is the only chair
verified to be one. Every themed chair located — the director's chairs in set
23, the school chairs in set 5 — is a front or back view and would seat a
character facing into its own backrest. [I1]

**Recommendation: ship `mission_control`, `broadcast`, `library` and `stage`
alongside `office`.** They separate cleanly at `1x`: a screen wall, a forest
of tripods, floor-to-ceiling bookcases, a row of drum kits. **`briefing` is the
marginal one** — it is buildable, it passes, and it is distinguishable by its
pink block floor and white slabs, but its identity is the weakest of the six and
it is the one to cut if the selector wants a shorter list.

### `mission_control` was rebuilt — M6b

The version above shipped through M6 and **did not read**. It was grey monitors
on a grey floor, and the recommendation that it "separates cleanly at 1x" was
wrong about it. Its own lint numbers had said so — the darkest theme at mean
0.753 and the least contrast margin at 0.439 — and this document recorded that
without drawing the conclusion.

Three separate faults, and it matters that they were separate, because the first
two look like the same fault and only the third explains why every earlier fix
failed.

**1. Two silhouettes, and both were a rectangle on legs.** `board` was Basement
164, a 58×38 flat screen on a low stand; `desk` was Basement 97, a 40×48
workbench with a pale top. One tile apart on the same seat, at `1x`, they merged
into a single horizontal slab, which is why the "bank of displays" never
arrived. `board` is now **Jail 146**, a 30×64 pair of screens stacked on a
pedestal. It is the only floor-standing vertical in any of the six themes, and
it is the shape the theme was always asking for.

**2. A floor that was not a floor.** Address (14,12) measures **0.043** of value
range after the import transform. That is a flat field with a rumour of a
pattern in it, and it is why the room read as the props floating on nothing.
Every floor tile on the sheet was measured post-transform for value range,
gridness (mean absolute neighbour difference, wrapped, so it also scores tiling
continuity) and mean; **(28,8)** is a fine square grid at range **0.090**,
seamless in both axes, and the only cool-toned one that survives the transform.
That last part is doing more work than the pattern: the other five themes are
all warm, so a cool floor is a whole channel of separation that nothing else was
using.

| Theme | floor value range |
|---|---:|
| `stage` | 0.157 |
| `briefing` | 0.110 |
| **`mission_control`** | **0.090** (was 0.043) |
| `library` | 0.063 |
| `broadcast` | 0.008 |

**3. No dark anchor, and the palette transform was the reason — not the
sprites.** Every theme that reads has one dark shape. Mission control's has to
be a screen, and every screen in every pack came out of the import the same pale
grey. That is not a property of the art: **the pack's darkest ink is value
0.314**, and the standard band `[0.55, 0.92]` lifts it to 0.667 whatever the
sprite is, so a screen face, a chalkboard and a desk top all land within a few
hundredths of each other. Four different screens were tried and recoloured
before this was measured rather than assumed.

So `mission_control` draws **its props** on a band floored at **0.46** instead of
0.55. The ceiling is unchanged, so this is a range expansion rather than a
dimming — light pixels barely move, dark pixels drop, and a screen separates
from its own bezel. The wall and the floor tile stay on the standard band: the
wall because it is the largest area and sits directly behind every character,
which is the same reason it is a flat, and the floor because it carries surface
identity by pattern and we can get that from tile choice for free.

`prop_value_floor` is a key in `THEMES` in `scripts/process-assets.py`. **It is
not a manifest key and the scene never sees it** — it is a parameter of the
import, like `SAT_TARGET`, and the manifest carries only the pixels it produced.

What it costs, stated plainly, because it is a spend and not a free win:

| | before | after |
|---|---:|---:|
| theme mean value | 0.753 | **0.741** |
| min character contrast (floor 0.40) | 0.439 | **0.427** |
| darkest room pixel in the theme | 0.667 | **0.604** |
| `board` mean value | 0.717 | **0.642** |
| wall mean − darkest prop pixel | 0.169 | **0.302** |

`mission_control` is still the theme with the least contrast margin, now 0.027
above the floor rather than 0.039. That is the trade and it was made
deliberately: **the check I7 actually cares about is that nothing in the room
out-shouts a character, and the darkest room pixel here is 0.604 against the
characters' darkest at 0.314** — nearly twice the distance. The mean-contrast
check is a proxy for that, it still passes, and it is what stops this being a
free hand. If a future theme wants a lower floor than 0.46 it will fail this
lint, and the lint will be right.

The last column is the one that says whether the work succeeded. `mission_control`
now has **the strongest anchor-to-wall separation of the six** — 0.302, against
`broadcast` 0.216 and `library` 0.212 — where before it had the weakest.

Two picks made and reversed at M6b, recorded so nobody finds them again:

- **Hospital 221**, a reception counter with a monitor on it, is the most
  workstation-shaped object in any pack. It is drawn **top-down**. Every desk in
  this room is a side view because the seated pose is; a top-down counter in a
  side-view room reads as a bathtub, which is what it looked like.
- **Museum 270**, a solid dark counter, was the best dark shape available at
  desk height and was cut for the opposite reason to everything else here: a
  solid 62×42 block in front of a seated character leaves nothing of the
  character but the top of its head. A desk that wins the value contest by
  deleting the cast is not a fix.

`desk` is now **Hospital 127**, a grey equipment table. It was picked on value,
not shape: Basement 97's glass top came out at mean 0.779 — the brightest thing
in the theme — sitting at exactly the height a seated torso occupies, so seven
of them made the desk row the loudest band on screen and the characters the
quietest thing in it.

### A placement bug in `preview-theme.py`, found while doing this — M6b

`prop_origin` was returning `y + (canvas.h - 1 - bottom_row)` for the scene y of
a prop's top row. That expression is the y-*up* offset from the canvas's bottom
edge to the content box's bottom — the correct quantity for SpriteKit's
`anchorPoint`, and `Manifest.swift`'s `anchor(inCanvas:)` computes it correctly.
But this function does not return an anchor. It returns the top row for a
y-*down* blit, which is `y + bottom_row`. The two are measured from opposite ends
of the canvas and agree only for a prop whose content bottom sits exactly halfway
down it.

The error was up to **~80 px at `1x`** — most of two tiles. Every chair and desk
in every theme preview was drawn well below the character sitting on it, and the
themed rooms read as furniture floating in the foreground. **It was invisible
because it was consistent**: every prop was wrong in proportion to how low its
art sits in its own canvas, so each picture stayed internally plausible and only
the relative heights were wrong.

**The scene was never affected** — this is the review tool only. But it is the
tool this document tells you to accept a theme with, so every theme judgement
made from an M6 preview was made against a wrong picture, and the `mission_control`
rework was two iterations in before it was caught. The lesson is the one the
tool's own docstring already carried and did not act on: it says "the geometry is
a transcription, and transcriptions drift", and nothing checked it.

Two picks were made and then reversed by looking at them at `1x`, which is the
only test that counts. Conference Hall 29, the lectern with a lit screen, lost
its body against a pale wall and left a card floating at chest height. Shooting
Range 15, the target mast — the single most "mission control" object either pack
owns — became a smudge behind the desk row. Both are recorded in
`scripts/process-assets.py` next to what replaced them.

### Two facts about the room that this work uncovered

**Of the Office room's 141 builder tiles, the scene can draw exactly 2.**
`TextureStore.roomTileChoice()` accepts a tile only if it is fully opaque *and a
single colour*, then takes the darkest as the floor and the lightest as the
wall. Two tiles pass. So today's room is two flat colour fields and the other
139 tiles are dead weight in the manifest — which is most of why a room drawn
wide reads as empty floor. Every theme therefore declares `builder.floor` and
`builder.wall` explicitly, *and* ships an authored flat of each tone so the
current heuristic still finds something and a theme still renders in its own
tones today. **Reading the declaration instead of searching for it is a small
scene change and it is the one that makes floors themeable.** It is additive:
`room` is untouched and the heuristic remains the fallback.

**The pack's wall tiles do not tile.** Every tile in `Room_Builder_Walls` carries
vertical trim — measured, the left and right edge columns differ on 28–32 of 32
rows for every tile picked — because the sheet draws wall *segments* with
corners, not a wall repeated across a 25-tile room. Tiled horizontally they show
a hard seam every 32 px. So a theme's `wall` is `provenance: "authored"`: a flat
field of the mean tone of a real pack tile, which is recorded beside it in
`wall_pattern_source`. That is also the better answer under I7 regardless — the
wall is the largest continuous area on screen and sits directly behind every
character, which is precisely where a busy pattern competes at the size
characters are hardest to read. The floors *do* tile cleanly and keep their
pattern; the floor is what carries a theme's surface identity.

### Manifest schema

`themes.sets.<id>` has **the same shape as `room`**, and `room` is unchanged —
byte-for-byte the resolved default theme. A scene that learns to select a theme
reads `themes.sets[id]` with the loader it already has; no existing reader
breaks, and `swift test` passes untouched. Every prop is padded bottom-centred
into one 64×96 canvas at import, which is why a single `props.canvas` still
covers them all even though the Theme Sorter singles arrive on tight per-sprite
canvases from 16×96 to 64×96. The per-role `content_box` discipline is
unchanged and is doing more work than before: these singles are not
bottom-aligned in their own canvases either. Selection mechanism is
`docs/ADR-002-themed-rooms.md`, which is not this document's decision.

### Lint

`scripts/lint-palette.py` now measures **every theme separately**, on the same
thresholds, and re-checks character value contrast against each theme's own mean
— pooling them would let a quiet theme carry a loud one, and only one theme is on
screen at a time. Thresholds are unchanged and were not touched.

| Theme | mean value | max saturation (ceiling 0.25) | darkest | min character contrast (floor 0.40) |
|---|---:|---:|---:|---:|
| `briefing` | 0.817 | 0.182 | 0.667 | 0.503 |
| `broadcast` | 0.784 | 0.114 | 0.667 | 0.470 |
| `library` | 0.766 | 0.183 | 0.667 | 0.452 |
| `mission_control` | 0.741 | 0.182 | 0.604 | 0.427 |
| `office` | 0.793 | 0.183 | 0.659 | 0.480 |
| `stage` | 0.786 | 0.183 | 0.667 | 0.472 |

`library`'s two numbers moved at M6c — 0.770/0.456 before — and nothing else in
this table did. That is the whole price of the one animated prop that ships.

All six pass. The saturation column passes **by construction** rather than by
luck — the import transform clamps every room pixel to 0.18 — so the honest
reading of that column is that it proves the transform ran, not that the source
art was tame. The contrast column is the one that could have failed: it is
`theme mean − character's darkest pixel`, so a theme that darkened the room
enough to swallow the cast would fail here. `mission_control` is the darkest
theme and has the least margin, at 0.427 against a floor of 0.40; it is the only
theme that spends any of that margin on purpose, and the M6b section below says
what it bought.

Five of the six numbers in the `mission_control` row moved at M6b and none of
the thresholds did. The five were 0.753 / 0.181 / 0.667 / 0.439 before.

## More than sitting at a desk — M6b

The maintainer asked "is there not props and animations?". There are. Three
things were asked for. **One is buildable and is built, one cannot be built and
the measurement says why, and one needs a manifest key that is not this
document's to add.** All three were settled by cutting the art and looking at it
rather than by reading the pack's filenames.

### 1. Dormancy: the `sleep` body row cannot draw it — the `sleep` *badge* can

A stopped subagent now goes dormant rather than departing, and the ask was to
cut the pack's `sleep` row (row 3, 13 frames) for it.

**Row 3 is not a person asleep at a desk. It is a head on a pillow, drawn from
above.** Six frames, no body below the chin, no direction blocks — and the same
row's frames 8–12 are the pack's own instruction diagram showing the head being
composited onto a **top-down bed sprite**, which is why there is no body: the
duvet is the bed's art, not the character's. `Spritesheet_animations_GUIDE.png`
labels it `sleep` beside that diagram.

Our room is side-on, every seat has an office chair, and no pack we own has a
bed that belongs in it. Importing row 3 puts a disembodied head at chest height
over a chair. It is exactly the failure the verify-before-you-write rule exists
to catch, and it is worth recording that the *name* was right and the *art* was
something else.

**The honest answer was one layer up.** Modern Interiors' UI sheet carries a
blue **`Z` speech bubble** at `UI_32x32.png` (356, 20, 24, 28) — 548 pixels, the
pack's own bubble, the same connected-component construction as `attention` at
(324, 22, 24, 28). It ships as `badges.states.sleep`.

That is the right layer for three reasons, not one:

- **`badges.states` already exists for exactly this.** It is the set of badge
  states that answer to no tool; `attention` is its only other member and was
  put there because no honest body animation existed for `Notification` either.
  This is the same finding a second time.
- **It claims only what the model knows.** "This agent finished a turn and may
  come back" is the dormant flag, which is data. A body pose would additionally
  claim a *posture*, which no event says. [I1]
- **It needs no new key and no new `BodyState` case.** `BodyState` is a closed
  enum in the scene; a seventh case is a Sources change. A badge state is not.

Measured, so the badge exemption's own sentence stays true: `sleep` peaks at
saturation **0.710** and bottoms at value **0.337** — pixel-identical numbers to
`question_mark`, because it is the same bubble and the same blue ink. No badge
owns the darkest pixel on screen and that still holds at eight badges.

### 2. `characters.poses.working` stays empty, and now there is a number for it

ADR-002 §7's pose table is implemented in the scene and absent from the
manifest, so every working character sits identically. The obvious fill is the
pack's second sit row.

**Row 5 is not a second way of sitting at a desk. It is sitting on the ground.**
On the bare `Bodies/` sheet, where no outfit hides the anatomy, row 4 extends the
legs forward — a chair sit — and row 5 folds them under — a cross-legged floor
sit. That much is a description. The number is what settles it:

- Rows 4 and 5 are **pixel-identical for image rows 0–39** of the 64-row frame.
  Every difference between them is in rows 40–63, which is the legs.
- Every theme's desk and chair cover the legs. Cut it, export it, seat the cast
  in it and render all six rooms at 720×400: **96 differing pixels out of
  288 000**, about 24 per character, for a four-agent room. At `1x` it is not a
  different pose; it is the same pose.

So the table is not written. A pose table whose two entries render identically
is a claim that the user cannot see, and shipping one would make §7 look
satisfied while the maintainer's actual complaint — every character sits the
same — remained true. The export was reverted; `CHAR_EXPORT` records why so the
next person does not cut row 5 again.

**What would fill it.** Nothing we own. The remaining rows are `phone_a/b`,
`push_cart`, `pick_up`, `lift`, `throw`, and the seven violent ones. None is
seated, so none can be a *seated* pose whatever it depicts. `phone` is also
refused on meaning, not only on posture: a phone means a call and `WebFetch`
means an HTTP request, and drawing one for the other is the badge-guessing
mistake with a body instead of a glyph. [I1]

### 3. Animated objects: cut, measured, and waiting on one manifest key

> **Superseded by M6c, below.** The `animation` key was approved and one of the
> four objects here ships. Three of the four numbers in the table below were
> wrong and two of the three verdicts were wrong; the M6c section corrects them
> and says how they were caught. It is kept because the shape it proposed is the
> shape that landed, and because being wrong about `old_tv` by a factor of three
> is the argument for generating these figures rather than typing them.

`3_Animated_objects/` is 310 spritesheets and this project had never opened it.
**Unlike every other folder in these packs, they are named** — there is no
render-and-guess step, the file is called
`animated_control_room_server_32x32.png`. Frame width is not in the filename and
every sheet is a single row, so it is measured per sheet and written into
`ANIMATED` in `scripts/process-assets.py`; a wrong frame width still slices into
plausible frames, which is the error that would survive review.

Three were adopted, on a rule stricter than "it looks nice":

| id | for | frames | frame | what | moving px |
|---|---|---:|---|---|---|
| `control_room_server` | `mission_control` | 3 | 32×96 | server rack, three bays of blinking LEDs | 80 of 2240 (3.6%) |
| `pendulum_clock` | `library` | 4 | 32×96 | longcase clock, swinging pendulum | 104 of 2272 (4.6%) |
| `old_tv` | `broadcast` | 6 | 64×64 | CRT on rabbit ears, screen static | 160 of 1544 (10.4%) |

**Every one idles on its own loop and none reacts to an event**, which is
ADR-002 §9's line: scenery that animates in response to activity is the room
asserting something the data did not say. A prop that blinks the same way whether
six agents are working or none claims nothing at all, so it sits in no volatility
band. [I1]

The moving-pixel fraction is in the table because I7 binds harder on a moving
prop than a still one — motion draws the eye and the eye belongs on the
characters. `old_tv` is the loudest at 10.4% and is the one to drop first if a
room reads busy. All three go through the same shadow strip and room transform as
any other prop: max saturation 0.183, darkest value 0.667, both inside the
existing ceilings. `old_tv` carries the Office pack's baked shadow at exactly
`RGB(167,151,150)`, so the existing flood-fill strip handles it unchanged — worth
knowing, because it means the animated folder is the same art pipeline and not a
new one.

All three fit the existing 64×96 prop canvas, which was a selection criterion
and not luck: `control_room_screens` is a 3×3 wall of monitors at **128×96** and
is the single best mission-control object in the download, and it is not on this
list because adopting it would change `props.canvas` for every theme in every
room. That is a scene-visible change and it is not mine.

**Nothing above is in the manifest.** `props.roles.<role>` carries one `file`,
and an animated prop needs a frame list and a rate. The art is cut to
`assets/processed/animated/32x32/<id>/frame_NN.png` anyway, and
`preview-theme.py --animated <id> --frames` stands it in the back row of its
theme and writes one 720×400 PNG per frame — so the decision can be made by
looking, which is this project's rule about art applied to a schema question.

The shape that would be needed, proposed rather than added, so it is one key and
additive and no existing reader breaks:

```json
"roles": {
  "board": {
    "file": "…/frame_00.png",
    "content_box": { … },
    "animation": {
      "frames": ["…/frame_00.png", "…/frame_01.png", "…/frame_02.png"],
      "fps": 4,
      "loop": true
    }
  }
}
```

`file` stays and stays first, so a reader that ignores `animation` draws frame 0
and is correct — the same degradation `characters.poses` already has. `fps` is
per prop rather than global because a pendulum and a rack of LEDs do not tick at
the same rate, and 8 fps (the character rate) makes a 3-frame LED loop strobe.

## Animated props: one ships — M6c

The maintainer approved the `animation` key as proposed and approved widening
`props.canvas` to 128 to admit `control_room_screens`. **One of the four objects
ships, the canvas is back at 64, and every refusal below is a number rather than
a preference.**

### What ships

| id | theme | role | frames | fps | moving px | lint cost |
|---|---|---|---:|---:|---|---|
| `pendulum_clock` | `library` | `board` | 4 | 5 | 64 of 2096 (**3.1%**) | 0.456 → 0.452 |

At 720×400 with four agents seated, one frame of that loop differs from the next
by **192 pixels of 288 000** — 0.067% of the panel. That is a prop that is alive
rather than a prop that waves, which is the line I7 draws once a prop can move.

### What does not, and why

**`control_room_screens` — fails the lint.** `mission_control`'s character
contrast goes **0.427 → 0.363** against a 0.40 floor. It does not spend the
margin, it exceeds it: 6796 visible pixels per frame across 11 frames is more
art than the rest of the theme put together, and the lint pools per file. Two
things about this are worth keeping.

*The canvas was never the obstacle.* Widening to 128 was tried, measured and put
back. Its content box is **120 px wide and the scene draws `board` at four points
96 px apart**, so its copies clip each other by 24 px whatever canvas they arrive
on — at `1x` the wall reads as broken monitors, not as a wall. Every other board
in every theme is 30–64 px, so this is the first object to hit a limit that was
always there. `scripts/preview-theme.py` now warns when a board is wider than the
back-row pitch, because that is a defect no manifest can show you: it only exists
once four copies are on screen.

*What would have to change.* Not the canvas — `RoomLayout`'s back-row pitch, or a
scene rule that a prop wider than the pitch is drawn once rather than per seat.
Both are scene changes.

**`control_room_server` — costs margin this theme does not have.** It composes
cleanly and it is the quietest object in the folder at 3.6%. Adopting it takes
`mission_control` from **0.427 to 0.408**. M6b spent that theme's margin on
purpose, deliberately, to buy a dark anchor; it has 0.027 left and this is not
what to spend it on. Reported rather than spent, which is what was asked.

**`old_tv` — floats, and moves three times as much as anyone thought.** It is a
television meant to stand *on* furniture: there is nothing under it in the art,
and the back row is a floor line, so four of them hang at chest height over
nothing. And it is **364 px of 1304 (27.9%) moving, not 160 of 1544 (10.4%)** —
the M6b figure was transcribed and wrong by a factor of three. It would pass the
lint (`broadcast` 0.470 → 0.462), and that is the point: the lint is a value
check and has nothing to say about motion or about a prop hanging in the air.

### The rule that decided all four

**An animated prop can only occupy `board`, so a theme may hold at most one.**
That is geometry, not preference. The scene draws `board` at the back row's even
seats — four on a 720 px panel — `plant` at the odd seats *and* seven more along
the foreground walkway, and `desk`/`chair` at every seat under a character.
`board` is the only slot where motion is neither in the always-on-screen
foreground row nor sitting on top of a character, which are the two places I7
says a background detail must not compete.

The corollary is the cost that has to be weighed every time: **`board` is also
every theme's identity object and its dark anchor** — the chalkboard, the drum
kit, the two-screen post. Adopting an animated prop spends it. `library` gives up
its chalkboard for the clock, and that is a real loss of the classroom read; the
bookcases in both rows carry the theme without it. `ANIMATED_ADOPTED` in
`scripts/process-assets.py` is one line and emptying it reverts every animated
prop, with the art still cut.

### The frame rate is in the download

**The pack ships a GIF of every animated object beside the spritesheet**, and a
GIF states its own per-frame delay. That is the only place in any of these packs
that says how fast a thing is supposed to move, and M6b's proposed `fps: 4` is
wrong for three of the four:

| id | GIF delay | fps |
|---|---:|---:|
| `control_room_server` | 50/100 s | 2 |
| `pendulum_clock` | 20/100 s | 5 |
| `old_tv`, `control_room_screens` | 10/100 s | 10 |

`scripts/process-assets.py` reads it, and **refuses to cut a sheet whose GIF
disagrees with the table** — on canvas size, on frame count, or on rate. That
also independently confirms the frame *width*, which is not recoverable from a
one-row sheet and which a wrong value still slices into plausible frames. This is
the verify-before-you-write rule applied to time: a frame rate is as much a claim
about the art as a filename is.

A non-uniform GIF delay is a hard skip rather than an average, because one `fps`
cannot describe a loop that holds its frames for different times.

### The key, as landed

```json
"roles": {
  "board": {
    "file": "assets/processed/animated/32x32/pendulum_clock/frame_00.png",
    "content_box": { "x": 16, "y": 6, "w": 32, "h": 72 },
    "animation": {
      "frames": ["…/frame_00.png", "…/frame_01.png", "…/frame_02.png", "…/frame_03.png"],
      "fps": 5,
      "loop": true,
      "fps_source": "…",
      "moving_px": 64,
      "visible_px": 2096,
      "measured_on": "the shipped frames, by scripts/build-manifest.py"
    },
    "source_set": "Modern Interiors 3_Animated_objects",
    "source_sheet": "animated_pendulum_clock_32x32.png",
    "provenance": "pack",
    "what": "longcase clock, swinging pendulum",
    "replaces_static": "assets/processed/themes/library/32x32/singles/board.png"
  }
}
```

Exactly as approved: **one additive object beside `file`, and `file` is first and
is frame 0**, so a reader that knows nothing about animation draws it and is
correct. The scene does not read `animation` yet and nothing about that is a bug.

Four notes on the fields, because three of them are not in the proposal:

- **`content_box` is the union over every frame**, not frame 0's. The scene
  anchors a prop by its box and draws every frame on one canvas at one position,
  so a box describing only frame 0 would be false for the rest of the loop, and
  the foreground-clearance test reads that box's height. For `pendulum_clock` the
  union equals frame 0's box, so the two readings agree and a `file`-only reader
  loses nothing — but that is a measurement, not a guarantee.
- **`moving_px`/`visible_px` are generated, not written down.** They are I7's
  number for a moving prop, and M6b transcribed them wrong twice. Generated
  figures cannot drift from the art.
- **`loop` is always `true` and there is no other value.** ADR-002 §6/§9: a prop
  idles on its own loop and never animates in reaction to an event. Nothing here
  takes input from the delta stream, so a prop blinks the same way whether six
  agents are working or none, and therefore claims nothing. [I1] There is no
  key by which it could.
- **`replaces_static`** names the still prop the theme would otherwise draw. The
  static single is still cut and still on disk, which is what makes reverting one
  line rather than a re-import.

**ADR-002 §9 currently says "Animated props. `3_Animated_objects/` exists and
stays out."** That sentence is now false and the ADR needs an amendment saying
what replaced it — the idle-only rule above. Writing it is not this document's
job and ADR-002 was out of scope for this change; it is flagged here so it is not
lost.

### The prop canvas was widened to 128 and put back, and nothing moved

Both states were built and all six themes rendered at 720×400 with characters:
**0 differing pixels of 288 000, in every theme.** Every lint number was
identical too, to three decimals, in all six.

That is not luck, it is the construction — padding is bottom-*centred* and
placement is by measured `content_box`, so widening adds 32 px of transparency on
each side, every box's `x` gains exactly 32, and the anchor
`(box.x + box.w/2) / canvas.w` is invariant. It was checked in pixels anyway,
because the last placement bug here was a *consistent* error that left every
picture internally plausible, and arithmetic is what produced that bug.

It is back at 64 because the object it was widened for cannot be drawn by the
room at any canvas size, and carrying 128 would double every themed prop texture
for nothing. The proof stands: the widening is free the moment something needs
it.

`scripts/process-assets.py` now also **refuses to pad a sprite that does not
fit** rather than silently writing the overhanging columns onto the wrong rows,
and `scripts/build-manifest.py` refuses to make a role of frames that are not the
declared canvas. Both replace a claim in a comment — "every prop selected was
measured first and fits" — with a check.

## Scripts

| Script | Does |
|---|---|
| `scripts/pnglite.py` | minimal PNG decode/encode, stdlib only. No pip anywhere in this pipeline. |
| `scripts/process-assets.py` | the import pass — room recolour, shadow strip, character slicing, badge cutting and badge compositing. Idempotent; verified byte-identical across a forced rerun. It also writes `assets/processed/badges/32x32/sources.json`, which records the sheet, cell and bounding box behind every badge, and the search result behind every badge that has none, and `_bubble_frame.png`, the pack's empty bubble on the badge canvas. |
| `scripts/generate-art.py` | **renamed from `generate-placeholders.py` at M5c.** Authors the four glyphs no pack draws — on the pack's 2× design grid, in the pack's four-colour palette — and composites them into `_bubble_frame.png`, so an authored badge is the same construction as a pack one. Also draws `document`/`checklist` as the fallback behind pack art, and the fallback cast under `--characters`. Falls back to a hand-drawn bubble only when there is no pack on disk at all. |
| `scripts/build-manifest.py` | generates `assets/manifest.json` from disk, re-stating every path. |
| `scripts/lint-palette.py` | the I7 gate, over `room` **and every theme**, on the same thresholds. Non-zero exit names the file and the value. |
| `scripts/contact-sheet.py` | renders index-named singles onto labelled contact sheets, because the packs ship no names. `--set`/`--office` for singles, `--sheet` to label a Room Builder grid by row-col, `--pick` to confirm specific candidates at 4×. A review tool: it writes to a scratch directory and never touches `assets/`. |
| `scripts/preview-theme.py` | composes a theme at `1x` at the real 720×400 panel, with characters, **from the manifest the scene loads**. A theme that cannot be looked at cannot be chosen. Also a check on the manifest: if this can render a theme, the manifest carries enough for the scene to. `--state` seats the cast in any body state, `--badge` puts a `badges.states` entry over every occupied seat, `--frames` writes one PNG per frame of whatever animated prop the theme carries, and `--animated <id>` is the review path for a candidate the manifest has **not** adopted. Warns when a `board` is wider than the back-row pitch, which is a defect only four copies on screen can show. A prop placement bug was fixed here at M6b — see above. |

Order: process → generate-art → manifest → lint.

`process-assets.py` cuts `assets/processed/animated/` for **every** object in
`ANIMATED`, whether or not the manifest adopts it, so a candidate can always be
stood in a room with `preview-theme.py --animated <id>` and argued about. Only
the ids in `ANIMATED_ADOPTED` reach the manifest. It is pruned like everything
else, so deleting a row from `ANIMATED` deletes its frames on the next run.
