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
  console, so four badges are still placeholders — see the badge table below,
  which now records what was searched rather than what is awaited.

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
either a Modern Interiors emote (`question_mark`, `attention`, cut whole) or a
Modern User Interface icon dropped into that frame (`document`, `checklist`).
The layering is unaffected: the badge is still one independent sprite above the
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

**Three of these seven are real art. Four are not, and no purchase will fix
them.** Corrected at M5b, replacing this section's previous claim that six were
blocked on buying Modern User Interface.

| Badge | Status | Source |
|---|---|---|
| document | **sourced** — M5b | Modern UI `Style_1` cell (28,22), a page with a pencil across its corner |
| checklist | **sourced** — M5b | Modern UI `Style_1` cell (31,18), a bulleted list |
| question mark | **sourced** — M0b | Modern Interiors emote sheet, blue `?` bubble |
| attention (`Notification`) | **sourced** — M0b | Modern Interiors emote sheet, red `!` bubble |
| magnifier, terminal, globe, plug | **placeholder** | nothing to source — see below |

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

**The placeholders do not, in fact, reuse the pack's bubble** — an earlier
version of this document said they did. Measured at M5b: their frame is a
hand-drawn lookalike with a heavier, darker border, which is why they read
*louder* than the real badges beside them. That is harmless and arguably
correct — a placeholder should be conspicuous — but the sentence was wrong and
is corrected rather than left standing.

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

   **Re-checked at M5b against real art rather than placeholders, because an
   exemption granted to art nobody had seen is not an exemption anyone
   checked.** It still holds, and now for a measured reason rather than a
   structural one. The composited badges are a light bubble (interior
   `RGB(235,225,246)`, value 0.965) carrying a glyph that bottoms out at value
   0.42 and 0.34 saturation. So they are neither the most saturated element on
   screen — the characters' accents clear 0.598 — nor the darkest, the
   characters' darkest pixel being 0.314. The exemption is not being used to
   smuggle in art that would have failed the room test; the badges would pass
   the room's saturation ceiling anyway, and only fail to be *room* art because
   they are brighter than the room's value band, which is the direction that
   costs nothing. If a future badge is ever the darkest or most saturated thing
   on screen, this exemption is the wrong answer and the badge is.
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

Mostly discharged. Characters, room, furniture and **three** badges are real art
as of M5b. What remains a placeholder:

- **Four tool badges** — magnifier, terminal, globe, plug. **Not blocked on a
  purchase any more.** Modern User Interface was bought at M5b, supplied
  `document` and `checklist`, and contains no icon for these four; the search is
  recorded above and in each manifest entry's `unsourceable` field.
  `scripts/generate-placeholders.py` draws them at the real badge canvas, so the
  swap stays a manifest edit with no code change and no layout change — as it
  just demonstrated, twice.

  The way to close these is different in kind from the last one: either find a
  pack that has them, or commission four 16×16 glyphs. There is no third pack
  left to buy in this family.
- A **fallback character set**, generated only on `--characters`. Not in the
  manifest. It exists so that a missing pack degrades to something that renders
  rather than to a crash.
- `SceneBitmaps.placeholderDesk`, now reached only if a manifest declares no
  `desk` role.

The original instruction stands for anything else that goes missing: flat-colour
blocks at the correct dimensions and the correct palette split, and make them
look like placeholders. A placeholder that could pass for final art will survive
to M5.

## Scripts

| Script | Does |
|---|---|
| `scripts/pnglite.py` | minimal PNG decode/encode, stdlib only. No pip anywhere in this pipeline. |
| `scripts/process-assets.py` | the import pass — room recolour, shadow strip, character slicing, badge cutting and badge compositing. Idempotent; verified byte-identical across a forced rerun. It also writes `assets/processed/badges/32x32/sources.json`, which records the sheet, cell and bounding box behind every badge, and the search result behind every badge that has none. |
| `scripts/generate-placeholders.py` | draws what no pack supplies. Still draws all six, but two of them are now only the fallback behind real art. |
| `scripts/build-manifest.py` | generates `assets/manifest.json` from disk, re-stating every path. |
| `scripts/lint-palette.py` | the I7 gate. Non-zero exit names the file and the value. |

Order: process → placeholders → manifest → lint.
