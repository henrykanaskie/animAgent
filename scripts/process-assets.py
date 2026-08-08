#!/usr/bin/env python3
"""Asset import pass. Cuts the three purchased packs into what the scene loads.

Three as of M5b: Modern User Interface was bought, and two more tool badges came
out of it. Four did not — the pack has no magnifier, no globe, no plug and no
terminal anywhere in it, which is a fact about the download and not a scheduling
problem. Those four are authored by scripts/generate-art.py as of M5c, since no
further packs will be bought. See docs/04-ART-DIRECTION.md.

docs/04-ART-DIRECTION.md: "Do the pass in a script committed to the repo, not by
hand in an image editor. Hand-edited assets cannot be regenerated when the pack
updates." This is that script. Everything under assets/processed/ is disposable
and reproducible; nothing here writes back into a pack.

Three layers, three treatments:

  ROOM      Modern Office singles + Room Builder. Desaturated and
            value-compressed under the I7 ceiling, baked shadow stripped.
  CHARACTER Modern Interiors premade sheets, sliced into per-frame PNGs.
            Colour is passed through UNTOUCHED — I7 gives the characters the
            saturation and the dark values, so processing them would destroy
            the very contrast the lint checks for.
  BADGE     Modern Interiors UI sheet, cut by measured rectangles, plus Modern
            User Interface icons composited into the *same* bubble frame. Colour
            untouched: a badge is UI floating above the room, not part of it.

Python 3 stdlib only. No pip, no Pillow.

Idempotent: output is a pure function of input bytes, pnglite's encoder is
byte-deterministic, and a state file skips unchanged inputs. Two runs leave the
tree identical — verified by hashing.
"""

import argparse
import colorsys
import collections
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "assets")
OFFICE = os.path.join(ASSETS, "Modern_Office_Revamped_v1.2")
INTERIORS = os.path.join(ASSETS, "moderninteriors-win")
USERINTERFACE = os.path.join(ASSETS, "modernuserinterface-win")
OUT = os.path.join(ASSETS, "processed")
STATE = os.path.join(OUT, ".import-state.json")

# ---------------------------------------------------------------------------
# Room palette transform [I7]
# ---------------------------------------------------------------------------

# Exact colour of the Office pack's baked drop shadow. Derived, not guessed: it
# is the single colour making up all 16560 pixels present in
# Modern_Office_32x32.png and absent from Modern_Office_Shadowless_32x32.png.
SHADOW_RGB = (167, 151, 150)

# I7 ceiling is 0.25 saturation. Target below it so 8-bit rounding cannot push a
# pixel over the line and fail the lint on a technicality.
SAT_TARGET = 0.18
SAT_SCALE = 0.35

# Room values are squeezed into this band. Both ends are load-bearing.
#
# The FLOOR is what makes the room incapable of owning the darkest pixel on
# screen, and it is set by measurement, not taste: the darkest pixel in the
# Modern Interiors premade characters sits at value 0.314, and I7 demands at
# least 0.40 of value contrast against the MEAN room value. A room mean of
# ~0.78 clears that with margin. An earlier band of [0.45, 0.85] produced a
# room mean of ~0.70 and failed the lint at 0.386 — the fix was to lighten the
# room, because I7 says the room is the low-contrast layer, not that the
# threshold is negotiable.
VALUE_FLOOR = 0.55
VALUE_CEIL = 0.92

# A theme may widen the band FOR ITS PROPS ONLY, by lowering the floor. Added at
# M6b for `mission_control` and deliberately not offered to the wall or the
# floor tile.
#
# What it is for. Every theme that reads at 1x has one dark shape — library's
# chalkboard, stage's drum kit. Mission control's dark shape has to be a screen,
# and the pack's darkest ink is value 0.314, which the standard band lifts to
# 0.667 whatever the sprite. That is why every screen we tried came out the same
# pale grey as the desk it stood on: the transform, not the choice of sprite,
# was flattening them. Lowering the floor for the prop layer expands the range
# the props are drawn on — the lights barely move, the darks drop — so a screen
# face separates from its own bezel and from the wall behind it.
#
# Why props only. The wall is the largest continuous area on screen and sits
# directly behind every character, so it stays on the standard band for the same
# reason docs/04-ART-DIRECTION.md gives for it being flat. The floor is the
# second largest and carries the theme's surface identity by *pattern*; a
# darker floor would buy texture we can get from tile choice and would spend
# contrast budget the props need more.
#
# What still binds. Nothing here touches a lint threshold. The room may still
# not own the darkest pixel on screen: at a floor of 0.46 the darkest prop pixel
# in the theme is 0.604 against the characters' darkest at 0.314. And I7's
# contrast check is `theme mean - character darkest >= 0.40`, measured over the
# theme's own art by scripts/lint-palette.py, which is what makes this a budget
# rather than a free hand. Spending it is what the numbers in
# docs/04-ART-DIRECTION.md record.
PROP_VALUE_FLOOR_DEFAULT = VALUE_FLOOR

# ---------------------------------------------------------------------------
# Themed rooms
# ---------------------------------------------------------------------------
#
# Modern Interiors ships 24 "Theme Sorter" single sets, 5330 sprites, named by
# index only — same as the Office singles, and for the same reason: the .ase
# holds unnamed frames with no slices and no tags. So every index below was
# found by rendering the set with scripts/contact-sheet.py and looking at it,
# then confirmed at 4x with `contact-sheet.py --pick` before being written here.
# Nothing in this table entered it any other way.
#
# THE FOUR ROLE NAMES ARE PLACEMENT SLOTS, NOT OBJECT NOUNS. The scene places
# exactly four things — a work surface at each seat, a seat, a standing object
# on the back wall, and a repeated accent along the back wall and the foreground
# walkway — and it looks them up under the names `desk`, `chair`, `board` and
# `plant`. Those names are the Office room's vocabulary and they are now the
# *interface*. A theme fills the `plant` slot with a console terminal or a stage
# curtain; that is not a mislabelling, it is the slot doing its job. Renaming
# them to `surface`/`seat`/`backdrop`/`accent` would say what they mean, but it
# is a scene change and this table is deliberately not one. See
# docs/04-ART-DIRECTION.md.
#
# `chair` is the Office chair in every theme, and that is a finding rather than
# laziness: the seated pose in the character pack faces right and *only* right,
# so the chair must be a side view with its backrest on the left. Office single
# 104 is the only chair verified to be one. Every themed chair located — the
# director's chairs in set 23, the school chairs in set 5 — is a front or back
# view and would seat a character facing into its own backrest. [I1]
#
# Floor and wall are (row, col) addresses into the Modern Interiors Room Builder
# subfiles, picked with `contact-sheet.py --sheet`. Each floor pattern occupies
# a 2x3 block on that sheet; the address is the top-left cell of the block.
THEME_FLOORS = os.path.join(
    INTERIORS, "1_Interiors", "%s", "Room_Bulder_subfiles_32x32",
    "Room_Builder_Floors_%s.png")
THEME_WALLS = os.path.join(
    INTERIORS, "1_Interiors", "%s", "Room_Bulder_subfiles_32x32",
    "Room_Builder_Walls_%s.png")
THEME_SINGLES = os.path.join(
    INTERIORS, "1_Interiors", "%s", "Theme_Sorter_Shadowless_Singles_%s")

# (set number, single index). Set "office" means the Modern Office singles,
# which is where the desk and the only usable chair come from.
THEMES = {
    "office": {
        "title": "Open Plan Office",
        "what": "the room as it shipped through M5 — the Modern Office pack",
        "floor": None,          # office keeps its own Room_Builder_Office tiles
        "wall": None,
        "roles": {
            "desk":  ("office", 34, "plain office desk, side view, top slab plus two legs"),
            "chair": ("office", 104, "office chair, side view, backrest to the left"),
            "board": ("office", 171, "presentation board on a stand, chart on the face"),
            "plant": ("office", 99, "small potted plant, floor standing"),
        },
    },
    # REBUILT at M6b. The first version passed the lint and failed the eye: it
    # read as grey monitors on a grey floor, and its own numbers agreed — the
    # darkest theme at mean value 0.753 and the least contrast margin at 0.439.
    # Three things were wrong and all three are fixed here rather than
    # recoloured.
    #
    #   1. Two silhouettes, both a rectangle on legs. The old `board` was a
    #      58x38 flat screen on a low stand and the old `desk` a 40x48 workbench
    #      with a pale top; at 1x, one tile apart, they merged into a single
    #      slab. `board` is now a 30x64 two-screen surveillance stack on a
    #      pedestal — tall, narrow, and nothing else in the six themes has that
    #      outline.
    #   2. A floor that was not a floor. Address (14,12) measures 0.043 of value
    #      range after the transform, which is a flat field with a rumour of a
    #      pattern in it. (28,8) is a fine square grid that survives the
    #      transform and tiles seamlessly in both axes — checked, not assumed.
    #   3. No dark anchor, and the transform was the reason. See
    #      PROP_VALUE_FLOOR_DEFAULT: props here are drawn on a band floored at
    #      0.46 instead of 0.55.
    "mission_control": {
        "title": "Mission Control",
        "what": "a two-tier screen wall over a console row — the closest thing "
                "to a launch control room that the packs we own can build",
        "floor": (28, 8),       # fine square grid, cool grey, transformed 0.722
        "wall": (30, 27),       # pale cool grey-blue, 0.909 — the screens need
                                # something bright behind them, and this is the
                                # only theme whose wall is not warm
        "prop_value_floor": 0.46,
        "roles": {
            # Basement 97, the steel workbench that held `desk` through M6, was
            # cut on value rather than on shape: its top is a pale glass slab
            # that came out of the transform at mean 0.779, the brightest thing
            # in the theme, sitting at exactly the height a seated character's
            # torso occupies. Seven of them made the desk row the loudest band
            # on screen and the characters the quietest thing in it. This one is
            # 0.745 with a mid-grey top, so the row recedes and the screens lead.
            "desk":  (19, 127, "grey equipment table, side view, with a boxed unit and "
                               "a pouch on the top"),
            "chair": ("office", 104, "office chair, side view, backrest to the left"),
            # Set 25's concentric target on a mast (single 15) was here first and
            # was cut after looking at it at 1x: a pale grey dish on a thin mast
            # against a pale wall, half occluded by the desk row, reading as a
            # smudge. It is the most "mission control" object either pack owns
            # and it still failed the only test that matters. Design at 2x,
            # accept at 1x.
            #
            # Basement 164, the wide flat screen that held `board` through M6,
            # was cut for the reason above: it is the same rectangle as the desk
            # in front of it.
            "board": (18, 146, "two screens stacked on a pedestal — a surveillance "
                               "monitor post; the only floor-standing vertical in "
                               "any theme"),
            "plant": (19, 315, "console bench with two wall screens on brackets above "
                               "it; repeated along the back wall it is the screen "
                               "wall, and along the foreground walkway it is the "
                               "second console row"),
        },
    },
    "broadcast": {
        "title": "Broadcast Studio",
        "what": "tripods everywhere — film cameras and softbox lights, a silhouette "
                "no other theme has",
        "floor": (16, 8),       # pale diagonal, 0.788
        "wall": (2, 5),         # near-white, 0.882 — a bright studio
        "roles": {
            "desk":  ("office", 34, "plain office desk, side view"),
            "chair": ("office", 104, "office chair, side view, backrest to the left"),
            "board": (23, 8, "studio softbox light on a tripod, tall"),
            "plant": (23, 1, "film camera on a tripod"),
        },
    },
    "library": {
        "title": "Reading Room",
        "what": "floor-to-ceiling bookcases and a chalkboard — the maintainer's "
                "'classroom', built from the Classroom and Library set",
        "floor": (16, 0),       # wood plank, 0.733
        "wall": (6, 4),         # warm off-white, 0.878
        "roles": {
            "desk":  (5, 26, "wooden desk with an open book and an inkwell on top"),
            "chair": ("office", 104, "office chair, side view, backrest to the left"),
            "board": (5, 39, "green chalkboard on splayed legs"),
            "plant": (5, 57, "tall bookcase, full height, packed spines"),
        },
    },
    "stage": {
        "title": "Rehearsal Room",
        "what": "a drum kit and a row of mic stands; the only theme whose "
                "back wall is not a rectangle",
        "floor": (10, 8),       # herringbone, 0.765
        "wall": (0, 4),         # plain light, 0.863
        "roles": {
            "desk":  ("office", 34, "plain office desk, side view"),
            "chair": ("office", 104, "office chair, side view, backrest to the left"),
            "board": (6, 37, "drum kit — kick, snare, toms, two cymbals on stands"),
            "plant": (6, 62, "microphone on a round-base stand"),
        },
    },
    "briefing": {
        "title": "Briefing Room",
        "what": "a lectern facing a wall of hanging curtain — reads as a hall "
                "rather than a workspace",
        "floor": (14, 8),       # large block tile, 0.769
        "wall": (8, 26),        # blue, 0.859
        "roles": {
            "desk":  ("office", 34, "plain office desk, side view"),
            "chair": ("office", 104, "office chair, side view, backrest to the left"),
            # Single 29, the lectern with a lit screen, was tried first: at 1x
            # its body is pale on a pale wall and all that survives is the
            # screen, which reads as a card floating at chest height. The flip
            # chart keeps a hard-edged white face and a visible tripod.
            "board": (13, 50, "flip chart — a white pad on a tripod easel"),
            "plant": (13, 1, "full-height hanging curtain panel"),
        },
    },
}

# ---------------------------------------------------------------------------
# Animated objects — added at M6b, adopted into the manifest at M6c
# ---------------------------------------------------------------------------
#
# `3_Animated_objects/` is 310 spritesheets and, unlike every other folder in
# these packs, **they are named**. There is nothing to render-and-guess here:
# the file is called `animated_control_room_server_32x32.png`. That is why this
# table is short and why it carries no "identified_by" apology — the sheet says
# what it is and the frames were still rendered and looked at before anything
# entered it.
#
# Frame width is NOT recoverable from the filename and every sheet is a single
# row, so it is measured per sheet and written down. Getting it wrong produces a
# sheet that still tiles into plausible-looking frames, which is the failure
# mode that would survive review — so it is no longer only written down. **The
# pack ships a GIF of every animated object beside the sheet**, and a GIF
# carries its own canvas size, its own frame count and its own per-frame delay.
# `_gif_timing()` reads it, and an object whose sheet does not agree with its
# own GIF is skipped rather than guessed at. That is the same
# verify-before-you-write rule this project applies to filenames, applied to
# time.
#
# THE FRAME RATE COMES OUT OF THAT GIF AND IS NOT A TASTE DECISION. M6b proposed
# "fps: 4" as an illustration and it is wrong for three of the four objects:
# the pack times the server at 50/100 s per frame (2 fps), the pendulum at
# 20/100 (5 fps), and the two 10/100 sheets at 10 fps. A pendulum driven at the
# rack's rate does not swing, and the rack driven at the pendulum's strobes.
# `fps` below is the declared value; the importer recomputes it from the GIF and
# refuses to cut an object whose GIF disagrees.
#
# THE SELECTION RULE, which is stricter than "it looks nice". ADR-002 §9 forbids
# scenery that animates *in response to activity* — that is the room asserting
# something the data did not say. Everything here idles on its own loop and
# claims nothing: LEDs blink, a pendulum swings, a screen carries static. None
# of them starts, stops, or changes with an event, so none of them is in any
# volatility band at all. [I1]
#
# And I7 binds harder here than on a still prop, because motion draws the eye
# and the eye belongs on the characters. The moving-pixel fraction of every
# adopted object is **measured on the shipped frames** by
# scripts/build-manifest.py and written into the manifest, rather than
# transcribed into this comment. It is transcribed nowhere precisely because
# M6b's transcription was wrong twice: it recorded `pendulum_clock` at 4.6% when
# the sheet measures 3.0%, and `old_tv` at 10.4% when the sheet measures 27.9%.
# The second one mattered — 27.9% is a prop that waves, not a prop that is
# alive, and the whole judgement about `old_tv` had been made against a number
# nothing generated.
#
# EACH OBJECT NAMES THE ROLE IT FILLS, AND IT IS ALWAYS `board`. That is
# geometry, not preference. The scene draws `board` at the even seats of the
# back row (four on a 720px panel), `plant` at the odd seats *and* seven more
# along the foreground walkway, and `desk`/`chair` at every seat under a
# character. `board` is the only slot where motion is neither in the foreground
# row nor sitting on top of a character, which are the two places I7 says a
# background detail must never compete. So one animated object per theme, and
# no theme may hold two.
ANIMATED = {
    # NOT ADOPTED, and this one was refused on a number rather than on a
    # picture: it composes well and it is the quietest object in the folder at
    # 3.6%. Adopting it takes `mission_control`'s character-contrast margin from
    # 0.427 to **0.408** against a 0.40 floor — 0.019 of the 0.027 that M6b
    # deliberately left. This theme is the only one that has ever spent margin
    # on purpose and it has the least left, so it is the one theme where a prop
    # that is merely nice does not get to spend any more.
    "control_room_server": {
        "sheet": "animated_control_room_server_32x32.png",
        "frame": (32, 96),
        "for": "mission_control",
        "role": "board",
        "fps": 2,
        "what": "server rack cabinet, three bays of blinking status LEDs",
    },
    # NOT ADOPTED, on two independent grounds, neither of which is the canvas
    # everyone thought was the obstacle. See M6c in docs/04-ART-DIRECTION.md.
    #
    #   1. **It fails the I7 lint.** `mission_control`'s character-contrast
    #      margin goes 0.427 -> **0.363** against a 0.40 floor. It does not cost
    #      margin, it exceeds it: 6796 visible px per frame across 11 frames is
    #      more art than the rest of the theme put together.
    #   2. Its content box is 120 px wide and the scene draws `board` at four
    #      points 96 px apart, so four copies clip each other by 24 px and the
    #      wall reads as broken monitors. Every other board in every theme is
    #      30-64 px, so this is the first object to hit a limit that was always
    #      there and that no canvas size changes.
    #
    # The prop canvas was widened to 128 to admit it and then put back, because
    # widening was never the thing in the way. It stays in this table so it is
    # still cut and still reviewable with
    # `preview-theme.py --animated control_room_screens`.
    "control_room_screens": {
        "sheet": "animated_control_room_screens_32x32.png",
        "frame": (128, 96),
        "for": "mission_control",
        "role": "board",
        "fps": 10,
        "what": "a 3x3 wall of wall-mounted monitors on a bracket frame, "
                "each screen cycling its own readout",
    },
    "pendulum_clock": {
        "sheet": "animated_pendulum_clock_32x32.png",
        "frame": (32, 96),
        "for": "library",
        "role": "board",
        "fps": 5,
        "what": "longcase clock, swinging pendulum",
    },
    # NOT ADOPTED. Two independent reasons, both found by looking at it in the
    # room. It is a TV meant to stand ON furniture — there is nothing under it
    # in the art — and the back row is a floor line, so four of them hang at
    # chest height over nothing. And it moves far more than M6b recorded: 364 px
    # of 1156 (31.5%), not 160 of 1544 (10.4%) and not the 364 of 1304 (27.9%)
    # M6c corrected it to — the numerator was right the second time and the
    # denominator was still typed. Flickering at 10 fps it is the strongest
    # attractor in any room here, and I7 says the eye belongs on the characters.
    #
    # **It is now refused by a check rather than by an eye.** M6c recorded that
    # it would pass the lint (`broadcast` 0.470 -> 0.462) because the lint was a
    # value check with nothing to say about motion. The motion budget added at
    # M6d says something: four copies of this change 13867 px of the panel per
    # second against a ceiling of 1461, which is 9.49x. Adopting it is now a red
    # build, and that is what was verified — see docs/04-ART-DIRECTION.md.
    "old_tv": {
        "sheet": "animated_old_tv_32x32.png",
        "frame": (64, 64),
        "for": "broadcast",
        "role": "board",
        "fps": 10,
        "what": "CRT television on rabbit-ear aerials, screen static",
    },
}

# Which animated object each theme actually adopts. An id here replaces that
# theme's static binding for the object's `role`; a theme absent from this set
# keeps the static prop. It is separate from ANIMATED so that art can stay cut
# and reviewable — `preview-theme.py` can still stand it in the room — without
# being in the manifest, which is the state all four were in through M6b.
#
# **One of the four ships.** Each of the other three is refused above its own
# row, on a measured ground rather than on taste: a lint failure, a lint spend
# this project cannot afford, and a prop that hangs in the air. What it costs to
# ship this one is 0.004 of `library`'s 0.056 of margin — 0.456 -> 0.452.
#
# Emptying this set reverts every animated prop in one line and nothing else
# changes; the art stays cut either way.
ANIMATED_ADOPTED = {"pendulum_clock"}

ANIMATED_DIR = os.path.join(INTERIORS, "3_Animated_objects", "%s", "spritesheets")
ANIMATED_GIF_DIR = os.path.join(INTERIORS, "3_Animated_objects", "%s", "gif")

# Every themed prop is padded into this canvas, bottom-centred, before it is
# written. That is what keeps a themed room a manifest swap with no code change:
# the scene reads ONE `room.props.canvas` for all props and anchors each prop by
# its own measured content_box inside it. The theme sorter singles arrive on
# tight per-sprite canvases — 32x32, 32x48, 16x96, 64x96 — so without this the
# manifest would have to carry a canvas per role and the scene would have to
# learn to read it. Every prop selected above was measured first and fits.
#
# **Widened to 128 at M6c and put back**, and the round trip is worth recording
# because the result is a fact rather than a preference.
#
# It was widened to admit `control_room_screens`, a 128x96 monitor wall. Both
# states were built and all six themes rendered at 720x400 with characters:
# **0 differing pixels of 288 000, in every theme.** That is not luck, it is the
# construction — padding is bottom-CENTRED and placement is by measured
# `content_box`, so widening adds 32 px of transparency on each side, every
# box's `x` gains exactly 32, and the anchor `(box.x + box.w/2) / canvas.w` is
# invariant. It was checked in pixels anyway, because the last placement bug
# here was a consistent error that left every picture internally plausible.
#
# It is back at 64 because widening was never what stood in the way.
# `control_room_screens` has a 120 px content box and the scene draws `board` at
# four points 96 px apart, so its copies clip each other whatever canvas they
# arrive on. Carrying a 128 px canvas would then double every themed prop
# texture for an object no room can draw — generality with no user. Flip this
# line and ANIMATED_ADOPTED to spend it, the moment a scene rule exists for a
# prop wider than the back-row pitch.
PROP_CANVAS = (64, 96)

# ---------------------------------------------------------------------------
# Character sheet layout — MEASURED, see docs/FINDINGS-M0.md
# ---------------------------------------------------------------------------

# Premade sheets are 1792x1312 at the 32x set: 56 columns of 32px by 20 rows of
# 64px, plus 32px of unused trailing padding (20*64 = 1280, 1312 - 1280 = 32).
# So a character frame is 32 wide by 64 tall.
CHAR_FW, CHAR_FH = 32, 64
CHAR_COLS, CHAR_ROWS = 56, 20

# Row order read off 2_Characters/Character_Generator/Spritesheet_animations_GUIDE.png
# and cross-checked against per-row column occupancy on the actual sheet.
CHAR_ROW_POSE = {
    0: ("base", 4),
    1: ("idle", 24),
    2: ("walk", 24),
    3: ("sleep", 13),
    4: ("sit_a", 12),
    5: ("sit_b", 12),
    6: ("phone_a", 14),
    7: ("phone_b", 26),
    8: ("push_cart", 48),
    9: ("pick_up", 48),
    10: ("gift", 40),
    11: ("lift", 56),
    12: ("throw", 56),
    13: ("hit", 24),
    14: ("punch", 24),
    15: ("stab", 48),
    16: ("grab_gun", 16),
    17: ("gun_idle", 24),
    18: ("shoot", 13),
    19: ("hurt", 13),
}

# Direction order within every multi-direction row. Established two ways:
#   - blocks 0 and 2 are pixel-exact mirrors of each other (side views);
#   - block 1 shows no skin or eyes in the head band (back), block 3 shows two
#     eyes and a mouth (front).
CHAR_DIRS = ("right", "up", "left", "down")

# What we actually cut. (pose_row, frames_per_direction, directions_to_export).
# Poses outside this list exist in the pack but have no event that licenses
# them [I1] — punch, stab, shoot and the rest are never going in the room.
CHAR_EXPORT = {
    "idle": (1, 6, ("right", "up", "left", "down")),
    "walk": (2, 6, ("right", "up", "left", "down")),
    # The desk pose. Side views only — the pack ships no front or back sitting
    # pose, which is why the room is laid out side-on. See docs/04.
    "sit": (4, 3, ("right", "left")),
    # Row 5, the SECOND sit row, is deliberately NOT exported. M6b cut it,
    # rendered it in all six rooms and measured it: it is sit-on-the-ground
    # against sit-on-a-chair — the bare body sheet extends the legs forward in
    # row 4 and folds them under in row 5 — and the two are pixel-identical
    # above image row 39, which is everything the desk and chair do not hide.
    # Four seated characters in a 720x400 room differ by **96 pixels of
    # 288000**. A second seated pose that nothing can see is not a second pose.
    # See docs/04-ART-DIRECTION.md.
    # SubagentStop's hand-over beat.
    "gift": (10, 10, ("right", "up", "left", "down")),
}

# The cast. Selected, not drawn — the pack ships 20 premades and the job is
# picking the subset that survives the 1x silhouette test while satisfying I7.
# Every one of these carries a colour above 0.55 saturation (01, 02, 03 and 05
# do not and were excluded), and this is the 6-subset with the largest minimum
# pairwise silhouette distance among those that qualify.
CHAR_CAST = ("06", "07", "09", "10", "17", "19")

# ---------------------------------------------------------------------------
# Badge rectangles — MEASURED off UI_32x32.png by connected-component bounds
# ---------------------------------------------------------------------------

# The UI sheet divides exactly into 18x16 cells of 32px, but the artwork is NOT
# cell-aligned: the speech-bubble emotes sit at a +4px x offset and are 28-34px
# tall, so they hang across the row boundary below them. Cutting on the nominal
# grid would clip every one. These rectangles are the connected-component
# bounding boxes, so the cut is reproducible rather than eyeballed.
BADGE_CANVAS = (24, 34)
BADGE_RECTS = {
    # name: (x, y, w, h) in UI_32x32.png
    "question_mark": (260, 16, 24, 34),  # blue "?" bubble
    "attention": (324, 22, 24, 28),      # red "!" bubble, for Notification
    # Blue "Z" bubble, cut at M6b for the dormant subagent.
    #
    # This is here rather than in CHAR_EXPORT because the pack's `sleep` row
    # cannot draw a dormant character and this can. Row 3 is labelled `sleep` in
    # the pack's own animation guide and is **a head on a pillow, drawn from
    # above**: six frames, no body, no direction blocks, and the guide's own
    # frames 8-12 show it being composited onto a top-down bed sprite. Our room
    # is side-on and has no bed, so the state resolves to a disembodied head
    # hovering over an office chair. See docs/04-ART-DIRECTION.md.
    #
    # The Z bubble says the same thing in the layer that already carries
    # non-tool state. `attention` is the precedent and this is the second
    # member of that set: it is not keyed by a tool, it is 548 pixels in the
    # pack's own bubble exactly like `attention`, and it claims only what the
    # model already knows — this agent finished a turn and may come back.
    "sleep": (356, 20, 24, 28),
}

# ---------------------------------------------------------------------------
# Badges composed from two packs — added at M5b, when Modern User Interface
# was finally bought
# ---------------------------------------------------------------------------

# The empty speech bubble in Modern Interiors' UI sheet. This is not a bubble
# that merely *resembles* the question-mark badge's frame — it is the same
# artwork: the connected component at (164,16) is 24x34 and 692 opaque pixels,
# exactly like the one at (260,16), and differencing the two leaves precisely
# the "?" glyph and nothing else. So compositing into it cannot change the badge
# silhouette, which is what docs/04-ART-DIRECTION.md promised the M5 swap would
# preserve.
BADGE_FRAME_RECT = (164, 16, 24, 34)

# The empty frame is also written out on its own, so that
# scripts/generate-art.py can composite into the *same pixels* rather
# than draw a lookalike. Named with a leading underscore because it is not a
# badge and must never be mistaken for one: build-manifest.py looks up badge
# files by badge name, and no badge is called this.
BADGE_FRAME_FILE = "_bubble_frame.png"

# Where a glyph may go inside that frame: the light interior, measured off the
# frame rather than guessed. x 2..21 and y 2..25 in frame-local coordinates —
# the border is a 2px band and the tail hangs below row 27.
BADGE_FRAME_INTERIOR = (2, 2, 20, 24)

# Modern User Interface sheets, at the 32x set.
MUI_SHEETS = {
    "style1": "Modern_UI_Style_%d_%s.png",
}

# The icons we could actually find, by 32px cell on Modern_UI_Style_1_32x32.png.
#
# THE SHEET IS ON A TRUE GRID, unlike Modern Interiors' emote sheet: 1952x1376
# is exactly 61x43 cells of 32, and every icon used here is wholly inside one
# cell. What is *not* consistent is the offset within the cell — the two icons
# below start at (8,8) and (8,10) and others in the same block start at (4,10)
# or (6,8) — so the cut is still "find the cell, then take the bounding box of
# what is in it", never "take the cell". A fixed offset would clip.
#
# Style 1 rows 18-22 hold a darker recolour of the same 41-glyph flat icon set
# that rows 6-10 hold. The dark set is the one used: the bubble interior is
# RGB(235,225,246), value 0.965, and the dark glyphs bottom out at value 0.42
# against the light set's 0.61. Inside a bright bubble that difference is the
# whole legibility of the badge at 1x.
MUI_BADGE_ICONS = {
    # badge name: (sheet key, cell x, cell y, what the glyph actually is)
    "document":  ("style1", 28, 22, "page with a pencil across its corner"),
    "checklist": ("style1", 31, 18, "bulleted list, three markers and three rules"),
}

# Badges this pack does not answer, and the reason, carried into the manifest so
# nobody has to re-derive it. Every 32px cell of both style sheets and the
# gamepad sheet was rendered and inspected at M5b: 337 distinct alpha masks on
# Style 1, 283 on Style 2, 28 more that straddle cell boundaries. The whole
# icon vocabulary is 41 flat glyphs (lock, unlock, 3x3 grid, back chevron,
# person, cog, home, list, trash, check, cross, plus, minus, four arrows, sort,
# refresh, swap, fast-forward, mail, play, back, up/down triangles, funnel,
# person, question mark, trophy, info, pause, plinth, speaker, mute, sliders,
# play-in-box, twitter, facebook, discord, edit, cart) plus a media strip
# (monitor, monitor-with-cursor, phone, image, dropdown, speech bubbles,
# checkbox, music, mute) plus an RPG item set (gifts, stars, jars, backpacks,
# hearts, coins, a hand mirror, a closed book, a gear, a phone-in-hand).
#
# None of it is a magnifier, a globe or a plug. The nearest misses were left
# alone on purpose and are named here so the next person does not "find" them
# again: the hand mirror at cell (14,9) is a circle on a handle and would read
# as a magnifier at 1x, and the monitor at cell (19,3) is the only screen in the
# pack. Pressing either into service is the failure M5 refused when it left the
# cog and the hammer alone. [I1]
MUI_ABSENT = {
    "magnifier": "no magnifier, loupe or search glyph exists in Modern User "
                 "Interface (all three sheets inspected cell by cell at M5b). The "
                 "closest shape is an RPG hand mirror at Style_1 cell (14,9), which "
                 "is a mirror.",
    "globe": "no globe, world or planet glyph exists in any of the three packs. "
             "Modern Interiors' only match on the name is "
             "animated_Christmas_snowball_globe, a snow globe.",
    "plug": "no plug, socket, outlet, cable or connector glyph exists in any of "
            "the three packs.",
    "terminal": "no console, prompt or shell glyph exists. The only screen in the "
                "pack is a monitor at Style_1 cell (19,3), and it sits inside the "
                "pack's media strip beside monitor-with-cursor, phone, image and "
                "speaker — so the pack's own semantics for it are 'display', not "
                "'shell'. Rejected on that ground alone and not on legibility: "
                "composited into the badge frame it measures glyph IoU 0.31 "
                "against document and 0.43 against checklist, which is no worse "
                "than pairs already shipping. A display standing in for a shell "
                "is the cog-and-hammer rule. Overruling this is one line — add "
                "\"terminal\": (\"style1\", 19, 3, ...) to MUI_BADGE_ICONS in "
                "scripts/process-assets.py and rebuild.",
}

SIZE_SETS = ("16x16", "32x32", "48x48")
DEFAULT_SIZES = ("32x32",)


def _neighbours(x, y, w, h):
    if x > 0:
        yield x - 1, y
    if x + 1 < w:
        yield x + 1, y
    if y > 0:
        yield x, y - 1
    if y + 1 < h:
        yield x, y + 1


def strip_shadow(w, h, px):
    """Remove the Office pack's baked drop shadow. Returns pixels stripped.

    Not a plain colour replace. RGB(167,151,150) is also used as a legitimate
    fill in a small number of tiles — 436 such pixels survive into the
    shadowless sheet — so a blind replace would punch holes in real art.

    Shadows are always outside the silhouette; legitimate uses of the colour are
    interior detail enclosed by other opaque pixels. So we flood inward from
    transparency through shadow-coloured pixels only, and strip what it reaches.

    Measured against the sheet ground truth: strips 16464 of 16560 true shadow
    pixels (99.4%) while sparing 260 of the 436 legitimate ones. The residual
    176 false strips are single pixels on a silhouette edge, invisible at 1x,
    which is the size that decides. An exact strip would need per-tile
    correspondence to the shadowless sheet, which the singles do not carry.
    """
    seed = collections.deque()
    seen = set()

    def is_shadow(x, y):
        i = (y * w + x) * 4
        return px[i + 3] > 0 and (px[i], px[i + 1], px[i + 2]) == SHADOW_RGB

    for y in range(h):
        for x in range(w):
            if not is_shadow(x, y):
                continue
            if x in (0, w - 1) or y in (0, h - 1):
                exposed = True
            else:
                exposed = any(
                    px[(ny * w + nx) * 4 + 3] == 0 for nx, ny in _neighbours(x, y, w, h)
                )
            if exposed:
                seen.add((x, y))
                seed.append((x, y))

    while seed:
        x, y = seed.popleft()
        for nx, ny in _neighbours(x, y, w, h):
            if (nx, ny) not in seen and is_shadow(nx, ny):
                seen.add((nx, ny))
                seed.append((nx, ny))

    for x, y in seen:
        i = (y * w + x) * 4
        px[i : i + 4] = b"\x00\x00\x00\x00"
    return len(seen)


def _bbox_in(w, h, px, x0, y0, rw, rh):
    """Bounding box of the opaque pixels inside one rectangle, in sheet coords."""
    bx0 = by0 = None
    bx1 = by1 = -1
    for y in range(y0, min(y0 + rh, h)):
        for x in range(x0, min(x0 + rw, w)):
            if px[(y * w + x) * 4 + 3] == 0:
                continue
            if bx0 is None or x < bx0:
                bx0 = x
            if x > bx1:
                bx1 = x
            if by0 is None or y < by0:
                by0 = y
            if y > by1:
                by1 = y
    if bx0 is None:
        return None
    return bx0, by0, bx1 - bx0 + 1, by1 - by0 + 1


def room_colour(r, g, b, floor=VALUE_FLOOR):
    """Desaturate and value-compress one colour. Pure; memoised by the caller."""
    hh, ss, vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    ss = min(ss * SAT_SCALE, SAT_TARGET)
    vv = floor + vv * (VALUE_CEIL - floor)
    nr, ng, nb = colorsys.hsv_to_rgb(hh, ss, vv)
    return (int(round(nr * 255)), int(round(ng * 255)), int(round(nb * 255)))


def recolour(px, cache, floor=VALUE_FLOOR):
    """Apply the room palette transform in place.

    Memoised on source RGB *and on the band floor*, because a theme may draw its
    props on a wider band — see PROP_VALUE_FLOOR_DEFAULT. Keying on the floor
    matters: without it the first band processed would poison every later one
    and the bug would look like "some props are the wrong tone", which is
    exactly the kind of thing nobody notices in a 720x400 panel.

    Pixel art has a tiny palette — the whole Office pack uses about 320 distinct
    colours — so this turns a per-pixel colorsys round trip into a dict lookup,
    making a full reimport fast enough that nobody is tempted to skip it.
    """
    for i in range(0, len(px), 4):
        if px[i + 3] == 0:
            continue
        key = (px[i], px[i + 1], px[i + 2], floor)
        out = cache.get(key)
        if out is None:
            out = cache[key] = room_colour(key[0], key[1], key[2], floor)
        px[i], px[i + 1], px[i + 2] = out


def gif_timing(path):
    """(width, height, frame count, per-frame delay in 1/100 s, loop count).

    The pack ships `3_Animated_objects/<size>/gif/` beside `spritesheets/`, and
    a GIF is the only place in any of these packs that states how fast a thing
    is supposed to move. Reading it is how the frame rate in the manifest stops
    being a taste decision: docs/04-ART-DIRECTION.md's rule is that nothing
    enters the manifest until it has been located in the download, and a frame
    rate is as much a claim about the art as a filename is.

    It also independently confirms the frame *width*, which is not recoverable
    from the sheet — every sheet is one row, so a wrong width still slices into
    plausible frames. The GIF's canvas is one frame, so sheet width divided by
    GIF width is the frame count, checkable against the GIF's own.

    Structure walk only: block headers, the Graphics Control Extension's delay
    field, and the NETSCAPE2.0 loop count. **No LZW decode** — the pixels come
    from the PNG sheet, which is the lossless copy. Returns None if the file is
    not a GIF or does not parse, which the caller treats as "unverified" rather
    than as an error.

    Delays are returned raw rather than averaged because a pack that ever ships
    a non-uniform loop should be *rejected*, not smoothed: `animation.fps` is one
    number and cannot describe a loop whose frames are held for different times.
    """
    try:
        with open(path, "rb") as f:
            b = f.read()
    except OSError:
        return None
    if b[:6] not in (b"GIF87a", b"GIF89a"):
        return None
    try:
        w = int.from_bytes(b[6:8], "little")
        h = int.from_bytes(b[8:10], "little")
        i = 13
        if b[10] & 0x80:                      # global colour table
            i += 3 * (2 << (b[10] & 7))
        delays, frames, loop = [], 0, None

        def skip_blocks(j):
            while b[j]:
                j += b[j] + 1
            return j + 1

        while i < len(b) and b[i] != 0x3B:    # trailer
            if b[i] == 0x21:                  # extension
                label, i = b[i + 1], i + 2
                size = b[i]
                sub = b[i + 1:i + 1 + size]
                i = skip_blocks(i + 1 + size)
                if label == 0xF9 and size >= 3:
                    delays.append(int.from_bytes(sub[1:3], "little"))
            elif b[i] == 0x2C:                # image descriptor
                frames += 1
                flags, i = b[i + 9], i + 10
                if flags & 0x80:              # local colour table
                    i += 3 * (2 << (flags & 7))
                i = skip_blocks(i + 1)        # LZW min code size, then data
            else:
                return None
        # NETSCAPE2.0 always means "animate"; its count is 0 for forever, and
        # every sheet in this folder is 0. Read it back plainly rather than
        # tracking it through the walk above.
        loop = 0 if b"NETSCAPE2.0" in b else None
    except (IndexError, ValueError):
        return None
    return (w, h, frames, delays, loop)


def _digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def _params_key():
    """Any change to the transform must invalidate every cached output."""
    return json.dumps(
        {
            "sat": [SAT_SCALE, SAT_TARGET],
            "val": [VALUE_FLOOR, VALUE_CEIL],
            "theme_prop_val": {k: v.get("prop_value_floor",
                                        PROP_VALUE_FLOOR_DEFAULT)
                               for k, v in sorted(THEMES.items())},
            "shadow": SHADOW_RGB,
            "cast": CHAR_CAST,
            "export": {k: list(v) for k, v in CHAR_EXPORT.items()},
            "badges": BADGE_RECTS,
            "canvas": BADGE_CANVAS,
            "badge_frame": [BADGE_FRAME_RECT, BADGE_FRAME_INTERIOR],
            "badge_icons": {k: list(v) for k, v in MUI_BADGE_ICONS.items()},
            "animated": {k: [v["sheet"], list(v["frame"]), v["for"], v["fps"]]
                         for k, v in sorted(ANIMATED.items())},
            "prop_canvas": list(PROP_CANVAS),
            "rev": 6,
        },
        sort_keys=True,
    )


class Importer:
    def __init__(self, force=False, quiet=False):
        self.force = force
        self.quiet = quiet
        self.state = {}
        self.new_state = {}
        self.cache = {}
        self.written = 0
        self.skipped = 0
        self.shadow_px = 0
        if os.path.exists(STATE) and not force:
            try:
                with open(STATE) as f:
                    blob = json.load(f)
                if blob.get("params") == _params_key():
                    self.state = blob.get("files", {})
            except (ValueError, OSError):
                self.state = {}

    def log(self, msg):
        if not self.quiet:
            print(msg)

    def _fresh(self, dst, key):
        rel = os.path.relpath(dst, OUT)
        if not self.force and self.state.get(rel) == key and os.path.exists(dst):
            self.new_state[rel] = key
            self.skipped += 1
            return True
        self.new_state[rel] = key
        return False

    def _emit(self, dst, w, h, px):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        pnglite.save(dst, w, h, px)
        self.written += 1

    # -- room ---------------------------------------------------------------

    def room_singles(self, sizes):
        for size in sizes:
            srcdir = os.path.join(OFFICE, "4_Modern_Office_singles", size)
            if not os.path.isdir(srcdir):
                self.log("  room singles %s: absent" % size)
                continue
            names = sorted(n for n in os.listdir(srcdir) if n.lower().endswith(".png"))
            for n in names:
                src = os.path.join(srcdir, n)
                dst = os.path.join(OUT, "room", size, "singles", n)
                key = _digest(src)
                if self._fresh(dst, key):
                    continue
                w, h, px = pnglite.load(src)
                self.shadow_px += strip_shadow(w, h, px)
                recolour(px, self.cache)
                self._emit(dst, w, h, px)
            self.log("  room/%s/singles: %d files" % (size, len(names)))

    def room_builder(self, sizes):
        """Slice the Room Builder sheet into floor and wall tiles.

        docs/04-ART-DIRECTION.md says build from singles because the combined
        sheets have uneven grids and off-grid sprites. That warning is about the
        *object* sheets. Floors and walls ship only as Room_Builder_Office,
        which is a plain uniform grid with no off-grid content, so slicing it is
        an exact integer division and not the guesswork the rule targets.
        Without this there is no floor for anyone to stand on.
        """
        for size in sizes:
            tile = int(size.split("x")[0])
            src = os.path.join(
                OFFICE, "1_Room_Builder_Office", "Room_Builder_Office_%s.png" % size
            )
            if not os.path.exists(src):
                self.log("  room builder %s: absent" % size)
                continue
            key = "slice:" + _digest(src)
            w, h, px = pnglite.load(src)
            if w % tile or h % tile:
                self.log(
                    "  room builder %s: %dx%d is not a whole number of %dpx tiles — skipped"
                    % (size, w, h, tile)
                )
                continue
            kept = 0
            for r in range(h // tile):
                for c in range(w // tile):
                    dst = os.path.join(
                        OUT, "room", size, "builder", "tile_r%02d_c%02d.png" % (r, c)
                    )
                    buf = pnglite.new(tile, tile)
                    opaque = 0
                    for y in range(tile):
                        sy = r * tile + y
                        for x in range(tile):
                            si = (sy * w + c * tile + x) * 4
                            di = (y * tile + x) * 4
                            buf[di : di + 4] = px[si : si + 4]
                            if px[si + 3] > 0:
                                opaque += 1
                    # A tile that is mostly holes is edge trim, not floor; laying
                    # it down would show the void behind the room.
                    if opaque * 100 < tile * tile * 60:
                        continue
                    kept += 1
                    if self._fresh(dst, key):
                        continue
                    recolour(buf, self.cache)
                    self._emit(dst, tile, tile, buf)
            self.log("  room/%s/builder: %d solid tiles" % (size, kept))

    # -- themed rooms -------------------------------------------------------

    def _theme_source(self, size, spec):
        """Locate the actual PNG for a (set, index) pick. Returns a path or None.

        Scans the directory rather than composing the filename, because the pack
        is not consistent about it: directory `23_Television_and_Film_Studio_...`
        holds files named `Television_and_FIlm_Studio_...` with a capital I. A
        composed filename would miss it and the role would silently vanish.
        """
        setno, index = spec[0], spec[1]
        if setno == "office":
            root = os.path.join(OFFICE, "4_Modern_Office_singles", size)
        else:
            root = THEME_SINGLES % (size, size)
            dirs = [d for d in os.listdir(root)
                    if d.split("_")[0] == str(setno)
                    and os.path.isdir(os.path.join(root, d))]
            if not dirs:
                return None
            root = os.path.join(root, dirs[0])
        if not os.path.isdir(root):
            return None
        suffix = "_%d.png" % index
        hits = [n for n in os.listdir(root) if n.endswith(suffix)]
        return os.path.join(root, hits[0]) if hits else None

    def _pad(self, w, h, px, cw, ch):
        """Composite a sprite bottom-centred into a cw x ch transparent canvas.

        Returns None if the sprite does not fit. That case used to be covered by
        "every prop selected was measured first and fits", which is a claim
        about the table rather than a check on it — and a negative offset here
        does not raise, it writes the overhanging columns onto the wrong rows
        and produces a plausible-looking file. The caller logs and skips, which
        is the same treatment a sheet that disagrees with its GIF gets.
        """
        if w > cw or h > ch:
            return None
        buf = pnglite.new(cw, ch)
        ox, oy = (cw - w) // 2, ch - h
        for y in range(h):
            for x in range(w):
                si, di = (y * w + x) * 4, ((y + oy) * cw + x + ox) * 4
                buf[di:di + 4] = px[si:si + 4]
        return buf

    def _mean_colour(self, tile, px):
        """Mean RGB of the opaque pixels — the flat stand-in for a patterned tile."""
        n, r, g, b = 0, 0, 0, 0
        for i in range(0, len(px), 4):
            if px[i + 3] == 0:
                continue
            n += 1
            r, g, b = r + px[i], g + px[i + 1], b + px[i + 2]
        if n == 0:
            return None
        return (r // n, g // n, b // n)

    def themes(self, sizes):
        """Import every themed room: four props, a floor, a wall, two flats.

        The two flats are authored, not cut: a flat field of the tile's own mean
        colour. They exist because the scene picks its floor and its wall by
        scanning the builder tiles for one that is fully opaque and a SINGLE
        colour, and taking the darkest and the lightest. Of the Office room's
        141 builder tiles exactly 2 pass that test, which is why today's room is
        two flat fields and why 139 patterned tiles in the manifest are never
        drawn. Until the scene reads the floor and wall it is told to use — the
        manifest now declares both — a theme that shipped only patterned tiles
        would render with no floor at all. So each theme ships both: the pattern
        it should use, and a flat of the right tone that the current heuristic
        will pick. Neither is a guess about which one the scene wants; the
        manifest names them.
        """
        for size in sizes:
            tile = int(size.split("x")[0])
            floors_p = THEME_FLOORS % (size, size)
            walls_p = THEME_WALLS % (size, size)
            have_builder = os.path.exists(floors_p) and os.path.exists(walls_p)
            if not have_builder:
                self.log("  themes %s: Room Builder subfiles absent" % size)

            for name, theme in sorted(THEMES.items()):
                base = os.path.join(OUT, "themes", name, size)
                prop_floor = theme.get("prop_value_floor",
                                       PROP_VALUE_FLOOR_DEFAULT)
                for role, spec in sorted(theme["roles"].items()):
                    src = self._theme_source(size, spec)
                    if src is None:
                        self.log("  themes/%s: %s source missing (%s:%s)"
                                 % (name, role, spec[0], spec[1]))
                        continue
                    dst = os.path.join(base, "singles", "%s.png" % role)
                    key = ("pad%dx%d:band%.3f:" % (PROP_CANVAS + (prop_floor,))
                           + _digest(src))
                    if self._fresh(dst, key):
                        continue
                    w, h, px = pnglite.load(src)
                    self.shadow_px += strip_shadow(w, h, px)
                    buf = self._pad(w, h, px, *PROP_CANVAS)
                    if buf is None:
                        self.log("  themes/%s: %s is %dx%d and does not fit the "
                                 "%dx%d prop canvas — skipped"
                                 % ((name, role, w, h) + PROP_CANVAS))
                        continue
                    recolour(buf, self.cache, prop_floor)
                    self._emit(dst, PROP_CANVAS[0], PROP_CANVAS[1], buf)

                if not have_builder or theme["floor"] is None:
                    continue
                for kind, sheet, addr in (("floor", floors_p, theme["floor"]),
                                          ("wall", walls_p, theme["wall"])):
                    r, c = addr
                    sw, sh, spx = pnglite.load(sheet)
                    if (r + 1) * tile > sh or (c + 1) * tile > sw:
                        self.log("  themes/%s: %s address %d,%d is off the sheet"
                                 % (name, kind, r, c))
                        continue
                    buf = pnglite.new(tile, tile)
                    for y in range(tile):
                        sy = (r * tile + y) * sw
                        for x in range(tile):
                            si = (sy + c * tile + x) * 4
                            buf[(y * tile + x) * 4:(y * tile + x) * 4 + 4] = spx[si:si + 4]
                    recolour(buf, self.cache)
                    key = "tile:%d,%d:" % (r, c) + _digest(sheet)
                    dst = os.path.join(base, "builder", "%s.png" % kind)
                    if not self._fresh(dst, key):
                        self._emit(dst, tile, tile, buf)

                    mean = self._mean_colour(tile, buf)
                    if mean is None:
                        continue
                    flat = pnglite.new(tile, tile)
                    for i in range(0, len(flat), 4):
                        flat[i], flat[i + 1], flat[i + 2], flat[i + 3] = (
                            mean[0], mean[1], mean[2], 255)
                    fdst = os.path.join(base, "builder", "flat_%s.png" % kind)
                    if not self._fresh(fdst, key + ":flat"):
                        self._emit(fdst, tile, tile, flat)
            self.log("  themes/%s: %d themes" % (size, len(THEMES)))

    # -- animated objects ---------------------------------------------------

    def animated(self, sizes):
        """Cut the named animated sheets into one PNG per frame.

        Same treatment as any other themed prop, and that is the point: baked
        shadow stripped, the room transform applied **on the target theme's own
        prop band**, and padded bottom-centred into PROP_CANVAS. They are
        furniture that happens to move, not a layer of their own, so I7 binds
        them exactly as it binds a desk — and the padding is what lets one
        `props.canvas` cover a moving prop and a still one.

        The theme band matters and is easy to miss: `mission_control` draws its
        props on a band floored at 0.46, so a server rack cut on the default
        band would be the one pale object in a theme built around dark screens.

        Every sheet is checked against the pack's own GIF of the same object
        before it is cut — canvas size, frame count, and a uniform delay that
        matches the declared `fps`. A sheet that disagrees with its GIF is
        skipped and named, because the failure it prevents (a wrong frame width
        slicing into plausible frames) is exactly the one that survives review.

        Output lands under `assets/processed/animated/<size>/<id>/frame_NN.png`.
        Every object is cut; only the ids in ANIMATED_ADOPTED are referenced by
        the manifest. `prune()` keeps it tidy, so removing a row from ANIMATED
        removes its frames on the next run.
        """
        for size in sizes:
            root = ANIMATED_DIR % size
            if not os.path.isdir(root):
                self.log("  animated %s: absent" % size)
                continue
            gifs = ANIMATED_GIF_DIR % size
            n_frames = 0
            for name, spec in sorted(ANIMATED.items()):
                src = os.path.join(root, spec["sheet"])
                if not os.path.exists(src):
                    self.log("  animated/%s: %s absent" % (size, spec["sheet"]))
                    continue
                fw, fh = spec["frame"]
                w, h, px = pnglite.load(src)
                if h != fh or w % fw:
                    self.log("  animated/%s: %s is %dx%d, not a whole number of "
                             "%dx%d frames — skipped" % (size, name, w, h, fw, fh))
                    continue
                count = w // fw
                if not self._timing_agrees(size, name, spec, gifs, fw, fh, count):
                    continue
                # An object that fits the prop canvas is padded into it and is
                # adoptable. One that does not is still cut, at its own frame
                # size, so `preview-theme.py --animated <id>` can stand it in a
                # room and it can be argued about — it just cannot be a manifest
                # role, and scripts/build-manifest.py refuses it on exactly that
                # test rather than on this table's say-so.
                fits = fw <= PROP_CANVAS[0] and fh <= PROP_CANVAS[1]
                cw, ch = PROP_CANVAS if fits else (fw, fh)
                if not fits:
                    self.log("  animated/%s: %s is %dx%d per frame, larger than the "
                             "%dx%d prop canvas — cut for review, not adoptable"
                             % ((size, name, fw, fh) + PROP_CANVAS))
                theme = THEMES.get(spec["for"], {})
                prop_floor = theme.get("prop_value_floor", PROP_VALUE_FLOOR_DEFAULT)
                key = ("anim%dx%d:pad%dx%d:band%.3f:"
                       % ((fw, fh, cw, ch) + (prop_floor,)) + _digest(src))
                for i in range(count):
                    dst = os.path.join(OUT, "animated", size, name,
                                       "frame_%02d.png" % i)
                    n_frames += 1
                    if self._fresh(dst, key):
                        continue
                    buf = pnglite.new(fw, fh)
                    for y in range(fh):
                        for x in range(fw):
                            si = (y * w + i * fw + x) * 4
                            di = (y * fw + x) * 4
                            buf[di:di + 4] = px[si:si + 4]
                    self.shadow_px += strip_shadow(fw, fh, buf)
                    padded = self._pad(fw, fh, buf, cw, ch)
                    recolour(padded, self.cache, prop_floor)
                    self._emit(dst, cw, ch, padded)
            self.log("  animated/%s: %d frames across %d objects (%d adopted)"
                     % (size, n_frames, len(ANIMATED), len(ANIMATED_ADOPTED)))

    def _timing_agrees(self, size, name, spec, gifs, fw, fh, count):
        """True if the pack's own GIF confirms this sheet's slicing and rate.

        Absent GIF is not a failure — the sheet is the art and the GIF is the
        corroboration — but it is logged, because an unverified frame rate is a
        claim about the download that nobody checked.
        """
        info = gif_timing(os.path.join(gifs, spec["sheet"].replace(".png", ".gif")))
        if info is None:
            self.log("  animated/%s: %s has no readable GIF — frame rate "
                     "unverified" % (size, name))
            return True
        gw, gh, gframes, delays, _loop = info
        if (gw, gh) != (fw, fh) or gframes != count:
            self.log("  animated/%s: %s sheet slices to %d frames of %dx%d but its "
                     "GIF is %d of %dx%d — skipped"
                     % (size, name, count, fw, fh, gframes, gw, gh))
            return False
        if not delays or len(set(delays)) != 1:
            self.log("  animated/%s: %s has a non-uniform GIF delay %s — one `fps` "
                     "cannot describe it, skipped" % (size, name, delays))
            return False
        fps = round(100.0 / delays[0], 3)
        if abs(fps - spec["fps"]) > 1e-6:
            self.log("  animated/%s: %s declares %g fps but its GIF holds each frame "
                     "%d/100 s (%g fps) — skipped"
                     % (size, name, spec["fps"], delays[0], fps))
            return False
        return True

    # -- characters ---------------------------------------------------------

    def characters(self, sizes):
        """Slice premade sheets into one PNG per frame.

        Colour is deliberately untouched. I7 assigns the characters the
        saturation and the dark values; running the room transform over them
        would erase exactly the contrast the palette lint exists to protect.
        """
        for size in sizes:
            unit = int(size.split("x")[0])
            fw, fh = unit, unit * 2
            base = os.path.join(
                INTERIORS, "2_Characters", "Character_Generator", "0_Premade_Characters", size
            )
            if not os.path.isdir(base):
                self.log("  characters %s: absent" % size)
                continue
            n_frames = 0
            for who in CHAR_CAST:
                stem = "Premade_Character_%s_%s.png" % (size, who) if size != "16x16" \
                    else "Premade_Character_%s.png" % who
                src = os.path.join(base, stem)
                if not os.path.exists(src):
                    self.log("  characters %s: %s absent — skipped" % (size, stem))
                    continue
                key = "chars:" + _digest(src)
                w, h, px = pnglite.load(src)
                if w // fw != CHAR_COLS:
                    self.log(
                        "  characters %s: %s is %dx%d, expected %d columns of %dpx — skipped"
                        % (size, stem, w, h, CHAR_COLS, fw)
                    )
                    continue
                for state, (row, per_dir, dirs) in CHAR_EXPORT.items():
                    for d in dirs:
                        block = CHAR_DIRS.index(d)
                        for k in range(per_dir):
                            col = block * per_dir + k
                            dst = os.path.join(
                                OUT, "characters", size, who,
                                "%s_%s_%02d.png" % (state, d, k),
                            )
                            n_frames += 1
                            if self._fresh(dst, key):
                                continue
                            buf = pnglite.new(fw, fh)
                            for y in range(fh):
                                sy = row * fh + y
                                if sy >= h:
                                    break
                                for x in range(fw):
                                    si = (sy * w + col * fw + x) * 4
                                    di = (y * fw + x) * 4
                                    buf[di : di + 4] = px[si : si + 4]
                            self._emit(dst, fw, fh, buf)
            self.log("  characters/%s: %d frames across %d premades"
                     % (size, n_frames, len(CHAR_CAST)))

    # -- badges -------------------------------------------------------------

    def badges(self, sizes):
        """Cut the sourceable badges onto a common canvas.

        Two sources, one canvas:

          * Modern Interiors' emote bubbles, cut whole — `question_mark` and
            `attention` are complete badges as drawn.
          * Modern User Interface icons dropped inside the *same* bubble frame.
            The frame is that pack's own empty bubble, so this composites two
            pieces of located pack art and draws nothing. Both licences permit
            editing; neither permits redistribution, and assets/ is gitignored.

        Only badges whose icon was actually found go here. The rest have no icon
        in any pack on disk — see MUI_ABSENT for what was looked for and where —
        and are authored by scripts/generate-art.py instead. No further packs
        will be bought, so that is a finished answer rather than a wait. [I1]
        """
        for size in sizes:
            unit = int(size.split("x")[0])
            scale = unit // 32
            if unit % 32:
                self.log("  badges %s: rectangles were measured at 32x — skipped" % size)
                continue
            src = os.path.join(INTERIORS, "4_User_Interface_Elements", "UI_%s.png" % size)
            if not os.path.exists(src):
                self.log("  badges %s: absent" % size)
                continue
            key = "badge:" + _digest(src)
            w, h, px = pnglite.load(src)
            cw, ch = BADGE_CANVAS[0] * scale, BADGE_CANVAS[1] * scale
            sources = {}
            for name, (x0, y0, rw, rh) in BADGE_RECTS.items():
                sources[name] = {
                    "provenance": "pack",
                    "sheet": "Modern Interiors / 4_User_Interface_Elements/UI_%s.png" % size,
                    "rect": [x0 * scale, y0 * scale, rw * scale, rh * scale],
                    "cut_by": "connected-component bounding box on the emote sheet, "
                              "which is not cell-aligned",
                }
                x0, y0, rw, rh = x0 * scale, y0 * scale, rw * scale, rh * scale
                dst = os.path.join(OUT, "badges", size, "%s.png" % name)
                if self._fresh(dst, key):
                    continue
                buf = pnglite.new(cw, ch)
                # Bottom-centre aligned: the bubble tail points at the head, so
                # the bottom edge is the anchor and must not drift between
                # badges of different heights.
                ox, oy = (cw - rw) // 2, ch - rh
                for y in range(rh):
                    if y0 + y >= h:
                        break
                    for x in range(rw):
                        if x0 + x >= w:
                            break
                        si = ((y0 + y) * w + x0 + x) * 4
                        di = ((oy + y) * cw + ox + x) * 4
                        buf[di : di + 4] = px[si : si + 4]
                self._emit(dst, cw, ch, buf)

            frame = self.badge_frame(size, scale, w, h, px, key)
            composed = self.badge_composites(size, scale, w, h, px, key, sources)
            self._write_badge_sources(size, sources, frame)
            self.log("  badges/%s: %d cut whole, %d composed, %d still unsourceable "
                     "(%s) — empty frame written to %s for the authored glyphs"
                     % (size, len(BADGE_RECTS), composed, len(MUI_ABSENT),
                        ", ".join(sorted(MUI_ABSENT)), BADGE_FRAME_FILE))

    def badge_frame(self, size, scale, fw, fh, fpx, framekey):
        """Cut the pack's EMPTY speech bubble onto the badge canvas, on its own.

        It is written out for one reason: scripts/generate-art.py needs the very
        same pixels. Until M5c the four badges no pack draws used a hand-made
        lookalike bubble — heavier border, darker ink — so they read louder in
        the room than the pack art beside them and the badge row spoke in two
        visual languages. Emitting the frame here rather than re-measuring the
        rectangle in the other script keeps BADGE_FRAME_RECT the single place
        that coordinate is written down.

        Not a badge: build-manifest.py maps badge *names* to files, so this file
        is never mistaken for one. It is recorded in sources.json under `frame`.
        """
        cw, ch = BADGE_CANVAS[0] * scale, BADGE_CANVAS[1] * scale
        fx, fy, frw, frh = [v * scale for v in BADGE_FRAME_RECT]
        rel = os.path.join("badges", size, BADGE_FRAME_FILE)
        dst = os.path.join(OUT, rel)
        key = "frame:" + framekey
        info = {
            "file": rel,
            "sheet": "Modern Interiors / 4_User_Interface_Elements/UI_%s.png" % size,
            "rect": [fx, fy, frw, frh],
            "interior": [v * scale for v in BADGE_FRAME_INTERIOR],
            "note": "the pack's own empty speech bubble — the same component the "
                    "question_mark badge is cut from, with no glyph in it. Every "
                    "badge on the canvas is this frame plus a glyph, the four "
                    "authored ones included as of M5c.",
        }
        if self._fresh(dst, key):
            return info
        buf = pnglite.new(cw, ch)
        fox, foy = (cw - frw) // 2, ch - frh
        for y in range(frh):
            for x in range(frw):
                si = ((fy + y) * fw + fx + x) * 4
                di = ((foy + y) * cw + fox + x) * 4
                buf[di : di + 4] = fpx[si : si + 4]
        self._emit(dst, cw, ch, buf)
        return info

    def badge_composites(self, size, scale, fw, fh, fpx, framekey, sources):
        """Drop Modern User Interface icons into the Modern Interiors bubble.

        The icon is located by 32px cell and then cut by the bounding box of
        whatever is inside that cell. Both halves matter. The cell is what makes
        the coordinate reproducible and reviewable — anyone can open the sheet
        and go to (28,22). The bounding box is what makes the cut correct, since
        this pack pads its icons into the cell at no fixed offset: the two used
        here start at (8,8) and (8,10), and siblings in the same block start at
        (4,10) and (6,8). Taking the cell whole would centre nothing.
        """
        if not os.path.isdir(USERINTERFACE):
            self.log("  badges %s: Modern User Interface absent — %d badges fall "
                     "back to their authored versions" % (size, len(MUI_BADGE_ICONS)))
            return 0
        cw, ch = BADGE_CANVAS[0] * scale, BADGE_CANVAS[1] * scale
        fx, fy, frw, frh = [v * scale for v in BADGE_FRAME_RECT]
        ix, iy, iw, ih = [v * scale for v in BADGE_FRAME_INTERIOR]

        loaded = {}
        made = 0
        for name, (sheet_key, cx, cy, what) in sorted(MUI_BADGE_ICONS.items()):
            stem = MUI_SHEETS[sheet_key] % (int(sheet_key[-1]), size)
            src = os.path.join(USERINTERFACE, size, stem)
            if not os.path.exists(src):
                self.log("  badges %s: %s absent — %s falls back to authored"
                         % (size, stem, name))
                continue
            if src not in loaded:
                loaded[src] = pnglite.load(src)
            sw, sh, spx = loaded[src]
            cell = 32 * scale
            if sw % cell or sh % cell:
                self.log("  badges %s: %s is %dx%d, not a whole number of %dpx cells "
                         "— %s falls back to authored" % (size, stem, sw, sh, cell, name))
                continue
            box = _bbox_in(sw, sh, spx, cx * cell, cy * cell, cell, cell)
            if box is None:
                self.log("  badges %s: %s cell (%d,%d) is empty — %s falls back to "
                         "its authored version" % (size, stem, cx, cy, name))
                continue
            bx, by, bw, bh = box
            if bw > iw or bh > ih:
                self.log("  badges %s: %s cell (%d,%d) is %dx%d, larger than the "
                         "%dx%d bubble interior — %s falls back to authored"
                         % (size, stem, cx, cy, bw, bh, iw, ih, name))
                continue

            sources[name] = {
                "provenance": "pack",
                "sheet": "Modern User Interface / %s/%s" % (size, stem),
                "cell": [cx, cy],
                "bbox_in_cell": [bx - cx * cell, by - cy * cell, bw, bh],
                "glyph": what,
                "frame_sheet": "Modern Interiors / 4_User_Interface_Elements/UI_%s.png" % size,
                "frame_rect": [fx, fy, frw, frh],
                "cut_by": "32px cell on a sheet that divides exactly, then the "
                          "bounding box inside that cell — the pack pads icons "
                          "into their cell at no fixed offset",
                "composed": "Modern User Interface icon inside Modern Interiors' own "
                            "empty speech bubble, which is pixel-identical to the "
                            "frame the question_mark badge already uses",
            }
            dst = os.path.join(OUT, "badges", size, "%s.png" % name)
            key = "compose:%s:%s" % (framekey, _digest(src))
            if self._fresh(dst, key):
                made += 1
                continue

            buf = pnglite.new(cw, ch)
            fox, foy = (cw - frw) // 2, ch - frh
            for y in range(frh):
                for x in range(frw):
                    si = ((fy + y) * fw + fx + x) * 4
                    di = ((foy + y) * cw + fox + x) * 4
                    buf[di : di + 4] = fpx[si : si + 4]
            gx = fox + ix + (iw - bw) // 2
            gy = foy + iy + (ih - bh) // 2
            for y in range(bh):
                for x in range(bw):
                    si = ((by + y) * sw + bx + x) * 4
                    if spx[si + 3] == 0:
                        continue
                    di = ((gy + y) * cw + gx + x) * 4
                    buf[di : di + 4] = spx[si : si + 4]
            self._emit(dst, cw, ch, buf)
            made += 1
        return made

    def _write_badge_sources(self, size, sources, frame=None):
        """Record where every badge came from, for build-manifest.py to read.

        The manifest has to say which sheet and which coordinates produced each
        badge, and the honest place for that is the script that did the cutting
        — not a second hardcoded table in the manifest builder that could drift
        from this one.
        """
        d = os.path.join(OUT, "badges", size)
        if not os.path.isdir(d):
            return
        blob = {"badges": sources, "unsourceable": MUI_ABSENT}
        if frame:
            blob["frame"] = frame
        with open(os.path.join(d, "sources.json"), "w") as f:
            json.dump(blob, f, indent=1, sort_keys=True)
            f.write("\n")

    # -- housekeeping -------------------------------------------------------

    def prune(self):
        """Delete outputs whose source no longer produces them.

        Idempotency has to cut both ways: if a pack drops a file or the cast
        changes, a stale processed copy would keep satisfying the manifest and
        hide the loss. Authored art and placeholders are left alone — a
        different script owns those, and they live under assets/authored/ and
        assets/placeholder/, not here.
        """
        removed = 0
        for root, _dirs, files in os.walk(OUT):
            for n in files:
                if not n.lower().endswith(".png"):
                    continue
                p = os.path.join(root, n)
                if os.path.relpath(p, OUT) not in self.new_state:
                    os.remove(p)
                    removed += 1
        for root, dirs, _files in os.walk(OUT, topdown=False):
            for d in dirs:
                p = os.path.join(root, d)
                if not os.listdir(p):
                    os.rmdir(p)
        return removed

    def save_state(self):
        os.makedirs(OUT, exist_ok=True)
        with open(STATE, "w") as f:
            json.dump({"params": _params_key(), "files": self.new_state}, f,
                      indent=1, sort_keys=True)
            f.write("\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sizes", nargs="+", choices=SIZE_SETS, default=list(DEFAULT_SIZES),
                    help="pack size sets to import (default: 32x32, per docs/04-ART-DIRECTION.md)")
    ap.add_argument("--force", action="store_true", help="reprocess even if unchanged")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    missing = [p for p in (OFFICE, INTERIORS) if not os.path.isdir(p)]
    if missing:
        print(
            "error: missing purchased pack(s):\n  %s\n"
            "These are gitignored. Unpack them under assets/ before importing."
            % "\n  ".join(missing),
            file=sys.stderr,
        )
        return 2
    # Modern User Interface is not fatal: without it two more badges fall back to
    # the versions scripts/generate-art.py draws, and everything else imports
    # unchanged. That is the degradation the fallback mechanism exists for.
    if not os.path.isdir(USERINTERFACE):
        print("note: %s is absent; %d badge(s) will use their authored fallback."
              % (os.path.relpath(USERINTERFACE, REPO), len(MUI_BADGE_ICONS)),
              file=sys.stderr)

    imp = Importer(force=args.force, quiet=args.quiet)
    imp.log("import -> %s" % os.path.relpath(OUT, REPO))
    imp.room_singles(args.sizes)
    imp.room_builder(args.sizes)
    imp.themes(args.sizes)
    imp.animated(args.sizes)
    imp.characters(args.sizes)
    imp.badges(args.sizes)
    removed = imp.prune()
    imp.save_state()
    imp.log(
        "done: %d written, %d unchanged, %d stale removed, %d shadow px stripped, "
        "%d room colours remapped" % (imp.written, imp.skipped, removed,
                                      imp.shadow_px, len(imp.cache))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
