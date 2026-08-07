#!/usr/bin/env python3
"""Asset import pass. Cuts the two purchased packs into what the scene loads.

Two, not three: Modern User Interface was never purchased, so six of the seven
tool badges have no source art and ship as placeholders. See README.md.

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
  BADGE     Modern Interiors UI sheet, cut by measured rectangles. Colour
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
            "rev": 3,
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
        """Cut the sourceable badges out of the UI sheet onto a common canvas.

        Only the icons we could actually find go here. The other five badges in
        the tool->badge table have no icon in any pack on disk and are generated
        by scripts/generate-placeholders.py instead — see docs/FINDINGS-M0.md.
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
            for name, (x0, y0, rw, rh) in BADGE_RECTS.items():
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
            self.log("  badges/%s: %d sourced (%s)"
                     % (size, len(BADGE_RECTS), ", ".join(sorted(BADGE_RECTS))))

    # -- housekeeping -------------------------------------------------------

    def prune(self):
        """Delete outputs whose source no longer produces them.

        Idempotency has to cut both ways: if a pack drops a file or the cast
        changes, a stale processed copy would keep satisfying the manifest and
        hide the loss. Placeholders are left alone — a different script owns
        those, and they live under assets/placeholder/, not here.
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
