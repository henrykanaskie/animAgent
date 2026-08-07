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


def room_colour(r, g, b):
    """Desaturate and value-compress one colour. Pure; memoised by the caller."""
    hh, ss, vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    ss = min(ss * SAT_SCALE, SAT_TARGET)
    vv = VALUE_FLOOR + vv * (VALUE_CEIL - VALUE_FLOOR)
    nr, ng, nb = colorsys.hsv_to_rgb(hh, ss, vv)
    return (int(round(nr * 255)), int(round(ng * 255)), int(round(nb * 255)))


def recolour(px, cache):
    """Apply the room palette transform in place.

    Memoised on source RGB. Pixel art has a tiny palette — the whole Office pack
    uses about 320 distinct colours — so this turns a per-pixel colorsys round
    trip into a dict lookup, making a full reimport fast enough that nobody is
    tempted to skip it.
    """
    for i in range(0, len(px), 4):
        if px[i + 3] == 0:
            continue
        key = (px[i], px[i + 1], px[i + 2])
        out = cache.get(key)
        if out is None:
            out = cache[key] = room_colour(*key)
        px[i], px[i + 1], px[i + 2] = out


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
            "shadow": SHADOW_RGB,
            "cast": CHAR_CAST,
            "export": {k: list(v) for k, v in CHAR_EXPORT.items()},
            "badges": BADGE_RECTS,
            "canvas": BADGE_CANVAS,
            "badge_frame": [BADGE_FRAME_RECT, BADGE_FRAME_INTERIOR],
            "badge_icons": {k: list(v) for k, v in MUI_BADGE_ICONS.items()},
            "rev": 4,
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
