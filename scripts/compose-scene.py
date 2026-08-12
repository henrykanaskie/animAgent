#!/usr/bin/env python3
"""Composes static multi-room floor plans from named catalogue props, as PNGs.

# Why this is a script and not a feature

The maintainer's question was "how can I trust the scenes will be any good",
and the honest answer is that a catalogue proves *availability*, not taste.
Nothing about naming 12,279 props demonstrates that a room built from them is
worth looking at. So this renders candidate rooms **before** any of it reaches
the app: no Swift, no layout refactor, no risk. If they look flat, an hour is
lost instead of a week, and the judgement is made from a picture rather than
from my description of one.

It deliberately does not import from the app or write anything the app reads.
Its only inputs are `assets/catalogue.json` and the processed art; its only
output is PNGs in a scratch directory.

# The bar, and what it taught

`assets/Modern_Office_Revamped_v1.2/6_Office_Designs/Office_Design_2.gif` and
`assets/moderninteriors-win/6_Home_Designs/Museum_Designs/32x32/` are rooms
composed by the packs' own artists from these same props. Measuring them, not
guessing, is what this file is built on:

  * A room is not "a wall band across the top". It is a **rect with four
    edges**, and the artist draws all four. Interior partitions are what make
    a picture read as a building rather than a stage set.

  * The north wall is exactly **two tiles tall** and is a single self-contained
    pair of Room Builder tiles: the *cap* tile carries a 12 px white floor-plan
    line in its top 12 rows and 20 px of wall face below it; the *body* tile
    carries 30 px more face and a 2 px dark baseboard in its bottom 2 rows.
    Measured in Office_Design_2 at x=200: line y=320..331, face y=332..381,
    baseboard y=380..383, floor from y=384. That is 12 + 52 = 64 px, on the
    tile grid, every time.

  * The other three edges are **line only** — 12 px for horizontal, 14 px for
    vertical, always 2 px dark / white / 2 px dark. You only see the *face* of
    a wall you are looking at head-on, so only the north wall gets one.

  * Doorways are not doors. They are **gaps cut clean through** the line and
    the face, with the neighbouring floor showing through.

  * Density is the whole game. Office_Design_2 packs eight desks, eight
    chairs, a monitor and scattered paper on every desk, a printer, plants in
    three corners and a wall unit into 16x17 tiles. Nothing is centred and
    nothing is alone: props come in rows, pairs and clusters, and the gaps
    between clusters are filled with small litter.

# Findings the app should take

**A catalogue name is a family, not an object.** `desk_corner_l` has 49
entries and they are five finishes of the same ten pieces, only two of which
are furniture; the other eight are modular segments. Asking for variant 0
draws a fragment. The first render of this file put six bare 6x86 partition
posts where six desks were meant to be, and it took a labelled contact sheet
to see why. `prop`'s `ink` argument selects the piece; see its docstring.

**All four seated directions are already available.** The character pack ships
`sit` in left and right only, and that has been treated as a hard limit on how
the room can be arranged. It is not. A seat is a pose *plus an occlusion*: a
standing `idle_down` planted inside the desk's footprint and depth-sorted
above it comes out as a head and shoulders behind a desk, which is what
sitting looks like from the front, and `idle_up` below the desk is a back view
that needs no trick at all. See `seat`. Nothing new has to be drawn or
imported for the room to face the camera.

**Position and depth are different numbers.** Every prop resting on another —
a monitor on a desk, a patient in a bed, a cup on a table — is drawn above the
surface's floor point, so sorting it on its own floor point puts it *behind*
the thing it stands on. The surface then paints over it. The symptom is
specific and survived two renders unread: monitors that look like screens
hovering with no base, because only the part clearing the desk's back edge
came through. See `place` and `on_desk`. A `SCENE_DEBUG=1` render draws every
ink box and floor point, which is the fastest way to see it.

The other half of the same class of bug is coordinates chosen against a room's
*rect* rather than its *floor* — the north wall eats the top two tiles, so a
5-tile room has 3 tiles of floor. `floor_of` reports anything standing outside
one, which is how the figures on walls were found rather than guessed at.

**Props have a facing, and a prop turned the wrong way is the one mistake a
viewer spots instantly.** Two of them here, and they are not the same shape.

*Monitors have exactly one view.* Every screen in 12,279 props is drawn face-on
with its keyboard below — `monitor_lit`, `monitor_dark`, `monitor_off_white`,
`laptop_open_lit`, all six 32x42 `workstation_composite` rigs. There is no rear
view anywhere. A screen is therefore being *looked at* from below, by someone
sitting between it and the viewer, so **a screen belongs only to a seat facing
away from the camera.** Give one to a camera-facing occupant and you have drawn
somebody staring at the back of their own monitor.

*Chairs have six.* `chair_office_swivel` is a full rotation — measured on the
Hospital singles, five colours of {profile facing left, three-quarter left,
front, profile facing right, three-quarter right, back}, and `chair_office_back`
and `chair_office_front` are two *models* of the same back view. Which way a
chair faces is a **choice the composer has to make and record**, not a property
of the pack. See `chair`.

I had this backwards for four renders and told the maintainer so: I read the
low-detail profiles, concluded the pack drew chairs only one way, and wrote
"there is no near-side chair" into this file as a fact about the art. It was a
fact about how far I had looked. The correction came from the packs' own rooms
(`Office_Design_2.gif`, the ice-cream shop preview), which is where it should
have come from first — see `chair` for what they show. **R9 now measures the
sprite rather than trusting either of us.**

# Why there is a linter in here

Everything above was found by looking at pictures one prop at a time, which is
slow, misses whatever is only wrong at 1x, and had me fixing symptoms in the
order I happened to notice them. `check_continuity` replaces that with five
rules, checked exhaustively on every run:

  R1  wall decor hangs on an actual wall, and not in a doorway
  R2  furniture stands on a floor — the walkable part, not the room's rect
  R3  and on one floor: no footprint straddling a wall or the plan's edge
  R4  no two pieces of furniture in the same floor space
  R5  anything resting on a surface is fully on some particular surface
  R6  nothing stands in a doorway
  R7  nothing is drawn and then buried by what is painted over it
  R8  a row of one name is not a row of one sprite
  R9  a chair declares which way it faces, and the sprite agrees

`library()` is the check on all of that. The first three scenes were fixed one
prop at a time until they passed, which proves the rules hold *there* and not
that they generalise. So the fourth was written straight through against the
rules, from a different pack's vocabulary, with no render looked at until the
linter was silent. It came out with **5 violations against the first three
scenes' 43**, and all five were coordinates rather than anything structural:
three plants over a wall line and two figures standing inside furniture. The
budget in `table_with_seats` also decided its floor plan before a single prop
was named, which is the point.

Its first run reported **43 violations across three scenes that had already
been eyeballed and called finished**, including two figures standing on walls,
a sign hanging in a doorway, six appliances inside a 416x72 prop that turned
out to be an entire wall of fridges rather than one, and cups floating beside
a table. R5 alone found nine. None of these were visible at 1x.

R6 and R7 came later, from an outside read of the finished renders, and they
matter more than the first five because they catch what *looks* right. R6
found a ticket office parked across the full width of a doorway and a plant in
another; R7 found a 140x86 dinosaur entirely inside that ticket office, a
visitor reduced to a floating clump of hair, an exit sign under a painting and
four mugs at 100% buried. Every one of those was correctly placed by R1-R5 —
they are not misplaced, they are underneath something — and every one of them
rendered, cost draw time, and could not be seen.

R8 is the subtlest and catches the most embarrassing class. `ink` narrows a
name to one piece of its family, which also shrinks the pool it indexes into —
often to two. A stride chosen against the full family then aliases: `3 + i * 4`
over a pool of two is odd every time. The ward drew all six of its nightstands
from one file, three identical patients per row, and three identical benches in
an unbroken run that reads as a fence. Each placement was individually correct.
It is judged against what is *reachable*, so a name with one catalogue entry is
not a complaint.

The same read found three structural bugs, all invisible from inside:
`_open_at`, step 2 of `draw_plan`, and the cap tiles — a boundary drawn
correctly by each of the two rooms that share it and walled over between them;
a doorway patched with two different floors stacked; and four of eight surfaces
built on a mid-run cap tile that omits the wall's outer edge.

Uses Pillow, which the app's own pipeline avoids — fine here, because nothing
in this file is part of the build. `scripts/process-assets.py` stays stdlib.
"""

import importlib.util
import json
import os
import sys

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "assets")
CATALOGUE = os.path.join(ASSETS, "catalogue.json")
BUILDER = os.path.join(ASSETS, "processed", "room", "32x32", "builder-full")
CHARS = os.path.join(ASSETS, "processed", "characters", "32x32")
SHEET = os.path.join(ASSETS, "Modern_Office_Revamped_v1.2",
                     "1_Room_Builder_Office", "Room_Builder_Office_32x32.png")

PANEL = (720, 400)
TILE = 32
# 22x12 tiles is 704x384 — the largest whole-tile plan that fits, leaving an
# 8 px surround so the plan reads as a drawing rather than a bleeding edge.
PLAN = (22, 12)
ORIGIN = (8, 8)
OUTSIDE = (34, 34, 44)

# ---------------------------------------------------------------------------
# Tile roles
#
# Established by rendering all 161 non-empty tiles to a labelled 3x grid and
# looking, then confirming each candidate's pixel cross-section.
#
# **We cut our own tiles rather than reading `processed/room/32x32/builder/`.**
# That directory is the app's, and `process-assets.py` drops every tile under
# 60% opaque on the grounds that a mostly-transparent tile is edge trim and
# laying it as floor would show the void behind the room. That rule is right
# for the app and wrong here: the entire thin-wall vocabulary — every plain
# horizontal and vertical run, every T-junction, every doorway jamb — is a
# 12 or 14 px line on an otherwise empty tile, so all of it falls under the
# cut. 141 tiles survive there; 161 exist. The missing 20 are exactly the
# pieces a floor plan is drawn with.
#
# So `_cut_tiles` slices the raw sheet and applies `process-assets.room_colour`
# at the same VALUE_FLOOR, which reproduces the app's own output byte for byte
# on the 141 tiles they share (verified) while keeping the other 20. Importing
# the transform rather than copying it means the two cannot drift.
#
#   rows 0-3, cols 0-9   structural thin walls. Wall = white 232 body with
#                        2 px 154,154,170 edges. Horizontal runs occupy the
#                        top 12 rows of a tile, vertical runs the left or
#                        right 14 columns. Survivors, all corners:
#                          r01_c05 r02_c01 r03_c01 r03_c04  north + east
#                          r01_c06 r02_c02 r03_c02 r03_c03  north + west
#                        WALL_CORNER below is the master they are cut from.
#   rows 0-3, cols 10-12 solid white wall mass (thick-wall interiors), plus
#                        r02_c14 which is fully transparent trim.
#   r00_c08              flat dark slab, the pack's shadow/void swatch.
#   rows 5,7,9,11 c0-c9  WALL CAP tiles: 12 px floor-plan line + 20 px face.
#                        c3/c7/c8/c9 carry the brightest cap highlight.
#   rows 6,8,10,12 c0-c9 WALL BODY tiles: 30 px face + 2 px baseboard.
#                        (c4-c6 are missing from every body row.)
#   rows 5..12, c10-c15  FLOORS, six per row-pair:
#                        r05/r06 c10-12 pale slab   c13-15 pale plank
#                        r07/r08 c10-12 grey micro  c13-15 tan carpet
#                        r09/r10 c10-12 grey lino   c13-15 tan lino
#                        r11/r12 c10-15 mauve lino
#
# Doorways are gaps rather than tiles, which is what Office_Design_2 draws
# anyway: the line and the face stop, and the floor beyond shows through.

# **Only columns 0-2 of a cap row carry the wall's top edge.** Every cap tile
# is 12 px of floor-plan line over 20 px of face, but the line is only drawn
# complete — 2 px dark, 8 px white, 2 px dark — in the first three columns.
# Columns 3-9 omit the top 2 px because they are mid-run pieces meant to butt
# against something above them. Four of these eight surfaces were built on c07
# and drew every room's north wall with its outer edge missing, which reads at
# 1x as a wall that fades into the background instead of ending.
SURFACES = {
    # name:      (floor,          cap,             body)
    "concrete":  ("tile_r07_c11.png", "tile_r07_c00.png", "tile_r08_c00.png"),
    "slab":      ("tile_r05_c11.png", "tile_r05_c00.png", "tile_r06_c00.png"),
    "plank":     ("tile_r05_c14.png", "tile_r05_c01.png", "tile_r06_c01.png"),
    "carpet":    ("tile_r07_c14.png", "tile_r09_c00.png", "tile_r10_c00.png"),
    "lino":      ("tile_r09_c11.png", "tile_r11_c00.png", "tile_r12_c00.png"),
    "lino_tan":  ("tile_r09_c14.png", "tile_r09_c02.png", "tile_r10_c02.png"),
    "mauve":     ("tile_r11_c12.png", "tile_r11_c01.png", "tile_r12_c01.png"),
    "white":     ("tile_r05_c10.png", "tile_r07_c02.png", "tile_r08_c02.png"),
}

WALL_H = 2 * TILE           # cap tile + body tile
LINE_H = 12                 # horizontal floor-plan line, measured
LINE_V = 14                 # vertical floor-plan line, measured
# Measured down x=16 of tile_r01_c01: 2 px edge, 8 px fill, 2 px edge. The
# vertical run is the same section rotated, 2/10/2 across 14 px. Knowing the
# exact section is what lets `Wall` draw runs and junctions procedurally in
# the artist's own ink instead of trying to tile pre-drawn corner pieces.
EDGE = (154, 154, 170, 255)
FILL = (232, 232, 232, 255)


# ---------------------------------------------------------------------------
# Art loading

def _cut_tiles():
    """Slice every non-empty tile out of the Room Builder sheet, once."""
    if os.path.isdir(BUILDER) and len(os.listdir(BUILDER)) >= 161:
        return
    spec = importlib.util.spec_from_file_location(
        "process_assets", os.path.join(REPO, "scripts", "process-assets.py"))
    pa = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pa)
    os.makedirs(BUILDER, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGBA")
    cache = {}
    for r in range(sheet.height // TILE):
        for c in range(sheet.width // TILE):
            src = sheet.crop((c * TILE, r * TILE, (c + 1) * TILE, (r + 1) * TILE))
            px = list(src.getdata())
            if not any(p[3] for p in px):
                continue
            out = []
            for red, green, blue, alpha in px:
                if alpha == 0:
                    out.append((0, 0, 0, 0))
                    continue
                key = (red, green, blue)
                hit = cache.get(key)
                if hit is None:
                    hit = cache[key] = pa.room_colour(red, green, blue, pa.VALUE_FLOOR)
                out.append((hit[0], hit[1], hit[2], alpha))
            im = Image.new("RGBA", (TILE, TILE))
            im.putdata(out)
            im.save(os.path.join(BUILDER, "tile_r%02d_c%02d.png" % (r, c)))


_tiles = {}


def tile(name):
    if name not in _tiles:
        _tiles[name] = Image.open(os.path.join(BUILDER, name)).convert("RGBA")
    return _tiles[name]


def fill_tiled(canvas, name, box):
    """Tile `name` over `box`, phase-locked to the plan origin so the pattern
    runs continuously from room to room the way a real floor does."""
    im = tile(name)
    x0, y0, x1, y1 = box
    # Snap back to the nearest tile boundary, fill whole tiles, then crop to
    # the box — `alpha_composite` cannot take a negative offset, so the phase
    # has to come from the crop rather than from the paste.
    sx = (x0 // im.width) * im.width
    sy = (y0 // im.height) * im.height
    scratch = Image.new("RGBA", (x1 - sx, y1 - sy))
    for y in range(0, scratch.height, im.height):
        for x in range(0, scratch.width, im.width):
            scratch.alpha_composite(im, (x, y))
    canvas.alpha_composite(scratch.crop((x0 - sx, y0 - sy, x1 - sx, y1 - sy)),
                           (x0, y0))


def load_index():
    with open(CATALOGUE) as fh:
        data = json.load(fh)
    by_name = {}
    for e in data["entries"]:
        if e["size_set"] != "32x32" or "name" not in e:
            continue
        by_name.setdefault(e["name"], []).append(e)
    for v in by_name.values():
        v.sort(key=lambda e: e["file"])
    return by_name


_props = {}
_index = None


def index():
    """The catalogue, loaded once.

    A scene is a list of tuples built before `compose` ever runs, so the
    helpers that build those tuples have no `by_name` handed to them. `chair`
    needs one anyway: which variants of a shared ink pool face left is a
    question about the *art*, and the honest answer is measured from it rather
    than hardcoded. Hence a module-level cache instead of threading the index
    through six call sites.
    """
    global _index
    if _index is None:
        _index = load_index()
    return _index


def prop(by_name, name, variant=0, ink=None):
    """One named prop's image and its content box, or None if absent.

    # Why `ink` exists, and why leaving it off is usually the bug

    A catalogue name is a *family*, not an object. `desk_corner_l` has 49
    entries and they are five finishes of the same ten pieces: a 32x16 back
    strip, a 32x32 surface with no legs, a 32x32 front with legs, a 64x38
    desk and a 64x64 L-desk. Only the last two are furniture; the rest are
    **modular segments** meant to be laid in runs. `partition` is worse — its
    six entries are a 6x86 post, a 64x42 panel and a 32x86 corner, so five in
    six draws a bare pole.

    Asking for variant 0 and hoping therefore produces a floor strewn with
    fragments, which is exactly what the first pass of this file rendered:
    poles standing where desks were meant to be. Selecting on ink dimensions
    picks the *piece*, and the variant index then walks the finishes of that
    piece rather than the pieces of that finish.
    """
    entries = by_name.get(name)
    if not entries:
        return None
    if ink is not None:
        sized = [e for e in entries
                 if (e["content_box"]["w"], e["content_box"]["h"]) == ink]
        if not sized:
            return None
        entries = sized
    pool = len({e["file"] for e in entries})
    e = entries[variant % len(entries)]
    key = e["file"]
    if key not in _props:
        path = os.path.join(ASSETS, e["file"])
        if not os.path.exists(path):
            path = os.path.join(REPO, e["file"])
        if not os.path.exists(path):
            return None
        _props[key] = Image.open(path).convert("RGBA")
    return _props[key], e["content_box"], key, pool


def character(variant, pose, facing, frame=0):
    p = os.path.join(CHARS, variant, "%s_%s_%02d.png" % (pose, facing, frame))
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


# ---------------------------------------------------------------------------
# Wall runs

class Wall:
    """Accumulates wall geometry, then rasterises it in two passes so that
    every junction — corner, T, cross — closes without special-casing."""

    def __init__(self):
        self.rects = []   # (x0, y0, x1, y1) of the *white* core

    def horizontal(self, x0, x1, y):
        """Line whose 12 px section sits above the boundary at `y`."""
        self.rects.append((x0, y - LINE_H + 2, x1, y - 2))

    def vertical(self, y0, y1, x):
        """Line whose 14 px section straddles the boundary at `x`."""
        self.rects.append((x - LINE_V // 2 + 2, y0, x + LINE_V // 2 - 2, y1))

    def draw(self, canvas):
        d = ImageDraw.Draw(canvas)
        for x0, y0, x1, y1 in self.rects:
            d.rectangle([x0 - 2, y0 - 2, x1 + 1, y1 + 1], fill=EDGE)
        for x0, y0, x1, y1 in self.rects:
            d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=FILL)


# ---------------------------------------------------------------------------
# The plan

class Room(dict):
    """A rect in TILE units plus its finishes. `doors` cut the walls."""

    def __init__(self, name, x, y, w, h, surface, doors=(), band=True):
        dict.__init__(self, name=name, x=x, y=y, w=w, h=h,
                      surface=surface, doors=list(doors), band=band)

    def __getattr__(self, k):
        return self[k]


def _door_spans(room, side):
    """Doorway spans on `side`, in tile units along that side."""
    out = []
    for d in room["doors"]:
        if d[0] != side:
            continue
        out.append((d[1], d[1] + d[2]))
    return out


def _cut(spans, a, b):
    """True if tile [a, b) falls inside any doorway span."""
    return any(s <= a and b <= e for s, e in spans)


OPPOSITE = {"north": "south", "south": "north",
            "west": "east", "east": "west"}


def _open_at(rooms, room, side, t):
    """Is `room`'s `side` open at tile `t` (absolute, along that side)?

    **A boundary between two rooms belongs to both of them, and each draws its
    own half.** So a door declared by one room is walled over by its neighbour
    unless the neighbour is asked too. That is not a hypothetical: the meeting
    room declared a west door onto the open plan, the open plan drew its east
    wall across the whole shared edge, and the result was a meeting room with
    no way in — reachable only by going through the break room. It rendered as
    an unbroken wall and nothing complained, because from each room's own point
    of view the drawing was correct.

    Rather than make callers remember, every wall query comes through here and
    asks both sides.
    """
    if side in ("north", "south"):
        local = t - room.x
        edge = room.y if side == "north" else room.y + room.h
        probe = (t, edge - 1 if side == "north" else edge)
    else:
        local = t - room.y
        edge = room.x if side == "west" else room.x + room.w
        probe = (edge - 1 if side == "west" else edge, t)
    if _cut(_door_spans(room, side), local, local + 1):
        return True
    other = room_at(rooms, probe[0], probe[1])
    if other is None or other is room:
        return False
    far = OPPOSITE[side]
    base = other.x if side in ("north", "south") else other.y
    return _cut(_door_spans(other, far), t - base, t - base + 1)


def room_at(rooms, tx, ty):
    for r in rooms:
        if r.x <= tx < r.x + r.w and r.y <= ty < r.y + r.h:
            return r
    return None


def draw_plan(rooms):
    W, H = PLAN[0] * TILE, PLAN[1] * TILE
    canvas = Image.new("RGBA", (W, H), OUTSIDE + (255,))

    # 1. Floors first, over the whole rect. Anything a doorway later cuts
    #    through therefore lands on real floor, not on the void.
    for r in rooms:
        floor = SURFACES[r.surface][0]
        fill_tiled(canvas, floor,
                   (r.x * TILE, r.y * TILE, (r.x + r.w) * TILE, (r.y + r.h) * TILE))

    # 2. North wall band: cap tile row then body tile row, per column,
    #    skipping doorway columns.
    #
    #    Nothing is drawn in the gap. Step 1 already laid this room's floor
    #    across the whole rect, so leaving the band off shows a clean 64 px of
    #    it — a threshold. An earlier version patched the gap's top tile with
    #    the floor of the room *beyond*, which put two different floor
    #    materials one above the other and left a hard seam across the middle
    #    of every doorway that read as a step.
    for r in rooms:
        if not r.band:
            continue
        _, cap, body = SURFACES[r.surface]
        for tx in range(r.x, r.x + r.w):
            if _open_at(rooms, r, "north", tx):
                continue
            canvas.alpha_composite(tile(cap), (tx * TILE, r.y * TILE))
            canvas.alpha_composite(tile(body), (tx * TILE, (r.y + 1) * TILE))

    # 3. Contact shadow the wall casts onto its own floor. The artists paint
    #    this in; without it the band floats.
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ds = ImageDraw.Draw(shade)
    for r in rooms:
        if not r.band:
            continue
        for tx in range(r.x, r.x + r.w):
            if _open_at(rooms, r, "north", tx):
                continue
            y = (r.y + 2) * TILE
            for i, a in enumerate((70, 46, 26, 12)):
                ds.rectangle([tx * TILE, y + i, tx * TILE + 31, y + i],
                             fill=(24, 24, 34, a))
    canvas.alpha_composite(shade)

    # 4. The other three edges, as lines. A room's bottom edge is only drawn
    #    where no room below is about to draw its own cap line there.
    wall = Wall()
    for r in rooms:
        for tx in range(r.x, r.x + r.w):
            if _open_at(rooms, r, "south", tx):
                continue
            below = room_at(rooms, tx, r.y + r.h)
            if below is not None and below.y == r.y + r.h and below["band"]:
                continue
            wall.horizontal(tx * TILE, (tx + 1) * TILE, (r.y + r.h) * TILE)
        for side, bx in (("west", r.x), ("east", r.x + r.w)):
            for ty in range(r.y, r.y + r.h):
                if _open_at(rooms, r, side, ty):
                    continue
                wall.vertical(ty * TILE, (ty + 1) * TILE, bx * TILE)
    wall.draw(canvas)

    # 5. Jambs: a doorway cut through the 64 px band leaves two raw edges.
    d = ImageDraw.Draw(canvas)
    for r in rooms:
        if not r.band:
            continue
        for s, e in _door_spans(r, "north"):
            for tx in (r.x + s, r.x + e):
                d.rectangle([tx * TILE - 1, r.y * TILE,
                             tx * TILE, (r.y + 2) * TILE - 1], fill=EDGE)
    return canvas


# ---------------------------------------------------------------------------
# Dressing

def place(canvas, items):
    """Bottom-centre every item's *ink* on its floor point and depth-sort by
    that point's y — the same convention the app uses, so a scene that reads
    here is telling the truth about what the app could draw.

    # Position and depth are not the same number

    The convention above works for things standing on the floor and breaks for
    everything standing on something else. A monitor on a desk has to be drawn
    *higher* than the desk's floor point, because it sits on a raised surface —
    but drawing it higher means sorting it behind, so the desk paints over it
    and the desk is bare. The first version of `desk_pod` hit this from both
    sides at once: monitors vanished under desks, and the seated figure meant
    to be *occluded* by a desk was the one thing drawn in front of it.

    So an item carries a sort key separate from its floor point. `z:` in the
    spec flags offsets it: `z:+2` puts a prop just in front of the surface it
    rests on while leaving it drawn where it looks right, and a negative one
    pushes a figure behind the desk it is sitting at. The two are independent
    because in a projection like this they were never the same thing.
    """
    shade = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(shade)
    for _, im, box, x, y, sh, *_r in sorted(items, key=lambda i: (i[0], i[3])):
        if sh:
            w = max(10, (box["w"] if box else im.width // 2))
            ds.ellipse([x - w // 2, y - 5, x + w // 2, y + 4],
                       fill=(20, 20, 30, 58))
    canvas.alpha_composite(shade)
    for _, im, box, x, y, _, *_r in sorted(items, key=lambda i: (i[0], i[3])):
        if box is None:
            canvas.alpha_composite(im, (x - im.width // 2, y - im.height))
        else:
            canvas.alpha_composite(
                im, (x - (box["x"] + box["w"] // 2), y - (box["y"] + box["h"])))


def _flags(entry):
    """`("wall", "ink:64x64", "z:+2")` -> (kind, (64, 64), 2).

    `kind` is what the prop is standing on, and every continuity rule keys off
    it: "floor" for furniture, "wall" for something hung on a wall face, "on"
    for anything resting on other furniture. It used to be a single `flat` flag
    meaning only "draw no shadow", which conflated a picture on a wall with a
    mug on a desk — and a checker cannot tell those apart, so neither could I.
    """
    kind, ink, z = "floor", None, 0
    for f in (entry[4] if len(entry) > 4 else ()):
        if f == "wall":
            kind = "wall"
        elif f == "flat":
            # `flat` alone is wall decor; `flat` with a `z` is something
            # resting on furniture. The two are distinguishable without a
            # third flag because a prop on a surface *must* carry a z — with
            # z 0 it sorts behind its own support and is painted over. So a
            # flat prop with no z has nothing under it but a wall.
            kind = "wall"
        elif f == "ground":
            # Lying on the floor rather than standing on it: a mat, a rug, a
            # dropped toy, a low platform. Casts no shadow and is not wall
            # decor, and nothing is wrong with something else standing on it.
            kind = "ground"
        elif f == "seat":
            # A chair with somebody in it. Exempt from the shared-floor rule
            # for the obvious reason.
            kind = "seat"
        elif f.startswith("ink:"):
            w, h = f[4:].split("x")
            ink = (int(w), int(h))
        elif f.startswith("z:"):
            z = int(f[2:])
    return ("on" if kind == "wall" and z else kind), ink, z


def floor_of(rooms, x, y):
    """The room whose *walkable* floor contains (x, y), or None.

    A room's rect is not its floor. The north wall eats the top two tiles of
    it, so a 9x5 room has 5 tiles of rect and 3 of floor, and coordinates
    chosen against the rect land a third of the way up a wall. This is how the
    meeting room ended up with a conference table and four chairs standing on
    the break room's wall band below it — every one of those y values was
    inside the room by the rect and outside it by the floor.
    """
    for r in rooms:
        top = (r.y + 2) * TILE if r["band"] else r.y * TILE
        if r.x * TILE <= x < (r.x + r.w) * TILE and \
                top <= y <= (r.y + r.h) * TILE:
            return r
    return None


# ---------------------------------------------------------------------------
# Continuity
#
# Everything below is here because eyeballing renders does not scale. Each of
# these rules was broken in a shipped scene and found by looking at a picture
# one prop at a time, which is the slowest possible way to find any of them and
# misses the ones that are only wrong at 1x. They are cheap to check and the
# check is exhaustive, so the composer checks them on every run.

# A prop whose first token is one of these is something a person sits on, and
# R9 makes it declare which way it faces. First token rather than substring on
# purpose: `bench_canteen` is seating and `lab_bench` is a worktop, and only
# the leading word tells them apart.
SEATING = ("chair", "armchair", "stool", "sofa", "bench", "wheelchair",
           "recliner")

FACINGS = ("up", "down", "left", "right", "none")


def check_facing(name, x, y, entry, im, box):
    """R9 — a chair declares which way it faces, and the sprite agrees.

    # Why this rule exists

    Every other rule here catches a prop in the wrong *place*. This one
    catches a prop in the wrong *orientation*, which is the class of error the
    maintainer reported three times running and the only one none of R1-R8
    could see: a chair standing exactly where a chair belongs, facing the
    wrong way.

    It cost four renders because I answered it from memory instead of from
    the art, wrote the wrong answer into this file's header as a fact, and
    then built two helpers on top of it. The rule replaces my judgement with a
    measurement that runs on every prop of every scene, every time.

    # What it can and cannot prove

    `backrest_side` separates a profile from a face-on chair exactly — the
    measured gap is +-8.4 px or 0.0 with nothing between — so a left profile
    used as a right-hand seat is caught outright, in any scene, from any pack.

    Up and down it **cannot** separate: both are symmetric about the sprite's
    axis, and no pixel measurement distinguishes the front of a backrest from
    the back of one. Those two are pinned in `CHAIR_VIEWS` from the packs'
    own room designs, and the rule checks membership rather than pretending
    to derive it. Where a family is not pinned, an `up`/`down` claim is
    checked only as far as "the sprite is at least face-on" — and saying so is
    the point, because a rule that overstated its reach would be worse than
    none.
    """
    if not name.split("_")[0] in SEATING:
        return []
    want = None
    for f in (entry[4] if len(entry) > 4 else ()):
        if f.startswith("facing:"):
            want = f[7:]
    at = "%s@%d,%d" % (name, x, y)
    if want is None:
        return ["R9 %s does not say which way it faces" % at]
    if want not in FACINGS:
        return ["R9 %s facing %r is not one of %s"
                % (at, want, "/".join(FACINGS))]
    got = backrest_side(im, box)
    if want in ("left", "right"):
        # A chair facing left has its backrest on the right, and vice versa.
        if got != ("right" if want == "left" else "left"):
            return ["R9 %s claims to face %s but its backrest measures %s"
                    % (at, want, got)]
    elif got != "face-on":
        return ["R9 %s claims to face %s but the sprite is a %s profile"
                % (at, want, got)]
    elif want in ("up", "down"):
        # Front and back are both symmetric about the sprite's own axis, so no
        # measurement of one sprite says which it is. I tried to derive it from
        # the family instead, twice, and it does not hold.
        #
        # The observation behind the attempt is sound and worth keeping: seen
        # from behind, the backrest hides the seat, so the back view loses the
        # seat's depth and comes out bodily shorter. It is true of
        # `chair_school` (44 vs 30), `chair_ornate` (46 vs 32) and
        # `chair_office_swivel` (42 vs 24) — three unrelated sheets.
        #
        # It is still not a *rule*, because a catalogue name is a family of
        # pieces rather than a set of views, which is the same thing `prop`
        # warns about for modular segments. Ranking `chair_office_back` by
        # height picks its 30x32 entry, which is not a chair at all but a
        # mislabelled prop with a laptop on it. Ranking `chair_waiting` picks
        # its 62x36, which is the two-seat unit of the same chair at the same
        # height. Both scenes were correct and both would have been reported.
        #
        # So the heuristic lives in `CHAIR_SUITES` as the reason each suite is
        # pinned the way it is — use it to propose a new suite, then look at it
        # once — and the rule checks only what is certain: that nothing uses a
        # sprite some suite has already identified as the opposite face.
        for views in CHAIR_SUITES.values():
            for face in ("up", "down"):
                if views[face] == (name, (box["w"], box["h"])) and face != want:
                    return ["R9 %s claims to face %s but %s ink %dx%d is a "
                            "pinned %s view"
                            % (at, want, name, box["w"], box["h"], face)]
    return []


def _band_of(rooms, x, y):
    """The room whose north wall band covers (x, y), or None."""
    for r in rooms:
        if not r["band"]:
            continue
        if r.x * TILE <= x < (r.x + r.w) * TILE and \
                r.y * TILE <= y < (r.y + 2) * TILE:
            return r
    return None


def _door_gap(room, side, x, y):
    """True if (x, y) falls in a doorway cut through `room`'s `side`."""
    for s, e in _door_spans(room, side):
        if side in ("north", "south"):
            if (room.x + s) * TILE <= x < (room.x + e) * TILE:
                return True
        elif (room.y + s) * TILE <= y < (room.y + e) * TILE:
            return True
    return False


def _walls_between(rooms, x0, x1, y):
    """Vertical room boundaries strictly inside the span x0..x1 at height y.

    A boundary is a wall. Furniture whose footprint spans one is standing half
    in each of two rooms, with the wall line drawn through it.
    """
    edges = set()
    for r in rooms:
        if r.y * TILE <= y <= (r.y + r.h) * TILE:
            edges.add(r.x * TILE)
            edges.add((r.x + r.w) * TILE)
    return sorted(e for e in edges if x0 < e < x1)


def check_continuity(rooms, placed):
    """Every rule the scenes have broken, as a list of complaints.

    `placed` is (name, x, y, w, h, kind) where kind is "floor", "wall" or
    "on" — resting on other furniture, which is exempt from the floor rules
    because its support is what stands on the floor.
    """
    out = []

    # R8. A row of the same name must not be a row of the same sprite.
    #
    # `ink` narrows a name to one piece of its family, which also shrinks the
    # pool it indexes into — often to two or three. A stride chosen against the
    # full family then aliases: `3 + i * 4` over a pool of 2 is odd every time.
    # The ward drew all six of its nightstands from one file, three identical
    # patients per row, and three identical benches in an unbroken run that
    # reads as a fence. Nothing else notices, because each placement on its own
    # is correct.
    families = {}
    for name, x, y, w, h, kind, source, pool, matched in placed:
        if matched:
            continue
        families.setdefault(name, [set(), 0, 0])
        families[name][0].add(source)
        families[name][1] += 1
        families[name][2] = pool
    # Judged against what is *reachable* — a name with one catalogue entry can
    # only ever draw one sprite, and a deliberate subset (only the lit screens,
    # say) is a choice rather than a bug. The complaint is using less than half
    # of what could have been used.
    #
    # A `matched` prop is exempt, because some runs are *meant* to be one
    # sprite: a table assembled from three abutted slabs is one table, and
    # walking the variant along it produced a top that was tan at one end and
    # dark orange at the other. The exemption is declared at the placement
    # rather than inferred, so it can be read off the scene.
    for name, (sources, count, pool) in families.items():
        if count > 2 and len(sources) * 2 <= min(count, pool):
            out.append("R8 %d x %s draw from %d sprite(s), %d available"
                       % (count, name, len(sources), pool))

    for name, x, y, w, h, kind, _, _p, _m in placed:
        left, right = x - w // 2, x - w // 2 + w
        if kind == "wall":
            # R1. Wall decor hangs on a wall, and a doorway is a hole in one.
            band = _band_of(rooms, x, y)
            if band is None:
                out.append("R1 %s@%d,%d hangs on no wall" % (name, x, y))
            elif _door_gap(band, "north", x, y):
                out.append("R1 %s@%d,%d hangs in a doorway" % (name, x, y))
            elif not (_band_of(rooms, left, y) and _band_of(rooms, right - 1, y)):
                out.append("R1 %s@%d,%d overhangs the wall's end" % (name, x, y))
        elif kind in ("floor", "ground", "seat"):
            # R2. Furniture stands on a floor.
            room = floor_of(rooms, x, y)
            if room is None:
                out.append("R2 %s@%d,%d is not on any floor" % (name, x, y))
                continue
            # R3. And on ONE floor — a footprint spanning a room boundary is
            # a desk with a wall drawn through it.
            if kind != "ground":
                for edge in _walls_between(rooms, left, right, y):
                    if not _door_gap(room, "west" if edge <= x else "east", x, y):
                        out.append("R3 %s@%d,%d straddles the wall at x=%d"
                                   % (name, x, y, edge))
    # R5. Anything resting on furniture has to be resting on some *particular*
    # piece of furniture, with its whole footprint on the surface. Otherwise it
    # is a mug in mid-air beside a desk — which looks, at panel size, exactly
    # like a mug on a desk, so this is not findable by eye.
    supports = [p for p in placed if p[5] == "floor"]
    for name, x, y, w, h, kind, _, _p, _m in placed:
        if kind != "on":
            continue
        left, right = x - w // 2, x - w // 2 + w
        held = False
        for _, fx, fy, fw, fh, _, _s, _p, _m in supports:
            fl = fx - fw // 2
            if fl <= left and right <= fl + fw and fy - fh <= y <= fy:
                held = True
                break
        if not held:
            out.append("R5 %s@%d,%d rests on nothing" % (name, x, y))

    # R4. Two pieces of furniture cannot occupy the same floor.
    #
    # Compared as *footprint rectangles* — the ink's bottom band, which is what
    # touches the ground. An earlier version compared horizontal spans only and
    # skipped any pair whose floor points differed by more than 10 px, which is
    # a hole you can drive furniture through: it passed a bench parked across a
    # plinth (18 px apart), a shelving unit standing inside a dinosaur skeleton
    # (6 px) and a 140 px dinosaur inside a ticket booth (28 px).
    floors = [p for p in placed if p[5] == "floor"]
    for i, (n1, x1, y1, w1, h1, _, _s1, _p1, _m1) in enumerate(floors):
        for n2, x2, y2, w2, h2, _, _s2, _p2, _m2 in floors[i + 1:]:
            d1, d2 = min(h1, 18), min(h2, 18)
            if y1 - d1 >= y2 or y2 - d2 >= y1:
                continue
            a0, a1 = x1 - w1 // 2, x1 - w1 // 2 + w1
            b0, b1 = x2 - w2 // 2, x2 - w2 // 2 + w2
            share = min(a1, b1) - max(a0, b0)
            if share > max(10, min(w1, w2) // 2):
                out.append("R4 %s@%d,%d and %s@%d,%d share %d px of floor"
                           % (n1, x1, y1, n2, x2, y2, share))

    # R6. A doorway is for walking through. Anything standing in one blocks the
    # only route between two rooms — and both R2 and R3 wave it through,
    # because a door aperture is legitimately outside the floor and legitimately
    # on a wall line. The museum had a ticket office across the whole width of
    # its north door and a potted plant in the west one.
    for name, x, y, w, h, kind, _, _p, _m in placed:
        if kind != "floor":
            continue
        left, right = x - w // 2, x - w // 2 + w
        for r in rooms:
            for side in ("north", "south", "west", "east"):
                for s, e in _door_spans(r, side):
                    if side in ("north", "south"):
                        gy = (r.y if side == "north" else r.y + r.h) * TILE
                        g0, g1 = (r.x + s) * TILE, (r.x + e) * TILE
                        blocked = (min(right, g1) - max(left, g0) > 8
                                   and gy - TILE <= y <= gy + 2 * TILE)
                    else:
                        gx = (r.x if side == "west" else r.x + r.w) * TILE
                        g0, g1 = (r.y + s) * TILE, (r.y + e) * TILE
                        blocked = (left < gx + 10 and right > gx - 10
                                   and g0 <= y <= g1)
                    if blocked:
                        out.append("R6 %s@%d,%d blocks the %s doorway of %s"
                                   % (name, x, y, side, r["name"]))
    return out


def report_hidden(items, size, floor=0.55):
    """Items whose ink is mostly painted over by whatever is drawn after them.

    **A prop that is drawn and then buried is a bug the eye cannot find**, and
    it is the single largest category the placement rules miss. The museum had
    a 140x86 dinosaur entirely inside a ticket booth, a visitor reduced to a
    floating clump of hair, an exit sign under a painting and a picture frame
    half behind a counter. All four rendered; all four were invisible; not one
    broke R1 through R6, because none of them is *misplaced* — they are
    correctly placed underneath something.

    So this composites into an index buffer rather than pixels: every opaque
    pixel records which item drew it last, and an item's surviving share of
    its own ink is how much of it a viewer actually gets. Cheap, exhaustive,
    and it needs no judgement about what ought to be in front of what.
    """
    order = sorted(items, key=lambda i: (i[0], i[3]))
    owner = [-1] * (size[0] * size[1])
    total = [0] * len(order)
    for index, (_, im, box, x, y, _, *_r) in enumerate(order):
        if box is None:
            ox, oy = x - im.width // 2, y - im.height
        else:
            ox, oy = x - (box["x"] + box["w"] // 2), y - (box["y"] + box["h"])
        alpha = im.getchannel("A").load()
        for py in range(im.height):
            gy = oy + py
            if not 0 <= gy < size[1]:
                continue
            row = gy * size[0]
            for px in range(im.width):
                if alpha[px, py] < 128:
                    continue
                gx = ox + px
                if 0 <= gx < size[0]:
                    total[index] += 1
                    owner[row + gx] = index
    seen = [0] * len(order)
    for o in owner:
        if o >= 0:
            seen[o] += 1
    return [(order[i][6], order[i][3], order[i][4], seen[i] / total[i])
            for i in range(len(order))
            if total[i] and seen[i] / total[i] < floor]


def compose(spec, by_name, out_path):
    rooms = spec["rooms"]
    plan = draw_plan(rooms)

    wall_zones = [((r.y) * TILE, (r.y + 2) * TILE) for r in rooms if r.band]
    items, missing, tiny, placed, breaks_hidden = [], [], [], [], []
    breaks_facing = []
    for entry in spec["props"]:
        name, x, y = entry[0], entry[1], entry[2]
        variant = entry[3] if len(entry) > 3 else 0
        kind, ink, z = _flags(entry)
        got = prop(by_name, name, variant, ink)
        if got is None:
            missing.append(name if ink is None
                           else "%s ink %dx%d" % ((name,) + ink))
            continue
        box = got[1]
        # A furniture-sized name that resolves to a sliver is a modular segment
        # picked by accident. Report it rather than drawing a pole and calling
        # it a partition — see `prop`'s note on families versus pieces.
        if min(box["w"], box["h"]) < 8:
            tiny.append("%s#%d %dx%d" % (name, variant, box["w"], box["h"]))
        breaks_facing += check_facing(name, x, y, entry, got[0], box)
        placed.append((name, x, y, box["w"], box["h"], kind, got[2], got[3],
                       "matched" in (entry[4] if len(entry) > 4 else ())))
        items.append((y + z, got[0], box, x, y,
                      kind in ("floor", "seat"), name))
    for entry in spec.get("people", []):
        v, pose, facing, x, y = entry[:5]
        z = entry[5] if len(entry) > 5 else 0
        im = character(v, pose, facing)
        if im is None:
            missing.append("character %s %s_%s" % (v, pose, facing))
            continue
        # A figure seated facing the camera stands *inside* the desk, whose own
        # floor point is what has to be on the floor — so check where the desk
        # is, not where the head is.
        placed.append((v, x, y, im.width, im.height, "seat", v, 1, False))
        items.append((y + z, im, None, x, y, z >= 0, "character " + v))
    place(plan, items)

    if os.environ.get("SCENE_DEBUG"):
        # Every item's ink rect and floor point, over the finished plan. Which
        # prop is where is not answerable by reading coordinates — a prop's ink
        # sits at an arbitrary offset inside a 64x96 canvas — so the only
        # reliable way to see that a cup is on a desk is to draw the boxes.
        d = ImageDraw.Draw(plan)
        for _, im, box, x, y, _, *_r in items:
            w = box["w"] if box else im.width
            h = box["h"] if box else im.height
            left = x - w // 2
            d.rectangle([left, y - h, left + w - 1, y - 1],
                        outline=(255, 80, 80, 255))
            d.line([x - 3, y, x + 3, y], fill=(80, 255, 120, 255))

    canvas = Image.new("RGBA", PANEL, OUTSIDE + (255,))
    canvas.alpha_composite(plan, ORIGIN)
    canvas.convert("RGB").save(out_path)
    if missing:
        print("  MISSING: %s" % ", ".join(sorted(set(missing))))
    if tiny:
        print("  SLIVERS: %s" % ", ".join(sorted(set(tiny))))
    # A surface is *meant* to disappear under what stands on it — a desk with
    # two screens, a tray and an occupant is doing its job at 30% visible. So
    # anything carrying something is exempt; the rule is about props buried by
    # things that have no business on top of them.
    # A support is *meant* to disappear under what stands on it, but only so
    # far. Exempting it outright hid the thing this rule is best at finding:
    # a conference table with 46 px chairs tucked against a 40 px top, which
    # leaves a 26 px strip and reads as a table cut off at both ends. So a
    # support gets a looser floor, not a free pass.
    carrying = set()
    for _, ox, oy, ow, _, okind, _os, _op, _om in placed:
        if okind != "on":
            continue
        for name, fx, fy, fw, fh, fkind, _fs, _fp, _fm in placed:
            fl = fx - fw // 2
            if fkind == "floor" and fl <= ox - ow // 2 and \
                    ox - ow // 2 + ow <= fl + fw and fy - fh <= oy <= fy:
                carrying.add((name, fx, fy))
    for label, hx, hy, frac in report_hidden(items,
                                             (PLAN[0] * TILE, PLAN[1] * TILE)):
        limit = 0.25 if (label, hx, hy) in carrying else 0.45
        if frac >= limit:
            continue
        breaks_hidden.append("R7 %s@%d,%d is %d%% buried"
                             % (label, hx, hy, 100 - int(frac * 100)))
    breaks = check_continuity(rooms, placed) + breaks_hidden + breaks_facing
    if breaks:
        print("  CONTINUITY (%d)" % len(breaks))
        for b in breaks:
            print("    " + b)
    print("  %d props, %d people" % (len(items) - len(spec.get("people", [])),
                                     len(spec.get("people", []))))
    return out_path


# ---------------------------------------------------------------------------
# Helpers for packing rooms densely, because loneliness is what made the old
# scenes look flat.

def row(name, x0, y, n, dx, v0=0, dv=1, flags=()):
    """`n` copies marching right, each a different catalogue variant."""
    return [(name, x0 + i * dx, y, v0 + i * dv, flags) for i in range(n)]


def col(name, x, y0, n, dy, v0=0, dv=1, flags=()):
    return [(name, x, y0 + i * dy, v0 + i * dv, flags) for i in range(n)]


def grid(name, x0, y0, nx, ny, dx, dy, v0=0, flags=()):
    out = []
    for j in range(ny):
        for i in range(nx):
            out.append((name, x0 + i * dx, y0 + j * dy, v0 + j * nx + i, flags))
    return out


# The 64x64 L-desk and the 64x38 straight desk are the only two entries in the
# 49-strong `desk_corner_l` family that are furniture rather than modular
# surface segments.
#
# **The straight desk is the one to build on, and the L is a trap.** Measured
# by alpha-scanning both, relative to the floor point the ink is bottom-centred
# on:
#
#   straight 64x38   x-32..x+31 solid from y-38 down to y-7, then a single
#                    leg at x-32..x-1 for the last 6 px. A plain slab.
#   L 64x64          only the RIGHT half x+0..x+31 exists above y-39. The
#                    top-left quadrant is a 32x25 hole.
#
# The first pod used the L and put a 64-wide rig across its top edge, which
# dropped half of every monitor into that hole — the render showed screens
# hanging in the air beside each desk with nothing under them. On the slab
# there is no hole to fall into, and a 32-wide rig covers exactly half of it.
DESK = ("ink:64x38",)
DESK_TOP = 38          # desk's back edge, above the floor point

# Which of the six 32x42 `workstation_composite` entries have a *lit* screen.
# Two of the six are drawn switched off, and a dark panel at panel size reads
# as a broken monitor rather than as an idle one — the room is meant to look
# staffed.
LIT_RIGS = (0, 1, 3, 4)


def on_desk(lift, ink=None):
    """Flags for a prop resting `lift` px up the desk it stands on.

    **`z` has to exceed `lift`, and by more than one might guess.** A prop on a
    desktop is drawn above the desk's floor point, so its own floor point is
    `y - lift`; sorting on that puts it *behind* by exactly `lift` pixels, and
    a token `z:2` does not begin to cover a 16 px lift. The desk then paints
    over everything below its own back edge, which is most of the prop.

    The symptom is specific and was on screen for two renders before anyone
    read it correctly: monitors that look like screens hovering with no base,
    because only the part clearing the desk's top edge survives. `lift + 1`
    puts the prop one pixel in front of its desk and nothing else changes.
    """
    flags = ["flat", "z:%d" % (lift + 1)]
    if ink is not None:
        flags.append("ink:%dx%d" % ink)
    return tuple(flags)


# ---------------------------------------------------------------------------
# Seating a character at a desk, in all four directions
#
# The character pack ships `sit` in **left and right only** — there is no
# front- or back-facing seated pose at any size, which is why every room this
# project has drawn so far has its cast side-on. That looked like a hard limit
# on the art. It is not; it is a limit on the *pose*, and a seat is made of a
# pose and an occlusion.
#
#   facing the camera   `idle_down`, standing, planted **inside** the desk's
#                       footprint and sorted above it. `place` depth-sorts on
#                       the floor point, so the desk draws over the legs and
#                       what is left is a head and shoulders behind a desk —
#                       which is what sitting looks like from the front.
#   facing away         `idle_up`, standing below the desk with a chair. No
#                       occlusion needed; a back view is a back view.
#
# So all four directions are available today, from art already imported. The
# only thing that was ever missing was the depth sort.

# Feet this far above the desk's floor point. The figure is ~34 px tall, so
# from a back edge at y-38 this leaves head and shoulders showing and buries
# everything below them — 8 px of overlap is enough to read as "behind", and
# more starts to look decapitated.
SEAT_INSET = 30
# Feet this far below the desk for the back view. The back-view chair is 46 px
# tall against a ~34 px figure, so it swallows an occupant placed level with
# it: the render came out as three empty chairs. Sitting the figure 30 px
# higher than the chair's own floor point leaves its head and shoulders above
# the backrest, which is what somebody in a high-backed chair looks like from
# behind.
SEAT_STANDOFF = 8
CHAIR_DROP = 38     # the chair's floor point, below the desk's


def _sheet_number(path):
    """The trailing integer in a singles filename, or -1.

    `Hospital_Singles_Shadowless_32x32_72.png` -> 72. The packs number singles
    in the order they were drawn, so consecutive numbers are one object's
    views and one colour's block; sorting by the string does not preserve
    either.
    """
    stem = os.path.splitext(os.path.basename(path))[0]
    tail = stem.rsplit("_", 1)[-1]
    return int(tail) if tail.isdigit() else -1


def backrest_side(im, box):
    """`"left"`, `"right"` or `"face-on"` — where the backrest sits.

    The horizontal centroid of the top 8 rows of ink against the centroid of
    the bottom 12. On a profile chair the backrest is a tall bar over one edge
    while the seat and feet spread the other way; on a face-on chair (front or
    back) the sprite is symmetric about its own axis.

    The threshold is not a number I chose. Measured over every chair sprite in
    the catalogue the gap is **+-8.4 px on a 22 px sprite, or 0.0 to the
    pixel** — the distribution is two spikes and a hole, so anything past 3 is
    unambiguous and nothing has ever landed in between.
    """
    px = im.load()
    x0, y0, w, h = box["x"], box["y"], box["w"], box["h"]

    def centroid(top, bottom):
        xs = [x for y in range(y0 + top, y0 + bottom)
              for x in range(x0, x0 + w) if px[x, y][3] > 128]
        return sum(xs) / len(xs) if xs else None

    high, low = centroid(0, 8), centroid(h - 12, h)
    if high is None or low is None:
        return "face-on"
    if high - low > 3:
        return "right"
    if low - high > 3:
        return "left"
    return "face-on"


# A *suite* is one chair drawn from four sides, as {facing: (name, ink)}.
#
# Rooms are furnished, not merely occupied. A library reading table ringed with
# grey padded office chairs is as wrong as a chair facing backwards, and the
# pack has the vocabulary to avoid it — every suite below is a real rotation
# the artist drew as consecutive singles on one sheet, so a table seated from
# a suite matches on all four sides.
#
# **`down` is always the family's tallest face-on view and `up` its shortest**,
# and that is not a convention imposed here. Seen from behind, the backrest
# hides the seat, so the silhouette loses the seat's depth and the back view is
# bodily shorter. Measured on three unrelated families — `chair_school` 44/30,
# `chair_ornate` 46/32, `chair_office_swivel` 42/24 — and R9 re-derives it on
# every run rather than trusting this comment.
CHAIR_SUITES = {
    # Office. Three views come from the swivel rotation, but `up` is the big
    # padded chair: that is the one the pack's own `Office_Design_2` puts
    # below every desk in the room.
    "office": {"up":    ("chair_office_back",   (32, 46)),
               "down":  ("chair_office_swivel", (28, 42)),
               "left":  ("chair_office_swivel", (22, 42)),
               "right": ("chair_office_swivel", (22, 42))},
    # Ladder-back, green frame, wooden seat. Four sprites, four sides.
    "school": {"up":    ("chair_school", (28, 30)),
               "down":  ("chair_school", (28, 44)),
               "left":  ("chair_school", (24, 40)),
               "right": ("chair_school", (24, 40))},
    # Turned wood with a slatted back — a reading room or a dining room.
    "wood":   {"up":    ("chair_ornate", (28, 32)),
               "down":  ("chair_ornate", (28, 46)),
               "left":  ("chair_ornate", (22, 46)),
               "right": ("chair_ornate", (22, 46))},
}

_chair_pools = {}


def chair_pool(suite, facing):
    """Which variants of a suite's ink pool actually face that way.

    `left` and `right` share one ink pool — the office suite's is twenty
    entries, five colours of two profiles each way — so the index alone does
    not say which. Rather than hardcode the stride (regular today, and it
    would rot silently if the catalogue were regenerated) every entry is
    **measured** and kept if its backrest is on the far side from the way it
    faces.
    """
    if (suite, facing) in _chair_pools:
        return _chair_pools[(suite, facing)]
    name, ink = CHAIR_SUITES[suite][facing]
    entries = [e for e in index().get(name, [])
               if (e["content_box"]["w"], e["content_box"]["h"]) == ink]
    if facing in ("up", "down"):
        pool = list(range(len(entries)))
    else:
        want = "right" if facing == "left" else "left"
        pool = [i for i in range(len(entries))
                if backrest_side(*prop(index(), name, i, ink)[:2]) == want]
    # Ordered by the sheet, not by the filename. `load_index` sorts entries as
    # strings, which puts `..._100.png` before `..._72.png` and scrambles the
    # colour blocks: the meeting room came out with a red chair on one side of
    # the table and a yellow one on the other, both asking for variant 0. A
    # chair's variant has to mean "which finish", and it only does if the pool
    # runs in the order the artist drew it.
    pool.sort(key=lambda i: _sheet_number(entries[i]["file"]))
    if not pool:
        raise SystemExit("no %s-facing sprite in %s ink %dx%d" %
                         ((facing, name) + ink))
    _chair_pools[(suite, facing)] = pool
    return pool


def _sheet_stem(path):
    """`.../Hospital_Singles_Shadowless_32x32_72.png` -> the part before `_72`."""
    stem = os.path.splitext(os.path.basename(path))[0]
    head, _, tail = stem.rpartition("_")
    return head if tail.isdigit() else stem


def chair(x, y, v=0, facing="down", flags=(), suite="office"):
    """A chair whose floor point is (x, y), facing `facing`, from `suite`.

    # The pack draws six views, and I spent four renders believing it drew one

    `chair_office_swivel` resolves to a full rotation. One colour's six
    consecutive Hospital singles are, in order: profile facing left,
    three-quarter left, **front**, profile facing right, three-quarter right,
    **back** — in five colours, plus a chunkier Jail set with the same
    coverage. `chair_office_back` and `chair_office_front` are the padded and
    mesh *models* of the same back view, which is the only part of my earlier
    reading that survived.

    # What the packs' own artists do with them

    Two rooms settle every question this raises, and both were sitting in
    `assets/` the whole time:

      * `Office_Design_2.gif` — every desk chair is the 32x46 back view and
        every one of them is drawn **below** its desk, so its occupant faces
        away from the camera. Where a character faces the camera at a desk,
        the artist draws **no chair at all**: the body covers it entirely.
      * `Ice_Cream_Shop_Design_preview_32x32.png` — cafe tables are seated on
        the **left and right** with mirrored profiles facing inward, not on
        the near and far edges.

    So the near side of a table is not undrawable, as this file claimed; it is
    the *easy* side, and takes the same back view a desk does. It is the far
    side that needs the front view, and the front view exists. `left`/`right`
    are the ones to reach for first all the same, because a profile reads as a
    chair at a glance where a face-on chair reads as a lump.

    Nothing here is trusted: R9 re-measures every chair on every run and
    fails the scene if the sprite disagrees with the declared facing.
    """
    pool = chair_pool(suite, facing)
    name, ink = CHAIR_SUITES[suite][facing]
    return (name, x, y, pool[v % len(pool)],
            ("ink:%dx%d" % ink, "facing:" + facing) + flags)


def seat(variant, x, y, facing="down"):
    """One character seated at the desk whose floor point is (x, y).

    Offset to the right of centre so the figure clears the rig, which occupies
    the desk's left half.
    """
    if facing == "down":
        return (variant, "idle", "down", x + 8, y - SEAT_INSET)
    return (variant, "idle", "up", x, y + SEAT_STANDOFF)


# A chair is 42-46 px tall and a table top is 34-42, so a chair tucked level
# with the table hides almost all of it. These are the clearances that keep a
# table looking like a table.
FAR_TUCK = 4      # far chair's feet overlap the table's back edge by this
NEAR_TUCK = 6     # near chair's head overlaps the table's front edge by this
SIDE_STANDOFF = 6  # side chair's near edge, inside the table's own edge
CHAIR_W = 22      # a profile chair's ink width


def table_with_seats(x, y, slabs=3, seats=(0, 0, 1, 1), v=0,
                     name="table_metal", ink=(52, 40), pitch=52, chair_h=46,
                     suite="office"):
    """A table and its chairs, laid out so both survive.

    `seats` is `(far, near, west, east)` — how many chairs on each edge.

    # Why the sides come first

    The default seats the ends, not the faces, because that is what the
    packs' own artists do: the ice-cream shop's cafe tables are seated left
    and right with mirrored profiles facing inward, and nothing in either
    pack's designs seats a table on the far edge at all. A profile chair
    reads as a chair instantly — you can see the backrest, the seat and the
    legs as separate parts. A face-on chair is a symmetric lump the same
    colour as the table, and at 1x it disappears into it.

    A side chair's own floor point sits level with the table's, offset
    `ink[0] // 2 + CHAIR_W // 2 - SIDE_STANDOFF` from centre so it laps the
    table's edge rather than floating beside it.

    # Why the faces are arithmetic rather than eyeballing

    The meeting room was hand-placed three times and came out wrong three
    times, the same way each time: the near chairs sat level with the table,
    and since they are 46 px tall against a 40 px top they covered all but a
    26 px strip. The table read as cut off at both ends, which is what it was.

    The top runs from `y - ink[1]` to `y`. A far chair's *feet* belong on the
    back edge, so its floor point is `y - ink[1] + FAR_TUCK`. A near chair's
    *head* belongs on the front edge, so its floor point is
    `y + chair_h - NEAR_TUCK` — below the table, not level with it.

    Note the vertical budget: a table seated on both faces needs
    `chair_h + ink[1] + chair_h - FAR_TUCK - NEAR_TUCK` px of floor, about 122
    for the office kit. A room with a north wall gives 32 px per tile minus
    64, so **six tiles is not enough for a table seated front and back** and
    seven is. That is why the meeting room is 7 tiles and the break room 5.
    Seating the sides instead costs nothing vertically, which is the other
    reason to prefer it.
    """
    out = []
    left = x - (slabs * pitch) // 2 + pitch // 2
    for i in range(slabs):
        # One finish for the whole table. Walking the variant along the run
        # walks the *finishes*, and the library came out as one tan slab
        # abutted to one dark orange one — a two-tone table nobody makes.
        out.append((name, left + i * pitch, y, v,
                    ("ink:%dx%d" % ink, "matched")))
    far, near, west, east = seats
    span = slabs * pitch
    for i in range(far):
        cx = x - span // 2 + span * (2 * i + 1) // (2 * far)
        out.append(chair(cx, y - ink[1] + FAR_TUCK, v, "down", suite=suite))
    for i in range(near):
        cx = x - span // 2 + span * (2 * i + 1) // (2 * near)
        out.append(chair(cx, y + chair_h - NEAR_TUCK, v, "up", suite=suite))
    # The table's own half-width, plus half a chair, less the overlap. Long
    # tables lap the outermost slab, not the centre.
    reach = span // 2 + CHAIR_W // 2 - SIDE_STANDOFF
    # A side chair's depth is not free. Placed level with the table's own
    # floor point it ties on the sort key, and `place` breaks ties by x — so
    # the chair to the *left* of a table draws behind it and the identical one
    # to the right draws in front. The meeting room showed exactly that: a
    # chair on one side, a sliver of chair on the other.
    #
    # So a side seat takes one of two depths, front corner first, the way the
    # ice-cream shop's cafe tables are seated. The front chair laps the near
    # edge and draws over it; the back one sits behind the table and is
    # meant to.
    depths = [y + 2, y - ink[1] + FAR_TUCK]
    for i in range(west):
        out.append(chair(x - reach, depths[i % 2], v, "right", suite=suite))
    for i in range(east):
        out.append(chair(x + reach, depths[i % 2], v, "left", suite=suite))
    return out


def desk_pod(x, y, v=0, facing="down"):
    """A desk, the kit on it, and a chair if one would be visible.

    The slab's ink is bottom-centred at (x, y): back edge y-38, front y-1. The
    rig's base lands at y-16, on the desktop rather than over its edge, and its
    screen rises 20 px above the back edge the way the pack's own office GIF
    draws a monitor. `z:` keeps all of it in front of the desk.

    A chair is only emitted for a back-facing seat. Facing the camera, the
    chair is behind the desk and would be entirely hidden — drawing one there
    just puts a stray backrest through the desktop.

    **A monitor can only belong to a seat that faces away from the camera,
    and that is a fact about the art rather than a preference.** Every screen
    in the pack is drawn face-on with its keyboard below it: `monitor_lit`,
    `monitor_dark`, `monitor_off_white`, `laptop_open_lit` and all six 32x42
    `workstation_composite` rigs. There is no rear view of a monitor anywhere
    in 12,279 props. A screen facing the camera is therefore being *looked at*
    from below, by someone sitting between it and the viewer.

    So a camera-facing occupant cannot have one. Giving them a screen puts
    them behind their own monitor looking at its back — which is what the
    first three renders of this scene showed, six times over.

    Camera-facing desks get orientation-neutral kit instead: paper, a tray, a
    mug, a lamp. Those read the same from either side, and the split gives the
    floor something the app wants anyway — desks that look like different
    kinds of work.
    """
    out = [("desk_corner_l", x, y, v, DESK)]
    if facing == "up":
        out += [
            # Two screens, filling the slab. Ink 32 wide against 64, so x-16
            # and x+16 tile it exactly. Base 16 px up the desk, screen clearing
            # the back edge by 20 px the way the pack's own GIF draws it.
            ("workstation_composite", x - 16, y - 16, LIT_RIGS[(3 * v) % 4],
             on_desk(16, (32, 42))),
            ("workstation_composite", x + 16, y - 16, LIT_RIGS[(3 * v + 1) % 4],
             on_desk(16, (32, 42))),
            chair(x, y + CHAIR_DROP, v // 2, "up", ("seat",)),
        ]
    else:
        out += [
            # 24x24 is the loose sheaf; the 32x42 entry is a filing tower and
            # overhangs the desk's right edge when centred this close to it.
            ("folder", x - 16, y - 16, 0, on_desk(16)),
            ("clipboard", x - 14, y - 10, v % 4, on_desk(10)),
            ("paper_stack", x + 18, y - 16, (v + 1) % 3, on_desk(16, (24, 24))),
            ("coffee_cup", x + 20, y - 10, 0, on_desk(10)),
        ]
    return out


# ---------------------------------------------------------------------------
# Three plans. Coordinates are plan pixels: (0, 0) is the plan's top-left,
# 704x384 overall, TILE=32.

def engineering():
    rooms = [
        Room("open plan", 0, 0, 13, 12, "concrete",
             doors=[("east", 8, 3)]),
        # A room's floor is its rect minus the two tiles its north wall eats.
        # `table_with_seats` needs ~122 px for a table with both sides
        # occupied, so the meeting room takes 7 tiles (160 px of floor) and
        # the break room 5 (96 px), which is a kitchenette rather than a
        # lounge. At 6 and 6 the conference table came out buried.
        Room("meeting", 13, 0, 9, 7, "carpet", doors=[("west", 3, 2)]),
        Room("break", 13, 7, 9, 5, "plank", doors=[("west", 2, 3)]),
    ]
    props = []
    # Open plan: whiteboard and chart on the north face, four desk pods.
    props += [("whiteboard_blank", 90, 60, 0, ("flat",)),
              ("chart_board", 200, 60, 1, ("flat",)),
              ("picture_framed", 280, 54, 3, ("flat",)),
              ("board_schedule", 340, 58, 2, ("flat",)),
              ("clock", 30, 52, 0, ("flat",))]
    seats = [(76, 162, "down"), (200, 162, "up"), (324, 162, "down"),
             (76, 306, "up"), (200, 306, "down"), (324, 306, "up")]
    for i, (sx, sy, f) in enumerate(seats):
        props += desk_pod(sx, sy, i, f)
    # Litter between the pods. Office_Design_2's lesson is that the gaps
    # between clusters are never bare floor, so every lane here gets something.
    props += [("plant_potted", 24, 118, 2, ()),
              ("plant_potted", 24, 372, 5, ()),
              ("printer_desk_composite", 384, 190, 0, ()),
              ("printer", 384, 250, 7, ("ink:30x36",)),
              ("cabinet_drawers", 388, 300, 0, ()),
              ("cabinet_drawers", 356, 356, 2, ()),
              ("water_cooler", 384, 366, 0, ()),
              ("pc_tower", 30, 250, 1, ("ink:26x44",)),
              ("pc_tower", 136, 344, 0, ("ink:26x44",)),
              ("pc_tower", 254, 206, 2, ("ink:26x44",)),
              ("bin", 158, 252, 7, ()),
              ("bin", 252, 374, 6, ()),
              ("cabinet_drawers", 26, 302, 4, ()),
              ("plant_potted", 250, 118, 9, ()),
              ("plant_potted", 366, 118, 13, ()),
              ("plant_potted", 112, 250, 4, ()),
              ("box_cardboard", 250, 250, 0, ("ink:32x42",)),
              ("box_cardboard", 276, 262, 1, ("ink:24x42",)),
              ("backpack", 214, 218, 0, ("ground",)),
              ("backpack", 252, 356, 1, ("ground",))]
    # Meeting room: long table, chairs down both sides, screen on the face.
    #
    # The table is two 52x42 `table_metal` slabs abutted, not a run of
    # `desk_counter`: that name's 32x46 entries are counter *segments* in three
    # finishes, and stepping the variant along a row walks the finishes rather
    # than the segments, so a four-piece run came out three tan and one grey.
    props += [("tv_wall", 566, 60, 1, ("flat",)),
              ("certificate", 648, 52, 0, ("flat",)),
              ("noticeboard", 484, 56, 0, ("flat",))]
    # Seated on all four edges — a meeting room is the one place a table is
    # meant to look surrounded. The 7 tiles this room has were chosen for
    # exactly the 122 px `table_with_seats` needs to seat both faces.
    props += table_with_seats(560, 176, slabs=3, seats=(2, 2, 1, 1), v=0)
    props += [("plant_potted", 442, 110, 8, ()),
              ("plant_potted", 690, 112, 12, ()),
              ("water_cooler", 688, 182, 0, ()),
              # Against the west wall, not the near edge of the table: the
              # near edge is now two chairs, and seating a table costs the
              # floor that used to hold the room's clutter.
              ("printer", 440, 170, 6, ("ink:30x32",)),
              ("cabinet_drawers", 448, 214, 1, ()),
              ("box_cardboard", 636, 214, 1, ("ink:32x42",)),
              ("box_cardboard", 664, 220, 0, ("ink:24x42",)),
              ("document_tray", 508, 162, 0, on_desk(40)),
              ("paper_stack", 560, 158, 0, on_desk(36, (24, 24))),
              ("coffee_cup", 552, 152, 0, on_desk(30)),
              ("coffee_cup", 610, 154, 0, on_desk(32))]
    # Break room: counters, cafe tables, sofa, vending.
    # The break room's north wall is 64 px of the panel's 400 and was carrying
    # two objects. The pack's own rooms hang something every two tiles.
    props += [("noticeboard", 462, 276, 1, ("flat",)),
              ("clock", 520, 264, 0, ("flat",)),
              ("sign_cafe", 616, 272, 0, ("flat",)),
              ("poster", 636, 274, 0, ("flat",))]
    # A 5-tile kitchenette: floor y 288-384. Appliances stand against the wall
    # with their tops overlapping its face, which is how the pack draws them,
    # and one small table sits clear of them.
    #
    # **No sofas and no tub chairs.** Both are in the pack and both were tried:
    # at 1x the 62x48 sofa's checkered seat reads as a grate and the 32x36 tub
    # chair reads as a washbasin. Legibility at the size the panel actually
    # runs beats naming the right object.
    props += [("coffee_machine", 462, 322, 0, ()),
              ("coffee_machine", 494, 322, 3, ()),
              # **The microwave and kettle stand on the floor, not on a
              # counter.** `counter_wood`'s 32x30 piece is 30 px tall and
              # anything set on it covers 24 of those 30, so the counter read
              # as a smear under an appliance. In a galley this narrow the
              # appliances are the run.
              ("microwave", 540, 322, 0, ()),
              ("kettle", 574, 320, 0, ()),
              ("water_cooler", 618, 322, 0, ()),
              ("vending_machine", 672, 328, 0, ("ink:48x68",)),
              ("plant_potted", 682, 380, 4, ()),
              ("bin", 462, 380, 7, ())]
    # **No table here.** `table_with_seats` needs ~122 px of floor and this
    # room has 96, so a table with either side occupied puts its chairs on the
    # south wall. A 5-tile room is a galley kitchen, not a cafe, and the
    # honest thing is to draw a galley. The cafe table lives in the open plan,
    # which has the depth for it.
    props += [("bin", 606, 380, 11, ())]
    cast = ("06", "07", "09", "10", "17", "19")
    people = [seat(cast[i], sx, sy, f)
              for i, (sx, sy, f) in enumerate(seats)]
    return {"name": "01-engineering-office", "rooms": rooms,
            "props": props, "people": people}


def museum():
    rooms = [
        Room("gallery", 0, 0, 14, 12, "slab",
             doors=[("east", 7, 3)]),
        Room("gift shop", 14, 0, 8, 6, "lino_tan", doors=[("west", 3, 2)]),
        Room("entrance", 14, 6, 8, 6, "lino",
             doors=[("west", 1, 3), ("south", 3, 3)]),
    ]
    props = []
    # Gallery: paintings hung along the face, barrier line, then cases.
    props += [("painting_framed", 60, 58, 2, ("flat",)),
              ("painting_framed", 150, 56, 8, ("flat",)),
              ("painting_framed", 240, 58, 14, ("flat",)),
              ("painting_framed", 330, 56, 20, ("flat",)),
              ("painting_framed", 410, 58, 26, ("flat",)),
              ("wall_plaque", 105, 56, 0, ("flat",)),
              ("wall_plaque", 285, 56, 0, ("flat",))]
    props += row("rope_barrier", 46, 106, 13, 32, v0=0,
                 flags=("ground", "ink:32x34"))
    props += [("column", 24, 196, 0, ("ink:32x82",)),
              ("column", 24, 348, 1, ("ink:32x82",)),
              ("column", 424, 196, 2, ("ink:32x82",)),
              ("column", 424, 348, 3, ("ink:32x82",))]
    props += [("display_case", 104, 196, 2, ("ink:54x88",)),
              ("display_case", 196, 196, 3, ("ink:54x88",)),
              ("display_case", 288, 196, 4, ("ink:54x88",)),
              ("artefact_case", 382, 196, 0, ()),
              ("skeleton", 210, 300, 4, ()),
              ("statue", 70, 296, 2, ()), ("statue", 350, 296, 6, ()),
              ("amphora_on_plinth", 120, 300, 1, ()),
              ("vase_on_plinth", 300, 300, 2, ()),
              ("plinth", 148, 348, 0, ()),
              ("lectern", 250, 348, 3, ()),
              ("bench", 376, 330, 0, ("facing:none",)),
              ("plant_potted", 380, 380, 11, ()),
              ("wall_plaque", 372, 60, 0, ("flat",)),
              ("bench", 130, 366, 0, ("facing:none",)),
              ("bench", 290, 366, 1, ("facing:none",)),
              ("sign_exit", 356, 56, 2, ("flat",)),
              ("plant_potted", 62, 384, 1, ()),
              ("laser_sensor", 60, 150, 0, ("ground",)),
              ("laser_sensor", 390, 150, 3, ("ground",))]
    # Gift shop: shelves along the face, tables of merch, a counter.
    props += [("poster_shirt", 500, 58, 1, ("flat",)),
              ("poster_shirt", 560, 58, 3, ("flat",)),
              ("sign_open", 638, 56, 0, ("flat",))]
    props += row("shop_shelf", 480, 132, 6, 34, v0=5, flags=("ink:32x42",))
    props += [("souvenir_display", 496, 186, 0, ("ink:64x50",)),
              ("display_table", 582, 186, 2, ("ink:60x60",)),
              ("display_table", 662, 186, 5, ("ink:60x60",)),
              ("amphora_souvenir", 480, 176, 2, on_desk(24, (28, 24))),
              ("plush_dinosaur", 576, 172, 5, on_desk(28, (32, 36))),
              ("shirt_folded", 652, 174, 0, on_desk(26, (26, 24))),
              ("shirt_folded", 676, 174, 2, on_desk(26, (26, 24)))]
    # Entrance: ticket desk, turnstiles, benches, a big centrepiece.
    props += [("sign_hanging", 648, 246, 0, ("flat",)),
              ("picture_framed", 470, 250, 0, ("flat",))]
    # The hall is 256x120 of floor and the ticket office takes 192x112 of it,
    # so everything else lives in the strip below, clear of the street door's
    # 96 px opening at x 544-640.
    props += [("ticket_counter", 566, 316, 0, ()),
              ("turnstile", 470, 356, 1, ()),
              ("turnstile", 502, 356, 3, ()),
              ("turnstile", 534, 356, 4, ()),
              ("plant_potted", 464, 382, 6, ()),
              ("plant_potted", 668, 340, 9, ()),
              ("bench", 670, 384, 2, ("facing:none",)),
              ("doormat", 592, 382, 4, ("ground",)),
              ("sign_exit", 690, 250, 4, ("flat",))]
    people = [("17", "idle", "up", 140, 150), ("07", "idle", "up", 320, 150),
              ("09", "idle", "down", 220, 340), ("19", "idle", "left", 542, 184),
              ("10", "idle", "up", 592, 356), ("06", "walk", "right", 480, 340)]
    return {"name": "02-museum", "rooms": rooms, "props": props,
            "people": people}


def hospital():
    rooms = [
        Room("ward", 0, 0, 12, 12, "white",
             doors=[("east", 8, 3)]),
        Room("reception", 12, 0, 10, 6, "lino", doors=[("west", 3, 2)]),
        Room("play area", 12, 6, 10, 6, "mauve", doors=[("west", 1, 3)]),
    ]
    props = []
    # Ward: two rows of beds head-to-wall, curtains, nightstands, IVs.
    props += [("window", 32, 60, 2, ("flat",)),
              ("clock", 138, 52, 0, ("flat",)),
              ("window", 248, 60, 4, ("flat",)),
              ("sign_medical", 358, 54, 0, ("flat",))]
    # `hospital_bed` has 49 entries across two orientations. The 64x44 piece is
    # the bed seen lengthways, and it is the only one `patient_lying` fits:
    # that prop is a 44x36 figure lying head-to-the-left, so laying it on the
    # 32x72 upright bed would put a sideways person across a vertical mattress.
    # Pairing them by ink is the difference between a ward and a furniture pile.
    BED = ("ink:64x44",)
    IV = ("ink:30x60",)
    for i, x in enumerate((66, 176, 286)):
        props += [("hospital_bed", x, 158, (3, 2, 4)[i], BED),
                  ("patient_lying", x - 2, 150, i * 2, on_desk(8, (44, 36))),
                  ("nightstand", x + 52, 178, i, ("ink:32x40",)),
                  ("iv_stand", x - 44, 154, i, IV),
                  ("board_schedule", x + 4, 56, i, ("flat",))]
    for i, x in enumerate((66, 176, 286)):
        props += [("hospital_bed", x, 306, (1, 3, 0)[i], BED),
                  ("patient_lying", x - 2, 298, 1 + i * 2, on_desk(8, (44, 36))),
                  ("nightstand", x + 52, 330, i + 2, ("ink:32x40",)),
                  ("iv_stand", x - 44, 302, 3 + i, IV),
                  chair(x + 20, 348, i, "up")]
    props += [("privacy_screen", 220, 236, 0, ()),
              ("room_divider", 250, 382, 1, ()),
              ("cabinet_medical", 36, 212, 0, ("ink:54x78",)),
              ("shelf_medical", 38, 264, 0, ("ink:58x68",)),
              ("sink_wall", 348, 60, 0, ("flat",)),
              ("dispenser_soap", 316, 60, 0, ("flat",)),
              ("bin", 320, 372, 11, ()),
              ("plant_potted", 24, 372, 1, ()),
              ("wheelchair", 360, 372, 3, ("facing:down",)),
              ("cabinet_steel", 112, 368, 3, ("ink:32x42",)),
              ("cabinet_steel", 146, 368, 0, ("ink:28x42",)),
              ("bin", 300, 254, 6, ())]
    # Reception: counter, waiting chairs, notice board, vending.
    props += [("counter_reception", 440, 132, 0, ()),
              ("counter_reception", 504, 132, 2, ()),
              ("counter_medical", 568, 132, 0, ()),
              ("plant_potted", 414, 190, 6, ()),
              ("printer", 622, 130, 7, ("ink:30x36",)),
              ("noticeboard", 470, 58, 0, ("flat",)),
              ("board_schedule", 560, 58, 3, ("flat",)),
              ("tv_wall", 640, 58, 2, ("flat",)),
              ("kiosk_touchscreen", 678, 128, 0, ())]
    # The 62x36 entries are the two-seat units and the 32x36 the singles.
    # Walking the variant by 1 across the whole family mixes the two and the
    # run comes out chair, bench, chair — but pinning the *double* was no
    # better: six seats at a 4 px spacing make an unbroken 190 px band that
    # reads as a fence rather than as seating. Singles at a 12 px gap read as
    # five chairs, which is what a waiting room looks like.
    props += row("chair_waiting", 470, 190, 4, 44, v0=0, dv=1,
                 flags=("ink:32x36", "facing:down"))
    props += [("vending_machine", 678, 190, 0, ("ink:48x68",)),
              ("stanchion_rope", 424, 172, 0, ("ground",)),
              ("stanchion_rope", 646, 172, 2, ("ground",)),
              ("fire_extinguisher", 690, 58, 0, ("flat",))]
    # Play area: mats, kid chairs, toy boxes, easels.
    props += [("chalk_drawing", 470, 250, 0, ("flat",)),
              ("chalk_drawing", 612, 250, 2, ("flat",)),
              ("poster", 640, 248, 0, ("flat",))]
    props += [("play_mat", 500, 320, 0, ("ground",)),
              ("table_round", 590, 320, 3, ("ink:54x54",)),
              ("chair_kids", 560, 316, 2, ("facing:down",)),
              ("chair_kids", 620, 316, 8, ("facing:up",)),
              ("chair_kids", 618, 348, 14, ("facing:left",)),
              ("toy_box", 440, 300, 1, ()),
              ("toy_box_animal", 440, 340, 2, ()),
              ("toy_bin_animal", 676, 300, 1, ()),
              ("easel_chalkboard", 660, 350, 4, ()),
              ("cabinet_kids", 470, 292, 3, ()),
              ("cabinet_kids", 510, 292, 9, ()),
              ("toy_plush", 520, 344, 1, ()),
              ("toy_plush", 546, 350, 4, ()),
              ("toy_figure", 486, 356, 2, ("ground",)),
              ("toy_stacking_ring", 630, 378, 0, ()),
              ("toy_block", 466, 378, 0, ("ground",)),
              ("bench", 600, 380, 3, ("facing:none",))]
    people = [("17", "idle", "down", 120, 200), ("07", "idle", "left", 336, 208),
              ("19", "idle", "down", 470, 132), ("09", "idle", "down", 556, 296),
              ("10", "idle", "down", 448, 366), ("06", "walk", "down", 400, 120)]
    return {"name": "03-hospital", "rooms": rooms, "props": props,
            "people": people}


def library():
    """A fourth plan, built only from the assemblies and never eyeballed.

    # Why this scene exists

    The first three were fixed one prop at a time until they passed. That
    proves the rules hold *here*; it does not prove they generalise, and the
    whole point of `check_continuity`, `table_with_seats`, `chair` and `prop`'s
    `ink` is that a new scene should get correctness without repeating the
    argument. So this one was written straight through against the rules — no
    render was looked at until the linter was silent — and out of a different
    pack's vocabulary: shelving, reading tables, armchairs, none of which the
    office kit covers.

    The budget from `table_with_seats` decides the plan before any prop is
    named: the reading room needs a table with a chair row, so it takes the
    full 12 tiles, and the two side rooms take 6 and 6 because neither holds
    a table.
    """
    rooms = [
        Room("reading room", 0, 0, 13, 12, "plank", doors=[("east", 8, 3)]),
        Room("stacks", 13, 0, 9, 6, "carpet", doors=[("west", 3, 2)]),
        Room("study", 13, 6, 9, 6, "slab", doors=[("west", 2, 3)]),
    ]
    props = []
    # Reading room: art on the face, shelving down the west wall, two reading
    # tables, armchairs in the corners.
    props += [("painting_framed", 70, 58, 15, ("flat",)),
              ("painting_framed", 170, 58, 19, ("flat",)),
              ("clock", 240, 52, 0, ("flat",)),
              ("painting_framed", 310, 58, 25, ("flat",)),
              ("noticeboard", 386, 56, 0, ("flat",))]
    props += [("shelf_library", 60, 148, 0, ()),
              ("shelf_library", 140, 148, 1, ()),
              ("shelf_library", 220, 148, 2, ()),
              ("globe", 300, 144, 0, ()),
              ("step_ladder", 350, 146, 2, ())]
    # A reading table, seated the way the ice-cream shop seats a cafe table:
    # profiles facing inward on both ends, and one reader at the near face.
    props += table_with_seats(120, 300, slabs=2, seats=(0, 2, 1, 1), v=0,
                              name="table_wood", ink=(60, 50), pitch=60,
                              chair_h=42, suite="wood")
    props += [("paper_stack", 96, 282, 0, on_desk(32, (24, 24))),
              ("coffee_cup", 148, 280, 0, on_desk(30)),
              ("lamp_floor", 30, 300, 0, ("ink:26x68",)),
              ("armchair", 300, 268, 0, ("ink:40x46", "facing:down")),
              ("armchair", 370, 268, 1, ("ink:40x46", "facing:down")),
              ("rug_patterned", 336, 300, 1, ("ground", "ink:60x60")),
              ("plant_potted", 30, 372, 10, ()),
              ("plant_potted", 386, 372, 15, ()),
              ("bin", 250, 372, 6, ())]
    # Stacks: nothing but shelving and a ladder, which is what a stack is.
    props += [("poster", 486, 56, 1, ("flat",)),
              ("noticeboard", 600, 56, 1, ("flat",))]
    props += [("bookcase_tall", 486, 152, 0, ("ink:50x78",)),
              ("bookcase_tall", 560, 152, 1, ("ink:50x78",)),
              ("bookcase_tall", 634, 152, 2, ("ink:50x78",)),
              ("step_ladder", 690, 150, 0, ("ink:24x38",)),
              ("plant_potted", 442, 186, 7, ()),
              ("bin", 690, 188, 11, ())]
    # Study: a librarian's desk, a lectern, and quiet seating.
    props += [("painting_framed", 500, 250, 16, ("flat",)),
              ("clock", 600, 246, 0, ("flat",)),
              ("poster", 646, 250, 3, ("flat",))]
    props += [("desk_librarian_composite", 470, 330, 0, ()),
              ("lectern_with_book", 540, 328, 0, ("ink:34x58",)),
              ("armchair", 620, 330, 2, ("ink:40x46", "facing:down")),
              ("table_wood", 682, 360, 0, ("ink:32x40",)),
              ("lamp_floor", 676, 290, 0, ("ink:26x68",)),
              ("rug_patterned", 600, 384, 2, ("ground", "ink:58x32")),
              ("plant_potted", 448, 380, 9, ()),
              ("bin", 560, 380, 7, ())]
    people = [("17", "idle", "up", 180, 340), ("07", "idle", "down", 200, 200),
              ("09", "idle", "up", 560, 190), ("19", "idle", "left", 350, 320),
              ("10", "idle", "down", 470, 372), ("06", "walk", "right", 420, 300)]
    return {"name": "04-library", "rooms": rooms, "props": props,
            "people": people}


SCENES = [engineering, museum, hospital, library]


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else \
        "/Users/henrykanaskie/.claude/jobs/6d016a50/tmp/scenes-v2"
    os.makedirs(out_dir, exist_ok=True)
    _cut_tiles()
    by_name = load_index()
    for build in SCENES:
        spec = build()
        path = os.path.join(out_dir, spec["name"] + ".png")
        print(spec["name"])
        compose(spec, by_name, path)
    print("\n%d scenes -> %s" % (len(SCENES), out_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
