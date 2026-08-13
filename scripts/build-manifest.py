#!/usr/bin/env python3
"""Build assets/manifest.json from what is actually on disk.

The manifest is the contract the scene builds against: named states, frame
lists, frame rate, canvas size, anchor points, and the badge name -> file map.
Swapping real art in at M5 must be a manifest edit with zero code change.

This is generated rather than hand-written for one reason, and it is the
art-director's standing rule: "Nothing enters the manifest until it exists in
the download." Deriving every entry by walking assets/ makes that true by
construction instead of by diligence — there is no way for a path to appear here
that was not just read off the filesystem. Every entry is re-stat'd before the
file is written, so a manifest that references a missing file cannot be
produced.

Run scripts/process-assets.py and scripts/generate-art.py first.

Python 3 stdlib only.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "assets")
PROCESSED = os.path.join(ASSETS, "processed")
AUTHORED = os.path.join(ASSETS, "authored")
PLACEHOLDER = os.path.join(ASSETS, "placeholder")
MANIFEST = os.path.join(ASSETS, "manifest.json")

SIZE = "32x32"
FPS = 8

# Body states, in the vocabulary of docs/04-ART-DIRECTION.md, mapped to what the
# pack actually ships. `read` is absent from this table on purpose: the Modern
# Interiors animation guide has no "read a book" row, so the state is
# unsourceable and docs/04 already permits dropping it.
STATES = {
    "idle":    {"pose": "idle", "loop": True,  "dirs": ("right", "up", "left", "down")},
    # The desk pose. Side views only — the pack ships no front or back sit.
    "working": {"pose": "sit",  "loop": True,  "dirs": ("right", "left")},
    "walk":    {"pose": "walk", "loop": True,  "dirs": ("right", "up", "left", "down")},
    "deliver": {"pose": "gift", "loop": False, "dirs": ("right", "up", "left", "down")},
}

# Composed, not sourced. Same frames as walk; the difference is where the scene
# starts and ends the movement, which is scene logic, not art.
COMPOSED = {"spawn": "walk", "depart": "walk"}

# Badge names exactly as they appear in the tool -> badge table in
# docs/03-EVENT-MODEL.md. This script does not get to invent, rename, or drop a
# row: the table is the contract and the manifest answers it.
BADGE_NAMES = ("document", "magnifier", "terminal", "globe", "checklist", "plug",
               "question_mark")
BADGE_LABELS = {"question_mark": "question mark"}

# Accent hues, assigned rather than sampled. [M5]
#
# docs/04-ART-DIRECTION.md claims "one accent hue per variant, chosen for mutual
# separation". Measured at M2, that claim was false of the art: the most
# saturated pixel of all six selected premades lands inside a 30 degree arc and
# variants 07 and 17 are hue-identical, because the generator dresses one body
# in variations of one warm palette. Sampling the art therefore produces six
# hues that do not separate, which is worse than useless for identity.
#
# These six are 60 degrees apart by construction, at HSV S=0.70 V=1.00. They are
# not a claim about the sprite - they are the nameplate border colour, which is
# drawn by the scene, not loaded from a file. Assignment is by manifest order so
# it is stable across rebuilds. scripts/lint-palette.py enforces the separation
# so the claim in the doc is checked rather than asserted.
ACCENT_HUES = ["#FF884D", "#C4FF4D", "#4DFF88", "#4DC3FF", "#884DFF", "#FF4DC4"]

# Prop roles. [M5]
#
# The pack ships 339 office singles named by index only - no layer names, no
# slice names, no tags anywhere in 00_Modern_Office_Singles.ase (checked: one
# unnamed layer, 339 unnamed frames). So a role cannot be read off a filename
# and there is nothing to look up. Each of these was identified by *rendering
# the contact sheet and looking at it*, which is what the standing rule asks
# for: locate the actual PNG before you write it down. The index is recorded so
# anyone can re-open the same file and disagree.
#
# Only the five roles the room actually places are listed. The other 334 singles
# stay unidentified and stay out of the role map - a role nothing draws is an
# invitation for the scene to guess. Monitors (121-133) and laptops (139-140)
# are identifiable too, but a monitor has to stand on a desk surface and the art
# carries no datum for where that surface is, so none is placed. [I1]
PROP_ROLES = {
    "desk":  {"index": 34,  "what": "plain office desk, side view, top slab plus two legs"},
    "chair": {"index": 104, "what": "office chair, side view, backrest to the left - a "
                                    "person on it faces right, which is the way a "
                                    "side-on seated character faces"},
    # **The second chair, and it is a facing rather than a variant.** [ADR-008]
    # A seat declares which way its occupant faces, and a side-view chair under
    # a back-facing occupant is a chair pointing 90 degrees away from the person
    # in it. This is the same office chair drawn from behind - the sprite
    # `Office_Design_2.gif` puts under every desk in the pack's own room.
    "chair_back": {
        "index": 101,
        "what": "office chair, back view - a person on it faces away from the "
                "camera, which is the way a back-row seated character faces",
        "identified_by": "rendered at 6x and inspected by eye for ADR-008; ink "
                         "32x46, matching the (32,46) family "
                         "scripts/compose-scene.py's CHAIR_SUITES pins as the "
                         "office suite's `up` view. Selected by ink dimensions "
                         "rather than by name: singles 279/280 carry the same "
                         "catalogue name at 30x32 and are a photocopier",
    },
    "plant": {"index": 99,  "what": "small potted plant, floor standing"},
    "board": {"index": 171, "what": "presentation board on a stand, floor standing, "
                                    "chart on the face"},
    # **The three desk-top declarations, and they were missing from this table
    # for as long as they have been in the manifest.** [ADR-006 §1a, §2c]
    #
    # They reached `assets/manifest.json` without reaching the generator, so
    # every `python3 scripts/build-manifest.py` since silently dropped all three
    # — `room.props.roles` is a GUARDED_SECTION, but the guard fires only when a
    # whole section is lost, and three of seven keys is not a section. Found by
    # regenerating and watching `DeskTopObjectTests` crash on a nil role. The
    # `what` and `identified_by` text below is the manifest's own, restored
    # verbatim, so the generator now reproduces the file it is supposed to own.
    "laptop": {
        "index": 135,
        "what": "open laptop, lid up, 3/4 view, screen showing two faint icon dots "
                "- a wedge silhouette, unbound: no scene code reads this role yet "
                "[ADR-006 SS1a authoring]",
        "identified_by": "rendered and inspected by eye for ADR-006; verified against "
                         "the desk-top width bound derived in ADR-006 SS2c (W <= 28px) "
                         "rather than trusted from the ADR's own table",
    },
    "papers": {
        "index": 153,
        "what": "small stack of a few loose sheets, angled - a low flat slab "
                "silhouette, unbound: no scene code reads this role yet "
                "[ADR-006 SS1a research]",
        "identified_by": "rendered and inspected by eye for ADR-006; the two taller "
                         "stacks at singles 154 and 155 read the same family but "
                         "measure 32px wide, over the SS2c width bound, so only 153 is "
                         "declared",
    },
    "pad": {
        "index": 179,
        "what": "book or pad standing upright on its spine, on a small base - a thin "
                "upright board silhouette, unbound: no scene code reads this role yet "
                "[ADR-006 SS1a coordinating]",
        "identified_by": "rendered and inspected by eye for ADR-006; the pack ships no "
                         "names for its singles",
    },
}


# ---------------------------------------------------------------------------
# The floor plan [ADR-007]
#
# The room drawn as a building rather than as a stage: floors that change
# material, wall bands with the pack's own 12 px floor-plan line on top,
# doorways cut clean through them, the dark *outside* above, and partitions
# between the rooms behind. It is authored here, in the generator that owns
# `assets/manifest.json`, for the same reason `process-assets.py` owns the
# scenery bands: somebody rendered it and looked at it, and no pixel signal
# recovers that judgement.
#
# **The surfaces are `scripts/compose-scene.py`'s, verbatim.** That file's
# `SURFACES` table was established by rendering all 161 non-empty Room Builder
# tiles to a labelled grid and confirming each candidate's pixel cross-section,
# and its output is what the maintainer looked at and asked for. Copying the
# triples rather than re-deriving them is deliberate: a second derivation is a
# second chance to pick a mid-run cap tile whose top edge is missing, which is a
# mistake that file already made and recorded.
#
# **Only the Modern Office builder sheet has these tiles.** Every other theme
# ships four tiles — a cut floor, a flat wall, and the two patterns they came
# from — so `build_plan` returns None for them and they keep the open floor.
# That is not a gap to be filled later by guessing: a plan needs a cap, a body
# and several floors that agree, and five of the six themes have no such set.
#
# **Every wall is column 1 of its row pair, and that is a measurement rather
# than a preference.** Columns 0 and 2 of a cap or body row carry the wall's
# *end* — a 2 px dark trim down the left edge or the right — because the sheet
# is drawn for wall segments with corners. Laid across a 25-tile room they draw
# a dark seam every 32 px, which at 1x reads as a row of panels rather than as a
# wall. Column 1 is the mid-run piece: it carries the complete 12 px top edge
# (columns 3–9 do not) and no vertical trim at all. Measured on all four row
# pairs; `compose-scene.py` mixes c00 and c01 and has the seams to show for it.
#
# A surface is a **finish**, not a room: `concrete` and `slab` name two floors
# under one wall, because the walkway and the work floor are one room with two
# materials in it and their shared north wall has to match.
PLAN_SURFACES = {
    # name:      (floor,             cap,                body)
    "concrete":  ("tile_r07_c11.png", "tile_r07_c01.png", "tile_r08_c01.png"),
    "slab":      ("tile_r05_c11.png", "tile_r07_c01.png", "tile_r08_c01.png"),
    "plank":     ("tile_r05_c14.png", "tile_r05_c01.png", "tile_r06_c01.png"),
    "carpet":    ("tile_r07_c14.png", "tile_r09_c01.png", "tile_r10_c01.png"),
    "lino":      ("tile_r09_c11.png", "tile_r11_c01.png", "tile_r12_c01.png"),
}

# Tile coordinates below are `RoomLayout`'s own grid: 32 px tiles, y **up**,
# `(0, 0)` the bottom-left corner of the room's nominal 25x9 box. A space's `h`
# includes the two rows its north wall eats, which is `06-SET-BUILDING.md` §2's
# convention and the thing people get wrong.
#
# The room's routes decided this plan and not the other way round:
#
#   * The near space covers rows -6..8, which is exactly what the open floor
#     painted, so the delivery row, the walkway and both seat rows are one
#     unbroken floor and no wall stands anywhere a character walks.
#   * Its band is at rows 7 and 8 — the wall line at y=224, where `upstageExit`
#     already ends. A leaver walks into it and fades, as it always has.
#   * `doorways` are on **seat columns** 3, 12 and 21 (seats 6, 0 and 5), so the
#     three characters whose columns carry one walk out through a door rather
#     than into a flat wall, and the rooms behind are reachable.
#   * Everything behind the band — rows 9..11 — is floor no route ever touches,
#     which is why the interior partitions are all there. It is the only part of
#     this room where a north-south wall fits: below it, seven seat columns 96 px
#     apart leave a 40 px gap between one seat's desk and the next seat's chair,
#     and a station prop already stands in the middle of every one of them.
ROOM_PLAN = {
    "spaces": [
        # The walkway: the delivery row, the aisle and the apron in front of
        # them, which `RoomLayout` already calls "the room's thoroughfare". It
        # carries **no band** — it is not a separate room, it is the circulation
        # half of one — so what marks it is the finish changing at the seat row
        # and nothing else. A line there would be a wall across seven columns
        # and across the one row anybody travels along.
        #
        # It is 78 px of the panel that was flat grey and is now legible as
        # something: the floor people cross. Nothing is *drawn* on it, so the
        # rule that replaced M5's foreground row is untouched — a floor is what
        # objects stand on, not an object. [ADR-007 §4, ADR-002 §1]
        {"name": "walkway", "surface": "concrete",
         "x": 2, "y": -6, "w": 21, "h": 8, "band": False},
        # (`concrete` is the grey micro-tile and `slab` the pale one. The
        # walkway takes the darker of the two so the work floor behind it is the
        # lighter field the cast is read against — I7's "characters own the
        # darkest values" is easier to hold over a pale floor than a grey one.)
        {"name": "open plan", "surface": "slab",
         "x": 2, "y": 2, "w": 21, "h": 7,
         "doorways": [3, 12, 21]},
        {"name": "store", "surface": "plank", "x": 2, "y": 9, "w": 8, "h": 3},
        {"name": "meeting", "surface": "carpet", "x": 10, "y": 9, "w": 6, "h": 3},
        {"name": "galley", "surface": "lino", "x": 16, "y": 9, "w": 7, "h": 3},
    ],
    # **Tiles 5 and 17, because those are the two boundaries no prop stands on.**
    # The `wall_line` scenery stands on the back strip's floor at x=64, 256 and
    # 640 — `RoomLayout.sceneryAnchors(.wallLine)` — and a partition at 8 or 20
    # put a vending machine and a coffee counter across a wall, which is
    # `06-SET-BUILDING.md`'s R3 and looked exactly as wrong as R3 says it does.
    # 160 and 544 are the midpoints of those gaps: 96 px from the nearest anchor
    # against props no wider than 56.
    "partitions": [
        {"x": 10, "y": 9, "h": 3},
        {"x": 16, "y": 9, "h": 3},
        # **The outer wall**, both edges, the full depth of the plan. [ADR-013]
        # Without these the plan simply stops and the floor gives way to the
        # void, which reads as a crop rather than as the end of a building —
        # every one of `scripts/compose-scene.py`'s reference scenes is bordered.
        # They run rows -6..11, the whole of the walkway and the rooms above it,
        # and they are admissible downstage of the seat row because they occlude
        # nobody: the line at tile 2 spans x 57..71 against a leftmost seat body
        # at 96..128. `RoomPlan.routeViolations` is what checks that rather than
        # this comment.
        {"x": 2, "y": -6, "h": 18},
        {"x": 23, "y": -6, "h": 18},
    ],
}


# **The office's dressing, placed by hand.** [RoomPlan.Dressing]
#
# Scene pixels on `RoomLayout`'s grid, y **up**: `x` is the centre of the prop's
# content box and `y` its bottom. The room is 800 wide and its near floor runs
# y 64..224, with the wall face above that and the back rooms' floor at 288.
#
# The seven seat columns stand at x = 112, 208, 304, 400, 496, 592 and 688, and
# each is a corridor one tile wide that a character walks up and down. A floor
# prop clears one when `|x - seat| >= (32 + width) / 2`; anything whose base is
# at or above the wall line at 224 is exempt, because that is where a leaver's
# feet stop. `RoomPlan.dressingViolations` is those two sentences as a check and
# `RoomPlanTests` runs it over this list — the numbers below are not trusted.
#
# **Why by hand at all.** The band system gave every prop one of four depths, so
# twenty props came out as four horizontal stripes across a floor with nothing
# between them, and the maintainer's word for the room was that the furniture
# "sits in one strip". `compose-scene.py`'s engineering office puts about twenty
# floor objects on a floor of the same area and no two of them share a row: a
# five-piece stack down one edge, a pair of boxes overlapping, three lanes with
# something in them and two with nothing. That is composition, it cannot be
# derived from a band name, so it is stated.
#
# The habits copied from that scene, deliberately:
#
#   * one edge carries a **stack** — printer over cabinet over tower over bin —
#     rather than the pieces being spread evenly along the wall;
#   * a lane is either full or empty, never uniformly half-filled;
#   * x is jittered inside a lane instead of being centred in it, because a
#     column of centred props is the lattice again by another route;
#   * the same object appears three or four times. The pack's own rooms repeat
#     one plant in three corners, and a room dressed from twenty distinct props
#     used exactly once each looks like a catalogue.
ROOM_DRESSING = [
    # The left edge: the five-piece stack.
    {"scenery": 13, "x": 256, "y": 176, "what": "printer with a sheet"},
    {"scenery": 10, "x": 160, "y": 186, "what": "two-drawer filing cabinet"},
    {"scenery": 16, "x": 352, "y": 180, "what": "PC tower"},
    {"scenery": 15, "x": 448, "y": 184, "what": "waste bin"},
    # Lane 1 (x 128..192, between seats at 112 and 208).
    {"role": "plant", "x": 158, "y": 196, "what": "small potted plant"},
    {"scenery": 16, "x": 170, "y": 124, "what": "PC tower"},
    {"scenery": 18, "x": 150, "y": 86, "what": "waste bin, full"},
    # Lane 2 (224..288). The scanner is 52 wide and has 12 px of x to live in,
    # which is why it is here and not in a lane that also wants a cabinet.
    {"scenery": 12, "x": 256, "y": 206, "what": "flatbed scanner"},
    {"role": "plant", "x": 246, "y": 160, "what": "small potted plant"},
    {"scenery": 17, "x": 264, "y": 96, "what": "backpack on the floor"},
    # Lane 3 (320..384) — deliberately thin, so the eye has somewhere to rest.
    {"scenery": 11, "x": 350, "y": 200, "what": "office printer"},
    {"scenery": 19, "x": 362, "y": 108, "what": "waste bin, mixed rubbish"},
    # Lane 4 (416..480).
    {"role": "plant", "x": 440, "y": 190, "what": "small potted plant"},
    {"scenery": 14, "x": 452, "y": 130, "what": "wooden two-drawer cabinet"},
    {"scenery": 16, "x": 436, "y": 84, "what": "PC tower"},
    # Lane 5 (512..576) — thin again.
    {"scenery": 10, "x": 540, "y": 204, "what": "two-drawer filing cabinet"},
    {"scenery": 15, "x": 552, "y": 118, "what": "waste bin"},
    # Lane 6 (608..672).
    {"role": "plant", "x": 634, "y": 198, "what": "small potted plant"},
    {"scenery": 17, "x": 648, "y": 100, "what": "backpack on the floor"},
    # The right edge: the second stack, mirroring the first without matching it.
    {"scenery": 11, "x": 640, "y": 212, "what": "office printer"},
    {"scenery": 14, "x": 640, "y": 186, "what": "wooden two-drawer cabinet"},
    {"role": "plant", "x": 544, "y": 178, "what": "small potted plant"},
    {"scenery": 18, "x": 160, "y": 214, "what": "waste bin, full"},
    # Standing on the wall line: the three boards. They are 60 px wide and 46
    # tall, so they are what the upstage half of the room reads as, and the
    # pictures below are hung in the gaps they leave.
    {"role": "board", "x": 176, "y": 224, "what": "presentation board"},
    {"role": "board", "x": 456, "y": 224, "what": "presentation board"},
    {"role": "board", "x": 688, "y": 224, "what": "presentation board"},
    # Hung on the near wall's 50 px of face. Nothing here is on the floor, so
    # the seat columns do not bind and the spacing is the picture's own.
    {"scenery": 0, "x": 88, "y": 238, "what": "whiteboard with sticky notes"},
    {"scenery": 1, "x": 286, "y": 240, "what": "blue planning board"},
    {"scenery": 4, "x": 348, "y": 254, "what": "wall clock"},
    {"scenery": 2, "x": 382, "y": 236, "what": "framed certificate with a medal"},
    {"scenery": 3, "x": 520, "y": 252, "what": "small framed picture"},
    {"scenery": 5, "x": 560, "y": 238, "what": "cork noticeboard with pinned notes"},
    {"scenery": 6, "x": 616, "y": 250, "what": "framed landscape painting"},
    # The back rooms' own floor, at y=288. The tall appliances stand against the
    # far wall's face, which is how the pack draws them, and clear of the two
    # partitions at x=160 and x=544.
    {"scenery": 7, "x": 100, "y": 288, "what": "water cooler"},
    {"scenery": 7, "x": 300, "y": 288, "what": "water cooler"},
    {"scenery": 8, "x": 600, "y": 288, "what": "vending machine"},
    {"scenery": 9, "x": 690, "y": 288, "what": "coffee counter"},
]


def plan_line_inks(path):
    """`(edge, fill)` of a cap tile's floor-plan line, measured down its middle.

    The section is 2 px dark / 8 px light / 2 px dark in the top 12 rows —
    measured in `Office_Design_2.gif` and reproduced here off the shipped bytes
    rather than transcribed, so a re-import that shifts a tone moves the
    partitions with it. `None` for a tile that does not carry one, which is how
    a surface that is not really a wall fails to be declared instead of being
    declared wrong.
    """
    try:
        w, h, px = pnglite.load(path)
    except Exception:
        return None
    if w < 4 or h < 12:
        return None
    def at(x, y):
        i = (y * w + x) * 4
        return tuple(px[i:i + 4])
    mid = w // 2
    edge, fill = at(mid, 0), at(mid, 4)
    if edge[3] != 255 or fill[3] != 255 or edge == fill:
        return None
    if at(mid, 1) != edge or at(mid, 10) != edge or at(mid, 11) != edge:
        return None
    return list(edge[:3]), list(fill[:3])


def build_plan(builder_tiles, dressing=None):
    """`plan` for a builder listing that has the tiles for one, else None.

    `dressing` is hand-placed and therefore indexes one theme's own scenery
    list, so it is passed in per theme rather than living in `ROOM_PLAN`: every
    theme with the builder tiles shares the walls, and only `office` has had its
    dressing composed.

    Gated on the **files**, not on a theme name: a theme whose sheet carries a
    cap, a body and the floors is one this plan can be drawn on, and every other
    theme keeps the open floor with no special case anywhere. [ADR-007 §6]
    """
    have = {os.path.basename(t): t for t in builder_tiles}
    surfaces = {}
    for name, (floor, cap, body) in sorted(PLAN_SURFACES.items()):
        if floor not in have or cap not in have or body not in have:
            return None
        inks = plan_line_inks(os.path.join(REPO, have[cap]))
        if inks is None:
            return None
        surfaces[name] = {
            "floor": have[floor], "cap": have[cap], "body": have[body],
            "line_edge": inks[0], "line_fill": inks[1],
        }
    if not surfaces:
        return None
    return {
        "note": "An authored floor plan [ADR-007]. Tile units on RoomLayout's own "
                "grid, y up; a space's `h` includes the two rows its north wall "
                "eats. `doorways` are absolute tile columns cut clean through that "
                "wall — nothing is drawn in one, the space's own floor is already "
                "there. `line_edge`/`line_fill` are measured off the cap tile and "
                "are what a partition is drawn from, because every plain wall run "
                "in the sheet is a 12-14 px stripe on an otherwise empty tile and "
                "the import pass drops anything under 60%% opaque. Route geometry "
                "is not in here and never may be: RoomPlan.routeViolations(in:) is "
                "the assertion that this plan stands in nobody's way.",
        "surfaces": surfaces,
        "spaces": [dict(s) for s in ROOM_PLAN["spaces"]],
        "partitions": [dict(p) for p in ROOM_PLAN["partitions"]],
        "dressing": [dict(d) for d in (dressing or [])],
    }


def rel(p):
    return os.path.relpath(p, REPO).replace(os.sep, "/")


def frames_for(cdir, pose, direction):
    """Every frame file for one pose and direction, in index order."""
    prefix = "%s_%s_" % (pose, direction)
    names = sorted(n for n in os.listdir(cdir)
                   if n.startswith(prefix) and n.endswith(".png"))
    return [rel(os.path.join(cdir, n)) for n in names]


def content_top(path, w, h):
    """First row holding an opaque pixel.

    The scene needs this to park a badge above the head without a magic number:
    the figure is bottom-aligned in a 32x64 frame and only fills the lower ~44
    rows, so the top of the canvas is not the top of the character.
    """
    _w, _h, px = pnglite.load(path)
    for y in range(h):
        for x in range(w):
            if px[(y * w + x) * 4 + 3] > 127:
                return y
    return 0


def content_box(path):
    """Tight bounding box of the opaque pixels: {x, y, w, h}, y down.

    A Modern Office single is a 64x96 canvas with the object dropped into it
    wherever it sat on the source sheet - the objects are *not* bottom-aligned
    and not centred, and their positions differ from each other by tens of
    pixels. So the scene cannot place one from the canvas alone. Recording the
    measured box lets it put the object's own bottom-centre on a named point,
    which is placement by measurement rather than by eyeballed offsets.
    """
    w, h, px = pnglite.load(path)
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if px[(y * w + x) * 4 + 3] > 127:
                if x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
                if y < y0:
                    y0 = y
                if y > y1:
                    y1 = y
    if x1 < 0:
        return None
    return {"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1}


def raised_frame(frames):
    """Which frame of an animation holds the body **highest**. [ADR-008]

    The `AmbientMotion` phrase table is a schedule over two positions of one
    bob — `settled` and `raised` — and until now `raised` was "the last frame",
    which is a measurement of the three-frame `sit` row (0, 0, up) that happens
    to be right there and is wrong everywhere else. The six-frame `idle` row
    bobs on frames **2 and 3** and returns to rest on 4 and 5, so `frameCount -
    1` picks a *settled* frame and a phrase built on it would hold a working
    character motionless. A seat that faces the camera draws the idle row, so
    that stopped being hypothetical.

    Mechanical, and the same rule for any row: the first frame whose ink starts
    highest.

    Measured on the state's first direction. For the two rows anything reads it
    for — `idle` and `working` — all four directions agree exactly, on every
    variant (idle 2, working 2). `walk` does **not** agree, because its bob is a
    stride and the down block starts on the raised foot; nothing reads `walk`'s,
    and a number that means "the up part of the loop" is not meaningful for a
    row whose loop is a gait. If a phrase is ever keyed on a walk, this is the
    line to revisit rather than to trust.
    """
    tops = [content_top(os.path.join(REPO, p), 32, 64) for p in frames]
    if not tops:
        return None
    return tops.index(min(tops))


def costume_ink_top(sets):
    """How far above the feet a costume's ink reaches, over every **seated**
    pose the room can draw. [ADR-008]

    This is the identity channel's own extent, and it is what an away-facing
    seat's chair is placed against: a chair back `H` px tall drawn in front of
    a character hides every costume pixel at any standoff below `H - this`, so
    a standoff chosen without it erases the costume completely and nothing
    fails. Measured here rather than in `Sources/` because the scene would have
    to open ~1000 PNGs to ask the same question at build time.

    `idle` and `working` only — the two states a seated character draws. `walk`
    reaches 2 px higher and no seat ever draws it.
    """
    highest = None
    for spec in sets.values():
        for layer in spec.get("layers", []):
            for state in ("idle", "working"):
                frames = layer.get("states", {}).get(state, {}).get("frames", {})
                for paths in frames.values():
                    for path in paths:
                        top = content_top(os.path.join(REPO, path), 32, 64)
                        highest = top if highest is None else min(highest, top)
    return None if highest is None else 64 - highest


def desk_surface_height(path, box):
    """How many px above the floor a desk's top surface sits. [ADR-006 SS2b]

    `content_box` measures a desk's own ink footprint, not the plane an object
    could stand on — usually the same row, but not when something is already
    drawn on the desk (`library` binds a wooden desk with an open book on it,
    whose box top is 8px above the slab underneath).

    The rule is mechanical: scan down from the top of `box`, row by row, for
    the first row carrying an unbroken horizontal run of opaque pixels at least
    80% of the box width. That row is the surface. For a bare desk it is the
    box's own top row; for `library` it finds the slab under the book instead.

    Converted to a height above the floor rather than left as an image row,
    because that is what a placement rule needs and what `content_box`'s own
    docstring establishes: the scene puts a prop's content_box *bottom*-centre
    on the floor point for its tile, so the box's bottom row is the floor and
    every row above it is that many px higher — `(box.y + box.h) - surface_row`.

    Returns `None` if no row clears the threshold, which should not happen for
    anything shaped like a desk; the caller treats that as "no surface" rather
    than guessing one. [I1]
    """
    w, h, px = pnglite.load(path)
    threshold = 0.8 * box["w"]
    for y in range(box["y"], box["y"] + box["h"]):
        run = best = 0
        for x in range(box["x"], box["x"] + box["w"]):
            if px[(y * w + x) * 4 + 3] > 127:
                run += 1
                best = max(best, run)
            else:
                run = 0
        if best >= threshold:
            return (box["y"] + box["h"]) - y
    return None


def build_characters():
    base = os.path.join(PROCESSED, "characters", SIZE)
    if not os.path.isdir(base):
        return None
    variants = {}
    for who in sorted(os.listdir(base)):
        cdir = os.path.join(base, who)
        if not os.path.isdir(cdir):
            continue
        states = {}
        ok = True
        for state, spec in STATES.items():
            per_dir = {}
            for d in spec["dirs"]:
                fl = frames_for(cdir, spec["pose"], d)
                if not fl:
                    ok = False
                    break
                per_dir[d] = fl
            if not ok:
                break
            states[state] = {
                "source_pose": spec["pose"],
                "loop": spec["loop"],
                "fps": FPS,
                "frame_count": len(next(iter(per_dir.values()))),
                "raised_frame": raised_frame(next(iter(per_dir.values()))),
                "frames": per_dir,
            }
        if not ok:
            continue
        for name, src in COMPOSED.items():
            states[name] = {
                "composed_from": src,
                "loop": True,
                "fps": FPS,
                "frame_count": states[src]["frame_count"],
                "raised_frame": states[src]["raised_frame"],
                "frames": states[src]["frames"],
            }
        first = states["idle"]["frames"]["down"][0]
        variants[who] = {
            "provenance": "pack",
            "source": "Modern Interiors / 0_Premade_Characters/%s/Premade_Character_%s_%s.png"
                      % (SIZE, SIZE, who),
            "head_top_px": content_top(os.path.join(REPO, first), 32, 64),
            "states": states,
        }
    if not variants:
        return None
    for i, who in enumerate(sorted(variants)):
        variants[who]["accent_hex"] = ACCENT_HUES[i % len(ACCENT_HUES)]
        variants[who]["accent_provenance"] = "assigned"
    return {
        "canvas": {"w": 32, "h": 64},
        "anchor": {"px": [16, 64], "normalized": [0.5, 0.0],
                   "note": "bottom-centre; the character stands on this point"},
        "directions": ["right", "up", "left", "down"],
        "frame_rate": FPS,
        "accent_note": "accent_hex is assigned, not sampled. The art's own most "
                       "saturated pixels do not separate — all six selected premades "
                       "land inside a 30 degree hue arc and two of them are "
                       "hue-identical (measured at M2). These six are 60 degrees "
                       "apart. The accent is drawn by the scene as the nameplate "
                       "border; it is not a claim about any pixel in the sprite. "
                       "scripts/lint-palette.py checks the separation.",
        "unsourceable_states": {
            "read": "no 'read a book' animation exists in Modern Interiors; "
                    "docs/04-ART-DIRECTION.md permits dropping it",
            "attention": "badge only, by design — no honest body animation exists [I1]",
        },
        "variants": variants,
    }


def build_costumes():
    """`characters.costumes` — the wardrobe, from what `costumes()` actually cut.

    **On, unconditionally.** It shipped behind a `--costumes` flag while
    `CostumeContractTests.theShippedManifestDeclaresNoWardrobeAndThatIsLegal`
    still asserted the committed manifest declared none. That assertion has
    flipped — the suite now reads a wardrobe out of the shipped manifest — so
    the flag had become a loaded gun: a rerun *without* it silently deleted a
    hand-verified section, which is exactly the failure the no-regression check
    in `main()` now refuses outright. There is no way to ask for a manifest
    without the wardrobe, because nothing wants one.

    Structure comes straight from `Manifest.costumes(_:frameRate:)`:
    `sets.<id>.layers[]` back to front, each layer carrying its own `states`,
    plus `roles` (exact `agent_type`) and `assignable` (the hash's pool).
    """
    base = os.path.join(PROCESSED, "costumes", SIZE)
    if not os.path.isdir(base):
        return None
    imp = import_process_assets()
    sets = {}
    for who in sorted(os.listdir(base)):
        cdir = os.path.join(base, who)
        if not os.path.isdir(cdir) or who not in imp.COSTUMES:
            continue
        spec = imp.COSTUMES[who]
        layers = []
        ok = True
        for index in range(len(spec["layers"])):
            ldir = os.path.join(cdir, "l%d" % index)
            if not os.path.isdir(ldir):
                ok = False
                break
            states = {}
            for state, sspec in STATES.items():
                per_dir = {}
                for d in sspec["dirs"]:
                    fl = frames_for(ldir, sspec["pose"], d)
                    if not fl:
                        ok = False
                        break
                    per_dir[d] = fl
                if not ok:
                    break
                states[state] = {
                    "source_pose": sspec["pose"],
                    "loop": sspec["loop"],
                    "fps": FPS,
                    "frame_count": len(next(iter(per_dir.values()))),
                    "frames": per_dir,
                }
            if not ok:
                break
            for name, src in COMPOSED.items():
                states[name] = {
                    "composed_from": src,
                    "loop": True,
                    "fps": FPS,
                    "frame_count": states[src]["frame_count"],
                    "frames": states[src]["frames"],
                }
            layers.append({"source": rel_layer_source(imp, spec, index),
                           "states": states})
        if not ok or not layers:
            continue
        sets[who] = {
            "title": spec.get("title", who),
            "asserts": spec.get("asserts") is not None,
            "reads": spec.get("reads", ""),
            "assertion": spec.get("asserts"),
            "layers": layers,
        }
    if not sets:
        return None
    # Insertion order, not sorted: `COSTUME_ROLES` is grouped by costume so a
    # reviewer can read "which names wear the lab coat" in one glance, and
    # sorting here would throw that grouping away on the way to the artefact
    # people actually read. Order is stable because the table is a literal.
    roles = {t: c for t, c in imp.COSTUME_ROLES.items() if c in sets}
    assignable = [c for c in imp.COSTUME_ASSIGNABLE if c in sets]
    # The invariant `CostumeContractTests` checks, checked here too so a bad
    # manifest is never written rather than written and then failed.
    asserting = [c for c in assignable if sets[c]["asserts"]]
    if asserting:
        print("error: %s assert and are assignable; a hash would be making a "
              "claim about an agent_type nobody anticipated [I1]"
              % ", ".join(asserting), file=sys.stderr)
        raise SystemExit(3)
    out = {
        "note": "Two tiers. `roles` is keyed on the exact agent_type string and "
                "may translate it — a test-engineer in a lab coat is the room "
                "repeating a name the user chose. `assignable` is the pool an "
                "unrecognised type is hashed over and nothing in it asserts, "
                "which is the question_mark rule on the character layer. [I1]",
        "sets": sets,
        "roles": roles,
        "assignable": assignable,
    }
    top = costume_ink_top(sets)
    if top is not None:
        out["ink_top_px"] = top
        out["ink_top_note"] = (
            "How far above the feet a costume's ink reaches, over the two "
            "states a seated character draws (`idle` and `working`), every "
            "set, every layer, every frame, every direction. It is the "
            "identity channel's own extent, and an away-facing seat's chair "
            "is placed against it: a chair back H px tall drawn in front of a "
            "character hides every costume pixel at any standoff below "
            "H - this. [ADR-008]")
    return out


def rel_layer_source(imp, spec, index):
    """Where one layer came from, for the About panel and for review."""
    kind, pick = spec["layers"][index]
    folder, tmpl = imp.COSTUME_LAYER_SRC[kind]
    name = tmpl % (pick[0], SIZE, pick[1]) if isinstance(pick, tuple) \
        else tmpl % (SIZE, pick)
    return "Modern Interiors / Character_Generator/%s/%s/%s" % (folder, SIZE, name)


def import_process_assets():
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "process_assets", os.path.join(REPO, "scripts", "process-assets.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_room():
    base = os.path.join(PROCESSED, "room", SIZE)
    if not os.path.isdir(base):
        return None
    def listing(sub):
        d = os.path.join(base, sub)
        if not os.path.isdir(d):
            return []
        return [rel(os.path.join(d, n)) for n in sorted(os.listdir(d)) if n.endswith(".png")]
    builder = listing("builder")
    props = listing("singles")
    if not builder and not props:
        return None

    # Roles. Each one is re-derived from the file on disk: if the single is not
    # there, the role is not written, and the manifest simply has one fewer role
    # rather than a dangling name.
    roles = {}
    for role, spec in sorted(PROP_ROLES.items()):
        path = os.path.join(base, "singles",
                            "Modern_Office_Singles_%s_%d.png" % (SIZE, spec["index"]))
        if not os.path.exists(path):
            continue
        box = content_box(path)
        if box is None:
            continue
        roles[role] = {
            "file": rel(path),
            "single_index": spec["index"],
            "provenance": "pack",
            "identified_by": spec.get(
                "identified_by",
                "rendered and inspected by eye at M5; the pack ships no "
                "names for its singles"),
            "what": spec["what"],
            "content_box": box,
        }
        if role == "desk":
            surface = desk_surface_height(path, box)
            if surface is not None:
                roles[role]["surface_y"] = surface

    out = {
        "tile": {"w": 32, "h": 32},
        "anchor": {"px": [0, 0], "normalized": [0.0, 0.0], "note": "bottom-left of the tile"},
        "provenance": "pack",
        "processed_by": "scripts/process-assets.py",
        "note": "Desaturated and value-compressed at import [I7]. Never edit these by "
                "hand — they are regenerated whenever the pack updates.",
        "builder": {
            "source": "Modern Office / Room_Builder_Office_%s.png" % SIZE,
            "note": "floors and walls, sliced on the sheet's exact 32px grid",
            "tiles": builder,
        },
        "props": {
            "source": "Modern Office / 4_Modern_Office_singles/%s" % SIZE,
            "canvas": {"w": 64, "h": 96},
            "identified": bool(roles),
            "note": "The pack names singles by index only — no filenames, no layer or "
                    "slice names in its .ase, no tags. The %d roles below were "
                    "identified by rendering the singles and looking at them; the "
                    "other %d files stay unidentified and are listed for completeness "
                    "only. An object is placed by putting its measured content_box "
                    "bottom-centre on a named point, because the singles are not "
                    "bottom-aligned in their canvas. The `desk` role additionally "
                    "carries `surface_y`: how many px above the floor its top surface "
                    "sits, measured by the topmost row of an 80%%-of-box-width ink run "
                    "rather than by the box's own top — the two disagree wherever "
                    "something is drawn standing on the desk. [ADR-006 SS2b] "
                    "`laptop`, `papers` and `pad` are desk-top object "
                    "declarations for ADR-006 SS1/SS2c — measured content_box "
                    "only, not yet placed by any scene code. A fourth kind, a "
                    "desk monitor with a lit screen for `running`, is "
                    "deliberately not declared: every candidate single in the "
                    "pack's desk-scale band (130-134, 30-32px wide) exceeds the "
                    "SS2c desk-top width bound of 28px, so no compliant art "
                    "exists for it. "
                    "`scenery` points into processed/themes/office/, not into "
                    "the folder above: `room` IS the resolved default theme "
                    "[ADR-002 SS14a] and its dressing has to be byte-identical to "
                    "themes.sets.office's or the same room would be two rooms. "
                    "Six of the office scenery props come from the Hospital set "
                    "— the only bins, filing cabinets, wall clocks and schedule "
                    "boards in either pack — and the room singles folder holds "
                    "the Office set only, so it could not carry them at all."
                    % (len(roles), len(props) - len(roles)),
            "scenery_note": SCENERY_NOTE,
            "roles": roles,
            "scenery": scenery_entries(
                "office", _theme_table().get("office", {}),
                lambda i, band, _set, _single: os.path.join(
                    PROCESSED, "themes", "office", SIZE, "scenery",
                    "%02d_%s.png" % (i, band))),
            "files": props,
        },
    }
    stations = build_stations(base)
    if stations is not None:
        out["props"]["stations"] = stations
    # `room` IS the resolved default theme [ADR-002 §14a], so it takes the same
    # plan `themes.sets.office` does or the same room would be two rooms.
    # `room` IS the resolved default theme, so it takes the office dressing.
    plan = build_plan(builder, ROOM_DRESSING)
    if plan is not None:
        out["plan"] = plan
    return out


def build_stations(base):
    """`room.props.stations` — the workspace one agent sits at. [ADR-002 §14c]

    Declared **once**, here under `room`, and inherited by every theme that does
    not declare its own. Only one object in either pack is a chair drawn side-on
    with its backrest on the left, which is what the pack's one-directional
    seated pose requires, so a station cannot be themed art anyway; six copies of
    this block would have been six places for it to drift.

    Every prop is a Modern Office single the room pass has already cut, so this
    reads the same PNGs `props.files` lists and measures each one's content box
    off the shipped bytes rather than restating a number somebody transcribed.
    The two-tier `roles`/`assignable` split is `characters.costumes`', verbatim.
    """
    imp = _importer()
    table = getattr(imp, "STATIONS", {}) if imp else {}
    if not table:
        return None
    max_w = getattr(imp, "STATION_PROP_MAX_W", 32)

    sets, oversize = {}, []
    for sid, spec in table.items():
        entry = {"title": spec["title"], "what": spec["what"],
                 "asserts": spec["asserts"]}
        index = spec.get("index")
        if index is not None:
            path = os.path.join(base, "singles",
                                "Modern_Office_Singles_%s_%d.png" % (SIZE, index))
            if not os.path.exists(path):
                continue
            box = content_box(path)
            if box is None:
                continue
            if box["w"] > max_w:
                oversize.append("%s (single %d) is %dpx wide"
                                % (sid, index, box["w"]))
            entry["prop"] = {
                "file": rel(path),
                "source_set": "Modern Office singles",
                "single_index": index,
                "provenance": "pack",
                "identified_by": imp.STATION_IDENTIFIED_BY,
                "what": spec["reads"],
                "content_box": box,
            }
        sets[sid] = entry
    if not sets:
        return None

    # The geometry limit, checked against the art rather than asserted about it.
    # A prop wider than the seat gap clips its neighbour at every seat, and the
    # cheapest place to find that out is before the manifest claims otherwise.
    if oversize:
        print("error: station prop wider than the %dpx seat gap: %s"
              % (max_w, "; ".join(oversize)), file=sys.stderr)
        raise SystemExit(3)

    roles = {t: s for t, s in getattr(imp, "STATION_ROLES", {}).items() if s in sets}
    assignable = [s for s in getattr(imp, "STATION_ASSIGNABLE", ()) if s in sets]
    # The I1 invariant `StationContractTests` checks, checked here too so a bad
    # manifest is never written rather than written and then failed.
    asserting = [s for s in assignable if sets[s]["asserts"]]
    if asserting:
        print("error: %s assert and are assignable; a hash would be making a "
              "claim about an agent_type nobody anticipated [I1]"
              % ", ".join(asserting), file=sys.stderr)
        raise SystemExit(3)

    return {
        "note": "A station is the workspace one agent sits at: the theme's own desk "
                "and chair, plus at most one floor-standing prop beside the seat. "
                "[ADR-002 SS4, SS7, SS14c]\n\n"
                "Two tiers, exactly as `characters.costumes` has them, and the split "
                "is the whole of I1 here. `roles` is keyed on the EXACT agent_type "
                "string a session produced, so a station reached through it is the "
                "room repeating a name the user chose - the same licence the "
                "nameplate runs on - and it may therefore assert what kind of worker "
                "this is. `assignable` is the pool the hash draws from for an "
                "agent_type nobody anticipated; arbitrary user text licenses no claim "
                "about the work, so every member of it must carry `asserts: false` "
                "and says only `this is a different agent from that one`.\n\n"
                "Declared ONCE, here under `room`, and inherited by every theme that "
                "does not declare its own: only one chair in either pack is a side "
                "view with its backrest on the left, so a station cannot be themed "
                "art anyway, and six identical copies of this block would be six "
                "places for it to drift. A theme that declares `props.stations` "
                "overrides the whole block for itself. `desk` and `chair` are omitted "
                "from every station below and inherited from the theme's own "
                "`props.roles`, so a station changes what stands BESIDE the seat and "
                "never what the theme's furniture looks like.\n\n"
                "Geometry, and both numbers are the layout's rather than taste. A "
                "prop is placed one tile to the character's left on the seat row, so "
                "its content box must be at most %dpx wide: the desk occupies "
                "x+12..x+44 of a 96px seat pitch and the next seat's prop starts at "
                "x+48. A station desk must also be at most 44px tall, because it is "
                "drawn IN FRONT of the body and 44 is how far the shortest variant's "
                "head sits above its own feet." % max_w,
        "sets": sets,
        "roles": roles,
        "assignable": assignable,
    }


SCENERY_NOTE = (
    "`scenery` is the room's dressing: everything the four roles above are not "
    "— printers, cabinets, bins, coolers, wall boards. An ordered list, not a "
    "map, because the order is what maps a prop onto an anchor. Each entry "
    "carries a `band` — `wall`, `wall_line`, `back_floor`, `mid_floor` — and "
    "that is the ONLY placement fact here: which column and which y is scene "
    "geometry and lives in RoomLayout.sceneryAnchors(_:), so the art swaps with "
    "no code change. The band is hand-authored in scripts/process-assets.py, "
    "because it cannot be derived — docs/PLACEMENT-BANDS.md is the measured "
    "negative result. A band the scene does not know draws nothing rather than "
    "guessing. Scenery is chosen by theme, decided at build time and identical "
    "for every agent; nothing in the delta stream reaches it, and none of it "
    "may ever carry an `animation` — the motion budget is priced on the four "
    "roles. [ADR-002 SS6 rule 1, SS14b, I1]"
)


def scenery_entries(theme_name, spec, path_for):
    """`props.scenery` for one room: the declared list, measured off disk.

    `path_for(index, band)` says where this room keeps the cut file, which is
    the one thing `room` and `themes.sets.<id>` do differently — the default
    room draws the Office singles straight out of `processed/room/`, and a theme
    draws its own re-padded copies. Everything else, including the order, is one
    list in `scripts/process-assets.py`: two copies of it would be two rooms.

    An entry whose file is missing or unmeasurable is dropped, so the manifest
    never names art that is not there.
    """
    out = []
    for index, entry in enumerate(spec.get("scenery", ())):
        band, setno, single, what = entry
        path = path_for(index, band, setno, single)
        if path is None or not os.path.exists(path):
            continue
        box = content_box(path)
        if box is None:
            continue
        out.append({
            "band": band,
            "file": rel(path),
            "source_set": "Modern Office singles" if setno == "office"
                          else "Modern Interiors Theme Sorter set %s" % setno,
            "single_index": single,
            "provenance": "pack",
            "identified_by": "named in assets/catalogue.json by "
                             "scripts/name-catalogue.py, then rendered at 6x with "
                             "its content box drawn and looked at before the index "
                             "was written into scripts/process-assets.py; the packs "
                             "ship no names for their singles",
            "what": what,
            "content_box": box,
        })
    return out


def _importer():
    """scripts/process-assets.py as a module, or None if unreadable.

    Imported rather than duplicated. The importer owns which single fills which
    slot, which animated object a theme adopts, and what canvas everything was
    padded into — those are the things that were established by looking at the
    art — and a second copy here would be a second source of truth that drifts.
    The hyphenated filename is why this needs importlib rather than `import`.
    """
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "process-assets.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("_process_assets", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _theme_table():
    mod = _importer()
    return getattr(mod, "THEMES", {}) if mod else {}


def _animated_table():
    """(ANIMATED, adopted ids, prop canvas) from the importer.

    `adopted` is deliberately a separate set from the table: the importer cuts
    every animated object it knows about so that `preview-theme.py` can stand
    any of them in a room and be looked at, and only the adopted ones reach the
    manifest. That is the same split docs/04-ART-DIRECTION.md asks for between
    art that exists and art that ships.
    """
    mod = _importer()
    if mod is None:
        return {}, set(), (64, 96)
    return (getattr(mod, "ANIMATED", {}),
            set(getattr(mod, "ANIMATED_ADOPTED", ())),
            tuple(getattr(mod, "PROP_CANVAS", (64, 96))))


def animated_role(name, spec, canvas):
    """`{file, content_box, animation}` for one adopted animated object.

    Three things here are measured on the shipped frames rather than declared.

    **`content_box` is the union over every frame**, not frame 0's. The scene
    anchors a prop by its box and draws every frame on one canvas at one
    position, so a box that described only frame 0 would be a claim about the
    prop that is false for the rest of the loop — and the foreground-clearance
    test in the scene reads that box's height. Where the union equals frame 0's
    box, as it does for everything adopted so far, the two readings agree and
    `file`-only readers lose nothing.

    **`moving_px` / `visible_px` / `transition_px`** are the I7 numbers for a
    moving prop. Motion draws the eye and the eye belongs on the characters, so
    how much of the object moves is the thing to look at before adopting one.
    They are generated here so they cannot drift from the art the way a
    transcribed figure did at M6b.

    The three are different quantities and the distinction is load-bearing.
    `moving_px` is the union over the loop against frame 0 — a per-loop total
    that grows with the number of frames and carries no rate. `transition_px` is
    what changes on each step, so `mean(transition_px) * fps` is pixels changed
    per second, which is comparable between a 3-frame loop at 2 fps and an
    11-frame loop at 10 fps. `scripts/lint-palette.py` budgets the second one.

    **`fps` was verified against the pack's own GIF at import**, which is the
    only place in these packs that states how fast anything moves.
    """
    d = os.path.join(PROCESSED, "animated", SIZE, name)
    if not os.path.isdir(d):
        return None
    files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    if not files:
        return None
    paths = [os.path.join(d, f) for f in files]
    frames = [pnglite.load(p) for p in paths]
    w, h, _ = frames[0]
    if any((fw, fh) != (w, h) for fw, fh, _ in frames):
        return None
    # One `props.canvas` covers every role, so a role whose frames are not on it
    # is not a role. This is the check that keeps `control_room_screens` out
    # rather than a comment in the importer's table: it is 128 px wide, the
    # canvas is 64, and the manifest would otherwise claim a size that is false
    # of the art. It fails loudly because a silently dropped role leaves a theme
    # with no backdrop.
    if (w, h) != tuple(canvas):
        print("  note: %s frames are %dx%d, not the %dx%d prop canvas — not "
              "adoptable as a role" % ((name, w, h) + tuple(canvas)), file=sys.stderr)
        return None

    box = None
    for p in paths:
        b = content_box(p)
        if b is None:
            continue
        if box is None:
            box = dict(b)
            continue
        x1 = max(box["x"] + box["w"], b["x"] + b["w"])
        y1 = max(box["y"] + box["h"], b["y"] + b["h"])
        box["x"] = min(box["x"], b["x"])
        box["y"] = min(box["y"], b["y"])
        box["w"] = x1 - box["x"]
        box["h"] = y1 - box["y"]
    if box is None:
        return None

    base = frames[0][2]
    visible = moving = 0
    for i in range(w * h):
        if any(f[2][i * 4 + 3] > 127 for f in frames):
            visible += 1
        if any(f[2][i * 4:i * 4 + 4] != base[i * 4:i * 4 + 4] for f in frames[1:]):
            moving += 1

    # Per *step* of the loop, wrapping past the last frame back to the first,
    # because `loop` is always true. `moving_px` above is the union over the
    # whole loop against frame 0, which grows with loop length and says nothing
    # about rate — a 20-frame loop that drifts one pixel at a time accumulates a
    # large union while changing almost nothing per second. This list is the raw
    # measurement the motion budget is computed from; integers, so the manifest
    # stays byte-deterministic and a reviewer can see the shape of the loop
    # rather than a mean somebody took.
    transitions = []
    for a, b in zip(frames, frames[1:] + frames[:1]):
        transitions.append(sum(
            1 for i in range(w * h)
            if a[2][i * 4:i * 4 + 4] != b[2][i * 4:i * 4 + 4]))

    return {
        "file": rel(paths[0]),
        "content_box": box,
        "animation": {
            "frames": [rel(p) for p in paths],
            "fps": spec["fps"],
            "loop": True,
            "fps_source": "the pack's own GIF of this object holds every frame "
                          "for %d/100 s; scripts/process-assets.py reads it and "
                          "refuses to cut a sheet whose GIF disagrees"
                          % round(100.0 / spec["fps"]),
            "moving_px": moving,
            "visible_px": visible,
            "transition_px": transitions,
            "measured_on": "the shipped frames, by scripts/build-manifest.py. "
                           "`moving_px` is the union over the loop against frame "
                           "0 and `visible_px` the union of visible pixels; "
                           "`transition_px` is the pixels that change on each "
                           "step of the loop, wrapping, and is what "
                           "scripts/lint-palette.py's motion budget is computed "
                           "from — mean(transition_px) * fps * how many times "
                           "the room draws this role. The lint recomputes all "
                           "three off the same PNGs and fails if they disagree "
                           "with these.",
        },
    }


def build_themes():
    """Every themed room, each shaped exactly like `room`.

    Why a sibling of `room` rather than a replacement for it: `room` is the
    contract the scene loads today, and a themed room has to be a manifest swap
    with zero code change. So `room` stays byte-for-byte what it was — it is the
    resolved default theme — and `themes.sets.<id>` carries the same shape for
    every theme including that default. A scene that learns to select a theme
    reads `themes.sets[id]` with the loader it already has for `room`; nothing
    has to be reshaped and no existing reader breaks.

    Each theme declares its own floor and wall explicitly. Today the scene
    instead *searches* the builder tiles for the only two that are fully opaque
    and a single colour and takes the darkest and lightest, which is why every
    theme also ships a flat tile of its floor's and wall's own mean tone: under
    the current heuristic a theme still renders, in its own tones, flat. The
    declared `floor`/`wall` are what it should use once it is told to.
    """
    base = os.path.join(PROCESSED, "themes")
    if not os.path.isdir(base):
        return None
    table = _theme_table()
    animated, adopted, prop_canvas = _animated_table()
    sets = {}
    for name in sorted(os.listdir(base)):
        tdir = os.path.join(base, name, SIZE)
        if not os.path.isdir(tdir):
            continue
        spec = table.get(name, {})
        # An adopted animated object replaces this theme's static binding for
        # the role it names. The static single is still cut and still on disk;
        # it is simply not what the theme draws, which is the same relationship
        # the flat builder tile has to the patterned one.
        anim = {a["role"]: (aid, a) for aid, a in sorted(animated.items())
                if aid in adopted and a["for"] == name}
        roles = {}
        for role in sorted(spec.get("roles", {})):
            if role in anim:
                aid, aspec = anim[role]
                entry = animated_role(aid, aspec, prop_canvas)
                if entry is not None:
                    static = os.path.join(tdir, "singles", "%s.png" % role)
                    entry.update({
                        "source_set": "Modern Interiors 3_Animated_objects",
                        "source_sheet": aspec["sheet"],
                        "provenance": "pack",
                        "identified_by": "the animated folder is the one place in "
                                         "these packs where the files are named; the "
                                         "frames were still cut and looked at in the "
                                         "room before this entry was written",
                        "what": aspec["what"],
                        "replaces_static": rel(static) if os.path.exists(static) else None,
                    })
                    roles[role] = {k: v for k, v in entry.items() if v is not None}
                    continue
            path = os.path.join(tdir, "singles", "%s.png" % role)
            if not os.path.exists(path):
                continue
            box = content_box(path)
            if box is None:
                continue
            setno, index, what = spec["roles"][role]
            roles[role] = {
                "file": rel(path),
                "source_set": "Modern Office singles" if setno == "office"
                              else "Modern Interiors Theme Sorter set %s" % setno,
                "single_index": index,
                "provenance": "pack",
                "identified_by": "rendered with scripts/contact-sheet.py and inspected "
                                 "by eye, then confirmed at 4x with --pick; the packs "
                                 "ship no names for their singles",
                "what": what,
                "content_box": box,
            }
            if role == "desk":
                surface = desk_surface_height(path, box)
                if surface is not None:
                    roles[role]["surface_y"] = surface

            # `role_variants` is extra stock for this role beyond `roles[role]`
            # itself — scripts/process-assets.py writes it to `<role>_<n>.png`
            # for n = 1, 2, .... `variants[0]` is always `roles[role]["file"]`,
            # unpicked, so a reader that has never heard of `variants` draws it
            # and is correct — same contract as `animation`'s `frames`. Missing
            # or unfittable stock is skipped rather than failing the build: a
            # pool that came up short of the source table is a real finding
            # (recorded beside the table in scripts/process-assets.py), not a
            # reason to drop the entries that did survive.
            wanted = spec.get("role_variants", {}).get(role)
            if wanted:
                variants = [roles[role]["file"]]
                for i in range(1, len(wanted) + 1):
                    vpath = os.path.join(tdir, "singles", "%s_%d.png" % (role, i))
                    if os.path.exists(vpath) and content_box(vpath) is not None:
                        variants.append(rel(vpath))
                if len(variants) > 1:
                    roles[role]["variants"] = variants

        bdir = os.path.join(tdir, "builder")
        tiles, declared = [], {}
        if os.path.isdir(bdir):
            tiles = [rel(os.path.join(bdir, n))
                     for n in sorted(os.listdir(bdir)) if n.endswith(".png")]
            # The floor is the cut tile: it tiles cleanly and its pattern is
            # most of what makes one theme not another.
            #
            # The WALL IS THE FLAT, and that is a finding about the pack rather
            # than a preference. Every wall tile in Room_Builder_Walls carries
            # vertical trim — measured: the left and right edge columns differ
            # on 28-32 of 32 rows for every tile picked — because the sheet is
            # drawn for wall *segments* with corners, not for a wall repeated
            # across a 25-tile room. Tiled horizontally they show a hard seam
            # every 32 px. The Office room never hit this because its builder
            # sheet yields a flat wall, which is what ships today.
            #
            # It is also the better answer under I7 even if the seams were not
            # there: the wall is the largest continuous area on screen and it
            # sits directly behind every character, so it is exactly where a
            # busy pattern would compete at the size characters are hardest to
            # read. The cut tile is still written out and still listed in
            # `tiles`, so the tone is traceable to a real tile in the download.
            floor_cut = os.path.join(bdir, "floor.png")
            wall_flat = os.path.join(bdir, "flat_wall.png")
            if os.path.exists(floor_cut):
                declared["floor"] = rel(floor_cut)
            if os.path.exists(wall_flat):
                declared["wall"] = rel(wall_flat)
            for extra, path in (("floor_flat", os.path.join(bdir, "flat_floor.png")),
                                ("wall_pattern_source", os.path.join(bdir, "wall.png"))):
                if os.path.exists(path):
                    declared[extra] = rel(path)
        else:
            # The default theme reuses the Office room's own builder tiles
            # rather than shipping a second copy of them.
            room = build_room()
            tiles = room["builder"]["tiles"] if room else []

        if not roles:
            continue
        plan = build_plan(tiles, ROOM_DRESSING if name == "office" else None)
        sets[name] = {
            "title": spec.get("title", name),
            "what": spec.get("what", ""),
            # ADR-002 §3e. `assignable` is what the *hash* may pick; every theme
            # is choosable by the user regardless. The split exists so a room
            # that would read as a claim about the work can be offered without
            # ever being assigned to someone by accident — the difference
            # between a user saying "make mine the jail" and the app deciding a
            # project looks like one. [I1]
            #
            # All six current themes are neutral workplaces, so all six are
            # assignable. The flag is here so the first theme that is not can
            # say so in the manifest rather than in a special case in Sources/.
            "assignable": spec.get("assignable", True),
            "tile": {"w": 32, "h": 32},
            "anchor": {"px": [0, 0], "normalized": [0.0, 0.0],
                       "note": "bottom-left of the tile"},
            "provenance": "pack",
            "processed_by": "scripts/process-assets.py",
            "builder": dict(
                {"tiles": tiles,
                 "source": "Modern Interiors / Room_Bulder_subfiles_%s" % SIZE
                           if os.path.isdir(bdir)
                           else "Modern Office / Room_Builder_Office_%s.png" % SIZE,
                 "note": "`floor` and `wall` are the two tiles this theme draws. "
                         "`floor` is cut from the pack. `wall` is provenance "
                         "'authored' — a flat field of the mean tone of the pack tile "
                         "recorded in `wall_pattern_source`, because every wall tile "
                         "in that sheet carries vertical trim and seams every 32px "
                         "when repeated across a 25-tile room. `floor_flat` is the "
                         "same treatment of the floor, and is what the scene's current "
                         "single-colour-tile heuristic will pick until it is told to "
                         "read `floor` and `wall`.",
                 "authored_tiles": ["wall", "floor_flat"],
                 "authored_because": "the pack's wall tiles do not tile seamlessly; "
                                     "measured in scripts/build-manifest.py"},
                **declared),
            "props": {
                "canvas": {"w": prop_canvas[0], "h": prop_canvas[1]},
                "identified": True,
                "note": "Every prop is padded bottom-centred into one %dx%d canvas at "
                        "import so that a single `canvas` covers them all. The theme "
                        "sorter singles arrive on tight per-sprite canvases and are NOT "
                        "bottom-aligned in them, so a prop is placed by putting its "
                        "measured content_box bottom-centre on a named point. The "
                        "canvas widened from 64 to 128 at M6c to admit a 128px-wide "
                        "animated prop; padding is bottom-centred and placement is by "
                        "content_box, so nothing moved — checked in pixels against a "
                        "before/after render of all six themes, not in arithmetic. "
                        "The `desk` role additionally carries `surface_y`: how many px "
                        "above the floor its top surface sits, measured by the topmost "
                        "row of an 80%%-of-box-width ink run rather than by the box's "
                        "own top — bottom-centred padding does not move it, since it is "
                        "computed from the box's own coordinates. [ADR-006 SS2b]"
                        % prop_canvas,
                "animation_note": "A role may carry an `animation` object beside `file`. "
                                  "`file` is frame 0 and stays first, so a reader that "
                                  "knows nothing about animation draws it and is "
                                  "correct. `animation.fps` comes from the pack's own "
                                  "GIF of the object, `loop` is always true, and the "
                                  "prop never reacts to an event — ADR-002 §6 rule 1 "
                                  "and §9. `moving_px`/`visible_px`/`transition_px` are "
                                  "I7's numbers for a moving prop and are measured on "
                                  "these frames; the motion budget in "
                                  "scripts/lint-palette.py is a budget on "
                                  "mean(transition_px) * fps, summed over every copy the "
                                  "room draws, against the quietest looping animation in "
                                  "the cast.",
                "variants_note": "A role may carry `variants` beside `file`: an ordered "
                                 "list of file paths, `file` first, so a reader that "
                                 "knows nothing about `variants` draws `file` and is "
                                 "correct — the same contract `animation` states for "
                                 "`frames`, in the same voice. What indexes it is the "
                                 "seat, at build time, identically for every agent: §6 "
                                 "rule 1 says the room does not change with activity at "
                                 "all, so nothing in the delta stream may reach this list "
                                 "after the room is built [ADR-002 SS6 rule 1, I1].",
                "scenery_note": SCENERY_NOTE,
                "roles": roles,
                "scenery": scenery_entries(
                    name, spec,
                    lambda i, band, _set, _single: os.path.join(
                        tdir, "scenery", "%02d_%s.png" % (i, band))),
            },
        }
        if plan is not None:
            sets[name]["plan"] = plan
    if not sets:
        return None
    return {
        "default": "office" if "office" in sets else sorted(sets)[0],
        "note": "Each entry has the same shape as `room`, which is the resolved "
                "default. The four role names are placement slots, not object nouns: "
                "`plant` is the repeated back-wall and walkway accent, and a theme "
                "fills it with whatever plays that part — a console terminal, a "
                "bookcase, a stage curtain. Selection mechanism is docs/ADR-002.",
        "sets": sets,
    }


def build_badges():
    real = os.path.join(PROCESSED, "badges", SIZE)
    drawn = os.path.join(AUTHORED, "badges", SIZE)

    # Where each cut badge came from, written by scripts/process-assets.py at the
    # moment it did the cutting. Read rather than restated so the two scripts
    # cannot disagree about which cell produced which badge.
    cut = {}
    unsourceable = {}
    sidecar = os.path.join(real, "sources.json")
    if os.path.exists(sidecar):
        with open(sidecar) as f:
            blob = json.load(f)
        cut = blob.get("badges", {})
        unsourceable = blob.get("unsourceable", {})

    out = {}
    for name in BADGE_NAMES:
        entry = None
        p = os.path.join(real, "%s.png" % name)
        if os.path.exists(p):
            entry = {"file": rel(p), "provenance": "pack"}
            entry.update(cut.get(name, {}))
            entry["provenance"] = "pack"
        else:
            p = os.path.join(drawn, "%s.png" % name)
            if os.path.exists(p):
                # M5c: these are authored final art, not placeholders. No
                # further art packs will be bought, so "placeholder" would be a
                # claim about a roadmap that does not exist. `placeholder` keeps
                # its meaning elsewhere in this manifest for things that really
                # are scaffolding.
                entry = {"file": rel(p), "provenance": "authored"}
                # The search that led here, in the words of the script that did
                # it. Kept because it is a real finding and someone will ask —
                # but worded as why this badge is *authored*, not as why it is
                # still waiting. Nothing here should send a reader shopping.
                reason = unsourceable.get(name)
                if reason:
                    entry["authored_because"] = reason
                    entry["searched"] = "Modern Interiors, Modern Office and Modern "
                    entry["searched"] += "User Interface, every 32px cell of all three "
                    entry["searched"] += "UI sheets rendered and inspected at M5b; "
                    entry["searched"] += "filename sweep of all 52726 PNGs in the three "
                    entry["searched"] += "packs. The search is closed, not paused."
                    entry["drawn_by"] = "scripts/generate-art.py — authored on the "
                    entry["drawn_by"] += "pack's own 2x design grid and in the pack's "
                    entry["drawn_by"] += "own four-colour icon palette, composited "
                    entry["drawn_by"] += "into the pack's own empty speech bubble"
                else:
                    entry["provenance"] = "placeholder"
                    entry["fallback_for"] = "pack art in assets/processed/; this file "
                    entry["fallback_for"] += "is only reached on a checkout without it"
        if entry is None:
            continue
        if name in BADGE_LABELS:
            entry["label"] = BADGE_LABELS[name]
        out[name] = entry
    if not out:
        return None
    extra = os.path.join(real, "attention.png")
    result = {
        "canvas": {"w": 24, "h": 34},
        "anchor": {"px": [12, 34], "normalized": [0.5, 0.0],
                   "note": "bottom-centre; the bubble tail points down at the head"},
        "note": "Badge colour is intentionally left unprocessed. A badge floats above "
                "the room rather than being part of it, so the I7 room saturation "
                "ceiling does not apply to it. Re-derived at M5c over every badge "
                "including the four authored ones, not just the two checked at "
                "M5b: no badge owns the darkest pixel on screen (every badge bottoms "
                "out at value 0.337 against the characters' 0.314), and the six that "
                "are drawn or composited here top out at saturation 0.384, which is "
                "the bubble's own border. The two emotes cut whole from the pack, "
                "question_mark (0.710) and attention (0.770), are the loud ones and "
                "always were — they are pack art, high-value rather than heavy, and "
                "they sit under the most saturated character pixel (1.000). Every "
                "badge is over the 0.25 room ceiling, which is why the exemption "
                "exists rather than being decorative.",
        "frame": {
            "source": "Modern Interiors / 4_User_Interface_Elements/UI_%s.png" % SIZE,
            "rect": [164, 16, 24, 34],
            "note": "Every badge shares this bubble, the four authored ones "
                    "included as of M5c — before that they drew a hand-made "
                    "lookalike with a heavier border and read louder in the room "
                    "than the pack art beside them. It is the same "
                    "692-pixel component the question_mark badge is cut from with "
                    "no glyph in it, so a swap cannot change the badge silhouette.",
        },
        "map": out,
    }
    states = {}
    if os.path.exists(extra):
        states["attention"] = {
            "file": rel(extra), "provenance": "pack",
            "note": "for Notification. Badge only — docs/04-ART-DIRECTION.md "
                    "rules out a body animation here [I1]."}
    dormant = os.path.join(real, "sleep.png")
    if os.path.exists(dormant):
        states["sleep"] = {
            "file": rel(dormant), "provenance": "pack",
            "note": "for a dormant subagent — one that stopped a turn, kept its "
                    "seat, and may be revived by a later event. Badge only, and "
                    "that is a finding rather than a shortcut: the pack's own "
                    "`sleep` body row is a head on a pillow drawn from above, to "
                    "be composited onto a top-down bed, so it cannot be worn by a "
                    "character sitting side-on in an office chair. Measured at "
                    "M6b — see docs/04-ART-DIRECTION.md. This says exactly what "
                    "the model knows and nothing more. [I1]"}
    if states:
        result["states"] = states
    return result


# Sections whose disappearance is data loss rather than a smaller manifest.
# Checked against the file about to be overwritten, because every one of them is
# populated from a table plus art on disk and either half going missing produces
# a manifest that is *internally* consistent, exits 0, and quietly costs the
# room a feature.
#
# This is not hypothetical. A rerun replaced a 1344-path manifest with a 148-path
# one in this project's history and it took a `git checkout` to get back; a rerun
# without the old `--costumes` flag deleted the wardrobe on exactly the same
# terms. `assets/` is gitignored apart from this file, so the manifest is the one
# art artefact a bad rerun can destroy for good.
# Each entry points at the leaf that actually carries the art, never at a
# wrapper around it. `costumes` and `stations` are both
# `{note, sets, roles, assignable}`, so guarding the wrapper guards nothing that
# can realistically be lost: a run that emitted the wrapper with `sets` empty --
# the shape you get when one processed directory is missing and the tables are
# still compiled in -- left a truthy dict behind and sailed past the check. The
# section names below are what the error message prints, so they are also what a
# reader is sent to look at.
GUARDED_SECTIONS = (
    ("characters", "variants"),
    ("characters", "costumes", "sets"),
    ("room", "props", "roles"),
    ("room", "props", "scenery"),
    ("room", "props", "stations", "sets"),
    ("badges", "map"),
    ("themes", "sets"),
)


def _dig(node, path):
    for key in path:
        if not isinstance(node, dict):
            return None
        node = node.get(key)
    return node


def sections_lost_against(path, manifest):
    """Names of GUARDED_SECTIONS present in the file at `path` and absent here.

    A malformed or missing file guards nothing — there is nothing to lose — and
    an empty section counts as absent, since an empty wardrobe dresses no one.
    """
    if not os.path.exists(path):
        return []
    try:
        with open(path) as f:
            prior = json.load(f)
    except (ValueError, OSError):
        return []
    return [".".join(sec) for sec in GUARDED_SECTIONS
            if _dig(prior, sec) and not _dig(manifest, sec)]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=MANIFEST,
                    help="where to write (default: assets/manifest.json)")
    args = ap.parse_args(argv)
    manifest = {
        "schema": 1,
        "generated_by": "scripts/build-manifest.py",
        "note": "Generated from files on disk. Do not hand-edit; rerun the "
                "generator. It stays generated: four badges are permanently "
                "provenance 'authored' because no owned pack draws them, so "
                "not every entry will ever read 'pack'.",
        "size_set": SIZE,
        "render": {
            "filtering": "nearest",
            "mipmaps": False,
            "integer_scales": [3, 2, 1],
            "note": "Integer scales only [I6]. 1x is the floor.",
        },
        "credit": {
            "required": True,
            "text": "Pixel art by LimeZu — limezu.itch.io",
            "url": "https://limezu.itch.io",
            "note": "Three packs, one author, so one credit line still covers all of "
                    "them: Modern Interiors and Modern User Interface both state "
                    "credits required; Modern Office says credits are appreciated. "
                    "The strictest term governs. Ships in the About panel.",
            "packs": ["Modern Interiors", "Modern Office (Revamped)",
                      "Modern User Interface"],
            "restrictions": "All three forbid resale and redistribution and permit "
                            "editing. Modern User Interface additionally forbids NFT "
                            "minting — a clause neither other pack carries, and the "
                            "only licence term in this project that restricts a use "
                            "rather than a distribution. Nothing here mints anything, "
                            "but the clause travels with the art, so any future use of "
                            "these badges inherits it.",
        },
    }
    for key, fn in (("characters", build_characters), ("room", build_room),
                    ("badges", build_badges), ("themes", build_themes)):
        section = fn()
        if section is not None:
            manifest[key] = section
    wardrobe = build_costumes()
    if wardrobe is not None:
        manifest.setdefault("characters", {})["costumes"] = wardrobe

    # Last gate: re-stat every path the manifest mentions. An entry that has
    # gone stale between the walk and the write is a bug scheduled for M2, and
    # this is the cheapest place to catch it.
    missing = []
    seen = [0]

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in ("file", "tiles", "files") or k == "frames":
                    pass
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
        elif isinstance(node, str) and node.endswith(".png") and node.startswith("assets/"):
            seen[0] += 1
            if not os.path.exists(os.path.join(REPO, node)):
                missing.append(node)

    walk(manifest)
    if missing:
        print("error: %d manifest paths do not exist on disk:" % len(missing), file=sys.stderr)
        for m in missing[:20]:
            print("   " + m, file=sys.stderr)
        return 1

    # The check above only catches paths we *declared* and could not find. With
    # no art at all nothing gets declared, so `missing` is empty and the run
    # looks like a success — and then overwrites the one art artefact that is
    # tracked in git with an empty shell, exit 0, no complaint.
    #
    # That is exactly what a fresh clone is: `assets/` is gitignored, so a
    # newcomer running the scripts in order before unpacking the packs destroys
    # the manifest and gets a green exit for it. Refuse instead.
    variants = manifest.get("characters", {}).get("variants", {})
    badge_map = manifest.get("badges", {}).get("map", {})
    empty = []
    if not variants:
        empty.append("no character variants")
    if not badge_map:
        empty.append("no badges")
    if seen[0] == 0:
        empty.append("no asset paths at all")
    if empty:
        print("error: refusing to write an empty manifest (%s)." % ", ".join(empty),
              file=sys.stderr)
        print("       The packs are not unpacked under assets/ — see README.md.",
              file=sys.stderr)
        print("       %s is left untouched." % rel(args.out), file=sys.stderr)
        return 2

    lost = sections_lost_against(args.out, manifest)
    if lost:
        print("error: refusing to write a manifest that drops a section the one "
              "on disk already has:", file=sys.stderr)
        for name in lost:
            print("   %s" % name, file=sys.stderr)
        print("       Whatever produced those entries is not running now — an "
              "unpacked pack, a table, a flag. Fix that, not this file.",
              file=sys.stderr)
        print("       %s is left untouched." % rel(args.out), file=sys.stderr)
        return 2

    with open(args.out, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")

    chars = manifest.get("characters", {}).get("variants", {})
    badges = manifest.get("badges", {}).get("map", {})
    ph = sum(1 for b in badges.values() if b["provenance"] == "placeholder")
    au = sum(1 for b in badges.values() if b["provenance"] == "authored")
    print("wrote %s" % rel(args.out))
    print("  %d character variants, %d states each" %
          (len(chars), len(next(iter(chars.values()))["states"]) if chars else 0))
    print("  %d badges (%d from pack, %d authored, %d placeholder)"
          % (len(badges), len(badges) - ph - au, au, ph))
    print("  %d asset paths, all verified present" % seen[0])
    wardrobe = manifest.get("characters", {}).get("costumes")
    if wardrobe:
        print("  %d costumes (%d recognised over %d agent types, %d assignable)"
              % (len(wardrobe["sets"]), len(set(wardrobe["roles"].values())),
                 len(wardrobe["roles"]), len(wardrobe["assignable"])))
    stations = _dig(manifest, ("room", "props", "stations"))
    if stations:
        print("  %d stations (%d recognised over %d agent types, %d assignable)"
              % (len(stations["sets"]), len(set(stations["roles"].values())),
                 len(stations["roles"]), len(stations["assignable"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
