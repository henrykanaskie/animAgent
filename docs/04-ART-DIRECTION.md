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

> **Half of that paragraph was refuted at M6g, and the half that was wrong is
> the half about the pack.** The reasoning above is right about *anchors*: there
> is no per-frame hand anchor anywhere in the download, and an arbitrary prop
> still cannot be placed against this art. It is wrong that the pack therefore
> offers nothing. `Character_Generator/Books/`, `/Accessories/` and
> `/Smartphones/` are **overlay layers drawn on the character sheet's own
> geometry** — 1792×1312, frame for frame, pose for pose — so they need no
> anchor at all: composite the sheet and every frame lands where the artist drew
> it. That was measurable at M0 from the file sizes alone and was not measured,
> and the consequence is that this document said "nothing is held" for six
> milestones on a premise that does not survive a `stat`.
>
> **The conclusion survives anyway, for a different and better-evidenced
> reason**, which is the whole point of separating the two: the held layers
> cover **only front-facing standing poses**, and this room draws a side-view
> seated character and nothing else. See "The generator's overlay layers" below
> for the coverage table, the pictures and the numbers. Reaching the right
> answer from a wrong premise is not the same as being right, and the difference
> is what cost the product its third layer.

Replaced by independent layers that never fight each other:

| Layer | Source | Carries |
|---|---|---|
| **Body** | Modern Interiors premade character sheets | what the agent is *doing* |
| **Costume** | the character generator's outfit sheets, on the body's own frames | what the agent *is* — keyed on `agent_type`. Added at M6h; see "Costumes" below |
| **Held object** | authored on the pack's grid, placed on a **measured** hand anchor | *which tool* is running, in the hands. Added at M7b; see "Held objects" below |
| **Badge** | emote bubble, floating above the head | *which tool* is running |
| **Room** | Modern Office tileset | the setting and the anchor desk |

> **"Nothing is held" was the rule from M0 to M7b and it is now wrong.** It
> survived on two claims. The first — no held art exists — was refuted at M6g
> and the refutation stands: the pack draws a held book and a held phone, on
> rows 7 and 6, and `Character_Generator/{Books,Smartphones}` repaints them. The
> second — the room cannot use them, because those two rows are front-facing
> standing poses and this room is side-view seated — is **still true and is not
> disturbed by anything below**.
>
> What was never checked is the step between them: *therefore no object can be
> placed at all*. That rested on "the sprites have no per-frame hand anchors",
> which is true of the download and does not finish the argument, because **on
> the one pose this room draws the hands do not move**. There is nothing to
> anchor per frame. The measurement is in "Held objects" below and it is one
> box, `x 14…17, y 52…55`, identical on all six cast variants, all three `sit`
> frames and both facings — 36 frames agreeing to the pixel. The rule outlived
> its own premise by seven milestones, which is what a conclusion does when
> nobody re-derives it after the reason changes.

The costume layer is a *worn* one and is a different question again: it says
what the agent is rather than what it is doing, and it is keyed on `agent_type`
rather than on a badge class.

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

- **`spawn`** — walk in using `walk`. There is no spawn animation and inventing
  one is not worth the cost.

  It said "from the room edge" until M6, and that was true of the aisle layout
  it was written for. The room is a lattice now: **every vertical move goes
  upstage**, so a character walks in down its own seat's column from its ring's
  delivery row, and out the same way. The edge is not involved, and the start
  point is inside the frame by construction — which is how M5's "the walk-in is
  visible from its first frame" survived the change instead of being traded for
  it.
- **`depart`** — the same in reverse, fading over the last leg. There is no
  frame edge behind the desks to leave by and a flat wall gives nothing to
  disappear behind, so the fade is the honest end of an upstage exit rather
  than a stylistic choice.

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
| magnifier | `Read`, `Glob`, `Grep`, `ToolSearch` |
| terminal | `Bash`, `BashOutput`, `KillShell` |
| globe | `WebSearch`, `WebFetch` |
| checklist | `TodoWrite`, `Agent`, `SendMessage` |
| plug | `mcp__*` (any) |
| question mark | anything unmapped, and `Monitor` deliberately |

**`docs/03-EVENT-MODEL.md` owns this table; this is a copy for the art.** It
said `Task` until M6 — the hook payload has always carried `Agent`, and `Task`
is the model-facing name that never appears in one. `ToolSearch` and
`SendMessage` were mapped at M6 from a walk of every `tool_name` in `fixtures/`,
and `Monitor` was left at the question mark on purpose: its schema takes either
a shell command or a WebSocket, mutually exclusive, and a badge keys on the name
alone, so `terminal` would claim a shell for what may be a socket. [I1]

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
   may be within 40° of hue. **Added at M6d, also not a relaxation:** a motion
   budget — everything a theme animates, counted once per copy the room draws,
   must change fewer pixels per second than the quietest looping animation in
   the cast. See "The motion budget" below. All the colour numbers are
   bit-identical across that change.

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

**A costume does not rescue this, and M6h measured it rather than hoping.** An
outfit layer adds 0-16 px of silhouette to a seated body out of ~1000, so the
twelve shipped costumes are silhouette-*identical*: 0.00% at their closest pair
against the undressed cast's 4.15%. What a costume buys is a ~100 px block of
the sprite changing value and hue, which is a real channel and a different one.
See "Costumes" below.

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

### The plate leads with the type — M7d

The section above is why the discriminator exists and it is still right about
that. What it left unsettled — and what the two-row plate then got backwards —
is **which of the two halves the plate leads with.**

Between M5 and M7d the plate was a saturated accent band carrying the
discriminator at 2×, with the type at 1× underneath. So the loudest element in
the room said `430`, `A69`, `2D4` — the last three hex characters of an
`agent_id` — and the half that answers *what is this agent* read `GENERAL-P…`
beneath it at half the size. The maintainer's complaint that started this line of
work was "the agent names should also be better differentiators, they are hard to
read"; M5 improved the legibility of the plate and inverted its hierarchy while
doing so.

**The type is the identity and the discriminator is the tiebreaker.** So:

| | band (top row) | dark row |
|---|---|---|
| before | discriminator, 2× | `agent_type`, 1×, 10 glyphs |
| after | `agent_type`, 1×, **11 glyphs** | discriminator, 1× |

The main agent has no `agent_type`, so its `MAIN` is what goes on the band —
which is the identity rule read once, not a special case, and it means every
character's band carries whatever name that character has.

#### No amount of magnification was available to the type, and this was measured

The type could not simply take the 2× the discriminator gave up.

- **Horizontally there is nothing to spend.** A plate is 6 px of frame plus its
  text, and 11 glyphs at 6 px each is 71 px against a 96 px seat pitch — a 25 px
  gap. Twelve glyphs is 77 px and a 19 px gap, which is the exact width that read
  as *nearly touching* at the wide default. At 2× the same 66 px of interior
  holds **five** glyphs: `GENE…`, `SECU…`, `CLAU…`. That is not an
  identification, and it collapses `claude-code-guide` onto every other
  `claude-code-*`.
- **The two seat rows do not buy any width, though they look as if they should.**
  Ring parity puts adjacent columns on different rows, so no two *seated* plates
  share a horizontal strip at all. But a back-row character walking down its own
  column to the aisle crosses the front row's line one pitch from a front-row
  seat, and two reporters of one ring stand a pitch apart on the same delivery
  row. Both are same-row pairs at exactly one pitch. The pitch is still the
  bound. [`RoomLayout.isBackRow`]

  > **Stale figures, named rather than quietly corrected.** The plate width these
  > arguments quote is **77 px** in three places — the "stagger" paragraph and
  > the "seven seats" paragraph in this document, and the matching doc comments
  > on `RoomLayout.seatCapacity` and `RoomLayout.isBackRow`. It was 65 px after
  > the rows split and it is 71 px now. Every conclusion survives the correction
  > with room to spare (a half-pitch is 48 px, which clears neither number), so
  > nothing in the layout is wrong; the numbers are. They are left for the change
  > that owns `RoomLayout` rather than edited from here, because a clearance
  > argument should be re-derived by whoever is holding that file, not patched by
  > whoever noticed.
- **Vertically it fits, and it does not work.** A 1×-wide, 2×-tall headline holds
  eleven glyphs and doubles the ink, and it was implemented and rendered into a
  seven-agent room at `1x`. It is *less* legible than 1×, not more: a 5×14 cell
  keeps 1 px vertical strokes against 2 px horizontal ones and keeps 1 px of
  tracking beside a 14 px glyph, so a word closes up into a picket fence and
  `MAIN` reads as `MFIN`. This face is designed on a square grid and survives
  being scaled only on both axes at once. The non-uniform `scaleX`/`scaleY` that
  was added to `PixelFont` for it has been taken back out rather than left
  available.

So the hierarchy is carried by **position and field**: the type is on the
saturated band, which is the plate's loudest element and the first thing a glance
lands on, and the discriminator is on the dark row beneath. The plate is 21 px
tall where it was 26 — the type's row keeps 2 px of air each side instead of 1,
because a band cut tight to a 5×7 face reads as letters jammed into a strip.

**The discriminator stays, always on, and none of M5's reasoning about it
changes.** Two `general-purpose` subagents are still separated by it; two agents
whose *types* truncate to the same eleven glyphs — `claude-code-guide` against a
hypothetical `claude-code-runner` — are separated by it too, which is a second
job it turned out to be doing all along. What changed is its size, not its
presence.

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

> **Two paragraphs above are out of date and the section below replaces them.**
> The "row of plants in front of the walkway" was removed from the scene at
> `4e7b43d` and the "decoration is placed outside the content band" argument went
> with it — see `RoomScene.buildRoom` for the rule that replaced it. And the
> residual's third sentence names two fixes it calls the only real ones; a third
> one existed and is what the section below does. Everything above about the
> **content band** itself still holds and is still what the camera fits.

## Composition, again: the room has depth now

The camera stopped pulling in on a small population: `1x` is the only scale a
normal room uses, so the panel is a fixed 720×400 window on the room and the
only question composition can ask is **what is inside that window**. Answering
"the zoom" had left the answer to "the picture" untouched, and the picture was
this: four characters in a 64 px band across the upper middle, a flat grey field
above them, and a third of the panel of bare floor below. About 28% of the frame
carried anything at all.

Three faults, and they are separate:

**1. Everyone was on one line.** Every seat stood on `baselineY`. Seats now sit
on **two rows a character's height apart**, and which row is *the parity of the
seat's ring*.

That last clause is the whole of why it is free. Seats fill outward in pairs, so
ring parity along x is perfect alternation — columns in x order are seats
6, 4, 2, 0, 1, 3, 5, rings 3, 2, 1, 0, 1, 2, 3 — and sending odd rings upstage
puts the occupied columns in a checkerboard **without moving a single column**.
Every clearance argument in `RoomLayout` rests on one number, *any two seats are
at least a seat pitch apart in x*, and the fold does not touch x at all. The two
crossings it adds — a front-row character walking upstage out of the room across
the back row's line, a back-row character walking down to the aisle across the
front row's — both happen inside the character's own column, and a column is a
pitch from every seat.

**A stagger is not this, and does not survive its own arithmetic** — re-derived
here rather than taken on trust, because the two ideas look alike. A stagger
nudges alternate seats by some offset `s` and keeps the columns closer together.
Two plates clear if they miss in x *or* miss in y. In y a plate is 26 px tall and
the grid step is 32, so the only offsets available are 0 or a whole row, and
everything strictly between is inside the 6 px of slack a row leaves over a
plate — an `s` in that range separates nothing. In x, halving the pitch to buy
the packing a stagger is for gives 48 px against a 77 px plate, which overlaps.
So a stagger either does nothing or is not a stagger: `s` of a whole row **is** a
second row, which is what this does, and it keeps the full 96 px pitch instead of
trading it away.

**Depth is free where width is not**, because two rows a character's height apart
cannot share a horizontal strip at any x. This is the same lesson the lattice
taught about the aisle.

**2. The decoration was in one strip, on one side.** The role was picked on
`seat % 2` — and seats fill outward *in pairs*, so `seat % 2` is not
"alternating", it is **which half of the room**. All four backdrops stood left of
centre and all three accents right of it; the room read as two rooms stitched at
the centre line. The roles now alternate along **x**, which gives the same four
and three — the counts are what the motion budget is priced on, so the
rearrangement had to be free — spread across the whole width.

They also stand at **two depths**: backdrops against the wall, accents a tile
behind the back seat row, alternating, so the upstage half of the room has a near
edge and a far edge instead of a single line.

**3. The wall was a flat field with nothing on it, and nothing could go on it.**
A theme's wall tile is an *authored flat* — the pack's own wall tiles carry
vertical trim and seam every 32 px when repeated across a 25-tile room — and no
pack we own draws anything that hangs on a wall. So the 36% of the panel above
the tallest badge could not be filled; it could only be **converted**. The floor
went from four rows to **seven**, which moves `wallBaseY` from 128 to 224 and
turns that dead band into floor, which is something objects can stand on. The
wall keeps a deliberate ~84 px of the frame: enough to read as a wall, not enough
to be the subject.

Measured on the 720×400 panel, `cameraY` clamped at 108 so the frame is
`[-92, 308]`:

| | before | after |
|---|---:|---:|
| `cameraY` | 93 | 108 |
| frame | `[-107, 293]` | `[-92, 308]` |
| frame carrying characters or furniture | 113 px (28%) | ≈250 px (63%) |
| wall in frame | 165 px (41%) | 84 px (21%) |
| …with nothing standing against it | all of it | none of it |
| seat rows | 1 | 2 |
| decoration depths | 1 | 2 |
| decoration confined to one half of the room | yes | no |
| foreground below the frame's own content band | 15 px wasted | 0 |

The "carrying characters or furniture" row is the top of the tallest backdrop
minus the bottom of the lowest seated plate, so it moves with the theme: 234 px
for `office`'s 46 px chart board, 268 px for `broadcast`'s 80 px softbox.

**What is left, and it is not small: 128 px — 32% of the panel — is foreground
reserve.** The frame's bottom edge sits exactly on `contentBand.bottom`, which is
the lowest pixel of a nameplate belonging to a character on the **outermost
delivery row**. Nothing is wasted there; it is simply empty whenever nobody is
walking, which is most of the time.

It is forced by arithmetic and the arithmetic is worth writing down, because the
obvious fixes do not work:

- The camera cannot go higher. `cameraY` is already clamped at `band.bottom +
  half`; one pixel more crops a plate.
- Making the band's bottom follow the deepest *occupied* ring buys 16 px, because
  the upward preference binds first — and it costs a vertical camera jump on
  every arrival that opens a new ring.
- There are three delivery rows because three same-side reporters (seats 1, 3, 5)
  must not share one, they must be a tile apart for their plates to clear, and a
  tile is the grid. None of the three is negotiable.
- Nothing decorative may be drawn there. That is not timidity — it is where every
  arrival, departure and report walk happens, and a prop in a corridor is a prop
  a character walks through.

The one fix that would work is a change to the report beat itself: deliver
*upstage* of the seat rows rather than downstage, which would free the whole
foreground. That is a redesign of the choreography and its safety proof, not a
composition change, and it is not this one.

## Seven seats, and what the room says about the eighth agent

The room has **seven seats and cannot honestly have more.** Until this was
fixed it drew an eighth agent anyway, on top of the first: `RoomLayout`'s
`seatColumn` and `ring` both wrap mod `seatCapacity`, so seat 7 resolves to seat
0's column *and* — the two-row fold keys on ring parity — seat 0's row. A total
overlap, not a near miss. Eight agents, seven characters, and no way for a
viewer to know. That is S5 failing at the first crowd past the seat count and it
is the room asserting a false number [I1].

**Neither obvious repair survives its own arithmetic**, and both are recorded
here so nobody spends the day rediscovering it:

- **Raising `seatCapacity` does not work.** At `1x` — the only scale the app uses
  — the panel is 720 px and the seat pitch is 96, so `96 × 7 = 672` is the
  physical maximum across the visible width. More seats moves the failure from
  "two characters overlapping" to "characters off screen", which is S5 breaking
  the same way and harder to notice.
- **Reusing the back row as a second lap does not work either**, which is a shame
  because it looks free: flipping `isBackRow` on odd laps gives 14
  non-overlapping *positions* in the same width, and the seating is fine — two
  rows a character's height apart cannot share a horizontal strip at any x. It
  breaks the **movement** argument. `isBackRow`'s own doc closes the walk-out
  crossing with *"its own column is a pitch from every back-row seat"*, and under
  the lap flip seat 0's column **contains** back-row seat 7, so a front-row
  character walking upstage walks through an occupied seat. Offsetting lap 1 by
  half a pitch does not rescue it: bodies clear, but a 77 px plate against
  another 77 px plate needs 77 px and has 48.

**So the room says it instead.** `SceneDirector` seats the first seven agents
and counts the rest; `SpriteIntent.setOverflow` carries that count; the room
stands a plate against the back wall reading `+N` over `MORE`. Seven characters
plus "+1" is still a count, so S5 stays answerable, and the plate asserts nothing
the data did not say. **Silently dropping the overflow agents was never an
option** — it is the same lie as drawing two on one spot, with nothing on screen
to catch it.

Four things about the plate, all of them measured:

- **It is a nameplate with no accent.** Same construction, same 5×7 face, same
  two rows — the count large on the lead line, the word small beneath — so it
  reads as the room's own lettering rather than as chrome. Every *character*
  plate carries a saturated accent band assigned 60° apart; this one carries the
  plate colour, so there is nobody it can be mistaken for.
- **It stands where nothing else does.** `RoomLayout.overflowPlatePosition` is a
  tile above the wall line on seat 0's own decoration column. The decoration
  columns alternate backdrop/accent along x and seat 0's is the middle of the
  seven, so it is an *accent* column: the backdrops are a full seat pitch away
  either side and the accent itself stands two tiles downstage, topping out at
  238 against the plate's 256. `RoomSceneTests
  .theOverflowPlateStandsWhereNoThemePutsAProp` asserts it against
  `RoomScene.decorationPlacements` — the function the room builds from, not a
  copy of it.
- **It is in the frame.** The plate exists only when every seat is taken, and a
  full room's camera span is fixed, so on the 720×400 panel the point is a
  constant. The scene clamps it into the frame anyway, because `--render` and
  `--window` take a size and a caption off screen is the silence it exists to
  break.
- **It is upstage of both seat rows**, so "nothing decorative is drawn nearer the
  camera than the seat row" is untouched — and it is not decoration in any case.

**A seat that frees goes to whoever has waited longest, and they walk in.**
Without that the overflow would be permanent: seats are released on departure and
reused by *new* arrivals, so an agent that found the room full would still be
undrawn after everyone on screen had left — a room of empty desks under a plate
reading "+3", which is true and useless. The walk-in is the same `spawn` every
character gets and claims nothing about when the agent started; it is driven by
the departure that freed the chair, which is a real event.

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

> **Something checks it now — M6f.** `preview-theme.py --verify` compares this
> tool's room against the room `spriteroom --render` draws, pixel for pixel, and
> the lint runs it. It found that this very repair left one pixel of itself
> behind, and found a second sign error nobody had looked for. See "The preview
> is checked against the scene" below.
>
> **Both are fixed and the register is empty — M6g.** All six themes now agree
> with the scene at zero differing pixels. The sign error was the one that
> mattered: every picture this tool had written showed the character in front of
> its desk rather than at it.

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
screen at a time. Thresholds are unchanged and were not touched. **The motion
budget added at M6d is scoped per theme for exactly the same reason**; its
numbers are in "The motion budget" below, and the colour table here is
bit-identical before and after it.

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

#### 1b. The `sleep` bubble is no longer drawn, and "it is the same bubble" is why

Everything above is still the right *layer* argument and none of it is retracted:
dormancy is a badge-state fact, `badges.states.sleep` is where it is recorded,
and no body pose could honestly carry it. What did not survive contact with the
room is the sentence in the paragraph immediately above — **"it is the same
bubble"** — read as a virtue.

At `1x`, and `1x` is every frame this app renders, the bubble's *presence* is the
loudest thing on screen: 548 opaque pixels at a median value of 210 over a floor
of 154, above an 11 px head. Measured against the six tool badges the `sleep`
bubble is:

| | |
|---|---|
| silhouette IoU vs every tool bubble | **0.792** |
| fraction of the sleep silhouette *inside* a tool bubble | **100%** |
| badge-slot footprint on a real 1x frame | **548 px vs 678** — 84% |

So the glyph that meant *stopped* was 84% of the glyph that meant *working*, in
the same slot, in the same shape, at the same value — and the only thing telling
them apart was ~11 px of ink nobody can resolve at this size. Given a real frame,
a cold reading of it inverted: six bubbles read as six busy agents when all six
were `Z` and the only working agent was the one with **no** badge.

**What ships instead is `SceneBitmaps.dormancyTab`** — 9x11 px, the plate colour,
the room's own font, the `×N` chip's construction. Two properties, and both were
tested before either was chosen:

- **Extent, not value, is what had to change.** Dimming the same bubble to
  `alpha 0.3` was rendered and measured: it drops the slot's contrast to ~28% of
  a working badge but leaves **72%** of the footprint, because alpha cannot make
  a bubble smaller. The tab is **15-19%**. At a glance you read *whether there is
  a bubble over that head*; you read how bright it is only after you have already
  looked.
- **It lands in the other family.** Every white bubble in this room is pack art
  about a tool call; every dark plate is the room's own lettering about a
  character. Dormancy is a statement about a character, so it joins the
  lettering — and telling a dark tab from a white bubble is a size-and-value
  judgement, which is exactly what survives `1x`. [I7]

Drawing it rather than loading it also means it exists on a checkout with no art,
which is why its test needs no `SceneArt` gate.

The pack art stays declared. `TextureStore.sleepTexture()` stays with it and is
now unused by the scene; both are kept because the *fact* is unchanged and the
manifest is where facts about art are recorded. If a future pack ships a
dormancy mark that is not a speech bubble, this is the key it goes under.

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
nothing. And it is **364 px of 1156 (31.5%) moving, not 160 of 1544 (10.4%)** —
the M6b figure was transcribed and wrong by a factor of three. It would pass the
lint (`broadcast` 0.470 → 0.462), and that is the point: the lint is a value
check and has nothing to say about motion or about a prop hanging in the air.

> **The denominator in that sentence was wrong too, and it was wrong here until
> M6d.** It read "364 of 1304 (27.9%)". The visible-pixel count is 1156 under
> every definition anyone might mean — union over the loop, per frame, alpha
> over 127 or over 0 — so the true fraction is 31.5%. The numerator was right the
> second time and the denominator was still typed. `control_room_server` has the
> same defect below: 80 of **2176** (3.7%), not 2240 (3.6%). Three passes at one
> figure, three transcriptions, two of them wrong. That is the whole argument for
> the motion budget measuring the pixels itself rather than reading a number
> somebody wrote down, and it is why the check below cross-checks the manifest
> instead of trusting it. **ADR-002 §14b repeats the 27.9% and is not corrected
> here** — that document is not this one's to edit, and the correction is flagged
> so it is not lost.

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
      "transition_px": [48, 40, 48, 32],
      "measured_on": "the shipped frames, by scripts/build-manifest.py …"
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

Five notes on the fields, because four of them are not in the proposal:

- **`content_box` is the union over every frame**, not frame 0's. The scene
  anchors a prop by its box and draws every frame on one canvas at one position,
  so a box describing only frame 0 would be false for the rest of the loop, and
  the foreground-clearance test reads that box's height. For `pendulum_clock` the
  union equals frame 0's box, so the two readings agree and a `file`-only reader
  loses nothing — but that is a measurement, not a guarantee.
- **`moving_px`/`visible_px` are generated, not written down.** They are I7's
  number for a moving prop, and M6b transcribed them wrong twice. Generated
  figures cannot drift from the art.
- **`transition_px` was added at M6d**, and it is a different quantity from
  `moving_px`, not a restatement of it: the pixels that change on each *step* of
  the loop, wrapping, as integers. `moving_px` is the union over the whole loop
  against frame 0, which grows with loop length and carries no rate at all. The
  motion budget is `mean(transition_px) × fps`, times how many copies the room
  draws, and none of that is recoverable from `moving_px`. See "The motion
  budget" below.
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

## The motion budget — M6d

I7 is mechanised on colour and was not mechanised on time. ADR-002 §14b recorded
the gap in as many words while refusing `old_tv`:

> It moves 27.9%, not the 10.4% first recorded — and it **would have passed the
> lint**, because the lint says nothing about motion. That is a real gap in I7's
> mechanisation and it is recorded here rather than papered over: nothing checks
> a moving-pixel budget.

It is checked now. `scripts/lint-palette.py` carries a fourth threshold beside
the three colour ones, on the same terms: measured, mechanical, non-zero exit
naming the offending file and value.

**Why this belongs in I7 at all.** In this product motion *means an agent is
working*. It is the one signal a glance actually reads — CLAUDE.md's
one-sentence product is "you glance at the notch and know what your agents are
doing", and what a glance resolves before anything else is which characters are
moving. So a prop that out-moves the characters is the time-axis equivalent of a
room element owning the darkest pixel on screen. Same invariant, second axis.

### What is measured, and what is not

Three quantities were candidates. **The one that governs is pixels changed per
second, on the panel, summed over every animated prop in a theme and multiplied
by the number of copies the room draws.** The other two are measured and printed
and neither is a gate.

**Not the prop's own moving fraction** — `moving_px / visible_px`, the figure
§14b quotes. It says what proportion of an object is restless, which is a
description of the object's character rather than of what the screen does. It is
not comparable between props: an object ten times larger with the same 364
moving pixels scores 3.1% instead of 31.5% and costs the panel exactly the same.
Gating on it would refuse a small busy prop and admit a large one that changes
the identical number of pixels.

**Not per-loop moving pixels either**, placed or unplaced. That figure grows with
loop length and carries no rate at all, so it prices `control_room_server` —
three frames at 2 fps — at 0.62 of the ceiling when per second it is 0.30, and it
cannot tell a 4-frame swing at 5 fps from an 11-frame flicker at 10.

**Pixels per second is what an eye competes with**, and the two corrections it
applies are both real: `old_tv` runs at 10 fps against the clock's 5, and a
6-frame loop is not twice as loud as a 3-frame one. It is computed from
`mean(transition_px) × fps`, where `transition_px` is what changes on each step
of the loop, wrapping — which is a new generated manifest field, see below.

**The placement multiplier is not a model of the room, it is arithmetic the
renderer agrees with.** `scripts/preview-theme.py` writing all four frames of
`library` at the real 720×400 panel differs between consecutive frames by
exactly four times the prop's own figure, and `broadcast` with `old_tv` stood in
the same slot likewise — no occlusion, no clipping, exact. So the lint multiplies
rather than renders, and the multiplication was checked in pixels.

The census itself — `board` ×4, `plant` ×10, `chair` ×7, `desk` ×7 on the shipped
25-column layout — lives in `role_placements()` in `preview-theme.py`, which is
where RoomLayout.swift is already transcribed, and the lint imports it. It is not
copied into the lint. `render()` counts what it actually placed and hard-fails if
the two disagree, so the number that a picture is drawn with is the number the
budget is computed with. **Two sources that can disagree is how 10.4% became
27.9% became 31.5%.**

> **That paragraph is wrong twice and is kept because it is the argument for
> what replaced it.** `plant` is ×3, not ×10 — M6e, above. And the cross-check
> it puts its faith in was two transcriptions of one dead layout agreeing with
> each other; it could never have caught the error it is offered here as
> insurance against. At M6f the two collapsed into one list, `prop_layout()`,
> and the tie between the census and the room became a pixel comparison against
> the real `RoomScene`. Two sources that can disagree was half the lesson; the
> other half is that two sources with one author are not two sources.

That census is also, on its own, the arithmetic behind §14b's rule that an
animated prop may only occupy `board`: `plant` costs two and a half times as
much and seven of its ten copies sit in the permanently-visible foreground row.
The lint does not enforce the rule by name — it prices it. Moving the *identical*
shipped clock from `board` to `plant` takes it from 0.57 of the ceiling to 2.01
and turns the build red.

### The number, and where it comes from

**The cast sets it.** I7's other thresholds are relative — the room must be
*under* the characters — so this one is too. A fixed pixel count picked from the
two animated props this project happens to own would be taste with a decimal
point on it. The ceiling is measured at lint time as the **quietest looping
animation any shipped variant plays**, in the same units, and the room's total
must come in under it. Recast the six and the ceiling moves with them.

Measured over the six shipped variants, every looping state, every direction:

| loop | frames | fps | quietest | loudest |
|---|---:|---:|---:|---:|
| `idle` | 6 | 8 | **1461 px/s** (10, up) | 2603 px/s (07, down) |
| `working` (sit) | 3 | 8 | 2837 px/s (10, right) | 4523 px/s (07, left) |
| `walk` / `spawn` / `depart` | 6 | 8 | 4661 px/s (06, up) | 6672 px/s (07, down) |

`deliver` is excluded because it does not loop; wrapping its last frame back to
its first would measure a cut that never plays.

**The ceiling is 1461 px/s**, and it is the minimum over the whole table rather
than over the poses a side-view room actually draws. `idle` up is a back view and
this room may never show it. Taking it anyway makes the ceiling stricter, and a
stricter number produced by a mechanical rule is worth more than a looser one
produced by a judgement about which frames get drawn. `idle` is also the right
family to take it from on the merits: I2 says a character idles unless it holds
an open tool call, so an idling character is the quietest thing the cast can
legitimately be while still on screen, and the room has to be under *that*.

**That last sentence stopped being true in M7 and the number did not move with
it.** The room no longer plays the idle loop: an idle body holds one frame, so an
idling character moves **0 px/s**, and the ceiling is now derived from an
animation the scene never draws. Nothing mechanical broke — 1461 px/s is a
property of the *sheet*, `scripts/lint-palette.py` measures it there, and it
still passes on all six themes — but the argument behind it now reads
differently: it bounds props against *the quietest thing the cast's art
contains*, not against the quietest thing the room actually shows.

The consequence is measurable and is recorded rather than argued away. In
`library`, over 8 consecutive 125 ms frames of the real capture, the animated
prop moves **164,014** of absolute pixel delta while the two working characters
move 841,718 — so a prop still does not out-move a working character, by 5.1×,
and it is a wall-band object well clear of the seat rows. But it *does* out-move
an idle one, which is now zero. In a themed room with an animated prop,
"something in the frame is moving" no longer means "somebody is working"; that
claim holds unqualified only where the props are still, which includes `office`,
the room this capture actually draws, measured at exactly **0** outside the
character columns.

**REVISIT WITH DATA.** The honest fix is to re-derive this ceiling from the
motion the room draws rather than from the motion the sheet contains, which would
lower it to the seated `working` loop and would reprice every candidate in the
table below. That is a change to the lint and to the accepted prop set, and it is
not one to make as a side effect of a change to the characters.

**The share is 1.0** — the room, in total, must move less than one character
does. That is the literal time-axis reading of I7 and it is the maintainer's own
sentence. The comparison is against *one* character rather than the population
because the room's motion does not scale with the population and character motion
does, so a single agent is the binding case; it is also the most common case and
the only one that reaches `3x`.

| candidate | frames | fps | own | on panel (×4) | share of ceiling | moves |
|---|---:|---:|---:|---:|---:|---:|
| `control_room_server` | 3 | 2 | 109 px/s | 437 px/s | **0.30** | 80 of 2176 (3.7%) |
| `pendulum_clock` — ships | 4 | 5 | 210 px/s | 840 px/s | **0.57** | 64 of 2096 (3.1%) |
| `control_room_screens` | 11 | 10 | 1171 px/s | 4684 px/s | **3.21** | 332 of 6796 (4.9%) |
| `old_tv` | 6 | 10 | 3467 px/s | 13867 px/s | **9.49** | 364 of 1156 (31.5%) |

Read the last two columns together, because between them they close the question
of which quantity to gate. **No threshold on the moving fraction reproduces this
ordering.** Any line that admits `pendulum_clock` at 3.1% and refuses `old_tv` at
31.5% sits somewhere in between; put it above 4.9% and it *admits*
`control_room_screens`, which is 3.21× over the panel budget, and put it below
4.9% and it refuses `control_room_server` at 3.7%, which is the quietest object
in the folder on the panel at 0.30. The fraction cannot separate these four in
the order the screen does, at any value, because it does not carry size and it
does not carry rate. That is not a preference between two reasonable measures; it
is one of them being unable to express the thing.

**REVISIT WITH DATA**, in the sense this document uses for `G` and the palette
thresholds. What is verified is that 1.0 separates every object anyone has
looked at — one adoption at 0.57 from three refusals at 3.21 and up, with
`control_room_server` passing on motion at 0.30 and refused on contrast instead,
which is the check discriminating rather than blocking. What is **not** verified
is where inside the 0.57–3.21 gap the line truly belongs, because nothing has
ever landed there. This data cannot distinguish a share of 0.6 from a share of
1.0, and picking the smaller one would assert a precision the measurements do not
support. The first prop that scores between 0.6 and 1.0 and looks wrong at `1x`
is the evidence that tightens it; the first that scores there and looks fine is
the evidence that it is right. Until then, do not nudge it.

### The lint recomputes and cross-checks. It does not read.

`scripts/build-manifest.py` generates `moving_px` and `visible_px` into every
animated role, and now `transition_px` beside them — the per-step pixel counts,
integers, so the manifest stays byte-deterministic and a reviewer sees the shape
of the loop rather than a mean somebody took.

The lint measures all three off the same PNGs and then **asserts the manifest
agrees**, failing loudly with both figures if it does not. Reading the declared
values instead would make the gate a tautology: the same code that wrote the
figure would be the only thing vouching for it, and a generator with a bug would
grade its own homework. Nothing else in this lint reads a number out of the
manifest either — the room's saturation is measured off the pixels, not looked
up. Recomputing also means the check works on a prop the manifest has *not*
adopted, which is the case every one of §14b's refusals was about.

### Lint numbers, room and all six themes

Colour, before and after this change — **identical, to three decimals, in every
row. No existing threshold was touched.**

| scope | mean value | max saturation (≤0.25) | darkest | min character contrast (≥0.40) |
|---|---:|---:|---:|---:|
| `room` | 0.785 | 0.183 | 0.659 | 0.472 |
| `briefing` | 0.817 | 0.182 | 0.667 | 0.503 |
| `broadcast` | 0.784 | 0.114 | 0.667 | 0.470 |
| `library` | 0.766 | 0.183 | 0.667 | 0.452 |
| `mission_control` | 0.741 | 0.182 | 0.604 | 0.427 |
| `office` | 0.793 | 0.183 | 0.659 | 0.480 |
| `stage` | 0.786 | 0.183 | 0.667 | 0.472 |

Motion, which did not exist before. Ceiling 1461 px/s:

| scope | animated props | px/s | share of ceiling |
|---|---:|---:|---:|
| `room` | 0 | 0 | 0.00 |
| `briefing` | 0 | 0 | 0.00 |
| `broadcast` | 0 | 0 | 0.00 |
| `library` | 1 | 840 | **0.57** |
| `mission_control` | 0 | 0 | 0.00 |
| `office` | 0 | 0 | 0.00 |
| `stage` | 0 | 0 | 0.00 |

The zero rows are printed rather than skipped. A motion budget that says nothing
about a still room is a motion budget nobody has watched run.

### It was watched failing

A threshold nobody has seen fail is not a threshold. Seven violations were
injected and every one exits non-zero naming the file and the value. The first is
the real thing, end to end — `old_tv` added to `ANIMATED_ADOPTED`, re-imported,
re-manifested — not a synthetic:

| injected | result |
|---|---|
| `old_tv` adopted into `broadcast` | **FAIL** — 13867 px/s against 1461, **9.49×**, naming `board`, `old_tv`, 4 copies × 3467 px/s. Its colour numbers in the same run are `broadcast` 0.470 → 0.462, i.e. it still passes every colour check, exactly as §14b said |
| the shipped clock moved from `board` to `plant` | **FAIL** — same art, 2940 px/s, 2.01×. Ten copies instead of four |
| `transition_px` altered by one pixel | **FAIL** — cross-check names declared and measured |
| `moving_px` altered | **FAIL** — cross-check |
| `loop: false` | **FAIL** — the budget measures the wrap and refuses to describe anything else |
| an animated role the layout does not place | **FAIL** — on-panel cost unknown, refuses to guess it |
| `role_placements()` made to disagree with what `render()` drew | **FAIL** in the preview tool, naming both counts — the tie between the picture and the budget. **Retired at M6f**: the two now read one list and cannot disagree, and this injection is no longer constructible. Its job is done by the scene comparison, whose own injections are tabulated in "The preview is checked against the scene" |

And the negative control: `control_room_server` adopted into `mission_control`
**passes** at 0.30 of the ceiling. The budget is not a blanket refusal of motion;
that object's refusal was and remains a contrast one.

## The preview is checked against the scene now — M6f

`scripts/preview-theme.py` is the tool this document tells you to accept a theme
with, and it has been **wrong twice**, both times in a way that looked right:

- **M6b** — `prop_origin` returned a y-up anchor offset where a y-down blit
  origin was needed. Up to ~80 px at `1x`. Invisible because it was
  *consistent*, so every picture stayed internally plausible.
- **M6e** — the placement census counted a foreground row of seven plants the
  scene had stopped drawing two commits earlier.

Both survived because the only thing checking the transcription was **another
copy of the same transcription**: a census compared against a `render()`
transcribing the same layout. **A transcription checked against a transcription
is not a check.** That is the whole finding and it is why this section exists.

### What is compared, and why that property

`spriteroom --render DIR --theme ID` draws the real `RoomScene` through the real
`SKRenderer`, offscreen, at any theme, with no window server and without
touching the display. (`--theme list` enumerates. Never `--panel-render` — that
reveals the real panel over whatever the user is doing.) So both pictures come
from one command each and can be diffed.

**Not byte-identical over the whole frame**, which would be the wrong bar: the
scene draws characters, nameplates and badges this tool deliberately does not
model, and its camera centres on the occupied span where the preview centres on
the room. What is compared is **the room** — floor, wall, and every copy of
every prop — pixel for pixel, in an **empty** room, over the whole tile field.

That is the property that matters because it is exactly the surface both bugs
lived on: *which roles, how many copies, and where each one's content box
lands*. A misplaced prop, a phantom copy or a missing copy cannot leave those
pixels equal. Every differing pixel is sorted into one of three statements — ink
this tool drew over bare room (a phantom), ink the scene drew over bare room (a
copy we are missing or have moved off), or ink both drew differently (a
misplacement inside the overlap) — so a failure reads as a finding rather than
as a pixel count.

Three things make it a comparison rather than a fit:

- **The room is empty by assertion, not by hope.** The render time is after
  `SessionEnd`, and the check refuses to proceed if any pixel exceeds 0.25
  saturation — the room is clamped to 0.18 by the import transform and
  characters own everything above it, so one saturated pixel means somebody is
  still on stage. I7 is what proves the stage is clear.
- **Registration is measured, not transcribed.** Both tools paint floor and wall
  over `drawnRows` × `drawnColumns` and nothing outside it, so at a viewport
  wide enough to show the whole field (1600×900; the 720×400 panel crops the
  outer seats, and a prop the panel cannot show is a prop the check could not
  count) the field's bounding box *is* the camera. The recovery is validated on
  the preview's own picture first, where the camera is known by construction,
  and only then applied to the scene's. **If the two fields differ in size the
  drawn range has drifted, and that is reported rather than fitted away.**
- **A residual offset is a failure, not a correction.** The check does not shift
  until the diff is zero. It measures the one translation that best explains the
  props, requires it to be the same for every role, requires the prop ink to
  match *exactly* at it, and requires every disagreeing pixel to fall inside a
  prop's own box.

### It found a third disagreement, and then a fourth

Both were recorded here unfixed at M6f, because the point of that exercise was
to learn whether the transcription is still wrong, not to have it quietly
corrected. **Both are fixed at M6g and the register is empty** — see "The
register is empty now — M6g" below, which also says what the pictures gained.
The two findings are kept in full because they are the derivations, and because
the shape of each is the useful part.

**Third — every prop in the preview stands one pixel into the floor.** All six
themes, every role, every copy.

> `prop_origin` returns `top = y + bottom_row`, which lands the content box's
> bottom *pixel* on the panel row covering scene y ∈ [y−1, y] — below the
> placement line. SpriteKit's `anchor(inCanvas:)` puts it on [y, y+1], standing
> *on* the line. The correction is `top = y + bottom_row + 1`.

It is the same y-up/y-down confusion M6b fixed, one pixel of it left behind: M6b
corrected which *end of the canvas* the offset was measured from and did not
correct which *side of the line* the bottom row falls. At `1x` it is one pixel,
so it changes no theme judgement — but it is the residue of an 80 px bug and it
was found by measurement rather than by reading.

**Fourth — the depth bias is transcribed with the wrong sign, so the paint order
within a seat is exactly reversed.**

> The scene sorts by `zPosition = Character.Layer.rowDepth(y) + bias`, and
> `rowDepth` is `1000 − y`: z runs *opposite* to y, so a positive bias pulls a
> node **forward**. The preview sorts on `y + bias`, painting larger keys first,
> so the same positive bias pushes it **backward**.
>
> | | back → front |
> |---|---|
> | scene | `chair`, character, `desk` |
> | preview | `desk`, character, `chair` |
>
> The correction is one character: sort on `y − bias`.

This one is not cosmetic. `RoomLayout.deskPosition` says the desk offset exists
because "at 32 px the only cue that a character is sitting *at* a desk rather
than beside one is whether the desk's near edge crosses it". In the scene it
crosses. **In every picture this tool has ever written, the character sits in
front of its desk instead, and the chair's backrest is painted over the desk.**

It went unseen for the same reason the other three did — it is invisible in
most of the room. Four of the six themes use the narrow Office 34 desk, whose
ink never reaches the chair's, so the reversal has nothing to show. It is
visible only in `mission_control` (Hospital 127) and `library` (Classroom 26):
364 and 1484 pixels respectively, and zero in the other four.

Both were held in a **named register** in `preview-theme.py` rather than
suppressed: the check still failed if the offset changed, if it stopped being
the same for every role, if any prop pixel disagreed outside the recorded
chair/desk overlap, or if anything disagreed outside a prop box at all. It
printed both defects, by name, on every run — including inside the lint. Fixing
either one did not turn the check red; forgetting about them did not turn it
green.

### The register is empty now — M6g

Both defects are corrected. All six themes now agree with `spriteroom --render`
at **zero differing pixels** over the whole tile field, with nothing forgiven.

- **`prop_origin` returns `y + bottom_row + 1`.** The derivation is written into
  the function so the next person does not redo it: `to_screen` maps scene y to
  panel row `origin_y − y` and `blit` fills downwards, so the content box's
  bottom row must land on `origin_y − y − 1`, the last row *above* the line. It
  is the third time this function has been wrong about y and the first time
  something other than another copy of itself said so.
- **`render()` sorts on `y − bias`.** The scene's biases in `prop_layout()` are
  unchanged — they were never ours to change. Only the direction they were read
  in was ours, and negating it puts the paint order back to `chair`, character,
  `desk`.

**The second fix is the one you can see.** At `1x` the first is one pixel. The
second changes 7 768–15 696 pixels of a 288 000-pixel panel in every theme, and
what changes is the thing the desk offset exists to produce: the character now
sits *behind* its desk with the near edge crossing it, and the chair's backrest
is behind the character instead of painted across its face. Cropped at 4× it is
not subtle, and it was visible in the wide picture of `library` and
`mission_control` all along.

The register survives as a shape rather than as a tolerance, with a
`register_summary()` printed on **every** run, including the empty one:

```
known-defect register: empty — every prop must land exactly where the scene
puts it, and nothing about a seat's paint order is forgiven
```

An empty register that prints nothing is indistinguishable from a check nobody
ran. The next defect is entered here by name, with its correction and its
measured extent, or it is not accepted at all.

### Where the check lives

**A mode of the tool, `preview-theme.py --verify`, which exits non-zero** — the
geometry and its check in one file, so an edit that causes drift and the thing
that catches it are on the same screen.

**And a stage in `scripts/lint-palette.py`, which is what makes it run rather
than be remembered.** A script somebody has to remember to run is what failed
twice. The lint is already a gate and already imports `role_placements()` from
this tool, so its motion budget is already priced on this transcription; before
M6f nothing tied that number to a renderer. `--no-scene` skips it for
colour-only iteration and says so in the output.

The same pass also collapsed the duplication that made M6e possible:
`prop_layout()` is now the single placement list, and `role_placements()` counts
it while `render()` draws it. The census assertion inside `render()` is
therefore a tautology now, and it says so — it is kept only to catch a drawing
loop that drops what it was handed. **The tie between the census and the room is
the scene comparison, not that assertion.**

### What it cannot cover

Stated the way the art gate states its own, because a gate whose absence looks
like a pass is the failure mode this project has already been bitten by:

- **It needs the app built and the art on disk.** It cannot run in a checkout
  without either. A missing binary is a **visible skip** naming the themes it
  did not check; `SPRITE_ROOM_REQUIRE_SCENE=1` turns that skip into a failure,
  the same arrangement `SPRITE_ROOM_REQUIRE_ART` gives the pixel tests.
- **Characters, nameplates and badges are not compared at all.** The comparison
  is of an empty room, so the preview's seated cast, its `--state`, `--badge`
  and `--population` paths are unverified — including the half of the
  depth-order defect that puts a character in front of its desk, which is a
  derivation and a picture rather than a measurement.
- **The camera is not compared, deliberately.** The scene frames the occupied
  span and the preview frames the room; they differ by −16,−3 px at every theme,
  which is a framing choice rather than a placement. The check measures that
  translation and registers by it. So a change in the *camera* — the content
  band, the vertical bias, the scale ladder — passes this check untouched.
- **Animation phase is not compared.** The check requires the scene to equal
  *some* frame of the preview's loop, not a particular one, because the phase is
  a function of render time. (At `--at 60` the harness's accumulated float clock
  lands a hair under 60.0, so `library`'s 5 fps clock shows frame 3 rather than
  frame 0. That is the harness, not the art.)
- **It compares one population and one moment.** The room is drawn identically
  at every population — seat 0 is always framed, so the camera does not move —
  but nothing here checks a busy room.

### Cost, and watching it fail

About 2.5 s a theme, ~15 s for all six, on top of a lint that was under a
second. That is the price of the only check in this repository that compares an
artefact against the product.

Seven violations were injected and every one exits non-zero naming the theme and
the quantity, plus both skip behaviours. **Re-run at M6g against the corrected
tool, with two more injections added** — the two defects the register used to
hold, which are now caught rather than forgiven. The pixel counts differ from
M6f's where the injection was run against a different theme; each row names the
theme it was measured on.

| injected | result |
|---|---|
| M6e's foreground row of seven plants restored | **FAIL** — 4480 px this tool drew over bare room (`office`) |
| M6b's mirrored `prop_origin` restored | **FAIL** — 33996 px, 17024 phantom and 16804 missing (`office`) |
| M6f's off-by-one `prop_origin` restored — **defect 1** | **FAIL** — 7364 px (`office`). Forgiven by the register until M6g |
| M6f's inverted depth bias restored — **defect 2** | **FAIL** — 1484 px, all inside the seat overlaps (`library`). Forgiven by the register until M6g |
| the drawn tile range narrowed one column | **FAIL** — "the drawn tile field is 1344x672 where this layout paints 1312x672" |
| one seat's `chair` no longer placed | **FAIL** — 404 px the scene drew over bare room (`office`) |
| the back row moved one tile sideways | **FAIL** — 15480 px, 6660 phantom and 7028 missing (`office`) |
| the floor tile swapped for the wall tile | **FAIL** — 410104 px (`office`) |
| the scene rendered at t=8, before the room empties | **FAIL** — "a pixel carries saturation 0.698 … a character is still on stage" |
| no built app | **SKIP**, naming the unchecked themes, exit 0 |
| no built app, `SPRITE_ROOM_REQUIRE_SCENE=1` | **FAIL** |

## The generator's overlay layers — M6g

The maintainer's complaint is that a character "shouldn't just have a speech
bubble", and the claim put to this document is that the character generator's
`Books`, `Accessories` and `Smartphones` folders are held-object layers
pre-registered to the character sheet, so the "nothing is held" rule was
answering a question about anchors that these files do not ask.

**The registration claim is true and is now verified rather than argued.**
`Books/32x32/*.png` and 80 of the 84 `Accessories/32x32/*.png` are **1792×1312**,
byte-for-byte the premade sheet's geometry — 56 columns of 32 px by 20 rows of
64 px. Composited straight onto a premade with no offset, the book lands in the
hands and a hat lands on the head, in every frame of the row, checked at 8×.
There is nothing to anchor because the artist already did it.

**And it does not reach this room, because of coverage.** Which pose rows each
layer actually carries ink on, measured by scanning the alpha channel rather
than by reading the folder name:

| Layer | Files | Sheet | Rows with ink | What that row is |
|---|---:|---|---|---|
| `Books` | 6 | 1792×1312 | **row 7 only** (`phone_b`), 12 frames | front-facing, standing |
| `Smartphones` | 5 | 768×384 | one row, 8 frames, registering to **row 6** (`phone_a`) | front-facing, standing |
| `Accessories` | 84 | 1792×1312 (80) | **every row**, `sit_a` and `sit_b` included, 12 frames each | worn, every pose |

Rows 6 and 7 are **single-direction**: no two of their twelve frames are pixel
mirrors, and both read front-on with the face visible, where an ordinary pose
row has four direction blocks of which blocks 0 and 2 are exact mirrors. That
is the same test that established the direction order at M0.

So the only rows any *held* object exists for are two front-facing standing
poses. Every working character in this room is a **side-view seated** sprite,
because the pack ships no front or back sit and the room was laid out side-on
for exactly that reason. A held book cannot be composited onto a seated
character: there is no book ink on the seated row to composite.

**Cut, put in the room, and looked at**, because that is this project's rule and
because the alternative would be refusing it from a table. Six agents in the
row-7 book pose at `1x` in the real 720×400 panel read as six front-facing
figures standing at side-view desks with a pale patch at chest height. It is the
`sleep` row again — the name was right and the art is something else.

> **Everything above still holds, and the sentence it was used to justify does
> not.** This section refuses *these two layers*, correctly, and it was read for
> seven milestones as refusing a held object altogether. It does not: the reason
> given — no per-frame hand anchor — is a fact about 20 pose rows, and the room
> draws one of them, on which the hands are still. See "Held objects: the hand
> anchor is a measurement — M7b" below for the box, the 36 frames it was
> measured over, and what a prop placed on it can and cannot do.

Two more numbers that settle it:

- **The premades already contain the book.** Compositing `Book_01` onto premade
  06's row-7 frame changes **8 pixels of 1080** and **0 pixels of silhouette**;
  the other five books change 68–96. The `Books` folder is a *recolour* of a
  book that is already drawn into the pose, not a prop that can be moved to
  another pose.
- **It does not read at `1x` even where it exists.** 68–96 changed pixels of a
  1080-pixel frame, in the character's own palette — the book's max saturation
  (0.822) and darkest value (0.314) are the body's own numbers to three
  decimals, because it is the same ink. It cannot out-shout the body, and for
  the same reason it does not separate from it.

### What does survive, and what it would cost

**`Accessories` is real, usable art on the pose this room actually draws.** It
registers exactly on the seated side-view frames — glasses on the eyes, a hat on
the head, checked at 8× — and covers all twelve frames of `sit_a`. Measured on
variant 06 seated, frame 0, against its bare 952 px, max saturation 0.598,
darkest 0.314:

| Accessory | px added to the silhouette | max saturation | darkest |
|---|---:|---:|---:|
| Chef hat | 404 | 0.598 | 0.314 |
| Snapback | 156 | 0.770 | 0.314 |
| Beanie | 132 | 0.598 | 0.314 |
| Detective hat | 128 | 0.873 | 0.314 |
| Backpack | 60 | 0.598 | 0.314 |
| Medical mask | 8 | 0.598 | 0.314 |
| Glasses, monocle, gloves | **0** | 0.598 | 0.314 |

**No accessory ever becomes the darkest pixel on screen** — every one bottoms out
at the cast's own 0.314, because it is the same pack ink. That is the I7 axis
this document says actually matters and it holds by construction. Two of them do
raise that character's peak saturation, which is I7-legal (characters own
saturation) but is a real number and is recorded here rather than waved past.

At `1x` in the panel, with six agents seated: **a snapback, a beanie and a
detective hat are told apart instantly; glasses, a monocle, gloves and a medical
mask are not visible at all**, and a backpack is on the far side of a
right-facing character and mostly occluded. The silhouette column predicts the
picture exactly, which is the rule this document has always stated — silhouette
carries identity, and a 0 px silhouette change is a channel with nothing in it.

**Nothing has been cut into `assets/` and nothing is in the manifest**, for three
reasons stated so the next person does not have to re-derive them:

1. **It is a worn layer, not a held one.** It says something about *who* is
   sitting there, not about what they are doing, so it cannot be keyed on the
   badge class the way a held object would be. Keyed on `agent_type` it is the
   character-layer twin of the station.
2. **Drawing it is a scene change.** A second sprite per character, composited
   or layered, is not something the manifest can turn on — the same wall the
   stations hit below.
3. **Half of the vocabulary asserts.** The pack's accessories are a ladybug, a
   bee, a policeman's hat, a balaclava, a zombie brain, a detective hat, a chef's
   hat, a party cone. A hash that puts a `security-reviewer` in a policeman's hat
   has made a claim about the work, which is §3e's argument about the jail theme
   arriving on the character layer. The neutral subset — beanie, snapback,
   backpack, glasses — is four items, of which two have a silhouette worth
   having.

## Held objects: the hand anchor is a measurement — M7b

The maintainer asked, repeatedly, for the people to actually be holding things.
M6g answered with the generator's layers, found they only cover two standing
front-facing rows, and stopped. This section is what is on the other side of
that stop.

### Rows 15 and 9, named

Both generator folders were re-measured rather than taken from the M6g table,
because the whole question turns on them:

| File | Sheet | 32-px rows with ink | Best fit onto a premade | Ink on transparency | Pixels changed |
|---|---|---|---|---|---:|
| `Books/32x32/Book_32x32_01.png` | 1792×1312 | **row 15 only**, 12 frames | `dy = 0` → **row 7** | 0 | **104** of 2656 |
| `Smartphones/32x32/Smartphone_32x32_1.png` | 768×384 | **row 9 only**, 8 frames | `dy = +128` → **row 6** | 0 | **24** of 592 |

"Best fit" is the row offset at which none of the layer's ink lands on
transparency; the next-best offset for either file puts 100–508 pixels on empty
canvas and changes 20–25× as many. So the registration is not a judgement.

`CHAR_ROW_POSE` calls rows 6 and 7 `phone_a` and `phone_b`, and rendered they
are a **front-facing standing figure holding a phone** and the **same figure
holding an open book at chest height**. The important consequence is the one
M6g already recorded and it is worth repeating in the sharpest form: **the
premade already contains the object.** Cutting row 7 is what makes a character
hold a book; the `Books/` folder only repaints the cover. That is why 104 pixels
change and not 2656.

Both rows are single-direction and front-facing, so **compositing either layer
pins the body to a standing pose**, and the room draws a side-view seated
character at a chair and a desk. Route 1 buys a held book at the price of the
pose, the chair and the desk. That has not changed and this section does not
adopt it.

### The hands do not move, so there is one anchor

The blocker on route 2 was "no per-frame hand anchor exists". True of the files,
and it stops mattering once you notice the room draws exactly one pose:

| | seated hand box, 32×64 canvas, y down |
|---|---|
| variants 06, 07, 09, 10, 17, 19 | `x 14…17`, `y 52…55` |
| `sit` frames 0, 1, 2 | the same box |
| facing `right` and facing `left` | the same box |

Measured by taking each variant's own skin from the lower face and locating that
colour below the shoulder line, over all **36** frames. The `sit` loop moves the
head and the torso by 2 px on frame 2 and leaves the hands alone; the left
frames are the right frames mirrored about a canvas whose centre the hand box
straddles symmetrically, so the mirror is a no-op on the anchor.

Two caveats, because the first version of the check asserted more than the art
supports and failed on three frames:

- Some variants show **forearm** skin above the hand, so the run starts at row
  48 or 50 rather than 52. The anchor is taken from the four rows every frame
  agrees on, `52…55`, and the arm is allowed to be there.
- The bottom row is 55 and the columns are 14…17 on all 36. Those are the
  invariants; the top is not one.

In the node's own coordinates — bottom-centre anchor, y up — that box's centre
is **(0, 10)**. `Character.seatedHandCentre` is that number and
`HeldObjectArtTests.theSeatedHandBoxIsWhereTheArtSaysItIs` re-derives it from
the shipped PNGs rather than pinning it against itself.

### The art, and why it is authored

Six objects, one per badge class that has one: `page`, `book`, `console`,
`globe`, `clipboard`, `plug`. **`question_mark` gets nothing** — an unmapped
tool gets no glyph because guessing one would be a claim the data did not make,
and it gets no object for the same reason with a larger surface. [I1]

Authored, on the M5c precedent and for the M5c reason: no further packs will be
bought, and no pack draws a hand-sized prop for this pose. Three constraints,
all measured off the pack rather than chosen:

- **The pack's grid.** Every feature in the 32× art is a 2×2 block, because the
  32× set is a 2× scale-up of a 16-px design. Each object is an ASCII design
  grid doubled on the way out, exactly as `generate-art.py` draws the badges. A
  test asserts the doubling rather than trusting the transcription.
- **The pack's palette.** `(58,58,80)`, `(70,70,94)` and `(86,89,114)` are the
  three structural inks **all eleven** files in `Books/` and `Smartphones/`
  share; the page white, the book blue, the gold, the lit-phone cyan, the pale
  casing and the orange are lifted from the same eleven files. A test pins the
  set, so a seventh object cannot introduce an unmeasured hue.
- **The pack's floor.** The outline is `(58,58,80)`, value **0.314**, the cast's
  own darkest pixel to three decimals. Nothing here goes below it, so a held
  object can never be the darkest thing on screen — I7's one non-negotiable
  axis — and every object peaks above 0.60 so something in it separates from a
  torso.

**`scripts/lint-palette.py` cannot see this layer and that is not an oversight
to fix by moving the art.** The lint reads `assets/manifest.json`; this layer is
drawn by the scene, like the nameplate, the `×N` and the placeholder desk. The
I7 numbers are therefore checked by `HeldObjectArtTests`, which runs on a fresh
clone with no art at all because the bitmaps are ours. What that costs is stated
plainly: a reviewer looking only at the lint output will not see these numbers.

### The size was decided by looking, twice

The first cut was a 12×12 canvas with a one-cell border all round. Rendered onto
a seated character it read as a dark patch, not as a thing being held: the
border is 2 px of the pack's darkest ink on every edge, the torso it lands on is
about 20×16 px, and the torso's own outline is the same colour. Dropping to
**12×10** and letting the fill reach the border is what made it read. The
placement moved with it — forward 3 px and up 2 from the hand centre, so the
object occupies canvas `x 13…24, y 47…56`: top edge a pixel under the chin, left
edge over the hands, bottom clear of the trousers.

### What it does not do

**A held object on this pose cannot change the silhouette, and this document's
own rule says silhouette is what carries identity at `1x`.** The seated body is
a chibi — the head spans `x 2…29, y 20…45` and the entire torso under it is
about 20×16 px — so the hands are in the middle of an existing outline. What the
layer buys is a ~90-px block of bright, hue-separated colour inside that
outline: the same channel a costume buys (M6h), at about the same size, on a
different key.

Measured on the shipped panel, `fixtures/three-subagents` at 720×400 with the
camera at `1x`, against the identical render with the layer switched off:

| t | agents working | pixels changed |
|---:|---:|---:|
| 6 s | 0 | **0** |
| 12 s | 1 | 90 |
| 20 s | 2 | 186 |

Zero at 6 s is I2 holding: nobody had an open call, so nobody held anything. 90
is one object; 186 is two. Nothing else in the frame moved.

The honest verdict from the pictures: at `1x` you can see that two characters
are holding *something* and a third is not, and you cannot name it. At `2x` it is
a device, a book, a page. At `3x` all six separate. **The badge above the head is
still the layer that carries tool identity** and this does not replace it.

### The rule

> A character holds an object exactly while its **body is `working`** and the
> **badge slot is showing a tool glyph**. The object is that badge's class.

Both halves are load-bearing:

- The body condition is I2 on the character layer: no open call, no ambient
  loop, empty hands. It also disposes of ADR-003's closing beat for free — a
  beat is by definition a glyph over an *idle* body, so the guard returns before
  the object is chosen, the same structural argument `SceneDirector.body(for:
  badge:)` makes about the working-pose lookup.
- The badge condition means `attention` and `sleep` empty the hands, because
  both take the slot away from the tool. A call parked at a permission gate is
  not running, and the room must not assert the work in a second, larger channel
  while the badge is correctly refusing to. The body still animates, because I2
  keys it on the open set alone and that is not this layer's to change.

## Costumes: the generator's outfit layer, keyed on `agent_type` — M6h

The maintainer's complaint is that the agent's *kind* is not visible on the
agent: "the software developers should have a computer, then the tester or
verifier should have a lab coat."

`agent_type` is real captured data, so dressing a character by its type is the
room repeating a name the user chose rather than inventing one. [I1] The art is
`Character_Generator/Outfits/32x32/` — 132 sheets, all 1792x1312, the premade
sheet's exact geometry.

**This section corrects nothing about the VM claim, because M0 already did.**
"No VM is needed and no generator has to run" has been in this document since
M0 and is right. What was never done is the second half: the layers were shown
not to need a tool, and then nobody rendered them.

### What a costume is, and what it is not

A costume is **an overlay layer cut exactly the way a premade is cut** — same
rows, same direction blocks, same frame counts, same 32x64 canvas, colour
untouched — drawn on a node above the body and stepped on the body's own frame
index. `Manifest.Costume` is a layer stack; `TextureStore.costumeFrames` drops
any layer whose frame count disagrees with the body's, **silently**, which is
why both are cut from one table (`CHAR_EXPORT`) instead of two.

It is deliberately **not** a pre-composited variant. Compositing body, eyes,
outfit, hair and accessory into new character sheets was built first and thrown
away: it produces a second cast that has to be selected, lint-checked and
kept in step with the first, and it throws away the premade underneath it.

### Coverage, checked before anything was designed on top of it

M6g's `Books` finding is what a coverage assumption costs, so the alpha channel
was scanned rather than the folder names. `scripts/cast-sheet.py --coverage`
reproduces this.

| Layer | Files | Geometry | Every cut row, direction and frame? |
|---|---:|---|---|
| Bodies | 9 | 1854x1312 | yes |
| Eyes | 7 | 1792x1312 | yes except the **`up` block**, which is a back view with no face in it |
| Outfits | 132 | 1792x1312 | yes, except **all five colourways of `Outfit_31`** on frame 8 of `gift`/`down` |
| Hairstyles | 200 | 1792x1312 | yes |
| Accessories | 84 | 1792x1312 (80), 1854x1312 (4) | yes except the `up` block on face-worn items |

The four rows this project cuts are `idle` (1), `walk` (2), `sit_a` (4) and
`gift` (10). Every outfit carries ink on all twenty rows except row 3 —
`sleep`, a head on a pillow with no body to dress — so **frame counts match the
body's by construction**. Bodies and four Accessories are 62 px wider than the
rest; that is trailing pad, both are 56 columns of 32 px from x=0, and
registration is `(0, 0)` everywhere. Measured, not assumed.

### Which outfits read as a role, and which are a different shirt

Rendered on a premade, front-facing and seated, at `1x` and `6x`
(`cast-sheet.py --outfits`). Thirteen of the 33 designs carry role vocabulary:

| Family | Reads as |
|---|---|
| 08 | long coat — white, light grey, charcoal. **The lab coat.** |
| 16 | solid work top with white cuffs, amber/orange/red. **Hi-vis.** |
| 09 | white shirt under a coloured apron. **Studio/service apron.** |
| 19 | bib dungarees with a brass buckle. **Engineer's overalls.** |
| 18 | open plaid shirt over a white tee. **Field/outdoor.** |
| 15 | tunic with a neckerchief. Chef's whites or scrubs. |
| 06 | dark suit with a bow tie. |
| 28 | navy business suit with a tie. |
| 22, 26 | open jacket over a white shirt. |
| 30 | hood up **with a face mask** — the only outfit with a real silhouette, and it covers the hair. |
| 33 | towel wrap. |
| 12 | plain buttoned shirt — the least dressed thing that is still a garment. |

The other twenty are tees, jumpers, buttoned shirts, patterned tops and two
swimsuits. **They are a different shirt.** Thirteen of them —
`01, 04, 10, 11, 13, 14, 17, 20, 21, 23, 24, 27, 29` — are the pool this
document draws neutral costumes from, and they were confirmed by rendering all
thirteen rather than by reading the numbers.

### What a costume can carry, and what it cannot

Measured on the seated frame, on a real premade rather than a bare body:

- **An outfit adds 0-16 px of silhouette out of ~1000.** Its ink lands inside
  the body's own outline in 26 of the 33 designs. **A costume does not repair
  M0's finding.** Flattened to black, the twelve shipped costumes are
  *indistinguishable*: minimum pairwise distance **0.00%** on both the seated
  and the front idle frame, maximum **2.06%**, against the undressed cast's
  4.15% seated and 7.28% front. Silhouette is not a channel a costume has.
- **What it changes is a contiguous block of ~100-130 px** — the torso and lap
  of the seated sprite — from one flat value to another. That is the channel.
- **Headwear is the only real silhouette on offer**: snapback +156 px on the
  seated frame, beanie +132, detective hat +128, chef hat +404; glasses,
  monocle and gloves +0. Over half that vocabulary asserts a role — a
  policeman's hat, a balaclava, a chef's hat — so it may only ever appear in
  `roles`, never in the pool. None is used today.
- **`Outfit_30` is the one outfit with an outline, and it costs the wearer its
  hair.** M0 measured hair as the channel that does work on this cast (7.3% to
  20.6% between the six variants, almost all of it hair). It is not taken.
- **No hair layer**, for the same reason: overwriting the cast's hair spends a
  proven identity channel to buy an unproven one.

### The measure that predicts the picture, and the one that does not

`04-ART-DIRECTION.md` and `lint-palette.py` speak HSV, where `V = max(R,G,B)`.
On this question that is the wrong axis: a saturated red block scores 0.895 and
a white shirt 0.891, and they look nothing alike. What a user does at `1x` is
tell two ~100 px blocks of flat colour apart, so the costumes are chosen on the
**RGB distance between those blocks' mean colours** (0-441), with the HSV value
reported beside it because the rest of this repo speaks it.

Both are printed by `cast-sheet.py --measure`. On the shipped set:

| | closest pair | distance |
|---|---|---:|
| the six recognised costumes | `apron` vs `office` | **67** |
| all twelve | `n06` vs `office` | **46** |
| furthest | `hivis` vs `overalls` | 229 |

### The wardrobe, and the two tiers

**Tier 1 — recognised types may say what they say.** `roles` is keyed on the
exact `agent_type` string, no folding, no prefix or suffix rules. The six names
are this repo's own `.claude/agents/`; `Explore` and `general-purpose` are the
two non-empty `agent_type` values that appear in `fixtures/`.

| `agent_type` | costume | outfit | what it asserts |
|---|---|---|---|
| `test-engineer` | `lab` | 08_01 | this agent tests. Translating the word *test* into a laboratory coat — the one mapping the maintainer named. |
| `build-verifier` | `hivis` | 16_01 | this agent inspects what was built. Translating *build* and *verifier* into site hi-vis. |
| `art-director` | `apron` | 09_02 | this agent works in a studio. Translating *art*. |
| `ingest-engineer`, `scene-engineer`, `ui-engineer` | `overalls` | 19_01 | this agent is an engineer. Translating the word *engineer*, which is all three names have in common. |
| `Explore` | `field` | 18_01 | this agent goes out and looks for things. Translating *Explore*. |
| `general-purpose` | `office` | 12_03 | nothing beyond *no speciality*, which is what the name says. Deliberately the least dressed of the six. |

**Three types share one costume on purpose.** Same costume means same kind of
worker — ADR-002 §4's ratified reading of four identical desks. Manufacturing
three costumes for three names that differ only in their prefix would be
decoration pretending to be information.

**Tier 2 — unrecognised types assert nothing.** `assignable` is six plain
shirts, `n01`-`n06`, hashed over. No coat, no hi-vis, no apron, no uniform, no
headwear. This is the `question_mark` rule on the character layer: **a hash
must never put an arbitrary agent in a lab coat**, because nothing in an
arbitrary string licenses one. Enforced twice — `CostumeContractTests` on a
fresh clone, `lint-palette.py` on a machine with the art — and both were watched
failing with `lab` added to the pool.

The main thread wears nothing. It has no `agent_id`, which is the identity rule
rather than an exception, and the scene renders it undressed.

### I7, which binds harder here than anywhere

A costume is drawn **on** the character, which owns the darkest and most
saturated pixels in the room. Two numbers per costume, on the seated frame, from
`cast-sheet.py --measure`:

| costume | max saturation | darkest value | block colour |
|---|---:|---:|---|
| `hivis` | 0.918 | 0.314 | (241,170,50) |
| `apron` | 0.770 | 0.314 | (220,195,152) |
| `overalls` | 0.743 | 0.314 | (93,137,222) |
| `office` | 0.627 | 0.314 | (161,166,163) |
| `field` | 0.557 | 0.314 | (158,115,110) |
| `lab` | **0.463** | 0.314 | (225,220,225) |
| `n01`-`n06` | 0.556 - 0.770 | 0.314 | see the table in `process-assets.py` |

Against the undressed cast: darkest **0.314** on every variant, weakest peak
saturation 0.598 (variant 06). Against the room: max saturation 0.183, mean
value 0.741-0.817 across the six themes.

- **No costume is ever the darkest thing on screen.** Every one bottoms out at
  the pack's own 0.314, which is the cast's floor to four decimals, because it
  is the same ink. That is by construction *and* by refusal: **five of the 132
  colourways go below it** — `Outfit_25` 02-05 at **0.224** and `Outfit_10_04`
  at **0.282** — and `COSTUME_EXCLUDED` names them, `process-assets.py` refuses
  to cut them, and `lint-palette.py` fails on one if it ever reaches a manifest.
  Watched failing at 0.224.
- **A costume can take its wearer under the 55% saturation floor, and one
  does.** `lab` covers premade 06's most saturated pixels and leaves the
  character peaking at **0.463** on the seated frame. That is still 2.5x the
  room's 0.183 ceiling, so I7's actual invariant — the room owns neither the
  saturation nor the dark values — holds; what it erodes is the margin the lint
  keeps. It is not repaired, because **a white lab coat has no saturation and
  there is no saturated lab coat**, and repainting the one garment the
  maintainer asked for by name to satisfy a threshold would be the wrong fix.
  Every other costume clears 0.55 by selection, and the lint prints the list.
- `lint-palette.py` gained a costume stage that measures both, over every
  declared frame, and prints "none declared" when there is no wardrobe — because
  a check that prints nothing is indistinguishable from one nobody ran.

### What is on disk, and what is in the manifest

`scripts/process-assets.py` cuts `assets/processed/costumes/32x32/<id>/l<n>/` —
1128 frames, 94 per costume, byte-identical across a forced rerun.

**`assets/manifest.json` declares the wardrobe, and `scripts/build-manifest.py`
emits it unconditionally.** It shipped behind a `--costumes` flag while
`CostumeContractTests.theShippedManifestDeclaresNoWardrobeAndThatIsLegal` still
asserted the opposite; that assertion has since flipped to
`theShippedManifestDeclaresAWardrobeTheResolverCanReach`, and the flag with it.
**The flag was the hazard, not the safeguard.** A rerun without it deleted a
hand-verified section and exited 0, which is the same failure mode that once
replaced a 1344-path manifest with a 148-path one. There is now no way to ask
for a manifest without the wardrobe, and `build-manifest.py` additionally
refuses to overwrite a manifest that already declares a section the run it is
about to write does not — see "Reproducible from the generator" below. The scene
half was ready before any of this: rendering `fixtures/three-subagents.jsonl` at
`720x400` through `spriteroom --render` against a costumed manifest changes
**352 px** against the same render with no wardrobe, all of it on the two
subagents that carry an `agent_type`, none of it on the main thread.

## Stations are specified, selected, and drawn by nothing — M6g

**Superseded 2026-08-09 by "Stations are art — M6h" below.** The scene draws
them now and `assets/manifest.json` declares eleven. The section is kept whole
because two of its measurements are still the reason the art is what it is — the
desk/chair ink ratio, and the finding that a bigger pool is not a better one —
and because the paragraph refusing to write a manifest nothing could render is
the correct instinct recorded at the moment it was right.

ADR-002 §4 and §7 give every theme a `props.stations.<id> = {desk, chair, prop?}`
map, and `ThemeSelector.station(agentID:agentType:in:)` picks one per agent.
Filling that map was scoped as a manifest-only change on the stated ground that
the scene already resolves stations. **It resolves them and it does not draw
them**, so the manifest half cannot be done alone.

The evidence, in the order it was gathered:

- `Manifest.swift` decodes `props.stations` into `Manifest.Station` and exposes
  `station(_:)` and `numberedStationIDs`. **Nothing under `Sources/` calls
  either** except `ThemeSelector` and the tests.
- `SceneDirector` stores the resolved id in the presentation record and never
  emits it: `SpriteIntent.spawnCharacter` carries `variant`, `nameplate` and
  `seat`, and no station.
- `RoomScene.buildRoom()` places `props.roles.chair` and `props.roles.desk` at
  every seat, once, at build time, from the **theme-wide** roles — occupied
  seats and empty ones alike.
- Measured rather than read: a manifest with six stations declared in **all six
  themes**, whose numbered desks are a chalkboard, a drum kit, a softbox, a flip
  chart and a two-screen post — art that could not possibly be mistaken for the
  desk that ships — renders **byte-identical** to the manifest with no stations
  at all, through `spriteroom --render` at 720×400 over a fixture carrying three
  agents of two different `agent_type`s. Six themes, six pairs of PNGs, zero
  differing bytes.

Writing the stations anyway would put a claim in the manifest that no user can
see, which is precisely why `characters.poses.working` is still empty (M6b): a
table whose entries render identically makes §7 look satisfied while the
complaint it answers stays true.

### What was decided anyway, so the scene work is not blocked on this again

**Pool size: 6, with ids `01`…`06` rather than `1`…`6`.** Both halves of that are
measurements, not taste.

`agent_type` in `fixtures/` is only ever three values across all 17 captures:
`general-purpose` (165 events), `Explore` (23) and **the empty string** (17),
which is `station.default` by construction and never enters the hash. So the
real hashable population is **two types**, and "the collision rate" is not a
probability — it is a fact that can be computed against the pinned FNV-1a. Over
a wider corpus of twelve plausible agent names — this repo's own `.claude/agents/`
plus the standard set — with ids `1`…`N`:

| pool | `Explore` vs `general-purpose` | stations used | colliding pairs of 66 |
|---:|---|---:|---:|
| 2 | **collide** | 2/2 | 47.0% |
| 3 | **collide** | 3/3 | 37.9% |
| 4 | separate | 3/4 | 45.5% |
| 5 | separate | 4/5 | 21.2% |
| 6 | separate | 5/6 | 13.6% |
| 7 | separate | 6/7 | 10.6% |
| 8 | **collide** | **3/8** | 68.2% |

**Pool size is not monotone in separation, and that is the finding.** At eight
stations ten of the twelve names land on `"8"`. The hash is pinned and its
inputs are one-character ids, so the id *strings are part of the key* and their
shape matters: `"10"`…`"80"` reproduces the `"1"`…`"8"` column exactly, while
zero-padded `"01"`…`"06"` uses **6 of 6** stations and drops the collision rate
to 12.1%, below the 1/6 an ideal hash would give. `numberedStationIDs` accepts
any all-digit id, so the padding is free.

The rule that follows is worth more than the number: **a station pool is checked
against the types that actually appear, with a script, before it is written
down.** Choosing 8 because 8 is more than 6 would have produced a room where
every subagent sits at the same desk.

**What varies: the desk, and never the chair.** Also measured, on the art already
in the manifest, at `1x` in the real panel with six agents seated:

| | visible pixels, 7 seats | per seat |
|---|---:|---:|
| `chair`, across the six themes | 680 – 1 448 | 97 – 207 |
| `desk`, across the six themes | 3 864 – 16 740 | 552 – 2 391 |

The desk is **5.7× to 16.6×** the chair's visible area, because the chair is
behind the character and the desk is in front of it. Swapping only the desk
between the three distinct desks the manifest holds changes 9 324–17 456 pixels
of the panel — **45–83% of all the ink the room has** — of which 4 816–10 376 is
silhouette. Swapping the chair could not change more than 1 448 even if a second
chair existed.

It does not. Office 104 is the only chair in any pack verified to be a side view
with its backrest on the left, which is what the pack's one-directional seated
pose requires; every themed chair located at M6 is a front or back view and
would seat a character facing into its own backrest. So `chair` is not a
variable, and a station's honest shape here is **a desk, and at most an adjacent
floor prop**.

**`station.main`.** The main thread is the anchor every report walks to and is
the one character the identity rule already treats as special — it has no
`agent_id` and no nameplate suffix. Its station should be the widest and tallest
work surface the theme owns, so the anchor is legible as the anchor from the
silhouette alone at `1x`, and it should be the *only* station that carries the
optional `prop`, because that is one more piece of ink at exactly one seat. It
must not be a *different kind* of furniture — a throne, a bigger chair — because
that would assert seniority, which no datum says. Bigger desk, same room.

## Stations are art — M6h

Eleven stations, declared once at `room.props.stations` and inherited by all six
themes. The mechanism, the two tiers and the two geometric limits are ADR-002
§14c; this section is the art and the measurements behind it.

**What varies is the prop, and M6g's own numbers are why.** M6g measured that the
desk is 5.7×–16.6× the chair's visible area, and concluded the desk is the
variable. Rendering the candidates says otherwise: every desk in the Modern
Office pack that fits the 32×44 limit comes out of the I7 transform as the same
pale slab, differing only in tone, and at `1x` a tone difference on a horizontal
slab under a body reads as nothing. Two hundred and seventy-four of the 339
singles were rendered from `assets/processed/` — the desaturated files, not the
raw sheet, because the transform is most of what decides this — and looked at.
Every station therefore overrides **only** `prop`; `desk` and `chair` are the
theme's own, per theme.

That also protects the theme. A station that carried its own desk would put an
Office slab in the Reading Room, which spends the identity the theme sets exist
to carry.

| station | asserts | single | what stands at the seat | box |
|---|---|---:|---|---|
| `main` | no | 98 | tall leafy pot plant | 32×56 |
| `default` | no | — | nothing; the empty desk the seat already has | — |
| `survey` | **yes** | 331 | packed rucksack | 26×42 |
| `screens` | **yes** | 275 | twin monitors on a floor pedestal | 32×70 |
| `drafting` | **yes** | 155 | stack of paper reams | 32×42 |
| `machine` | **yes** | 168 | floor-standing copier | 24×44 |
| `reference` | **yes** | 204 | two-drawer filing cabinet | 24×48 |
| `n01` | no | 100 | snake plant | 22×52 |
| `n02` | no | 173 | water cooler | 26×60 |
| `n03` | no | 147 | briefcase | 30×32 |
| `n04` | no | 202 | tall single locker | 24×76 |

Every index was found the way the standing rule asks: rendered with
`contact-sheet.py --office`, inspected at 3× and 6×, and the content box measured
off the shipped PNG with `build-manifest.py`'s own `content_box` rule. All eleven
are already in `room.props.files`, so nothing new was imported and the import
pass had nothing to cut for them — the table above lives in `process-assets.py`
as `STATIONS` because that script owns which single fills which slot, not because
a station costs it any work.

**The pool is checked against real names, which is M6g's rule applied to a
different pool.** `roles` translates the five agent types a session actually
produces, so the hash is only ever asked about a name nobody anticipated. Over a
corpus of sixteen plausible unrecognised names, `n01`…`n04` uses **4 of 4**
stations with **23.3%** colliding pairs against the 25.0% an ideal hash would
give. A pool of four is enough because the tier above it takes the traffic.

**`station.main` is not the widest desk, and M6g's recommendation is declined.**
It cannot be: a station no longer varies the desk. It carries the largest prop
instead — the tall leafy plant, 32×56, the biggest silhouette in the set — which
is the same argument (read the anchor from the silhouette at `1x`) reached
through the channel that still exists.

**Two theme desks fail the station limits, and it is not new.** Measured off the
manifest: `library`'s `props.roles.desk` is 56×70 and `mission_control`'s 44×36,
against limits of 32 wide and 44 tall. The height one was visible — rendering
`fixtures/three-subagents.jsonl` in `library` at 720×400 showed the desk drawn
over the face of every seated character, because a desk takes the row's depth
plus a half deliberately and 70px is well past the 44px at which the shortest
variant's head starts. `buildRoom()` places it at every seat whether anyone is
sitting there or not, so this predates stations entirely and no station made it
worse.

> **The height half is fixed, and the fix is in the scene rather than in the
> art.** `RoomScene.surfaceDepthBias(deskHeight:headClearance:)` resolves a
> desk's depth from its own content box: at or under the shortest head it is
> drawn **in front of** the body, as it always was, and above it **behind** the
> body and behind the chair. The argument for putting a desk in front assumes a
> desk shorter than the person at it — at 32 px the near edge crossing the body
> is the only cue that a character is sitting *at* one. At 70 px that cue is not
> weakened, it is moot: the desk covers the whole body including the face, and a
> room whose characters have no faces cannot be read at all. Losing a depth cue
> costs less than losing the character. `scripts/preview-theme.py` transcribes
> the same rule, so `lint-palette.py --verify` still holds the two pictures
> together.
>
> **And the test now checks what the room DRAWS rather than what a station
> DECLARES**, which is why the defect survived a milestone:
> `StationContractTests.everyStationFitsTheSeatItIsDrawnAt` walks every desk any
> theme can put at a seat — inherited and station-declared, `manifest.room`
> included — and asserts none of them is drawn in front of a head.
>
> **The width half is not fixed and is bounded instead.** A desk is centred on
> `deskPosition`, so its right edge reaches `28 + w/2` from its seat and the next
> seat's station prop lane starts at `+48`: `library`'s 56px desk overhangs that
> lane by **8px** and `mission_control`'s 44px one by **2px**. Nothing is
> hidden by it. Closing it means choosing a different desk single in
> `assets/manifest.json`, which was out of scope; the measured overhang is
> asserted, so a theme arriving with a desk wide enough to stand *on* the
> neighbour fails instead of shipping.

**The lint sees the station props under `room`, not under the theme drawing
them.** All eleven are Modern Office singles, which `room.props.files` already
declares, so they are measured against `room`'s thresholds and the six per-theme
contrast figures are byte-identical to before this change (`mission_control`
still 0.427 against a 0.40 floor). That is a real gap: a station prop is on
screen in every theme and is scored against none of them. It is small today
because every one of them came off the same transform band the room did, and it
stops being small the first time a station carries themed art.

## Reproducible from the generator — M6i

`assets/manifest.json` is generated, and for a while it was not. Two sections had
been hand-authored into it — the wardrobe at `characters.costumes` (12 sets, a
`roles` table, an `assignable` pool) and the station map at `room.props.stations`
(11 stations, the same two-tier shape) — that `build-manifest.py` knew nothing
about. **A rerun deleted both and exited 0.** That is not a hypothetical: a rerun
in this project's history replaced a 1344-path manifest with a 148-path one, and
recovery was a `git checkout` plus a re-run. `assets/` is gitignored apart from
this one file, so the manifest is the single art artefact a bad rerun can destroy
outright.

Three changes close it, and the order matters — the first two make the rerun
correct, the third makes being wrong about that survivable:

1. **`STATIONS`, `STATION_ROLES`, `STATION_ASSIGNABLE` and `STATION_PROP_MAX_W`
   in `process-assets.py`**, with a `build_stations()` emitter in
   `build-manifest.py` that measures each prop's `content_box` off the shipped
   PNG rather than restating a transcribed number. The tables live in the import
   pass for the reason every other single-index table does: that script owns
   which single fills which slot. The 32px seat-gap limit from ADR-002 §14c is
   checked against the measured box at emit time, so a prop that would clip its
   neighbour fails the generator instead of the suite.
2. **`characters.costumes` is emitted unconditionally.** The `--costumes` flag is
   gone. See above.
3. **A no-regression check before the write.** `build-manifest.py` reads the
   manifest it is about to overwrite and refuses, exit 2, if any of
   `characters.variants`, `characters.costumes`, `room.props.roles`,
   `room.props.stations`, `badges.map` or `themes.sets` is populated there and
   empty in the run about to replace it. The empty-manifest guard already caught
   *no art at all*; this catches the far likelier case of one directory missing,
   where the result is internally consistent, plausible, smaller, and exits 0.
   Verified by parking `assets/processed/costumes/` and rerunning: exit 2, the
   target untouched.

**The bar was byte-identical and it is met.** `build-manifest.py --out` to a
temporary file, `cmp` against the committed manifest: zero differing bytes,
3269 asset paths, over a tree that already carried both hand-authored sections.
Two properties made that reachable and both are worth keeping:

- **Insertion order is the emitted order** for `costumes.roles`, `stations.sets`
  and `stations.roles`. The tables are grouped by costume and by tier, which is
  how a reviewer wants to read them; the emitter used to `sorted()` the costume
  roles and threw that grouping away on the way to the artefact people actually
  read.
- **The `roles` tables are keyed on names a stranger's session produces.** ADR-002
  §14c's finding — that `costumes.roles` was keyed almost entirely on this
  repository's own invented subagent names, addressed to an audience of one — now
  holds for the wardrobe too: 21 entries led by Claude Code's own agent types
  (`Explore`, `Plan`, `general-purpose`, `claude`, `claude-code-guide`,
  `statusline-setup`) and the conventional names a user picks by hand
  (`tester`, `reviewer`, `developer`, `designer`), with this repo's own names
  kept at the end of their costume's group.

## Scripts

| Script | Does |
|---|---|
| `scripts/pnglite.py` | minimal PNG decode/encode, stdlib only. No pip anywhere in this pipeline. |
| `scripts/process-assets.py` | the import pass — room recolour, shadow strip, character slicing, badge cutting and badge compositing. Idempotent; verified byte-identical across a forced rerun. It also writes `assets/processed/badges/32x32/sources.json`, which records the sheet, cell and bounding box behind every badge, and the search result behind every badge that has none, and `_bubble_frame.png`, the pack's empty bubble on the badge canvas. |
| `scripts/generate-art.py` | **renamed from `generate-placeholders.py` at M5c.** Authors the four glyphs no pack draws — on the pack's 2× design grid, in the pack's four-colour palette — and composites them into `_bubble_frame.png`, so an authored badge is the same construction as a pack one. Also draws `document`/`checklist` as the fallback behind pack art, and the fallback cast under `--characters`. Falls back to a hand-drawn bubble only when there is no pack on disk at all. |
| `scripts/build-manifest.py` | generates `assets/manifest.json` from disk, re-stating every path. **Takes no flag that changes what it emits** — a clean rerun reproduces the committed manifest byte for byte, and it refuses to overwrite one that already declares a section this run does not. `--out` redirects the write, which is how that claim is checked. |
| `scripts/lint-palette.py` | the I7 gate, over `room` **and every theme**, on the same thresholds. Three colour checks and, since M6d, a **motion budget** — everything a theme animates, counted once per copy the room draws, must change fewer pixels per second than the quietest looping animation in the cast. It measures the frames itself and cross-checks the manifest's generated figures rather than reading them. Since M6f it also runs the **scene comparison**: the placement census it multiplies by is checked against the real `RoomScene`, so the count is tied to a renderer instead of to a second opinion from the same author. A missing app binary is a visible skip, not a pass; `SPRITE_ROOM_REQUIRE_SCENE=1` makes it a failure and `--no-scene` skips it loudly. Non-zero exit names the file and the value. |
| `scripts/cast-sheet.py` | the costume review pass: `--coverage` scans the generator layers' alpha channel per pose row and direction, `--outfits` renders all 33 designs on a premade front-facing and seated, `--costumes` puts every costume on a seated character at `1x` and `4x`, `--room` seats the recognised six in the real 720x400 panel, `--measure` prints the silhouette matrix against M0's arithmetic plus the value, block-colour and I7 tables, and `--select` re-derives the assignable pool. A review tool: writes to a scratch directory, never touches `assets/`. |
| `scripts/contact-sheet.py` | renders index-named singles onto labelled contact sheets, because the packs ship no names. `--set`/`--office` for singles, `--sheet` to label a Room Builder grid by row-col, `--pick` to confirm specific candidates at 4×. A review tool: it writes to a scratch directory and never touches `assets/`. |
| `scripts/preview-theme.py` | composes a theme at `1x` at the real 720×400 panel, with characters, **from the manifest the scene loads**. A theme that cannot be looked at cannot be chosen. Also a check on the manifest: if this can render a theme, the manifest carries enough for the scene to. `--state` seats the cast in any body state, `--badge` puts a `badges.states` entry over every occupied seat, `--frames` writes one PNG per frame of whatever animated prop the theme carries, and `--animated <id>` is the review path for a candidate the manifest has **not** adopted. Warns when a `board` is wider than the back-row pitch, which is a defect only four copies on screen can show. A prop placement bug was fixed here at M6b, two more were found at M6f and left standing on purpose, and **both were fixed at M6g** — the register is empty and all six themes agree with the scene at zero differing pixels. See "The preview is checked against the scene" above. It also owns `prop_layout()`, the single list of every prop the room places, which `role_placements()` counts for the motion budget and `render()` draws. **`--verify` compares the result against the real `RoomScene` through `spriteroom --render`, pixel for pixel, and exits non-zero on any disagreement the register does not name — and the register is empty, so that is any disagreement at all. `register_summary()` prints its contents, including its emptiness, on every run.** `--size WxH` widens the panel past the shipped 720×400, which is what `--verify` needs to see the outer seats. |

Order: process → generate-art → manifest → lint. The lint now needs the app
built, because its last stage renders the real scene; `swift build` before it,
which is the order the definition of done already puts them in.

`process-assets.py` cuts `assets/processed/animated/` for **every** object in
`ANIMATED`, whether or not the manifest adopts it, so a candidate can always be
stood in a room with `preview-theme.py --animated <id>` and argued about. Only
the ids in `ANIMATED_ADOPTED` reach the manifest. It is pruned like everything
else, so deleting a row from `ANIMATED` deletes its frames on the next run.

## Motion is the channel that survives `1x` — M7c

Three detail channels shipped before this one and every one of them was shipped
at the only zoom that ships. `RoomCamera.comfortablePopulation` is empty by the
maintainer's decision, so `scale(forPopulation:)` returns `minimumScale` in every
configuration: the room renders at `1x`, always. At `1x` this document's own
measurements say costumes are a 0.00% closest-pair silhouette difference, a held
object is ~90 px of colour inside an existing outline, and every desk desaturates
to the same pale slab. All three ask the eye to *resolve* something. Motion does
not.

### What the seated art holds — two positions, and that decides everything

Re-derived from the six shipped premades rather than taken from a row name, and
the premade sheet was cut fresh rather than read off `CHAR_ROW_POSE`:

- The sheet is 1792x1312 on a 32x64 canvas: **20 pose rows**, 0...19, with the
  trailing 32 px carrying no ink.
- A character is bottom-aligned, so the last canvas row is the floor. **Rows 4
  and 5 are the only rows whose every frame keeps its feet off it** — `maxY` 61
  against 63 for all eighteen others. Row 5 is the cross-legged floor sit and no
  event means *sit on the ground*, so the room draws row 4 and nothing else.
  This confirms M6g on a second reading rather than restating it.
- **Row 4 is 3 frames per direction and they hold two positions, not three.**
  Over all six variants, block 0:

  | variant | frame 0 vs 1 | frame 0 vs 2 | bbox top |
  |---|---:|---:|---|
  | 06 | 16 px | 548 px | 20 → 20 → **18** |
  | 07 | 20 px | 772 px | 16 → 16 → **14** |
  | 09 | 32 px | 552 px | 16 → 16 → **14** |
  | 10 | **0 px** | 532 px | 20 → 20 → **18** |
  | 17 | 8 px | 616 px | 18 → 18 → **16** |
  | 19 | 8 px | 728 px | 14 → 14 → **12** |

  Frames 0 and 1 are the same pose — an eye blink, and identical on variant 10.
  Frame 2 lifts the whole upper body by 2 px, which is 530-770 px of a
  950-1160 px body.

**So there are not six seated loops to hand out. There is one gesture — a
two-position bob — and the only thing a tool class may choose is when it plays.**
That is the finding, and it is why nothing below invents a frame: every pixel
drawn is a pixel the artist drew for this pose, and a phrase is a schedule over
frames that already exist. The relationship is the one `spawn` and `depart`
already have to `walk`.

### The phrases

`SpriteRoomScene/AmbientMotion.swift`, keyed on the badge class, on the
manifest's own 8 fps grid — 125 ms per step, no new rate anywhere. A two-position
bob has exactly two parameters, **period** and **duty**, so the six mapped
classes are laid out on a 3x2 grid of them rather than tasted one at a time.

| class | phrase | period | raised | reads as |
|---|---|---:|---:|---|
| `terminal` | `S R` | 250 ms | 50% | a continuous fast chatter |
| `document` | `S S S R` | 500 ms | 25% | quick taps with a pause between |
| `plug` | `S R R R` | 500 ms | 75% | held up, with a quick dip |
| `magnifier` | `S S S S S S R R` | 1000 ms | 25% | long still, one slow rise |
| `globe` | `S S S S R R R R` | 1000 ms | 50% | a slow even breathe |
| `checklist` | `S S R R R R R R` | 1000 ms | 75% | held up, one slow dip |
| `question_mark` | — the shipped loop | 375 ms | 33% | unchanged |

Duty is the parameter carrying most of the weight, deliberately. Period is a
rhythm and needs watching; duty is the character's *average* posture and is
half-legible from a glance. `magnifier` and `checklist` are exact inverses of
each other for that reason, and `globe` sits between them.

**`question_mark` gets no phrase.** The rule is the one this document already
applies to the badge and `HeldObject` already applies to the hands: the honest
motion for a tool we cannot name is the motion a character has always had.
`Monitor` is permanently in that bucket. [I1]

### What it buys, measured on the shipped renderer at `1x`

`fixtures`-scale numbers are not the test here; the M7a live capture is, because
it is the only stream that has three classes open at once. Rendered at 720x400
with the camera at `1x`, sampling the 8 fps grid, three characters at their desks
over 12 consecutive frames:

| character | badge | changed px per transition | pattern over 12 steps |
|---|---|---:|---|
| A69 | terminal | 530 | `S R S R S R S R S R S R` |
| 430 | plug | 367 | `S R R R S R R R S R R R` |
| 2D4 | globe | 341 | `S S S S R R R R S S S S` |

For comparison, on the same room: a held object is **90 px** and does not move,
and a costume is **0 px** of silhouette. The bob is the largest per-character
change this room can make and the only one that is temporal.

Formally, every pair of phrases is separated — no phase alignment can make two of
them agree — within **375 to 875 ms** of watching, worst pair `magnifier` against
`globe`.

### What it does not do, and this is the honest half

**A motion is only as visible as the call is long.** [I2] There is no closing
beat for the body: ADR-003 §2 makes the body idle for every frame of the badge's
beat and declares itself void otherwise, and `CLAUDE.md`'s I2 clause permits the
badge to carry a fact the body does not *provided the body is truthful for every
frame*. So this channel inherits ADR-003's exposure problem and cannot inherit
its fix. On the same 224 s capture:

| class | calls | total open s | median s | calls ≥ 250 ms |
|---|---:|---:|---:|---:|
| terminal | 18 | 102.75 | 0.054 | 3 |
| plug | 4 | 100.06 | 25.016 | 4 |
| globe | 8 | 13.19 | 1.764 | 8 |
| document | 10 | 0.75 | 0.074 | **0** |
| magnifier | 16 | 0.11 | 0.006 | **0** |
| checklist | 5 | 0.07 | 0.010 | **0** |

**15 of 61 calls last long enough for the body to complete one bar of the
shortest phrase.** Three of the six classes never do. Their motion at `1x` is not
subtle, it is **absent** — the same three classes the badge channel was blind to
before ADR-003, blind for the same reason, and this time with no honest remedy.
The claim this layer may make is that it separates the classes an agent *dwells*
in. It may not be described as giving every agent its own visible animation.

Two further limits, stated rather than discovered later:

- **`terminal` alternates on every frame of the grid**, which is the fastest the
  8 fps art allows. It reads as busy; if it reads as vibration to the maintainer,
  it is the one phrase to slow, and `S S R R` is the free cell next to it.
- **The hardest pair to tell apart by eye is `plug` against `globe`** — both
  change position every 500 ms and differ only in duty. The formal separation
  (625 ms) is real; the perceptual one is the weakest in the table.
