#!/usr/bin/env python3
"""Render a themed room at 1x, at the real panel size, with characters in it.

Why this exists
---------------
A theme that cannot be looked at cannot be chosen. The scene is SpriteKit and
needs a window server, so it cannot produce a picture in a headless review, and
"trust me, the bookcases read at 1x" is exactly the kind of claim that
docs/04-ART-DIRECTION.md refuses to accept about art. This composes the same
room the scene composes, from the *same manifest the scene loads*, and writes a
PNG.

That second point is the useful one beyond the pictures: everything here (tile
paths, prop paths, per-role content_box, the prop canvas, character frames) is
read out of assets/manifest.json. Nothing is hard-coded but the geometry, which
is transcribed from Sources/SpriteRoomScene/RoomLayout.swift and RoomScene.swift
and named after it. So if this renders a theme correctly, the manifest carries
enough for the scene to render it too, which is the claim the themed-room work
has to make. It is a *review tool*, not part of the build: it writes only where
it is told to and never touches assets/.

The geometry is a transcription, and transcriptions drift. It is deliberately
narrow (floor, wall, the four prop slots, seated bodies) and it does not draw
nameplates or badges, which live in an overlay band this is not trying to model.
Treat it as a picture of the room, not as a second implementation of the scene.

**`--verify` is what stops that sentence being an excuse.** It renders the real
`RoomScene` through the real `SKRenderer` (`spriteroom --render`, offscreen, no
window server) and compares the two pictures pixel for pixel. It exists because
this transcription has been wrong twice (M6b's `prop_origin` mirrored a y-up
anchor into a y-down blit, and M6e's placement census counted a foreground row
the scene had stopped drawing) and both times the only thing checking it was
*itself*: a census compared against a `render()` transcribing the same layout.
A transcription checked against a transcription is not a check. See "Verifying
against the scene" below the code, and docs/04-ART-DIRECTION.md.

Usage
-----
    preview-theme.py --out DIR                 # every theme in the manifest
    preview-theme.py --out DIR --theme library
    preview-theme.py --out DIR --population 3
    preview-theme.py --out DIR --state working --badge sleep
    preview-theme.py --out DIR --theme library --frames        # every frame
    preview-theme.py --out DIR --animated old_tv --frames      # a candidate
    preview-theme.py --out DIR --size 1600x900                 # a wider panel
    preview-theme.py --verify --out DIR        # against the real scene; exits 1

Python 3 stdlib only.
"""

import argparse
import glob
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO, "assets", "manifest.json")

_MANIFEST_JSON = None


def manifest_json():
    """The manifest, loaded once. `seated_head` measures the cast off it."""
    global _MANIFEST_JSON
    if _MANIFEST_JSON is None:
        with open(MANIFEST) as fh:
            _MANIFEST_JSON = json.load(fh)
    return _MANIFEST_JSON


# The real panel. docs/04-ART-DIRECTION.md and the notch geometry: the drop-down
# is 720x400, and 1x is the only scale a normal room uses now that the camera
# draws the room wide at every population (commit 004b587).
PANEL_W, PANEL_H = 720, 400
SCALE = 1

# Transcribed from RoomLayout.swift. Names match the Swift so a drift is
# findable by grep rather than by memory.
TILE = 32
SEAT_CAPACITY = 7
SEAT_SPACING_TILES = 3
COLUMNS = SEAT_CAPACITY * SEAT_SPACING_TILES + 4      # 25
ROWS = 9
WALL_ROWS = 2
FLOOR_ROWS = ROWS - WALL_ROWS                          # 7
WIDTH = COLUMNS * TILE                                 # 800
HEIGHT = ROWS * TILE                                   # 288
BASELINE_Y = TILE * 2                                  # 64
AISLE_Y = BASELINE_Y - TILE                            # 32
WALL_BASE_Y = FLOOR_ROWS * TILE                        # 224
OVERSCAN_ROWS = 6
DRAWN_ROWS = range(-OVERSCAN_ROWS, ROWS + OVERSCAN_ROWS)
DRAWN_COLUMNS = range(-8, COLUMNS + 9)

# The decoration bands draw one prop per seat pitch, so consecutive copies of
# one role are two pitches apart and consecutive props of *any* role one pitch.
# A board whose content is wider than a pitch overlaps its own neighbours and
# clips them, which is not a thing you can see in a manifest: it is only
# visible once four copies are on screen. M6c hit it with a 120px monitor wall.
# Every shipping board is 30-64 px.
BACK_ROW_PITCH = SEAT_SPACING_TILES * TILE                 # 96

# RoomLayout.swift: seats sit on two rows a character's height apart, chosen by
# the parity of the seat's ring, and the two decoration bands stand upstage of
# both: accents a tile behind the back row, backdrops against the wall.
SEAT_ROW_DEPTH_TILES = 2
BACK_SEAT_ROW_Y = BASELINE_Y + TILE * SEAT_ROW_DEPTH_TILES   # 128
ACCENT_ROW_Y = BACK_SEAT_ROW_Y + TILE                        # 160
BACKDROP_ROW_Y = WALL_BASE_Y                                 # 224
PLATE_DROP_BELOW_FEET = 20
CONTENT_BAND_BOTTOM = AISLE_Y - PLATE_DROP_BELOW_FEET  # 12

CHAR_H = 64
# How far above its own feet the *shortest* cast variant's head starts:
# `characters.canvas.height - max(head_top_px)` over the manifest, asserted as 44
# by `StationContractTests.everyStationFitsTheSeatItIsDrawnAt`. It is the line
# `RoomScene.surfaceDepthBias` resolves a desk's depth against; see
# `desk_depth_bias`.
SHORTEST_HEAD = 44
# The direction the seated pose is drawn in. `RoomLayout.seatedFacing`.
SEATED_FACING = "right"
VOID = (18, 18, 22, 255)
# `RoomScene.voidColour` as 8-bit sRGB: SKColor(0.14, 0.13, 0.17) truncated.
VOID_ROOM = (35, 33, 43, 255)


def load(path):
    return pnglite.load(os.path.join(REPO, path))


def blit(dst, dw, dh, src, sw, sh, x0, y0):
    """Alpha-over, clipped to the destination."""
    for y in range(sh):
        dy = y0 + y
        if dy < 0 or dy >= dh:
            continue
        for x in range(sw):
            dx = x0 + x
            if dx < 0 or dx >= dw:
                continue
            si = (y * sw + x) * 4
            a = src[si + 3]
            if a == 0:
                continue
            di = (dy * dw + dx) * 4
            if a == 255:
                dst[di:di + 4] = src[si:si + 4]
            else:
                for c in range(3):
                    dst[di + c] = (src[si + c] * a + dst[di + c] * (255 - a)) // 255
                dst[di + 3] = 255


def seat_column(index):
    wrapped = index % SEAT_CAPACITY
    step = (wrapped + 1) // 2
    sign = -1 if wrapped % 2 == 0 else 1
    return COLUMNS // 2 + sign * step * SEAT_SPACING_TILES


def seat_x(index):
    return seat_column(index) * TILE + TILE // 2


def seat_ring(index):
    wrapped = index % SEAT_CAPACITY
    return (wrapped + 1) // 2


def seat_y(index):
    """Which of the two seat rows this seat is on: its ring's parity.

    `RoomLayout.isBackRow(seat:)`. Ring parity along x is perfect alternation,
    so this puts the occupied columns in a checkerboard without moving any of
    them, which is why every clearance argument in the layout survives it.
    """
    return BACK_SEAT_ROW_Y if seat_ring(index) % 2 else BASELINE_Y


SCENERY_COLUMNS = sorted(
    x for x in
    [min(seat_x(s) for s in range(SEAT_CAPACITY)) - TILE * 1.5]
    + [seat_x(s) + TILE * 1.5 for s in range(SEAT_CAPACITY)]
    if 0 < x < WIDTH)
OVERFLOW_PLATE_X = seat_x(0) + TILE * 1.5


# `RoomLayout.decorationColumns`: the seven prop columns, alternating backdrop
# (on the wall line) and accent (a tile behind the back seat row) along x.
DECORATION_COLUMNS = sorted(seat_x(s) + TILE * 1.5 for s in range(SEAT_CAPACITY))
BACKDROP_COLUMNS = [x for i, x in enumerate(DECORATION_COLUMNS) if i % 2 == 0]

# `RoomPlan`: a wall band is two tiles, of which 2 px is baseboard and 12 px is
# the floor-plan line, leaving 50 px of face. [ADR-007]
BASEBOARD_PX = 2
PLAN_LINE_PX = 12
PARTITION_PX = 14
WALL_FACE_TOP = WALL_BASE_Y + WALL_ROWS * TILE - PLAN_LINE_PX   # 276
HUNG_PROP_Y = WALL_BASE_Y + TILE // 4                           # 232
FAR_FLOOR_Y = WALL_BASE_Y + WALL_ROWS * TILE                    # 288


def plan_of(theme):
    """The theme's floor **plan**, or None for the open floor. [ADR-007]

    Strictly the drawing: spaces and the surfaces they are painted from. A plan
    that carries only `dressing` is not one of these: it draws no floor, no
    band and no partition, and the room under it is the open floor exactly as
    before. Ask `dressing_of` for that, and keep the two questions apart: the
    first draft of this admitted a dressing-only plan here, which made the
    preview skip the open-floor paint entirely and disagree with the scene by
    840,000 pixels of bare floor.
    """
    plan = theme.get("plan")
    if not plan or not plan.get("spaces") or not plan.get("surfaces"):
        return None
    return plan


def dressing_of(theme):
    """The theme's hand-placed dressing, or `[]` for one that takes the bands.

    Independent of `plan_of`: a theme may compose its room without drawing a
    floor plan [`Manifest.plan(_:)`, which admits
    `!spaces.isEmpty || !dressing.isEmpty`], and `office` does both while
    `library` and `stage` do only this.
    """
    return ((theme or {}).get("plan") or {}).get("dressing") or []


def painted_field(_plan=None):
    """`(x0, x1, y0, y1)` tile bounds of everything the room paints, inclusive.

    The overscan rectangle, with or without a plan: **a planned room paints the
    same field, it just paints most of it as surround.** `RoomScene.buildPlan`
    lays a flat quad of the scene's own background tone over the whole drawn
    range before anything else, precisely so that a plan's edge meets a
    deliberate colour rather than whatever is behind the scene: offscreen that is
    the renderer's black clear, on the panel it is the SKView's background, and a
    room whose surround changed with the host would be a room with a different
    edge in every screenshot.

    So both pictures are registered on one rectangle, and this function exists to
    say that rather than to compute it.
    """
    return (DRAWN_COLUMNS[0], DRAWN_COLUMNS[-1], DRAWN_ROWS[0], DRAWN_ROWS[-1])


def plan_doorway_columns(plan):
    out = set()
    for space in (plan.get("spaces") or []):
        out.update(space.get("doorways") or [])
    return out


def scenery_anchors(band, plan=None):
    """Transcribed from `RoomLayout.sceneryAnchors(_:)`. [M8 Phase 2b, ADR-007]

    The eight columns are the gaps between the seat columns, which are the only
    floor in this room no route ever crosses. `wall` is the exception: with no
    plan it hangs two tiles up the wall face, above the line where a leaver's
    feet stop, so it may use the seat columns and is behind everything.

    **Under a plan the two upper bands move**, and they move onto the two things
    a plan gives the room that an open floor has not got: a wall you can see the
    face of, and a strip of floor behind it. A picture hangs on the face, clear
    of the doorways and of anything standing in front of it; the tall floor props
    stand on the far room's floor line instead of poking out of the top of the
    near wall. The two lower bands are unmoved.
    """
    if band == "wall":
        if not plan:
            return [(x, WALL_BASE_Y + TILE * 2)
                    for x in sorted(seat_x(s) for s in range(SEAT_CAPACITY))]
        doorways = plan_doorway_columns(plan)
        blocked = set(BACKDROP_COLUMNS) | {OVERFLOW_PLATE_X}
        xs = [float(seat_x(s)) for s in range(SEAT_CAPACITY)] + list(SCENERY_COLUMNS)
        return [(x, HUNG_PROP_Y) for x in sorted(xs)
                if x not in blocked
                and int(round(x - TILE / 2.0)) // TILE not in doorways]
    if band == "wall_line":
        y = FAR_FLOOR_Y if plan else WALL_BASE_Y
        return [(x, y) for i, x in enumerate(SCENERY_COLUMNS)
                if i % 2 == 0 and x != OVERFLOW_PLATE_X]
    if band == "back_floor":
        return [(x, WALL_BASE_Y - TILE) for i, x in enumerate(SCENERY_COLUMNS)
                if i == 0 or i % 2]
    if band == "mid_floor":
        return [(x, BACK_SEAT_ROW_Y + TILE) for i, x in enumerate(SCENERY_COLUMNS)
                if i == 0 or i % 2]
    return []


SCENERY_BANDS = ("wall", "wall_line", "back_floor", "mid_floor")


def scenery_layout(theme):
    """`(prop, x, y)` for every piece of a theme's scenery, in the order the
    scene draws it.

    Kept out of `prop_layout()` on purpose. That function is what
    `role_placements()` counts, and the census exists for one thing only: the
    motion budget, which prices a *role* by the copies of it on the panel.
    Scenery may not animate at all (`scripts/lint-palette.py` fails a manifest
    where it does), so it has no place in that count and folding it in would
    make the budget's own table harder to read for nothing.
    """
    declared = theme.get("props", {}).get("scenery", []) or []
    plan = plan_of(theme)
    placed = []
    # **A plan that places its dressing by hand states every point**, and then
    # the four bands do not run at all; `RoomScene.buildRoom` makes the same
    # all-or-nothing choice on the same condition. The role-typed entries in the
    # list are `prop_layout`'s, not this function's; the two split the list on
    # the same key the scene does.
    dressing = dressing_of(theme)
    if dressing:
        for item in dressing:
            index = item.get("scenery")
            if index is None or not (0 <= index < len(declared)):
                continue
            placed.append((declared[index], float(item["x"]), float(item["y"])))
        return placed
    for band in SCENERY_BANDS:
        props = [e for e in declared if e.get("band") == band]
        if not props:
            continue
        for i, (x, y) in enumerate(scenery_anchors(band, plan)):
            placed.append((props[i % len(props)], x, y))
    return placed


def _neck_row(w, h, px):
    """`SeatedHead.neckRow(of:)`. The first row of the sprite that is not head."""
    counts = []
    for y in range(h):
        counts.append(sum(1 for x in range(w) if px[(y * w + x) * 4 + 3] > 0))
    inked = [y for y in range(h) if counts[y] > 0]
    if not inked:
        return None
    last_ink = inked[-1]
    widest = max(counts)
    if widest <= 0:
        return None
    last_widest = max(y for y in range(h) if counts[y] == widest)
    if last_widest >= last_ink:
        return last_ink + 1
    row = last_widest
    while row + 1 <= last_ink and counts[row + 1] <= counts[row]:
        row += 1
    narrowest = counts[row]
    while row - 1 > last_widest and counts[row - 1] == narrowest:
        row -= 1
    return row


_SEATED_HEAD = None


def seated_head(manifest):
    """`SeatedHead` ported: `(canvas_w, canvas_h, suffix_clearance)` or None.

    How tall a surface standing at a given near edge may be before it covers a
    head pixel, measured over every seated frame of every cast variant: the
    same measurement `RoomScene.seatedHeadMeasurement` takes, off the same art.

    **It is ported rather than approximated, because approximating it is what
    was wrong here.** This file used to answer the desk's depth with
    `height > 44`, a single number standing in for the shortest head; the scene
    has answered it two-dimensionally since M7e, because a desk is centred seven
    eighths of a tile to the character's right and a *wider* desk therefore
    reaches *further left* across the body. The same 36 px desk clears every
    head at `+12` and covers six of them at `+8`. `mission_control`'s 40x36
    equipment table is exactly that case, and the two files disagreed about it
    at every one of the seven seats (392 px) with nothing failing, because
    `spriteroom_binary()` was resolving to a `.build/release/spriteroom` older
    than the fix.
    """
    global _SEATED_HEAD
    if _SEATED_HEAD is not None:
        return _SEATED_HEAD or None
    variants = manifest.get("characters", {}).get("variants", {})
    per_column, pixels, measured, size = None, 0, 0, None
    for name in sorted(variants):
        state = variants[name].get("states", {}).get("working", {})
        for path in state.get("frames", {}).get(SEATED_FACING, []) or []:
            w, h, px = load(path)
            if size is None:
                size = (w, h)
                per_column = [None] * w
            elif (w, h) != size:
                continue
            neck = _neck_row(w, h, px)
            if neck is None:
                continue
            measured += 1
            for y in range(min(neck, h)):
                for x in range(w):
                    if px[(y * w + x) * 4 + 3] > 0:
                        pixels += 1
                        below = h - 1 - y
                        if per_column[x] is None or below < per_column[x]:
                            per_column[x] = below
    if not measured or not pixels or size is None:
        _SEATED_HEAD = False
        return None
    w, h = size
    suffix = list(per_column)
    for i in range(w - 2, -1, -1):
        if suffix[i + 1] is not None and (suffix[i] is None or suffix[i + 1] < suffix[i]):
            suffix[i] = suffix[i + 1]
    _SEATED_HEAD = (w, h, suffix)
    return _SEATED_HEAD


def seated_head_clearance(manifest, near_edge_x):
    """`SeatedHead.clearance(nearEdgeX:)`. 0 when nothing could be measured:
    a clearance we cannot measure is not a clearance we may assume."""
    head = seated_head(manifest)
    if head is None:
        return 0
    w, h, suffix = head
    column = int(math.floor(near_edge_x + w / 2.0))
    if column < 0:
        return suffix[0] if suffix[0] is not None else h
    if column >= w:
        return h
    return suffix[column] if suffix[column] is not None else h


def desk_depth_bias(desk_height, near_edge_x=None, manifest=None):
    """Transcribed from `RoomScene.surfaceDepthBias(deskHeight:headClearance:)`.

    A desk short enough to sit at is drawn **in front of** the body: at 32 px the
    only cue that a character is sitting *at* a desk rather than beside one is
    whether the desk's near edge crosses it. A desk taller than the head
    clearance at its own near edge goes **behind** the body and behind the chair
    instead, because at that height the near-edge cue is not weakened but moot:
    a desk that covers the whole body including the face, in a room whose
    characters are the subject.

    `None` means "this theme declares no desk", which is the placeholder path;
    the placeholder is 26 px tall and therefore always the in-front case. With
    no manifest to measure the cast from, the old constant is the fallback.
    """
    if desk_height is None:
        return 0.5
    if manifest is not None and near_edge_x is not None:
        clearance = seated_head_clearance(manifest, near_edge_x)
    else:
        clearance = SHORTEST_HEAD
    return -0.5 if desk_height > clearance else 0.5


# **Which way each seat faces, and what that brings with it.** [ADR-008]
# Transcribed from `RoomLayout.SeatFacing` and `RoomLayout.seatFacing(_:)`: the
# back row faces away from the camera because it is the only row with the 30 px
# of clear floor its chair needs, and the front row faces the camera.
# **No seat draws a chair.** `RoomLayout.SeatFacing.seatRole` measures why: a
# chair under an occupant has to clear the head band at feet +22
# (`SeatedHeadOcclusionTests`) and stay above the nameplate at feet -13
# (`RoomScene.seatedPlateDrop`), which leaves 36 px, and `chair_back` is 46. Ten
# px too tall and no standoff exists. `side_on` keeps its entry because the rule
# is about the art and not about the facing (a suite with a back view under
# 36 px would bring the chair straight back) but the shipped lattice has no
# side-on seat, so in practice this map is empty.
SEAT_ROLE = {"toward_camera": None, "away_from_camera": None,
             "side_on": "chair"}
# How far above the feet a costume's ink reaches, and how far the top edge of an
# away-facing chair is allowed inside that band. `RoomLayout.awayChairStandoff`.
COLLAR_ROWS_ABOVE_CHAIR = 6
# Which row of the body a camera-facing desk's top edge lands on.
# `RoomLayout.deskCutAboveFeet`.
DESK_CUT_ABOVE_FEET = 12
# How far upstage of the feet an away-facing seat's desk stands.
# `RoomLayout.awayDeskUpstage`.
AWAY_DESK_UPSTAGE = TILE / 4


def seat_facing(index):
    """`RoomLayout.seatFacing(_:)`."""
    return "away_from_camera" if seat_ring(index) % 2 else "toward_camera"


def away_chair_standoff(chair_height, costume_top):
    """`RoomLayout.awayChairStandoff(metrics:)`: 30 px for the shipped art."""
    return max(0.0, chair_height - costume_top + COLLAR_ROWS_ABOVE_CHAIR)


def chair_y(index, chair_height, costume_top):
    """Where this seat's chair stands, or its own row when it is side-on."""
    if seat_facing(index) == "away_from_camera":
        return seat_y(index) - away_chair_standoff(chair_height, costume_top)
    return seat_y(index)


# **The desk pod.** [ADR-009] `RoomLayout.monitorScreenClearance`: how far above
# the desk's own back edge a screen rig's top has to reach, which is what fixes
# where a prop standing on a pod's desktop puts its feet.
MONITOR_SCREEN_CLEARANCE = 20


def is_desk_pod(metrics):
    """`RoomLayout.SeatMetrics.isDeskPod`: a slab wide enough for a rig either
    side of its occupant, and a theme that binds one. False for five of six."""
    _dh, _ch, _ct, desk_w, mon_w, mon_h = metrics
    return mon_w > 0 and mon_h > 0 and desk_w >= mon_w * 2


def desk_top_lift(surface_y, metrics):
    """`RoomLayout.deskTopLift(surfaceHeightAboveFloor:metrics:)`.

    `surface_y` finds the *back* edge of a slab whose top surface is 25 rows
    deep, so a pod derives the lift from its own two heights instead: 38 + 20 -
    42 = 16 for the shipped office pod.
    """
    if not is_desk_pod(metrics):
        return surface_y
    desk_h, _ch, _ct, _dw, _mw, mon_h = metrics
    return min(max(0.0, desk_h + MONITOR_SCREEN_CLEARANCE - mon_h), desk_h)


def pod_slot_offset_x(metrics):
    """`RoomLayout.podSlotOffsetX(metrics:)`: 16 px for the shipped pod."""
    if not is_desk_pod(metrics):
        return 0.0
    _dh, _ch, _ct, desk_w, mon_w, _mh = metrics
    return (desk_w - mon_w) / 2.0


def away_desk_offset_x(metrics):
    """`RoomLayout.awayDeskOffsetX(metrics:)`: 0 for a pod, seven eighths of a
    tile for every desk narrow enough that its occupant cannot be centred on it."""
    return 0.0 if is_desk_pod(metrics) else TILE * 0.875


def desk_point(index, metrics):
    """`RoomLayout.deskPosition(_:metrics:)`."""
    facing = seat_facing(index)
    desk_height = metrics[0]
    if facing == "toward_camera":
        return (seat_x(index),
                seat_y(index) - max(0.0, desk_height - 1 - DESK_CUT_ABOVE_FEET))
    if facing == "away_from_camera":
        return (seat_x(index) + away_desk_offset_x(metrics),
                seat_y(index) + AWAY_DESK_UPSTAGE)
    return (seat_x(index) + TILE * 0.875, seat_y(index))


def seat_metrics(theme=None):
    """**The measured art the seat furniture is placed against**, for one theme.

    `RoomScene.seatMetrics(desk:)` in this file's terms, in `SeatMetrics`' own
    field order: the desk's ink height, the back chair's ink height, how far
    above the feet a costume reaches, the desk's ink width, and the screen rig's
    ink width and height. A theme that binds no back chair simply has none to
    stand, and one that binds no `monitor` is not a pod, which is the same
    answer the scene gives in both cases. [ADR-008, ADR-009]
    """
    roles = (theme or {}).get("props", {}).get("roles", {}) if theme else {}
    if not roles:
        roles = manifest_json().get("room", {}).get("props", {}).get("roles", {})
    costumes = manifest_json().get("characters", {}).get("costumes", {})

    def box(role, axis):
        entry = roles.get(role)
        return float(entry["content_box"][axis]) if entry else 0.0

    return (box("desk", "h"), box("chair_back", "h"),
            float(costumes.get("ink_top_px", 0)),
            box("desk", "w"), box("monitor", "w"), box("monitor", "h"))


def default_seat_metrics():
    """The shipped room's metrics: the manifest's own default theme.

    `role_placements()` needs them, because how many rigs the room draws is a
    property of the theme's art now rather than of the layout alone.
    """
    manifest = manifest_json()
    name = manifest.get("themes", {}).get("default")
    theme = manifest.get("themes", {}).get("sets", {}).get(name)
    return seat_metrics(theme)


def prop_layout(metrics=None, desk_near_edge_x=None, manifest=None, dressing=None,
                roles=None):
    """**Every prop the room draws, once, as `(role, x, y, depth_bias)`.**

    Scene coordinates, y-up, the point being the content box's bottom-centre.
    Transcribed from `RoomScene.furnish()`; ordered the way that function draws,
    so a reader can hold the two side by side.

    This is the *only* copy of the placement arithmetic in this file.
    `role_placements()` counts it and `render()` draws it, so those two can no
    longer drift apart, and that means the census cross-check inside `render()`
    is now a tautology rather than a check. It is kept for the one thing it can
    still catch (a `render()` that stops drawing something it enumerated) and it
    is **not** what ties this file to the scene. `--verify` is. See below.

    **Why one copy matters here specifically.** At M6e `role_placements()` was
    found counting a foreground row of seven plants that `4e7b43d` had removed
    from the scene two commits earlier, and it survived because the cross-check
    compared it against a `render()` that transcribed the *same* dead layout.
    Two agreeing transcriptions of a room that does not exist is what this
    collapse removes; comparing the result against the real renderer is what
    replaces it.

    Consequence of that error, recorded rather than quietly corrected: the
    motion budget was **3.3x too strict on `plant`**, and ADR-002 §14b's
    argument that `board` is the only role that can carry motion was priced on
    the demolished row. `plant` is in fact the *cheaper* slot. The budget is the
    rule; the role is not.
    """
    placed = []
    # Two decoration bands upstage of both seat rows, alternating along x:
    # backdrops against the wall, accents a tile behind the back seat row.
    # Alternating on x rather than on seat index is what stopped all four
    # backdrops landing in the left half of the room and all three accents in
    # the right: seats fill outward in pairs, so `seat % 2` is *which side*.
    # The counts are unchanged by the reordering (board 4, plant 3), which is
    # the constraint this placement was designed against: the motion budget is
    # priced per copy. [ADR-002 §14b]
    # Under a hand-placed plan the boards and plants are in the dressing list
    # with everything else, so this lattice is skipped exactly as the scene
    # skips it. The census the motion budget reads therefore counts the copies
    # the panel actually draws, which is the only reason it is a census.
    dressing = [d for d in (dressing or []) if d.get("role")]
    if dressing:
        for item in dressing:
            placed.append((item["role"], float(item["x"]), float(item["y"]), 0.0, 0))
    else:
        columns = sorted(
            x for x in (seat_column(s) * TILE + TILE // 2 + TILE * 1.5
                        for s in range(SEAT_CAPACITY))
            if x < WIDTH)
        for index, x in enumerate(columns):
            backdrop = index % 2 == 0
            placed.append(("board" if backdrop else "plant", x,
                           BACKDROP_ROW_Y if backdrop else ACCENT_ROW_Y, 0.0, 0))
    # No foreground row. `4e7b43d` removed it from the scene and replaced it
    # with a stronger rule than the one it lost: nothing decorative is drawn
    # nearer the camera than the seat row. This preview drew seven plants that
    # did not exist for two commits, which is why every theme picture between
    # `4e7b43d` and M6e shows them.
    #
    # **A chair at every seat that has one, in the view its facing needs, and a
    # desk wherever that facing puts it.** [ADR-008]
    #
    # Transcribed from `RoomLayout.chairPosition(_:metrics:)` and
    # `deskPosition(_:metrics:)`:
    #
    #   * a **side-on** seat keeps what it always had: the chair on the seat's
    #     own point a hair behind the body, the desk seven eighths of a tile to
    #     the right on the same row, taking the row depth plus a half so its
    #     near edge crosses the body;
    #   * an **away-facing** seat puts the back view of the chair a whole
    #     standoff *downstage* of the body and its desk a quarter tile upstage;
    #   * a **camera-facing** seat has no chair at all and its desk stands
    #     downstage, deep enough that its top edge lands on the body's waist.
    #
    # Neither turned case takes a depth bias: the furniture is genuinely on a
    # different row from its occupant, so the row sorts it and there is no tie
    # to break. `desk_depth_bias` is the side-on tie-breaker and only that.
    metrics = metrics or (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    desk_height, chair_height, costume_top = metrics[0], metrics[1], metrics[2]
    bias = desk_depth_bias(desk_height or None, desk_near_edge_x, manifest)
    for seat in range(SEAT_CAPACITY):
        facing = seat_facing(seat)
        role = SEAT_ROLE[facing]
        if role is not None:
            placed.append((role, seat_x(seat),
                           chair_y(seat, chair_height, costume_top),
                           -0.25 if facing == "side_on" else 0.0, 0))
    for seat in range(SEAT_CAPACITY):
        facing = seat_facing(seat)
        x, y = desk_point(seat, metrics)
        placed.append(("desk", x, y, bias if facing == "side_on" else 0.0, 0))
    # **The kit on the desktop.** [ADR-009] `RoomScene.podFurniture(seat:metrics:)`:
    # a screen rig at every away-facing seat and a paper stack at every
    # camera-facing one, both lifted onto the desktop and both biased by
    # `lift + 0.25` so the lift does not sort them behind the desk they stand on.
    # Nothing at all for a theme that is not a pod.
    if is_desk_pod(metrics):
        lift = desk_top_lift(desk_height, metrics)
        offset = pod_slot_offset_x(metrics)
        roles = roles or manifest_json().get("room", {}).get("props", {}).get("roles", {})
        for seat in range(SEAT_CAPACITY):
            facing = seat_facing(seat)
            x, y = desk_point(seat, metrics)
            if facing == "away_from_camera":
                # **Both slots, always.** `RoomLayout.PodRigSlot`: the `monitor`
                # role is not a monitor, it is a whole workstation carrying its
                # own desk surface, keyboard and front edge, so one of them on a
                # 64 px slab leaves the slab's own top exposed beside it and the
                # pod reads as two desks at two angles. Two tile it exactly.
                #
                # The variant is keyed `seat + slot`, so the two slots of one pod
                # never draw the same picture: `compose-scene.py`'s `desk_pod`
                # does the same with `LIT_RIGS[(3v)%4]` beside `[(3v+1)%4]`.
                # The rig keeps the pod's own lift: a screen is *meant* to clear
                # the desk's back edge, and it stands at a facing with no face in
                # front of it to cover.
                for rig, sign in ((0, -1), (1, 1)):
                    placed.append(("monitor", x + sign * offset, y + lift,
                                   lift + 0.25, seat + rig))
            elif facing == "toward_camera":
                # Four objects, not one, each on a lift derived from its own ink
                # height. The seat rotates which object stands in which slot, so
                # `slot + seat` is the variant index: build-time, keyed on the
                # seat and on nothing in the delta stream. [I1, ADR-002 SS6 rule 1]
                kit = roles.get("desk_kit")
                for slot in POD_KIT_DRAW_ORDER:
                    index = POD_KIT_SLOTS.index(slot) + seat
                    drawn_role = variant_role(kit, index)
                    if drawn_role is None:
                        continue
                    ink_h = float(drawn_role["content_box"]["h"])
                    kit_lift = desk_kit_lift(ink_h, slot, metrics)
                    if kit_lift is None:
                        continue
                    rank = 0 if _slot_is_back_row(slot) else 1
                    placed.append((
                        "desk_kit",
                        x - offset if _slot_is_left(slot) else x + offset,
                        y + kit_lift, kit_lift + 0.25 * (rank + 1), index))
    return placed


def role_placements(metrics=None, dressing=None, roles=None):
    """How many times the room draws each prop role on one panel.

    **It used to be a fact about the layout alone and it is not one any more.**
    That sentence stood here while every theme filled the same four slots; ADR-009
    gave the office theme a desk wide enough to carry a screen rig, and how many
    rigs the room draws is now a property of the *art*: four at a theme whose
    desk is a pod and none at a theme whose desk is not. So it takes the metrics
    of the room being priced, and defaults to the manifest's own default theme
    rather than to nothing, because a census of no theme in particular is the kind
    of second opinion this file exists to stop trusting.

    It exists because `scripts/lint-palette.py`'s motion budget is a budget on
    what reaches the screen, and a prop placed four times costs four times as
    much as one placed once: a quantity the manifest cannot see, because the
    manifest describes art and this is geometry. The lint imports this rather
    than transcribing the seat arithmetic a fourth time.

    The counts on the shipped 25-column layout are `board` 4, `plant` 3,
    `chair_back` 4, `desk` 7, and `chair` **0**, because ADR-008 gave the seat
    a facing: the four back-row seats take the back view of the chair, the three
    front-row seats face the camera and take no chair at all (the body covers
    one entirely), and no seat in the shipped lattice is side-on. `board` and
    `plant` alternate across the seven seats of the back row. At the office pod
    add `monitor` 4 (one per away-facing seat, in the left of its desk's two kit
    slots) and `desk_kit` 3, the paper stack a camera-facing pod carries because
    no screen has an honest rear view. The keys are always present, at zero if
    nothing is placed, so a caller cannot read a missing role as a missing count.
    """
    counts = {"board": 0, "plant": 0, "chair": 0, "chair_back": 0, "desk": 0,
              "monitor": 0, "desk_kit": 0}
    for role, _x, _y, _bias, _v in prop_layout(
            metrics if metrics is not None else default_seat_metrics(),
            dressing=dressing, roles=roles):
        counts[role] = counts.get(role, 0) + 1
    return counts


def pick_tiles(theme):
    """(floor, wall) paths for a theme.

    Prefers the tiles the theme *declares*. Falls back to the heuristic the
    scene uses today (scan for fully-opaque single-colour tiles, darkest is the
    floor and lightest the wall) so a theme with no declaration still draws,
    and so this shows what the scene would actually do with it.
    """
    b = theme.get("builder", {})
    if b.get("floor") and b.get("wall"):
        return b["floor"], b["wall"], "declared"
    flats = []
    for p in b.get("tiles", []):
        w, h, px = load(p)
        colours, opaque, total_v = set(), 0, 0.0
        for i in range(0, len(px), 4):
            if px[i + 3] <= 200:
                continue
            opaque += 1
            colours.add((px[i], px[i + 1], px[i + 2]))
            total_v += max(px[i], px[i + 1], px[i + 2]) / 255.0
        if opaque == w * h and len(colours) == 1:
            flats.append((total_v / opaque, p))
    if not flats:
        first = b.get("tiles", [None])[0]
        return first, first, "fallback"
    flats.sort()
    return flats[0][1], flats[-1][1], "heuristic"


# **The four desktop slots of a camera-facing pod.** [ADR-009]
# `RoomLayout.PodKitSlot`, transcribed: declaration order is the raw value the
# variant index is offset by, `drawOrder` puts the back row first, and `isLeft`
# / `isBackRow` are the two facts the position and the lift are derived from.
POD_KIT_SLOTS = ("back_right", "back_left", "front_left", "front_right")
POD_KIT_DRAW_ORDER = ("back_right", "back_left", "front_left", "front_right")


def _slot_is_left(slot):
    return slot in ("back_left", "front_left")


def _slot_is_back_row(slot):
    return slot in ("back_left", "back_right")


def desk_kit_lift(ink_h, slot, metrics):
    """`RoomLayout.deskKitLift(inkHeight:slot:metrics:)`.

    Back row `H - h`, so the object's top lands exactly on the desk's back edge;
    front row half that, so its top lands on the desktop's mid-line. Either way
    every pixel is inside the band the desk already covers, which is the whole
    of "it cannot cover a face": for any object no taller than the desk, and
    `None` for one that is, which has no lift that satisfies the bound.
    """
    desk_h = metrics[0]
    if ink_h <= 0 or ink_h > desk_h:
        return None
    on_back_edge = desk_h - ink_h
    return on_back_edge if _slot_is_back_row(slot) else on_back_edge / 2.0


_ink_boxes = {}


def ink_box(path):
    """`TextureStore.inkBox(path:)`: the opaque bounding box of one PNG.

    The manifest declares **one** `content_box` per role and the `desk_kit`
    variants are not co-registered in their canvases: four boxes sharing no
    edge. Placing a variant against the role's box puts the mug 20 px in the
    air, so the box is measured off the file exactly as the scene measures it.
    Alpha `> 0`, matching `TextureStore.inkBox(of:)` rather than this file's own
    `ALPHA_FLOOR`, because that is the function being transcribed.
    """
    if path in _ink_boxes:
        return _ink_boxes[path]
    w, h, px = pnglite.load(os.path.join(REPO, path))
    min_x, min_y, max_x, max_y = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if px[(y * w + x) * 4 + 3] > 0:
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
    box = None if max_x < min_x or max_y < min_y else {
        "x": min_x, "y": min_y, "w": max_x - min_x + 1, "h": max_y - min_y + 1}
    _ink_boxes[path] = box
    return box


def variant_role(role, index):
    """`RoomScene.variantProp(_:_:)`: a role drawn with entry `index` of its
    `variants`, carrying that file's own measured ink box.

    Entry 0 is the role itself, declared box included, so a role with no
    `variants` and a request for entry 0 both return the role untouched.
    """
    variants = (role or {}).get("variants") or []
    if not role or len(variants) < 2:
        return role
    path = variants[index % len(variants)]
    if path == role["file"]:
        return role
    box = ink_box(path)
    if box is None:
        return role
    out = dict(role)
    out["file"] = path
    out["content_box"] = box
    out.pop("animation", None)
    return out


def prop_origin(role, canvas, x, y):
    """Scene-space top-left of a prop whose content box's bottom-centre is (x, y).

    The whole reason content_box is in the manifest: the singles are not
    bottom-aligned in their canvas, so the canvas cannot place them.

    **Corrected at M6b: this was mirrored, and it silently misplaced every prop
    in every theme.** The old expression was `y + (canvas.h - 1 - bottom_row)`,
    which is the y-*up* offset from the canvas's bottom edge to the content
    bottom: the right quantity for SpriteKit's anchorPoint, and it is what
    Manifest.swift's `anchor(inCanvas:)` correctly computes. But this function
    does not return an anchor: it returns the scene y of the image's TOP row,
    which `to_screen` then converts and `blit` fills downwards from. Those two
    offsets are measured from opposite ends of the canvas, so they agree only
    for a prop whose content bottom sits exactly halfway down it (row 47.5 of
    96) and disagree by twice the difference otherwise.

    The error was up to ~80 px at 1x: the chairs and desks in every theme
    preview were drawn most of a tile-and-a-half below the character sitting on
    them, and the room read as furniture floating in the foreground. It was
    invisible as a bug because every prop was wrong *in proportion to how low
    its art sits in its own canvas*, so the picture stayed internally plausible.
    The scene was never affected.

    **Corrected again at M6g: M6b's repair left one pixel of itself behind.**
    M6b fixed which *end of the canvas* the offset is measured from and stopped
    there; it did not ask which *side of the placement line* the content box's
    bottom row falls on. `top = y + bottom_row` puts that row on the panel row
    whose scene band is [y-1, y], one pixel *into* the floor. SpriteKit's
    `anchor(inCanvas:)` puts it on [y, y+1], standing *on* the line, which is
    what `--verify` measured against the real renderer: every prop, every theme,
    all 21 copies, exactly one row low. The `+ 1` is that row.

    Derivation, so the next person does not have to redo it. `to_screen` maps
    scene y to panel row `origin_y - y`, and `blit` fills *downwards* from that
    row, so image row `r` of a canvas whose top is at scene `top` lands on panel
    row `(origin_y - top) + r`. The content box's bottom row must land on the
    last panel row *above* the line, which is `origin_y - y - 1`. Therefore
    `(origin_y - top) + bottom_row = origin_y - y - 1`, i.e.
    `top = y + bottom_row + 1`. The third time this function has been wrong
    about y, and the first time something other than another copy of itself
    said so.
    """
    box = role["content_box"]
    left = x - (box["x"] + box["w"] / 2.0)
    bottom_row = box["y"] + box["h"] - 1
    top = y + bottom_row + 1
    return left, top


# Animated props are in the manifest as of M6c: a role may carry an `animation`
# object beside `file`, and `file` is frame 0. So the normal path here reads
# them out of assets/manifest.json like everything else, and `--frame`/`--frames`
# only choose which frame of the loop to draw.
#
# `--animated <id>` remains, and it is the review path for an object that has
# NOT been adopted. It stands any directory under assets/processed/animated/ in
# the `board` slot of whatever theme is being drawn, measuring its content box
# here the same way scripts/build-manifest.py measures an adopted one. That is
# how a candidate gets looked at in the room before it is written down, which is
# the rule this whole tool exists to serve.
ANIMATED_ROOT = os.path.join(REPO, "assets", "processed", "animated", "32x32")


def union_content_box(paths):
    """Tight box of the opaque pixels over every frame. Same measure as the
    manifest's, so a candidate and an adopted prop are judged identically."""
    x0, y0, x1, y1 = None, None, -1, -1
    for p in paths:
        w, h, px = load(p)
        for y in range(h):
            for x in range(w):
                if px[(y * w + x) * 4 + 3] <= 127:
                    continue
                x0 = x if x0 is None else min(x0, x)
                y0 = y if y0 is None else min(y0, y)
                x1, y1 = max(x1, x), max(y1, y)
    if x0 is None:
        return None
    return {"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1}


def animated_override(name):
    """A role-shaped dict for an animated object the manifest has not adopted."""
    d = os.path.join(ANIMATED_ROOT, name)
    if not os.path.isdir(d):
        return None
    paths = [os.path.join("assets", "processed", "animated", "32x32", name, f)
             for f in sorted(os.listdir(d)) if f.endswith(".png")]
    if not paths:
        return None
    box = union_content_box(paths)
    if box is None:
        return None
    return {"file": paths[0], "content_box": box,
            "animation": {"frames": paths, "fps": 0, "loop": True}}


def role_frames(role):
    """Every frame a role draws: one for a still prop, N for an animated one.

    `file` first and always correct is the whole point of the `animation` key's
    shape, so this reads `file` and treats `animation.frames` as an override
    rather than the other way round.
    """
    if not role:
        return []
    frames = (role.get("animation") or {}).get("frames")
    return list(frames) if frames else [role["file"]]


def camera(panel_w, panel_h):
    """The preview's own panel<->scene mapping, as two functions.

    Split out of `render()` so `--verify` can convert a placement to a panel
    pixel with the *same* arithmetic the picture was drawn with rather than a
    fifth copy of it. `origin` is the panel pixel of scene (0, 0): panel x is
    `origin.x + sx` and panel y is `origin.y - sy`, which is all a y-down blit
    of a y-up scene ever is.

    Camera: 1x, centred on the room. The room is 800 px wide and the panel is
    720, so a full-width room is cropped a tile and a bit each side, which is
    what the shipped panel does at 1x. The *scene* centres on the occupied span
    instead, so the two pictures differ by a whole-picture translation; that is
    a framing choice, not a placement, and `--verify` measures it rather than
    assuming it.
    """
    cam_x, cam_y = WIDTH / 2.0, HEIGHT / 2.0
    x0 = panel_w / 2.0 - cam_x * SCALE
    y0 = panel_h / 2.0 + cam_y * SCALE

    def to_screen(sx, sy):
        """Scene (y-up) -> panel pixel (y-down)."""
        return (int(round(x0 + sx * SCALE)), int(round(y0 - sy * SCALE)))

    return to_screen, (x0, y0)


def _solid(w, h, rgba):
    px = bytearray()
    for _ in range(w * h):
        px += bytes(rgba)
    return bytes(px)


def draw_plan(buf, panel_w, panel_h, to_screen, plan):
    """`RoomScene.buildPlan(_:)`, step for step. [ADR-007]

    Transcribed, and `--verify` is what stops that being an excuse: the two
    pictures are compared pixel for pixel over the field both paint, so a jamb
    one column out or a shadow one row low is a failure here rather than a
    surprise in the panel.

    The surround comes first and covers the whole drawn range, which is what
    `RoomScene.voidColour` renders to: `SKColor(0.14, 0.13, 0.17)` truncated to
    8 bits. It is the one colour in this file that is a transcription of a Swift
    constant rather than of a measurement, and `--verify` is what keeps it
    honest.
    """
    surfaces = plan.get("surfaces") or {}
    sx, sy = to_screen(DRAWN_COLUMNS[0] * TILE, (DRAWN_ROWS[-1] + 1) * TILE)
    blit(buf, panel_w, panel_h,
         _solid(len(DRAWN_COLUMNS) * TILE, len(DRAWN_ROWS) * TILE, VOID_ROOM),
         len(DRAWN_COLUMNS) * TILE, len(DRAWN_ROWS) * TILE, sx, sy)

    def tile_at(path, column, row):
        w, h, px = load(path)
        sx, sy = to_screen(column * TILE, (row + 1) * TILE)
        blit(buf, panel_w, panel_h, px, w, h, sx, sy)

    for space in (plan.get("spaces") or []):
        surface = surfaces[space["surface"]]
        for row in range(space["y"], space["y"] + space["h"]):
            for column in range(space["x"], space["x"] + space["w"]):
                tile_at(surface["floor"], column, row)

    for space in (plan.get("spaces") or []):
        if not space.get("band", True) or space["h"] < WALL_ROWS:
            continue
        surface = surfaces[space["surface"]]
        body_row = space["y"] + space["h"] - 2
        cap_row = space["y"] + space["h"] - 1
        doorways = set(space.get("doorways") or [])
        for column in range(space["x"], space["x"] + space["w"]):
            if column in doorways:
                continue
            tile_at(surface["body"], column, body_row)
            tile_at(surface["cap"], column, cap_row)
            # The contact shadow, anchored by its TOP edge on the band's foot
            # and four rows deep: `SceneBitmaps.wallContactShadow`.
            for i, alpha in enumerate((70, 46, 26, 12)):
                sx, sy = to_screen(column * TILE, body_row * TILE - i)
                blit(buf, panel_w, panel_h, _solid(TILE, 1, (24, 24, 34, alpha)),
                     TILE, 1, sx, sy)
        edge = tuple(surface["line_edge"]) + (255,)
        for column in doorways:
            if not space["x"] <= column < space["x"] + space["w"]:
                continue
            for side in (column, column + 1):
                sx, sy = to_screen(side * TILE - 1, (body_row + WALL_ROWS) * TILE)
                blit(buf, panel_w, panel_h, _solid(2, WALL_ROWS * TILE, edge),
                     2, WALL_ROWS * TILE, sx, sy)

    for partition in plan.get("partitions") or []:
        surface = None
        for space in (plan.get("spaces") or []):
            if space["x"] <= partition["x"] < space["x"] + space["w"]:
                surface = surfaces[space["surface"]]
                break
        if surface is None:
            surface = surfaces[sorted(surfaces)[0]]
        h = partition["h"] * TILE
        edge = tuple(surface["line_edge"]) + (255,)
        fill = tuple(surface["line_fill"]) + (255,)
        px = bytearray(_solid(PARTITION_PX, h, edge))
        for y in range(2, h - 2):
            for x in range(2, PARTITION_PX - 2):
                i = (y * PARTITION_PX + x) * 4
                px[i:i + 4] = bytes(fill)
        sx, sy = to_screen(partition["x"] * TILE - PARTITION_PX // 2,
                           (partition["y"] * TILE) + h)
        blit(buf, panel_w, panel_h, bytes(px), PARTITION_PX, h, sx, sy)


def render(theme, name, population, out_path, characters, seed_variants,
           badge=None, animated=None, frame=0, panel=None):
    panel_w, panel_h = panel or (PANEL_W, PANEL_H)
    floor_p, wall_p, how = pick_tiles(theme)
    _fw, _fh, floor_px = load(floor_p)
    _ww, _wh, wall_px = load(wall_p)

    buf = bytearray(bytes(VOID) * (panel_w * panel_h))
    to_screen, _origin = camera(panel_w, panel_h)

    plan = plan_of(theme)
    if plan:
        draw_plan(buf, panel_w, panel_h, to_screen, plan)
    else:
        # Floor and wall, over the drawn range so no zoom shows the void.
        for r in DRAWN_ROWS:
            y0 = r * TILE
            src = wall_px if y0 >= WALL_BASE_Y else floor_px
            for c in DRAWN_COLUMNS:
                sx, sy = to_screen(c * TILE, y0 + TILE)
                blit(buf, panel_w, panel_h, src, TILE, TILE, sx, sy)

    canvas = theme["props"]["canvas"]
    roles = dict(theme["props"]["roles"])
    # A candidate that is not in the manifest stands in the `board` slot: the
    # standing object against the back wall, and the only one of the four whose
    # art does not also appear in the foreground row or under a character.
    if animated:
        override = animated_override(animated)
        if override is not None:
            roles["board"] = override
    board = roles.get("board")
    if board is not None and board["content_box"]["w"] > BACK_ROW_PITCH:
        print("  warning: %s board content is %d px wide against a %d px back-row "
              "pitch: its four copies overlap and clip each other"
              % (name, board["content_box"]["w"], BACK_ROW_PITCH), file=sys.stderr)

    drawn = []   # (depth, kind, payload): painter's order, matching zPosition
    census = {}  # role -> how many copies this render actually placed

    def add_prop(role_name, x, y, bias=0.0, variant=0):
        # **The variant is resolved here, not at placement.** `prop_layout()`
        # decides *which* entry a seat draws; this turns that index into a file
        # and the file's own measured ink box, exactly as
        # `RoomScene.variantProp(_:_:)` does. The census still counts the role,
        # because a variant is the same role drawn from different stock.
        role = variant_role(roles.get(role_name), variant)
        if role is None:
            return
        frames = role_frames(role)
        left, top = prop_origin(role, canvas, x, y)
        census[role_name] = census.get(role_name, 0) + 1
        # `y - bias`, not `y + bias`. See the sort below.
        drawn.append((y - bias, "prop", (frames[frame % len(frames)], left, top)))

    # One placement list, drawn here and counted by `role_placements()`. The
    # desk's depth is a function of *this theme's* desk, so the height goes in
    # rather than the bias being a constant; see `desk_depth_bias`.
    desk = roles.get("desk")
    # The near edge is where the layout puts this desk, not a property of its
    # box: the desk is centred `TILE * 0.875` to the character's right and
    # anchored on its own content box, so a wider desk reaches further left
    # across the body. `RoomScene.surfaceNearEdgeX(of:layout:)`.
    near_edge = (TILE * 0.875 - desk["content_box"]["w"] / 2.0) if desk else None
    metrics = seat_metrics(theme)
    for role_name, x, y, bias, variant in prop_layout(
            metrics, near_edge, manifest_json(), dressing_of(theme), roles):
        add_prop(role_name, x, y, bias=bias, variant=variant)

    # The scenery, drawn from `scenery_layout()` and deliberately not counted:
    # see that function for why it stays out of the census.
    for entry, x, y in scenery_layout(theme):
        left, top = prop_origin(entry, canvas, x, y)
        drawn.append((y, "prop", (entry["file"], left, top)))

    # A body at the occupied seats. Depth sorting puts it between its chair and
    # its desk, which is what the biases in `prop_layout()` are for.
    for seat in range(population):
        variant = seed_variants[seat % len(seed_variants)]
        drawn.append((seat_y(seat), "char",
                      (characters[(variant, seat_facing(seat))],
                       seat_x(seat), seat_y(seat))))

    # What was placed must match what `role_placements()` says is placed, because
    # the lint's motion budget multiplies a prop's own motion by that count and
    # never renders anything.
    #
    # **This is no longer the check it used to be, and saying so is the point.**
    # Both sides now read `prop_layout()`, so they cannot disagree about the
    # room; all this can still catch is a drawing loop that drops or duplicates
    # a placement it was handed. Until M6e the two sides were separate
    # transcriptions and this comparison was believed to be the tie between the
    # budget and the picture: it was not, because both transcribed a foreground
    # row the scene had already demolished, and they agreed with each other and
    # with nothing the scene draws. `--verify` is the tie now. Only roles this
    # theme actually declares are compared: a theme missing a role draws none
    # of it, which is not a drift.
    expected = role_placements(metrics, dressing_of(theme), roles)
    for role_name, n in sorted(census.items()):
        if expected.get(role_name) != n:
            raise SystemExit(
                "internal: %s drew %d copies of `%s` but role_placements() says %s. "
                "These are the same arithmetic and scripts/lint-palette.py trusts "
                "the second one." % (name, n, role_name, expected.get(role_name)))

    # Higher y is further away, so it paints first.
    #
    # **The bias is subtracted, and it was added until M6g.** The scene sorts on
    # `zPosition = Character.Layer.rowDepth(y) + bias` where `rowDepth` is
    # `1000 - y`, so z runs *opposite* to y and a positive bias pulls a node
    # **forward**. This list is sorted on the row itself, largest first, so a
    # positive bias added here would push the node **backward**: the same
    # number meaning the opposite thing, which reversed the paint order inside
    # every seat:
    #
    #     scene    back -> front:   chair (-0.25), character, desk (+0.5)
    #     preview  back -> front:   desk,          character, chair
    #
    # Negating it puts this list back on the scene's convention: the desk's
    # +0.5 lowers its key so it paints last and its near edge crosses the seated
    # body, which `RoomLayout.deskPosition` says is the only cue at 32 px that a
    # character is sitting *at* a desk rather than beside one. The chair's -0.25
    # raises its key so its backrest goes behind. `prop_layout()` keeps the
    # scene's own numbers; only the direction they are read in was ours, and it
    # was wrong.
    for _depth, kind, payload in sorted(drawn, key=lambda d: -d[0]):
        if kind == "prop":
            path, left, top = payload
            w, h, px = load(path)
            sx, sy = to_screen(left, top)
            blit(buf, panel_w, panel_h, px, w, h, sx, sy)
        else:
            path, x, row = payload
            w, h, px = load(path)
            sx, sy = to_screen(x - w / 2.0, row + h)
            blit(buf, panel_w, panel_h, px, w, h, sx, sy)

    # Badges last, and above everything, which is where the scene puts them.
    # This tool does not model the overlay band; it draws one badge over every
    # occupied seat so a new badge can be looked at in the room it will appear
    # in. The anchor is the manifest's own: bubble bottom-centre on the point
    # `head_top_px` above the character's feet.
    if badge is not None:
        bw, bh, bpx = load(badge["file"])
        for seat in range(population):
            head_top = seat_y(seat) + CHAR_H - badge["head_top_px"]
            sx, sy = to_screen(seat_x(seat) - bw / 2.0, head_top + bh)
            blit(buf, panel_w, panel_h, bpx, bw, bh, sx, sy)

    if out_path is not None:
        pnglite.save(out_path, panel_w, panel_h, buf)
    return how, (panel_w, panel_h, buf)


# ---------------------------------------------------------------------------
# Verifying against the scene
# ---------------------------------------------------------------------------
#
# Everything above draws a picture of the room from a transcription of
# RoomLayout.swift and RoomScene.swift. Everything below checks that picture
# against the room the product actually draws.
#
# **Why it is not enough to check this file against itself.** It has been wrong
# twice and both times it looked right, because the only thing checking it was
# another copy of the same transcription:
#
#   M6b  `prop_origin` returned a y-up anchor offset where a y-down blit origin
#        was needed: up to ~80 px at 1x, invisible because it was *consistent*,
#        so every picture stayed internally plausible and every theme accepted
#        at M6 was accepted against a wrong picture.
#   M6e  `role_placements()` counted a foreground row of seven plants the scene
#        had stopped drawing two commits earlier. Its cross-check compared that
#        census against a `render()` transcribing the same dead layout. The two
#        agreed with each other and with nothing the scene does.
#
# So the reference here is the real thing: `spriteroom --render DIR --theme ID`
# draws the actual `RoomScene` through the actual `SKRenderer`, offscreen, at
# any theme, with no window server and without touching the display. Never
# `--panel-render`, which reveals the real panel over the user's screen.
#
# **What is compared, and why that is the property that matters.** Not bytes:
# the scene draws characters, nameplates and badges this tool deliberately does
# not model, and its camera centres on the occupied span where this one centres
# on the room. What is compared is the *room* (floor, wall, and every copy of
# every prop) pixel for pixel, in an empty room, after registering the two
# pictures on the tile field they both draw. That is exactly the surface the
# two known bugs lived on: which roles, how many copies, and where each one's
# content box lands. A picture that agrees on all of it agrees about placement,
# because a misplaced, missing or phantom prop cannot leave the pixels equal.
#
# **Registration is measured, not transcribed.** Both tools paint floor and wall
# over `DRAWN_ROWS` x `DRAWN_COLUMNS` and nothing outside it, so at a viewport
# wide enough to show the whole field the field's bounding box *is* the camera.
# The recovery is validated on this tool's own picture first (where the camera
# is known by construction from `camera()`) and only then applied to the
# scene's. If the two fields differ in *size*, the drawn range has drifted, and
# that is reported rather than fitted away.

# A viewport wide enough that the whole drawn tile field, 1344x672, is inside
# both pictures with margin. Bigger than the 720x400 panel on purpose: the
# panel crops the outer seats, and a prop the panel cannot show is a prop this
# check could not count.
VERIFY_PANEL = (1600, 900)

# The fixture is only a way to reach an *empty* room: after `SessionEnd` every
# character has departed and what is left is floor, wall and props, which is
# the whole of what this tool models. Any fixture would do; this is the
# shortest one that ends cleanly.
VERIFY_FIXTURE = os.path.join("fixtures", "single-agent-simple.jsonl")
VERIFY_AT = 60.0

# Room saturation is clamped to 0.18 by the import transform and characters own
# everything above it [I7], so a single pixel over this ceiling means somebody
# is still on stage and the render time was too early. Leaning on I7 to assert
# the room is empty is cheaper than modelling departures, and it double-checks
# I7 on the real renderer's output as a side effect.
VERIFY_EMPTY_MAX_SAT = 0.25

# ADR-010 gave `office` its own props the pack's own saturation (up to 0.873,
# measured) so the flat ceiling above no longer means "somebody is on stage"
# for that theme; its own furniture already clears it with nobody in the room.
# `verify_theme` below raises the ceiling, per theme, to whatever that theme's
# OWN dressed-but-uninhabited room actually measures (via this script's own
# `render()`, not the compiled binary), plus this margin for the small
# rendering differences `scene_agreement`'s known-defect register already
# tolerates elsewhere in this file.
#
# **What this gives up, named rather than quietly absorbed.** The check can no
# longer catch every straggling character in `office`: cast variant 06 peaks at
# 0.598, which is *below* office's own 0.873, so a variant-06 character still
# on stage at t=`VERIFY_AT` would not trip this specific assertion there. The
# render is still guaranteed empty by the fixture's own timing (`VERIFY_AT` is
# chosen to be well after `SessionEnd`) so this was always a second,
# independent sanity check rather than the mechanism of emptiness; for `office`
# it is a weaker second check, not a missing one, and it still catches a
# render that is more saturated than the theme's own furniture, whatever the
# cause.
VERIFY_EMPTY_SAT_MARGIN = 0.03

# ---------------------------------------------------------------------------
# The known-defect register
# ---------------------------------------------------------------------------
#
# **It is empty, and its emptiness is printed on every run.** M6f found two
# disagreements between this picture and the scene's and entered them here
# rather than absorbing them into a tolerance, because the ask then was to
# learn that the transcription was still wrong rather than to have it quietly
# corrected. Both were corrected at M6g and both entries are gone:
#
#   1. Every prop stood one pixel into the floor, all six themes, all 21
#      copies. `prop_origin` returned `y + bottom_row` where a y-down blit
#      needs `y + bottom_row + 1`. See that function.
#   2. The depth bias was transcribed with the wrong sign, so the paint order
#      inside every seat was reversed and every picture this tool had written
#      showed the character in front of its desk. `render()` sorts on
#      `y - bias` now. See the sort.
#
# What is left is the shape, and it is kept rather than deleted for one
# reason: a defect that is found next time is entered here **by name, with its
# correction and its measured extent**, or it is not accepted at all. A silent
# tolerance is what this whole file exists to not be. `register_summary()` is
# printed by `verify()` whether or not there is anything in it, so "the
# register is empty" is a claim someone made this run and not an absence
# nobody noticed.

# Whole-picture prop row offsets the check will accept. `(0,)` is "every prop
# lands exactly where the scene puts it". M6f also accepted -1 while defect 1
# was open; that entry is removed, so a reappearance of it now fails.
ACCEPTED_PROP_ROW_OFFSETS = (0,)

# Whether a `chair`-over-`desk` inversion inside a seat's own overlap rectangle
# is accepted. **False.** M6f set it True while defect 2 was open and confined
# it to the per-seat intersection of the two boxes, which is all an empty room
# can show of a paint-order bug. With the sign corrected the two pictures agree
# there pixel for pixel, so the exemption is withdrawn rather than left
# standing over a thing that no longer happens.
ACCEPT_CHAIR_DESK_OVERLAP = False


def register_summary():
    """One line naming what the check is currently willing to forgive.

    Printed on every `--verify` run, including the one inside
    `scripts/lint-palette.py`. An empty register has to say so out loud: the
    failure mode this whole comparison was built against is a disagreement that
    nobody is looking at, and a tolerance that prints nothing is one.
    """
    entries = []
    for offset in ACCEPTED_PROP_ROW_OFFSETS:
        if offset != 0:
            entries.append("a whole-picture prop row offset of %+d" % offset)
    if ACCEPT_CHAIR_DESK_OVERLAP:
        entries.append("`chair` over `desk` inside a seat's own overlap")
    if not entries:
        return ("known-defect register: empty: every prop must land exactly "
                "where the scene puts it, and nothing about a seat's paint "
                "order is forgiven")
    return "known-defect register: %d entr%s: %s" % (
        len(entries), "y" if len(entries) == 1 else "ies", "; ".join(entries))


def spriteroom_binary():
    """The built app, or None. `SPRITEROOM_BIN` overrides."""
    override = os.environ.get("SPRITEROOM_BIN")
    if override:
        return override if os.path.exists(override) else None
    for build in ("release", "debug"):
        path = os.path.join(REPO, ".build", build, "spriteroom")
        if os.path.exists(path):
            return path
    return None


def field_box(w, h, px):
    """Bounding box of everything that is not the picture's own background.

    The background is sampled at (0, 0) (this tool's `VOID`, the scene's clear
    colour) so the caller must give a viewport big enough that the tile field
    does not reach a corner. Returns None if it does, because a field touching
    an edge may be cropped and a cropped field is not a datum.
    """
    bg = bytes(px[0:4])
    row_bg = bg * w
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        row = px[y * w * 4:(y + 1) * w * 4]
        if row == row_bg:
            continue
        if y < miny:
            miny = y
        maxy = y
        for x in range(w):
            if row[x * 4:x * 4 + 4] != bg:
                if x < minx:
                    minx = x
                break
        for x in range(w - 1, -1, -1):
            if row[x * 4:x * 4 + 4] != bg:
                if x > maxx:
                    maxx = x
                break
    if maxx < 0:
        return None
    if minx == 0 or miny == 0 or maxx == w - 1 or maxy == h - 1:
        return None
    return (minx, miny, maxx, maxy)


def field_origin(image, plan=None):
    """`(x0, y0)`: the panel pixel of scene (0, 0), recovered from the picture.

    Panel x is `x0 + sx` and panel y is `y0 - sy`. Returns
    `(origin, None)` or `(None, complaint)`.

    The field is the overscan rectangle for an open floor and the plan's own
    rect under a plan: a plan stops, and everything above it is surround.
    """
    w, h, px = image
    box = field_box(w, h, px)
    if box is None:
        return None, ("the drawn tile field touches a panel edge, so the "
                      "picture cannot be registered: render it larger")
    x0, x1, y0, y1 = painted_field(plan)
    want_w = (x1 - x0 + 1) * TILE
    want_h = (y1 - y0 + 1) * TILE
    got_w, got_h = box[2] - box[0] + 1, box[3] - box[1] + 1
    if (got_w, got_h) != (want_w, want_h):
        return None, ("the drawn tile field is %dx%d px where this layout paints "
                      "%dx%d (columns %d..%d, rows %d..%d): the drawn range has "
                      "drifted" % (got_w, got_h, want_w, want_h, x0, x1, y0, y1))
    return (box[0] - x0 * TILE, box[1] + (y1 + 1) * TILE), None


def max_saturation(image):
    """Peak HSV saturation in the picture, ignoring fully transparent pixels."""
    _w, _h, px = image
    peak = 0.0
    for i in range(0, len(px), 4):
        if px[i + 3] == 0:
            continue
        r, g, b = px[i], px[i + 1], px[i + 2]
        hi = max(r, g, b)
        if hi == 0:
            continue
        s = (hi - min(r, g, b)) / float(hi)
        if s > peak:
            peak = s
    return peak


def scene_render(binary, theme, out_dir, fixture=VERIFY_FIXTURE, at=VERIFY_AT,
                 panel=VERIFY_PANEL):
    """One offscreen frame of the real scene. Returns `(image, complaint)`.

    `--render`, never `--panel-render`: this must not put anything on the
    user's screen, and it must not bind a port.
    """
    w, h = panel
    # `--render-scale 1`, and it is not a convenience. This tool draws at
    # SCALE = 1 and registers both pictures on the 1344x672 tile field they
    # both paint; an EMPTY room takes 2x from the population ladder, at which
    # the field is 2688x1344 and cannot fit any frame worth comparing over. The
    # check reported agreement anyway for as long as `.build/release/spriteroom`
    # was older than that camera policy, which is the failure mode this whole
    # file exists to close. See `SceneBinding.pinnedScale`.
    cmd = [binary, os.path.join(REPO, fixture), "--render", out_dir,
           "--theme", theme, "--at", "%g" % at, "--render-scale", "1",
           "--size", "%dx%d" % (w, h)]
    try:
        run = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                             timeout=300)
    except OSError as exc:
        return None, "could not run %s: %s" % (binary, exc)
    except subprocess.TimeoutExpired:
        return None, "%s --render timed out" % binary
    if run.returncode != 0:
        return None, ("%s --render exited %d: %s"
                      % (binary, run.returncode,
                         (run.stderr or run.stdout).strip().splitlines()[-1:]))
    written = sorted(glob.glob(os.path.join(out_dir, "*.png")))
    if not written:
        return None, "%s --render wrote no PNG" % binary
    return pnglite.load(written[-1]), None


# **One unit per channel, and it is a compositing rounding difference rather
# than a tolerance on placement.**
#
# `blit` above is integer alpha-over (`(src*a + dst*(255-a)) // 255`, floored)
# and SpriteKit blends premultiplied floats and rounds. On a fully opaque pixel
# the two agree exactly, which is why this was never needed: every prop either
# pack ships is hard-edged. `mission_control`'s locker bank is the first with a
# translucent panel, and its 744 semi-alpha pixels came out one unit darker in
# the scene than here, on every one of them: 744 measured differences, 744
# pixels of glass, exactly.
#
# It cannot hide what this check is for. A prop drawn one pixel out of place
# moves a hard edge, and a hard edge in this art is a step of tens of units; a
# missing or phantom copy is the difference between prop ink and bare floor.
# Neither survives a threshold of one. Anything larger would start to, so this
# is one and is compared per channel rather than summed.
COMPOSITE_EPSILON = 1


def _same(a, b):
    """Whether two RGBA pixels agree to within the compositing epsilon."""
    return a == b or all(abs(x - y) <= COMPOSITE_EPSILON for x, y in zip(a, b))


def _classify(scene, preview, room, offset, box):
    """Every pixel where the two pictures disagree, sorted into three kinds.

    `room` is this tool's own picture with no props at all, so it says what bare
    floor and wall look like at each pixel. That turns a raw difference into a
    statement about props:

      `preview_only`  this tool drew prop ink where the scene shows bare room:
                      a phantom copy, which is exactly the M6e failure.
      `scene_only`    the scene drew prop ink where this tool shows bare room:
                      a copy this tool is missing, or one it has moved away from.
      `moved`         both drew ink and it differs: a misplacement inside the
                      overlap, which is the M6b failure.

    Coordinates are the preview's. `offset` maps preview to scene.
    """
    dx, dy = offset
    pw, ph, ppx = preview
    sw, sh, spx = scene
    _rw, _rh, rpx = room
    out = {"preview_only": [], "scene_only": [], "moved": []}
    x_from, y_from, x_to, y_to = box
    for y in range(y_from, y_to + 1):
        sy = y + dy
        if sy < 0 or sy >= sh:
            continue
        base_p = y * pw * 4
        base_s = sy * sw * 4
        # Rows are equal far more often than not; comparing them whole first is
        # what keeps a 1.4 megapixel diff cheap in pure Python.
        span_p = ppx[base_p + x_from * 4:base_p + (x_to + 1) * 4]
        sx_from, sx_to = x_from + dx, x_to + dx
        if sx_from < 0 or sx_to >= sw:
            continue
        span_s = spx[base_s + sx_from * 4:base_s + (sx_to + 1) * 4]
        if span_p == span_s:
            continue
        for x in range(x_from, x_to + 1):
            i = base_p + x * 4
            j = base_s + (x + dx) * 4
            if _same(ppx[i:i + 4], spx[j:j + 4]):
                continue
            bare = rpx[i:i + 4]
            preview_ink = not _same(ppx[i:i + 4], bare)
            scene_ink = not _same(spx[j:j + 4], bare)
            if preview_ink and scene_ink:
                out["moved"].append((x, y))
            elif preview_ink:
                out["preview_only"].append((x, y))
            else:
                out["scene_only"].append((x, y))
    return out


def _mismatch_count(scene, preview, offset, points):
    """How many of `points` (preview coordinates) disagree at `offset`."""
    dx, dy = offset
    pw, _ph, ppx = preview
    sw, sh, spx = scene
    bad = 0
    for x, y in points:
        sx, sy = x + dx, y + dy
        if sx < 0 or sy < 0 or sx >= sw or sy >= sh:
            bad += 1
            continue
        if not _same(ppx[(y * pw + x) * 4:(y * pw + x) * 4 + 4],
                     spx[(sy * sw + sx) * 4:(sy * sw + sx) * 4 + 4]):
            bad += 1
    return bad


def _best_offset(scene, preview, points, around, window=6):
    """The offset near `around` that matches `points` best, and its residual.

    A diagnostic, not the check: it turns "7364 pixels differ" into "everything
    is one row low", which is the difference between a number and a finding.
    """
    sample = points if len(points) <= 3000 else points[::max(1, len(points) // 3000)]
    best = None
    for oy in range(around[1] - window, around[1] + window + 1):
        for ox in range(around[0] - window, around[0] + window + 1):
            bad = _mismatch_count(scene, preview, (ox, oy), sample)
            if best is None or bad < best[0]:
                best = (bad, (ox, oy))
    exact = _mismatch_count(scene, preview, best[1], points)
    return best[1], exact


def role_boxes(theme, roles=None):
    """Panel rectangles of every prop copy this tool places, per role.

    Preview panel coordinates, from `prop_layout()` and `prop_origin()`: the
    same two functions that drew the picture, so this cannot describe a room
    the picture did not draw.
    """
    canvas = theme["props"]["canvas"]
    declared = theme["props"]["roles"]
    to_screen, _origin = camera(*VERIFY_PANEL)
    boxes = {}
    for role_name, x, y, _bias, _v in prop_layout(
            seat_metrics(theme), None, manifest_json(), dressing_of(theme), declared):
        if roles is not None and role_name not in roles:
            continue
        role = variant_role(declared.get(role_name), _v)
        if role is None:
            continue
        left, top = prop_origin(role, canvas, x, y)
        px, py = to_screen(left, top)
        box = role["content_box"]
        boxes.setdefault(role_name, []).append(
            (px + box["x"], py + box["y"],
             px + box["x"] + box["w"] - 1, py + box["y"] + box["h"] - 1))
    return boxes


def verify_theme(theme, name, binary, out_dir, scratch, fixture=VERIFY_FIXTURE,
                 at=VERIFY_AT, panel=VERIFY_PANEL):
    """Compare one theme's preview against the real scene. Returns a report dict."""
    report = {"theme": name, "ok": False, "notes": [], "failures": []}

    scene_dir = os.path.join(scratch, "scene-" + name)
    os.makedirs(scene_dir, exist_ok=True)
    scene, complaint = scene_render(binary, name, scene_dir, fixture, at, panel)
    if complaint:
        report["failures"].append(complaint)
        return report

    # ADR-010: the ceiling is per theme: `office`'s own dressed-but-empty room
    # (this tool's own `render()`, no characters, so it cannot itself be the
    # thing tripping the check) measures its true furniture peak, and anything
    # over that plus a small margin is not explained by furniture. Every other
    # theme's furniture peaks at ~0.18, so `max(VERIFY_EMPTY_MAX_SAT, ...)`
    # leaves the flat 0.25 exactly where it was for them. See
    # VERIFY_EMPTY_SAT_MARGIN for what this gives up for `office`.
    _how, empty_room = render(theme, name, 0, None, {}, [], panel=panel)
    empty_ceiling = max(VERIFY_EMPTY_MAX_SAT,
                        max_saturation(empty_room) + VERIFY_EMPTY_SAT_MARGIN)

    peak = max_saturation(scene)
    if peak > empty_ceiling:
        report["failures"].append(
            "the scene render at t=%g is not an empty room: a pixel carries "
            "saturation %.3f, over the %.2f this theme's own dressed-but-empty "
            "room measures (%.2f margin), so a character is still on stage. "
            "Render later."
            % (at, peak, empty_ceiling, VERIFY_EMPTY_SAT_MARGIN))
        return report

    plan = plan_of(theme)
    scene_origin, complaint = field_origin(scene, plan)
    if complaint:
        report["failures"].append("scene render: " + complaint)
        return report

    # Bare floor and wall: the same theme with every prop role removed. It is
    # what makes a difference legible as "phantom prop" or "missing prop"
    # instead of "1268 pixels".
    bare_theme = dict(theme)
    bare_theme["props"] = dict(theme["props"])
    bare_theme["props"] = {"canvas": theme["props"]["canvas"], "roles": {}}
    _how, room = render(bare_theme, name, 0, None, {}, [], panel=panel)

    preview_origin, complaint = field_origin(room, plan)
    if complaint:
        report["failures"].append("preview: " + complaint)
        return report
    # The recovery is validated where the answer is already known. `camera()`
    # states this tool's own origin outright; if reading it back off the pixels
    # disagrees, the recovery is wrong and nothing measured with it means
    # anything, including the scene's.
    _to_screen, declared_origin = camera(*panel)
    if preview_origin != (int(declared_origin[0]), int(declared_origin[1])):
        report["failures"].append(
            "field registration is unsound: read %s off this tool's own picture "
            "where camera() says %s"
            % (preview_origin, (int(declared_origin[0]), int(declared_origin[1]))))
        return report

    offset = (scene_origin[0] - preview_origin[0], scene_origin[1] - preview_origin[1])
    report["camera_offset"] = offset
    report["notes"].append(
        "camera differs by %+d,%+d px: the scene centres on the occupied span, "
        "this tool on the room" % offset)

    # Compare over the tile field and nothing else: it is the whole of what
    # both pictures draw, and by construction of `offset` the scene's field
    # lands on exactly this rectangle. Outside it both are their own void
    # colour, which are different colours and mean nothing.
    fx0, fx1, fy0, fy1 = painted_field(plan)
    left = preview_origin[0] + fx0 * TILE
    top = preview_origin[1] - (fy1 + 1) * TILE
    box = (left, top,
           left + (fx1 - fx0 + 1) * TILE - 1,
           top + (fy1 - fy0 + 1) * TILE - 1)

    boxes_by_role = role_boxes(theme)
    loop = max([len(role_frames(r)) for r in theme["props"]["roles"].values()] or [1])
    best = None
    for frame in range(loop):
        _how, preview = render(theme, name, 0, None, {}, [], frame=frame, panel=panel)
        diff = _classify(scene, preview, room, offset, box)
        total = sum(len(v) for v in diff.values())
        if best is None or total < best[0]:
            best = (total, frame, preview, diff)
        if total == 0:
            break
    total, frame, preview, diff = best
    report["frame"] = frame
    report["diff"] = {k: len(v) for k, v in diff.items()}
    if loop > 1:
        report["notes"].append("animated: matched frame %d of %d" % (frame, loop))

    if total == 0:
        report["ok"] = True
        report["prop_offset"] = (0, 0)
        return report

    # Disagreement. Say what kind, and whether one translation explains it,
    # which is the difference between "7364 pixels differ" and "the props are
    # one row low".
    def ink_in(rects, margin=0):
        pts = []
        for (x0, y0, x1, y1) in rects:
            for y in range(max(box[1], y0 - margin), min(box[3], y1 + margin) + 1):
                base = y * preview[0] * 4
                for x in range(max(box[0], x0 - margin), min(box[2], x1 + margin) + 1):
                    i = base + x * 4
                    if preview[2][i:i + 4] != room[2][i:i + 4]:
                        pts.append((x, y))
        return pts

    all_boxes = [r for rects in boxes_by_role.values() for r in rects]
    all_ink = sorted(set(ink_in(all_boxes)))
    shift, residual = _best_offset(scene, preview, all_ink, offset)
    prop_offset = (shift[0] - offset[0], shift[1] - offset[1])
    report["prop_offset"] = prop_offset
    report["residual"] = residual

    per_role = {}
    for role_name, rects in sorted(boxes_by_role.items()):
        pts = sorted(set(ink_in(rects)))
        if not pts:
            continue
        rshift, rres = _best_offset(scene, preview, pts, offset)
        per_role[role_name] = ((rshift[0] - offset[0], rshift[1] - offset[1]),
                               rres, len(rects))
    report["per_role"] = per_role

    # Where the seat's chair and its own desk overlap. Paired by placement
    # order, which is seat order in `prop_layout()`, so this is the same seat's
    # two props and not two arbitrary rectangles.
    overlaps = []
    chairs, desks = boxes_by_role.get("chair", []), boxes_by_role.get("desk", [])
    for c, d in zip(chairs, desks):
        x0, y0 = max(c[0], d[0]), max(c[1], d[1])
        x1, y1 = min(c[2], d[2]), min(c[3], d[3])
        if x0 <= x1 and y0 <= y1:
            overlaps.append((x0, y0, x1, y1))
    in_overlap = set()
    for (x0, y0, x1, y1) in overlaps:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                in_overlap.add((x, y))
    wrong = set(p for p in all_ink if _mismatch_count(scene, preview, shift, [p]))
    unexplained = sorted(wrong - in_overlap)
    report["absorbed"] = len(wrong) - len(unexplained)
    report["unexplained"] = len(unexplained)

    # Every pixel the two disagree on has to be inside a prop's own box, grown
    # by the offset. Without this the shift measurement could be perfect while
    # the floor, the wall or a prop the scene draws and this tool does not sat
    # unexamined outside every box.
    margin = max(1, abs(prop_offset[0]), abs(prop_offset[1]))
    inside = set()
    for (x0, y0, x1, y1) in all_boxes:
        for y in range(y0 - margin, y1 + margin + 1):
            for x in range(x0 - margin, x1 + margin + 1):
                inside.add((x, y))
    stray = {kind: [p for p in pts if p not in inside] for kind, pts in diff.items()}
    n_stray = sum(len(v) for v in stray.values())
    report["stray"] = n_stray

    uniform = all(v[0] == prop_offset for v in per_role.values())
    absorbed = report["absorbed"]
    if (uniform and len(unexplained) == 0 and n_stray == 0 and prop_offset[0] == 0
            and prop_offset[1] in ACCEPTED_PROP_ROW_OFFSETS
            and (absorbed == 0 or ACCEPT_CHAIR_DESK_OVERLAP)):
        # Reached only when the register is non-empty, because with it empty
        # this function has already returned on `total == 0` above. Both
        # branches name the register entry that let the picture through, so a
        # forgiven disagreement is never a silent one.
        report["ok"] = True
        if prop_offset[1] != 0:
            report["notes"].append(
                "REGISTER: props agree only %d row off, which "
                "ACCEPTED_PROP_ROW_OFFSETS permits. Otherwise exact: %d copies "
                "over %d roles, same art, same columns, nothing disagreeing "
                "outside a prop's box."
                % (abs(prop_offset[1]), len(all_boxes), len(per_role)))
        if absorbed:
            report["notes"].append(
                "REGISTER: %d pixels inside the %d seat chair/desk overlaps "
                "where the two pictures paint the same two props in the "
                "opposite order, which ACCEPT_CHAIR_DESK_OVERLAP permits."
                % (absorbed, len(overlaps)))
        return report

    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, "%s-disagreement.png" % name)
        marked = bytearray(preview[2])
        for kind, colour in (("preview_only", (255, 64, 64, 255)),
                             ("scene_only", (64, 255, 64, 255)),
                             ("moved", (255, 220, 0, 255))):
            for x, y in diff[kind]:
                i = (y * preview[0] + x) * 4
                marked[i:i + 4] = bytes(colour)
        pnglite.save(path, preview[0], preview[1], marked)
        report["diff_png"] = path

    report["failures"].append(
        "%s: %d pixels of the room disagree with the scene "
        "(%d this tool drew over bare room: a copy the scene does not draw; "
        "%d the scene drew over bare room: a copy this tool is missing or has "
        "moved; %d drawn by both and different). %d of them fall outside every "
        "prop box, which is floor, wall or a prop this tool knows nothing "
        "about. Best single prop offset %+d,%+d leaves %d prop pixels wrong "
        "outside the known chair/desk overlap; per role %s."
        % (name, total, len(diff["preview_only"]), len(diff["scene_only"]),
           len(diff["moved"]), n_stray, prop_offset[0], prop_offset[1],
           len(unexplained),
           ", ".join("%s x%d offset %+d,%+d residual %d"
                     % (r, v[2], v[0][0], v[0][1], v[1])
                     for r, v in sorted(per_role.items())) or "none"))
    return report


def verify(sets, names, out_dir, fixture=VERIFY_FIXTURE, at=VERIFY_AT,
           binary=None, required=False):
    """Run the comparison over every named theme. Returns an exit code.

    A skip is not a pass and is never silent: with no built app, or no Metal
    device, this says so in as many words and prints the themes it did not
    check. `SPRITE_ROOM_REQUIRE_SCENE=1` turns that skip into a failure, which
    is the same arrangement `SPRITE_ROOM_REQUIRE_ART` gives the art gate.
    """
    binary = binary or spriteroom_binary()
    required = required or os.environ.get("SPRITE_ROOM_REQUIRE_SCENE") == "1"
    if binary is None:
        print("scene check: SKIPPED: no built app at .build/{debug,release}/"
              "spriteroom, so the real scene cannot be rendered. %d theme(s) "
              "unchecked: %s. Run `swift build`, or set SPRITE_ROOM_REQUIRE_SCENE=1 "
              "to make this a failure." % (len(names), ", ".join(names)),
              file=sys.stderr)
        return 1 if required else 0

    # Before anything is compared, say what this run is prepared to forgive.
    # An empty register is the interesting case and it is the one a silence
    # would hide, so it is printed too.
    print("  %-16s %s" % ("", register_summary()))

    scratch = tempfile.mkdtemp(prefix="preview-verify-")
    codes = []
    try:
        for name in names:
            report = verify_theme(sets[name], name, binary, out_dir, scratch,
                                  fixture=fixture, at=at)
            for note in report["notes"]:
                print("  %-16s %s" % (name, note))
            if report["ok"]:
                print("%-16s agrees with the scene" % name)
            else:
                codes.append(1)
                for f in report["failures"]:
                    print("%-16s DISAGREES: %s" % (name, f), file=sys.stderr)
                if report.get("diff_png"):
                    print("%-16s   marked-up diff: %s"
                          % (name, os.path.relpath(report["diff_png"], REPO)),
                          file=sys.stderr)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    return 1 if codes else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--theme", action="append", help="repeatable; default is all")
    ap.add_argument("--population", type=int, default=4)
    ap.add_argument("--state", default="working",
                    help="body state to seat the cast in (default: working)")
    ap.add_argument("--badge", help="draw this badges.states entry over every "
                                    "occupied seat, e.g. sleep")
    ap.add_argument("--animated", help="review path: an assets/processed/animated/ "
                                       "object id that the manifest has NOT adopted, "
                                       "stood in the back row's board slot")
    ap.add_argument("--frames", action="store_true",
                    help="write one PNG per animation frame of whatever the theme's "
                         "animated prop is (or of --animated)")
    ap.add_argument("--frame", type=int, default=0,
                    help="draw this frame of the loop (default 0, which is `file`)")
    ap.add_argument("--size", default="%dx%d" % (PANEL_W, PANEL_H),
                    help="panel size WxH (default %dx%d, the real drop-down)"
                         % (PANEL_W, PANEL_H))
    ap.add_argument("--verify", action="store_true",
                    help="compare this tool's room against the real scene, "
                         "pixel for pixel, via `spriteroom --render`. Exits "
                         "non-zero on any disagreement")
    ap.add_argument("--fixture", default=VERIFY_FIXTURE,
                    help="--verify: fixture to reach an empty room with")
    ap.add_argument("--at", type=float, default=VERIFY_AT,
                    help="--verify: fixture second to render the scene at; must "
                         "be after every character has left")
    ap.add_argument("--manifest", default=MANIFEST)
    args = ap.parse_args(argv)

    try:
        size_w, size_h = (int(v) for v in args.size.lower().split("x", 1))
        if size_w <= 0 or size_h <= 0:
            raise ValueError
    except ValueError:
        print("error: --size wants WxH, e.g. 720x400", file=sys.stderr)
        return 2

    with open(args.manifest) as f:
        m = json.load(f)

    sets = m.get("themes", {}).get("sets")
    if not sets:
        print("error: manifest declares no themes; run scripts/build-manifest.py.",
              file=sys.stderr)
        return 2

    # **One frame per (variant, seat facing).** [ADR-008] A seat declares which
    # way its occupant faces and `BodyState.artState(facing:)` decides which row
    # that draws: the sit row for a side-on seat, the standing `idle` row for a
    # seat turned toward or away from the camera. This used to take
    # `frames["right"]` unconditionally, which drew every seat side-on: the
    # picture the app stopped drawing.
    variants = sorted(m["characters"]["variants"])
    seated = {}
    for v in variants:
        states = m["characters"]["variants"][v]["states"]
        if args.state not in states:
            print("error: no state %r (have: %s)"
                  % (args.state, ", ".join(sorted(states))), file=sys.stderr)
            return 2
        for facing, direction in (("side_on", "right"), ("toward_camera", "down"),
                                  ("away_from_camera", "up")):
            state = args.state
            if state == "working" and direction in ("up", "down"):
                state = "idle"
            frames = states[state]["frames"].get(direction)
            if not frames:
                frames = states[state]["frames"]["right"]
            seated[(v, facing)] = frames[0]

    badge = None
    if args.badge:
        entry = m.get("badges", {}).get("states", {}).get(args.badge)
        if entry is None:
            print("error: no badges.states %r (have: %s)"
                  % (args.badge,
                     ", ".join(sorted(m.get("badges", {}).get("states", {})))),
                  file=sys.stderr)
            return 2
        badge = {"file": entry["file"],
                 "head_top_px": m["characters"]["variants"][variants[0]]["head_top_px"]}

    if args.animated and animated_override(args.animated) is None:
        print("error: no frames under assets/processed/animated/32x32/%s: "
              "run scripts/process-assets.py" % args.animated, file=sys.stderr)
        return 2

    os.makedirs(args.out, exist_ok=True)
    names = args.theme or sorted(sets)
    for name in names:
        if name not in sets:
            print("error: no theme %r (have: %s)" % (name, ", ".join(sorted(sets))),
                  file=sys.stderr)
            return 2

    if args.verify:
        return verify(sets, names, args.out, fixture=args.fixture, at=args.at)

    for name in names:
        # How many frames this theme actually has. A theme with no animated prop
        # has one, whatever --frames says, rather than silently writing six
        # copies of the same picture.
        if args.animated:
            loop = len(animated_override(args.animated)["animation"]["frames"])
        else:
            loop = max([len(role_frames(r))
                        for r in sets[name]["props"]["roles"].values()] or [1])
        n_frames = loop if args.frames else 1
        for f in range(n_frames):
            suffix = "_f%02d" % f if (args.frames and loop > 1) else ""
            out = os.path.join(args.out, "%s%s.png" % (name, suffix))
            how, _image = render(sets[name], name, args.population, out, seated,
                                 variants, badge=badge, animated=args.animated,
                                 frame=f if args.frames else args.frame,
                                 panel=(size_w, size_h))
            print("%-16s %-9s %s" % (name, how, os.path.relpath(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
