# 04 — Art direction

Revised after selecting the source art. Three LimeZu packs, all under the same
licence:

- **Modern Interiors** — characters, the character generator, base interiors.
- **Modern Office (Revamped)** — desks, chairs, monitors. The room.
- **Modern User Interface** — the icon set used for tool badges.

Licence terms are identical across all three: use in a commercial or
non-commercial project is permitted, redistribution of the assets is not, credit
to `limezu.itch.io` is required. Two consequences that are not negotiable:
`assets/` is gitignored or the repo is private, and the credit link ships in an
About panel.

---

## The rule that governs this whole document

**Nothing enters `assets/manifest.json` until it has been located in the
downloaded files.**

Multiple buyers have reported sprites visible in the packs' promotional images
that do not exist in the download — chairs, sofas, a back-view sitting pose.
Specifying a scene around a pose that does not ship is a failure discovered at
M2, when it is expensive. Frame counts, canvas sizes, and pose names in this
document are therefore **claims to verify, not facts**. Verify at M0, alongside
the hook payloads, and correct this file.

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
| **Body** | Modern Interiors character sheets | what the agent is *doing* |
| **Badge** | Modern UI icon set, floating above the head | *which tool* is running |
| **Room** | Modern Office tileset | the setting and the anchor desk |

Nothing is held. Delete every reference to a held prop.

## Canvas

- Packs ship at 16×16, 32×32, and 48×48. **Use the 32× set** unless M0 finds it
  incomplete — one buyer reported interiors content missing at 32 and 48.
- Character sprites: expected 32×32. Verify.
- Room tiles: 16×16 at the 16× set, scaling accordingly.
- Badges: the UI icon set's native size, unscaled relative to the character.
- Integer render scale only: `3x`, `2x`, `1x`. [I6] `1x` is the floor.
- `.nearest` filtering on every texture. No mipmaps.

**Build the manifest from the singles, not the sheets.** All three packs supply
individual PNGs (300+ in Modern Office alone), and buyers consistently report
the combined sheets are difficult to slice — grids are uneven and some sprites
sit off-grid. You have no auto-slicer. Singles avoid the problem entirely.

## Body states

Five states are sourced directly. Two are composed. None are invented.

| State | Source | Notes |
|---|---|---|
| `idle` | `idle` | standing, not at a desk |
| `working` | `_sit` / `_sit2` / `_sit3` | side-view sitting. This is the desk pose. |
| `walk` | `run` | the pack ships a run cycle, not a walk. Slow the frame rate rather than redrawing. |
| `deliver` | `gift` | a handing-over animation. Exactly the `SubagentStop` beat. |
| `read` | `read a book` | optional flavour for read-class tools; drop if it reads as unrelated at `2x`. |

Composed, not sourced:

- **`spawn`** — walk in from the room edge using `walk`. There is no spawn
  animation and inventing one is not worth the cost.
- **`depart`** — the same in reverse.

Not represented at all:

- **`attention`** (`Notification`) — no suitable body animation exists. Use the
  badge alone. A state shown by badge only is honest; a body animation
  repurposed from `punch` or `shoot` would be fiction. [I1]

Frame rate 8 fps. Frame counts come from the download.

## Sitting is side-view only

The `_sit` poses are side-view. The back-view sitting pose that appears in the
Modern Office demo gif could not be found in either pack by at least one buyer.

**Design the room so desks are viewed from the side.** Do not lay out an office
that requires characters facing away from the camera, and do not put a
back-view desk in the manifest before someone has found that sprite in the
files. If it genuinely does not exist, the side-view layout is the design — not
a compromise to fix later.

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

Pick the closest icon in the UI pack for each row at M0 and record the filename
in the manifest. Unmapped tools get the question mark and are logged — never
guess a badge for a tool you do not recognise. [I1]

**Multiple open calls:** show the badge for the *lowest-ordinal* tool in the
table, plus a small `×N`. Deterministic ordering keeps the badge stable while
calls interleave; most-recent-wins flickers. [I3]

## The palette rule is now a build step [I7]

I7 was written assuming we authored both the room and the characters. We do
not — the room is a purchased tileset with its own palette, and the characters
come from a generator.

So the rule becomes a **preprocessing pass**, not an authoring instruction:

1. Room tiles are desaturated and value-compressed at asset-import time, by
   script, into `assets/processed/`. The licence permits editing.
2. Character sprites pass through untouched.
3. The existing lint runs over `assets/manifest.json` after processing, and the
   thresholds in the previous version of this document still apply: room under
   25% saturation, every character carrying something above 55%, at least 40%
   value contrast between a character's darkest pixel and the mean room value.

Do the pass in a script committed to the repo, not by hand in an image editor.
Hand-edited assets cannot be regenerated when the pack updates.

Note that the packs ship **shadow options**, and several tiles carry a baked
grey shadow that does not blend with arbitrary floors. Prefer the shadowless
variants where supplied; the import script strips the rest.

## Character distinctness

Characters come from the generator, so their identity is a set of choices, not
a drawing task. The constraint from the previous version survives intact:
**silhouette carries identity at `1x`.**

- Choose outfits and hairstyles that differ in *outline*, not only in colour.
- Verify by flattening two variants to solid black. If you cannot tell them
  apart, they are the same character in different colours.
- One accent hue per variant, and that hue appears nowhere in the processed
  room.

The generator is Windows and Linux only — its author has stated there is no Mac
build because of Apple's signing requirements. Export the full cast in one
session under a VM, commit the results to `assets/`, and do not make the build
depend on the tool.

## Typography

No font ships with any of the three packs; the previews use Arial Bold. Source a
pixel font for nameplates. Arial at 8pt beside this art looks exactly as wrong
as it sounds.

## Placeholders

Unchanged: ship M1 and M2 with flat-colour blocks at the correct dimensions and
the correct palette split. The scene builds against the manifest, so real art is
a manifest swap with no code change.
