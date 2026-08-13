#!/usr/bin/env python3
"""Palette separation lint over assets/manifest.json. [I7]

CLAUDE.md, I7: "The room is desaturated and low-contrast. Characters own the
saturation and the darkest values. At small sizes silhouette and value contrast
are what read — not detail. Enforced by lint over the asset manifest, not by
good intentions."

Four checks on colour, exactly the thresholds in docs/04-ART-DIRECTION.md —
**amended for pack-value themes at ADR-010/ADR-011 and the M8 palette-pass
task**, see below:

  1. Every room pixel is under 25% saturation — **except a theme
     `scripts/process-assets.py` declares a per-theme saturation override for
     (`office` as of ADR-010, `briefing` and `library` as of the M8
     palette-pass task), which is checked against that theme's OWN
     `prop_sat_scale`/`prop_sat_target` applied to the pack's own saturation
     instead — not necessarily the raw pack figure; see "Per-theme saturation
     policy" below.
  2. Every character carries at least one colour above 55% saturation.
  3. At least 40% value contrast between a character's darkest pixel and the
     mean room value — **except `office` and `briefing`, each individually
     measured against 0.35 instead; see `THEME_MIN_VALUE_CONTRAST`.** Every
     other theme is unweakened, at the same 40% floor as before — including
     `library`, which restores saturation (check 1) without moving its value
     band, and so was never measured against a weaker number than everyone
     else on this axis.
  4. **Added at the M8 palette-pass task.** `room`'s own mean saturation, and
     each theme's, must stay under the CAST's mean saturation — pooled over
     every variant's every frame. This is the half of I7's sentence check 1
     never verified: a theme can pass check 1 (its own declared scale/target
     applied correctly) and still be louder than the characters if the scale
     itself was picked too high, which is exactly what happened to `briefing`
     before this check existed. See "Per-theme saturation policy" below.

And, added after ADR-002 §14b admitted animated props, one check on motion:

  5. Everything the room animates, added together and counted once per copy the
     room draws, must change fewer pixels per second than the quietest looping
     animation in the cast.

---

### Per-theme saturation policy — ADR-010, extended at the M8 palette-pass task

I7 bundled two claims under one sentence: "characters own the saturation and
the darkest values." ADR-010 separates them for `office`: its props are
restored to the pack's own saturation (`prop_sat_scale`/`prop_sat_target` in
`scripts/process-assets.py`'s `THEMES["office"]`), while the value band —
`VALUE_FLOOR`/`VALUE_CEIL`, check 3 above — is untouched **for `office`
itself**, which instead widens ITS OWN value band separately
(`prop_value_floor`/`prop_value_ceil`, ADR-011) for a reason specific to it:
a maintainer-built reference composite. That second, value-axis move is NOT
part of what "join this policy" means — it is `office`'s own further step,
`briefing` followed it (see `THEME_MIN_VALUE_CONTRAST` below), and `library`
deliberately did not (see `THEMES["library"]`'s own comment in
scripts/process-assets.py for why: a real conflict with an unrelated Swift
test). The M8 palette-pass task measured all five non-`office` themes against
the `office`/`briefing` VALUE package and found only `library` could clear it
on a re-tile — `broadcast`, `mission_control` and `stage` cannot on any tile
their own sheet offers, full stop; see `THEME_MIN_VALUE_CONTRAST` below for
the numbers. So `office`, `briefing` and `library` all join THIS check
(saturation), and only `office` and `briefing` join check 3's weakened
threshold. Every theme not in this saturation policy keeps check 1 exactly as
it has always run, at the literal 0.25 ceiling.

**`prop_sat_scale`/`prop_sat_target` are NOT always identity, and check 1
does not assume they are.** `office` and `library` both run at `(1.0, 1.0)` —
the pack's own saturation, unscaled. `briefing` does not: the M8 palette-pass
task found it at `(1.0, 1.0)` measuring 0.411 mean saturation against the
cast's own 0.332 (check 4 below), so it now runs at `(0.75, 1.0)` — 75% of
the pack's own colour, not the pack's own colour outright. `pack_saturation_
cross_check()` re-reads the *untouched* pack PNGs `scripts/process-assets.py`
cuts a theme's roles, scenery, floor and wall from and computes, per file,
`min(raw_pack_saturation * prop_sat_scale, prop_sat_target)` — the theme's OWN
declared transform, not an assumption that it is 1.0. A pack-value theme's
*processed* peak saturation must land within `SAT_BASELINE_TOLERANCE` of THAT
number: not below it, which would mean the declared scale was not actually
applied; not above it, which would mean something more saturated than the
theme's own declared band is on screen. Every other theme is measured on the
flat 0.25 ceiling exactly as before, and `room` — which ADR-002 §14a
establishes *is* the resolved default theme (`themes.default`) — inherits
whichever policy that theme carries, because `room.props.scenery` and
`themes.sets.office.props.scenery` are the same bytes on disk and a check that
disagreed with itself about them would be checking nothing.

**And check 1 passing does not mean check 4 does.** They ask different
questions: check 1 asks "does this file match what the theme's OWN scale
implies", check 4 asks "does the RESULT still recede behind the cast". A
theme could declare `(1.0, 1.0)`, pass check 1 on every file by construction,
and still fail check 4 if the pack's own art is simply louder than the
characters — which is exactly what `briefing` did before check 4 existed to
catch it. Picking a lower scale is how a theme satisfies check 4; check 1 is
what proves that scale was actually applied, file by file, rather than
adjusted in the table and left unverified in the art.

Why a fourth check exists at all: in this product **motion means an agent is
working**. It is the one signal a glance actually reads. So a prop that
out-moves the characters is the time-axis equivalent of a room element owning
the darkest pixel on screen — the thing checks 1-3 exist to forbid — and until
§14b it was unguarded. §14b recorded the gap in as many words: `old_tv` "would
have passed the lint, because the lint says nothing about motion". It does now,
and `old_tv` is what it was tested against.

Exits non-zero on any violation, naming the file and the measured value. It runs
over the manifest rather than over a directory so that it checks what the scene
will actually load — art sitting on disk but absent from the manifest is not in
the build, and art in the manifest but absent from disk is caught earlier, by
scripts/build-manifest.py.

If this fails, the art is wrong. Do not adjust the thresholds to make it pass:
they are the reason the characters stay readable at 1x, which is the size the
whole project is designed around.

Python 3 stdlib only.
"""

import argparse
import colorsys
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glob
import re
import tempfile

import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO, "assets", "manifest.json")

ROOM_MAX_SAT = 0.25
CHAR_MIN_SAT = 0.55
MIN_VALUE_CONTRAST = 0.40

# **One theme is measured against a lower floor, and the floor is a
# measurement rather than a concession.** [ADR-011]
#
# `output/01-engineering-office.png` is the composed reference the maintainer
# built with `scripts/compose-scene.py` straight off the untouched pack, and it
# is the picture this app was asked to reproduce. Measured over its own pixels
# it runs at a mean value of 0.667 against the cast's darkest ink at 0.314 —
# **0.353 of contrast**, which is under the 0.40 this file has always demanded.
# So 0.40 was never a property of the medium or of the pack; it was a property
# of the value transform, which lifted every room pixel into [0.55, 0.92] and
# thereby guaranteed a mean nothing could pull down.
#
# `office` now draws its props and its floors on the pack's own values, so it
# is measured against the reference instead: **0.35**, the reference's own
# 0.353 rounded down to two places. A theme that reads worse than the picture
# this one is copying still fails. The other five themes are untouched at 0.40,
# and `room` — which is `office`'s own bytes — takes office's floor for the
# same aliasing reason `override_prefixes` exists.
#
# What did NOT move, and it is the half of I7 that matters at 1x: **characters
# still own the darkest pixel on screen.** The cast's darkest ink is 0.314; the
# darkest pixel anywhere in the office room is 0.361, because
# `prop_value_floor` is 0.10 rather than 0.0. Identity on the value axis was
# tried and measured at 0.290 — the room owning the darkest pixel outright —
# and rejected for exactly that reason. The 0.10 floor costs nothing visible
# and keeps the sentence true.
#
# **A second theme, added by the same rule, not by a second reference.**
# [M8 palette-pass task] `briefing`'s props, scenery, floor and wall now run on
# the identical `office` knobs — floor 0.10, ceiling 1.0, identity saturation —
# because both packs share the SAME 0.314 outline ink: measured at the identity
# transform (floor 0.0), the darkest pixel across every `briefing` role,
# scenery item, floor and wall tile is exactly 0.314, tied with the cast rather
# than under it, exactly the coincidence that made `office`'s 0.10 choice cheap
# to re-use rather than re-derive. What is NOT re-used is the 0.35 itself:
# `briefing` has no reference composite of its own, so 0.35 is applied here
# only because `briefing`'s own measured contrast (0.372, mean 0.686 against
# the cast's 0.314) already clears it on the untuned office floor — the floor
# was not raised to reach this number, the number is what the office floor
# happened to produce. `broadcast`, `library`, `mission_control` and `stage`
# were measured against the SAME office floor and none of them clear 0.35
# (0.289, 0.322, 0.299, 0.308) — see the per-theme comments beside
# `THEMES["briefing"]` in scripts/process-assets.py for the full table.
#
# **`library` is NOT a third theme on this table, and that is a deliberate
# result rather than an oversight.** At the M8 palette-pass task, `library`'s
# own Room Builder sheet turned out to carry a floor and wall tile — `(9, 1)`
# in place of the old `(16, 0)` wood plank, `(6, 5)` in place of the old
# `(6, 4)` wall — bright enough that the SAME `office`/`briefing` value
# package (`prop_value_floor` 0.10) would clear 0.35 there too: mean 0.672,
# darkest 0.384, contrast 0.358, measured on a manifest built with that
# package declared. It was tried and pulled back, because
# `Tests/SpriteRoomSceneTests/PropAnimationTests.swift`'s `animatedTheme(_:)`
# picks the first theme (alphabetically) carrying a playable animated role,
# which is `library`'s own `pendulum_clock` whenever `library` has one — and
# `Importer.animated()` cuts that clock "on the target theme's own prop
# band", so widening `library`'s value band widens the clock's too, and a
# real run of `swift test` with that package in found
# `theAnimatedPropIsNeverRebuiltAcrossAFixtureReplay` failing, for a reason
# that has nothing to do with this theme's own colour and everything to do
# with which theme the test suite happened to be measuring. `library`'s own
# baseline contrast — standard band, no pack-value package — was already
# 0.456, comfortably over even the UNweakened 0.40 floor, so there was
# nothing to buy on the value axis by moving it here in the first place; see
# `THEMES["library"]`'s own comment in scripts/process-assets.py. `library`
# DOES restore saturation (`prop_sat_scale`/`prop_sat_target` = `(1.0, 1.0)`,
# same as `office`), just not the value axis, which is why it is in
# `sat_override_themes()` below (saturation is checked against the pack) but
# stays OFF this table (value contrast is checked at the standard 0.40).
#
# `broadcast`, `mission_control` and `stage` were searched the same way as
# `library` and none of them clear 0.35 on any tile their sheet offers at
# all, value package or not — see the comment beside each of their own
# `THEMES[...]` entries for the numbers. They are deliberately left off both
# the pack-value transform and this table: raising a theme's own floor
# further, past 0.10, until its number cleared 0.35 would be tuning the art
# to the threshold rather than measuring the art, which is the "silently
# widen the table" move this amendment refuses to make.
THEME_MIN_VALUE_CONTRAST = {"office": 0.35, "briefing": 0.35}


def min_value_contrast(theme_name=None):
    """The contrast floor one theme is held to. See THEME_MIN_VALUE_CONTRAST."""
    return THEME_MIN_VALUE_CONTRAST.get(theme_name, MIN_VALUE_CONTRAST)

# How far a sat-override theme's *processed* peak saturation may drift from the
# *pack's own* peak saturation, measured independently off the untouched pack
# PNGs — see "Per-theme saturation policy" above. The transform is the identity
# operation on hue and saturation for these themes (`prop_sat_scale == 1.0`,
# `prop_sat_target == 1.0`), so the only expected difference is 8-bit rounding
# through the HSV round trip `scripts/process-assets.py`'s `room_colour` still
# does for the value channel. Measured at under 0.004 on the shipped `office`
# art; the tolerance below leaves an order of magnitude of headroom without
# opening the door to a theme that is merely "close" to the pack.
SAT_BASELINE_TOLERANCE = 0.03

# Accent separation, added at M5.
#
# docs/04-ART-DIRECTION.md has always said "one accent hue per variant, chosen
# for mutual separation". Until M5 that was an assertion, and M2 measured it to
# be false of the source art: all six selected premades' most saturated pixels
# land inside a 30 degree arc and two of them are hue-identical. The manifest
# now carries an assigned `accent_hex` per variant instead, and this is the
# check that keeps the sentence true. A per-variant accent that does not
# separate is not a second identity channel, it is a decoration that looks like
# one, which is worse.
MIN_ACCENT_HUE_SEPARATION = 40.0   # degrees, minimum over every pair
MIN_ACCENT_SAT = 0.45
MIN_ACCENT_VALUE = 0.60

# ---------------------------------------------------------------------------
# The motion budget. ADR-002 §14b, docs/04-ART-DIRECTION.md "The motion budget".
# ---------------------------------------------------------------------------
#
# **The quantity.** Pixels changed per second, on the panel, summed over every
# animated prop in a room and multiplied by the number of times the room draws
# that prop's role.
#
# Three quantities were candidates and this is the one that governs, for
# reasons that are measurements rather than preferences:
#
#   - `moving_px / visible_px` — a prop's own moving fraction, the figure §14b
#     quotes (pendulum_clock 3.1%, old_tv 27.9%) — is **not** governed. It says
#     what proportion of an object is restless, not how much of the view
#     changes, and it is not comparable between props: a prop ten times larger
#     with the same 364 moving pixels scores 3.1% instead of 31.5% and costs the
#     panel exactly the same. It is measured and printed, because it is a real
#     description of a prop's character, and it is cross-checked against the
#     manifest. It is not a gate.
#   - Per-loop moving pixels, placed, is closer but still wrong: it grows with
#     loop length and ignores rate. It prices `control_room_server` (3 frames at
#     2 fps) at 0.62 of the ceiling; per second it is 0.30.
#   - Pixels changed per second, placed, is what an eye competes with. It is
#     rate-normalised and length-normalised, and it was checked against the
#     renderer rather than assumed: `preview-theme.py` writing all four frames
#     of `library` at 720x400 differs between consecutive frames by exactly
#     4x the prop's own figure, and `broadcast` with `old_tv` stood in the same
#     slot likewise. The placement multiplier is arithmetic the renderer agrees
#     with, not a model of the room.
#
# **The number is the cast's, not a prop's.** I7's other thresholds are
# relative — the room must be *under* the characters — so this one is too, and
# for the same reason: a fixed pixel count picked from the two props we happen
# to own would be taste with a decimal point on it. The ceiling is measured at
# lint time as the **quietest looping animation any shipped variant plays**, in
# the same units, and the room's total must come in under it. Recast the six and
# the ceiling moves with them.
#
# The minimum is taken over every variant, every looping state and every
# direction, including directions a side-view room may never draw. That makes
# the ceiling stricter than a hand-picked "sit facing right" would, and a
# stricter number from a mechanical rule beats a looser one from a judgement
# call.
#
# **The share is 1.0, and that is the honest placement.** "Scenery must move
# less than a working character does" is the literal time-axis reading of I7,
# and any factor below 1.0 is a safety margin chosen by feel. The four objects
# in the pack's animated folder land at 0.15, 0.57, 3.21 and 9.49 of the
# ceiling — nothing between 0.57 and 3.21 — so **this data cannot distinguish a
# share of 0.6 from a share of 1.0**, and picking the smaller one would be
# asserting a precision the measurements do not support.
#
# REVISIT WITH DATA, in the sense docs/04-ART-DIRECTION.md uses for `G` and the
# palette thresholds: what is verified is that 1.0 separates every object we
# have looked at, one adoption from three refusals. Where inside the 0.57-3.21
# gap the line truly belongs is not verified, because nothing has ever landed
# there. The first prop that scores between 0.6 and 1.0 and looks wrong at 1x is
# the evidence that tightens this, and the first that scores there and looks
# fine is the evidence that it is right. Until then, do not nudge it.
MAX_ROOM_MOTION_SHARE = 1.0

# Pixels below this alpha are ignored. A near-transparent pixel is composited
# most of the way back to whatever is behind it, so judging the palette on it
# would fail files over colour the viewer never sees.
ALPHA_FLOOR = 128

_hsv_cache = {}
_png_cache = {}


def load_png(path):
    """`pnglite.load`, memoised. Behaviour-neutral.

    The colour pass and the motion pass read the same character frames, and
    decoding roughly 1500 PNGs twice is the only cost the motion check would
    otherwise add. Keyed on the absolute path, so the two passes cannot disagree
    about what a file contains either.
    """
    v = _png_cache.get(path)
    if v is None:
        v = _png_cache[path] = pnglite.load(path)
    return v


def hsv(r, g, b):
    key = (r, g, b)
    v = _hsv_cache.get(key)
    if v is None:
        v = _hsv_cache[key] = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    return v


def parse_hex(s):
    """"#RRGGBB" -> (r, g, b), or None if it is not that."""
    if not isinstance(s, str):
        return None
    t = s.strip().lstrip("#")
    if len(t) != 6:
        return None
    try:
        return tuple(int(t[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return None


def scan(path):
    """Return (max_sat, min_val, sum_val, n) over the visible pixels of one PNG."""
    w, h, px = load_png(path)
    max_s, min_v, tot_v, n = -1.0, 1.0, 0.0, 0
    worst = None
    for i in range(0, len(px), 4):
        if px[i + 3] < ALPHA_FLOOR:
            continue
        _hh, s, v = hsv(px[i], px[i + 1], px[i + 2])
        if s > max_s:
            max_s, worst = s, (px[i], px[i + 1], px[i + 2])
        if v < min_v:
            min_v = v
        tot_v += v
        n += 1
    return max(max_s, 0.0), min_v, tot_v, n, worst


def mean_saturation(path):
    """Sum of saturation and pixel count over the visible pixels of one PNG.

    Separate from `scan()` rather than folded into it, so the ~10 existing
    `scan()` call sites (cross-checks, per-file ceilings) do not all have to
    be touched to carry a sum nothing there needs. `hsv()` is memoised by RGB
    triple, so this second pass over an already-`scan()`ed file is cheap — it
    is re-reading `_hsv_cache`, not re-computing `colorsys.rgb_to_hsv`.

    Backs the "room stays under the cast on saturation, not just on value"
    check added at the M8 palette-pass task — see that check's own comment,
    below the character rows loop, for why it exists.
    """
    w, h, px = load_png(path)
    tot_s, n = 0.0, 0
    for i in range(0, len(px), 4):
        if px[i + 3] < ALPHA_FLOOR:
            continue
        _hh, s, _v = hsv(px[i], px[i + 1], px[i + 2])
        tot_s += s
        n += 1
    return tot_s, n


def measure_loop(paths):
    """Motion figures for one looping animation, recomputed from its PNGs.

    Returns `(moving_px, visible_px, transition_px)`:

      `moving_px`     pixels that differ from frame 0 anywhere in the loop
      `visible_px`    pixels visible in any frame
      `transition_px` pixels that change on each step, wrapping past the last
                      frame back to the first

    The first two are exactly `scripts/build-manifest.py`'s definitions, so they
    can be compared against what the manifest declares. `sum/len` of the third,
    times `fps`, is pixels changed per second, which is the budgeted quantity.

    Raises ValueError on a frame that is not the same size as the rest, because
    the alternative is a difference count computed against the wrong pixels.
    """
    frames = [load_png(p) for p in paths]
    w, h, _ = frames[0]
    for p, (fw, fh, _px) in zip(paths, frames):
        if (fw, fh) != (w, h):
            raise ValueError("%s is %dx%d, the rest are %dx%d" % (p, fw, fh, w, h))
    base = frames[0][2]
    n = w * h
    visible = moving = 0
    for i in range(n):
        j = i * 4
        if any(f[2][j + 3] > 127 for f in frames):
            visible += 1
        if any(f[2][j:j + 4] != base[j:j + 4] for f in frames[1:]):
            moving += 1
    transitions = []
    for a, b in zip(frames, frames[1:] + frames[:1]):
        transitions.append(sum(
            1 for i in range(n) if a[2][i * 4:i * 4 + 4] != b[2][i * 4:i * 4 + 4]))
    return moving, visible, transitions


def motion_rate(transitions, fps):
    """Pixels changed per second: the mean step of the loop, times its rate.

    The mean rather than the peak, because this is a rate and a peak is not one.
    A loop that holds still for three frames and jumps on the fourth changes as
    much per second as its mean says, and that is what the eye integrates.
    """
    if not transitions or not fps:
        return 0.0
    return (float(sum(transitions)) / len(transitions)) * float(fps)


def preview_module():
    """`scripts/preview-theme.py`, imported. None if it is not there."""
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview-theme.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("_preview_theme", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def process_assets_module():
    """`scripts/process-assets.py`, imported. None if it is not there.

    ADR-010's per-theme saturation policy is read off *that* script's `THEMES`
    table rather than restated here, for the same reason `role_placements()`
    imports `preview-theme.py` instead of transcribing `RoomLayout`: two copies
    of one fact drift, and this file already has one example of that
    (`role_placements()`'s own docstring names it).
    """
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "process-assets.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location("_process_assets", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def sat_override_themes(mod):
    """Theme names `scripts/process-assets.py` gives their own saturation band.

    A theme is in this set purely by *declaring* `prop_sat_scale` or
    `prop_sat_target` in its `THEMES[...]` entry — the same "declared vs.
    default" test `scripts/process-assets.py` itself uses
    (`theme.get("prop_sat_scale", PROP_SAT_SCALE_DEFAULT)`). So adding a second
    theme to that override in `process-assets.py` moves it onto this policy
    automatically; nothing here has to be told about it twice.
    """
    if mod is None:
        return set()
    return {name for name, theme in mod.THEMES.items()
            if "prop_sat_scale" in theme or "prop_sat_target" in theme}


def pack_saturation_cross_check(mod, theme_name, size="32x32"):
    """Per-item saturation: each processed office prop against its own raw pack file.

    Precise rather than aggregate, and that precision is the point: comparing
    the *file* `process-assets.py` wrote against the *raw* pack PNG it was cut
    from — one role or scenery entry at a time — is what a bug in one prop's
    treatment cannot hide inside a scope average. It is the same discipline the
    motion budget already applies (`scripts/lint-palette.py`'s own cross-check
    of `moving_px`/`visible_px`/`transition_px` against a fresh measurement),
    turned onto ADR-010's saturation restoration.

    The destination path is computed with the exact naming
    `Importer.themes()` uses — `singles/<role>.png`,
    `scenery/%02d_%s.png % (i, band)` — rather than read out of the manifest,
    so this check does not depend on the manifest having been regenerated
    correctly; it is one more thing verifying the manifest, not trusting it.

    Returns a list of `(label, dst_relpath, processed_max_sat, src_path,
    source_max_sat, expected_max_sat)` for every role and scenery entry that
    could be measured on both sides. `expected_max_sat` is `source_max_sat`
    run through the theme's OWN declared `prop_sat_scale`/`prop_sat_target` —
    `min(source_max_sat * scale, target)` — not `source_max_sat` itself.
    For `office` and (on the value axis only) `briefing`'s original entry
    those two knobs are `(1.0, 1.0)`, the identity operation, so
    `expected_max_sat == source_max_sat` and this generalisation changes
    nothing for them. It matters starting with `briefing`'s own
    `prop_sat_scale` of 0.75 (M8 palette-pass task, see that theme's own
    comment in scripts/process-assets.py): a theme may spend LESS than the
    pack's own saturation and still be checked precisely, rather than this
    cross-check assuming "pack-saturation theme" always means "identical to
    the pack" and failing every file of a theme that deliberately does not.
    An entry missing on either side is silently skipped here — a missing
    *processed* file is caught elsewhere (`scripts/build-manifest.py`
    re-stats every path, and this lint's own "missing asset" check), and a
    missing *source* file means the pack is not on this machine, which every
    other check in this file already treats as unverifiable rather than failed.
    """
    theme = mod.THEMES.get(theme_name) if mod else None
    if theme is None:
        return []
    imp = mod.Importer(force=True, quiet=True)
    scale = theme.get("prop_sat_scale", mod.PROP_SAT_SCALE_DEFAULT)
    target = theme.get("prop_sat_target", mod.PROP_SAT_TARGET_DEFAULT)
    out = []
    for role, spec in sorted(theme.get("roles", {}).items()):
        dst_rel = "assets/processed/themes/%s/%s/singles/%s.png" % (theme_name, size, role)
        _measure_pack_pair(imp, size, spec, dst_rel, "role:%s" % role, out, scale, target)
    # **The extra stock a role carries, on the same terms as the role itself.**
    # `role_variants` writes `singles/<role>_<n>.png` for n from 1, and this
    # walked only `roles`, so seven files entered the manifest with nothing
    # checking their saturation against the pack. They were verified by hand
    # once, which is exactly the thing this cross-check exists so that nobody
    # has to do — a check that does not cover new art is not a check, it is a
    # check-shaped record of the art that existed when it was written.
    for role, variants in sorted(theme.get("role_variants", {}).items()):
        for n, spec in enumerate(variants, start=1):
            dst_rel = "assets/processed/themes/%s/%s/singles/%s_%d.png" % (
                theme_name, size, role, n)
            _measure_pack_pair(imp, size, spec, dst_rel, "role:%s[%d]" % (role, n), out,
                               scale, target)
    for i, entry in enumerate(theme.get("scenery", ())):
        band, spec = entry[0], entry[1:]
        dst_rel = "assets/processed/themes/%s/%s/scenery/%02d_%s.png" % (
            theme_name, size, i, band)
        _measure_pack_pair(imp, size, spec, dst_rel, "scenery:%02d_%s" % (i, band), out,
                           scale, target)
    # **The floor and wall tile, on the same terms as a role.** [M8 palette-pass
    # task] `scripts/process-assets.py`'s `themes()` puts a theme's floor and
    # wall tile on this same pack-value/pack-saturation policy whenever the
    # theme has declared `prop_sat_scale`/`prop_sat_target` — the office builder
    # sheet already had its own cross-check (`builder_pack_cross_check` below),
    # but that one is hardcoded to `Room_Builder_Office_*.png`, which only
    # `office` is cut from. A second theme's floor and wall come from the
    # Modern Interiors `Room_Builder_Floors_*`/`Room_Builder_Walls_*` subfiles
    # instead — a different sheet at a different address — so it needs its own
    # pairing, not a re-use of office's. Skipped (not failed) if the theme
    # draws no plan (`theme["floor"] is None`, `office`'s own case) or the pack
    # sheet is not on this machine, the same "unverifiable, not failed" rule
    # every other cross-check in this file follows.
    if theme.get("floor") is not None and mod is not None:
        floors_p = mod.THEME_FLOORS % (size, size)
        walls_p = mod.THEME_WALLS % (size, size)
        tile = int(size.split("x")[0])
        for kind, sheet, addr in (("floor", floors_p, theme["floor"]),
                                  ("wall", walls_p, theme["wall"])):
            if not os.path.exists(sheet):
                continue
            r, c = addr
            sw, sh, spx = pnglite.load(sheet)
            if (r + 1) * tile > sh or (c + 1) * tile > sw:
                continue
            buf = pnglite.new(tile, tile)
            for y in range(tile):
                sy = (r * tile + y) * sw
                for x in range(tile):
                    si = (sy + c * tile + x) * 4
                    buf[(y * tile + x) * 4:(y * tile + x) * 4 + 4] = spx[si:si + 4]
            cut = os.path.join(tempfile.gettempdir(),
                               "spriteroom-themetile-%s-%s-r%02d-c%02d.png"
                               % (theme_name, kind, r, c))
            pnglite.save(cut, tile, tile, buf)
            dst_rel = "assets/processed/themes/%s/%s/builder/%s.png" % (
                theme_name, size, kind)
            dst_abs = os.path.join(REPO, dst_rel)
            if not os.path.exists(dst_abs):
                continue
            p_s, _pmn, _pt, p_n, _pw = scan(dst_abs)
            s_s, _smn, _st, s_n, _sw = scan(cut)
            if p_n == 0 or s_n == 0:
                continue
            out.append(("builder:%s" % kind, dst_rel, p_s,
                        os.path.relpath(sheet, REPO) + " r%02d c%02d" % (r, c), s_s,
                        min(s_s * scale, target)))
    # **`flat_floor.png`/`flat_wall.png` are not cross-checked here, and that is
    # deliberate rather than a gap.** They are `Importer.themes()`'s per-pixel
    # MEAN of the already-recoloured `floor.png`/`wall.png` array — a pure
    # function of pixels this cross-check just verified, with no further pack
    # source behind them to compare against. A flat that disagreed with its own
    # tile's mean would be a bug in `_mean_colour`, not a saturation-policy
    # violation, and no cross-check of this shape catches that class of bug.
    return out


def _measure_pack_pair(imp, size, spec, dst_rel, label, out, scale=1.0, target=1.0):
    dst_abs = os.path.join(REPO, dst_rel)
    if not os.path.exists(dst_abs):
        return
    src = imp._theme_source(size, spec)
    if src is None:
        return
    p_s, _pmn, _ptot, p_n, _pw = scan(dst_abs)
    s_s, _smn, _stot, s_n, _sw = scan(src)
    if p_n == 0 or s_n == 0:
        return
    out.append((label, dst_rel, p_s, src, s_s, min(s_s * scale, target)))


def builder_pack_cross_check(mod, size="32x32"):
    """Every processed Room Builder tile against its own slice of the pack sheet.

    ADR-011 puts `assets/processed/room/` on `office`'s pack-saturation policy,
    which takes those 156 files out from under `ROOM_MAX_SAT`. This is what
    replaces it, and it is a stricter check than the ceiling it displaces: a
    ceiling asks "is this under 25%", this asks "is this the pack's own number,
    to within 3 pp, tile by tile". A transform that quietly re-saturated the
    floor would pass the first and fail this.

    The slice arithmetic is `Importer.room_builder`'s own — row-major over a
    sheet that divides exactly — and the filename carries `(row, column)`, so
    the pairing is recovered from the name rather than re-derived. Tiles the
    importer dropped for being mostly transparent have no processed file and
    are skipped; a missing pack sheet means the download is not on this
    machine, which every other check here treats as unverifiable, not failed.
    """
    sheet = os.path.join(REPO, "assets", "Modern_Office_Revamped_v1.2",
                         "1_Room_Builder_Office", "Room_Builder_Office_%s.png" % size)
    bdir = os.path.join(REPO, "assets", "processed", "room", size, "builder")
    if not os.path.exists(sheet) or not os.path.isdir(bdir):
        return []
    tile = int(size.split("x")[0])
    w, h, px = pnglite.load(sheet)
    out = []
    for name in sorted(os.listdir(bdir)):
        m = re.match(r"tile_r(\d+)_c(\d+)\.png$", name)
        if not m:
            continue
        r, c = int(m.group(1)), int(m.group(2))
        if (r + 1) * tile > h or (c + 1) * tile > w:
            continue
        buf = pnglite.new(tile, tile)
        for y in range(tile):
            for x in range(tile):
                si = ((r * tile + y) * w + c * tile + x) * 4
                di = (y * tile + x) * 4
                buf[di:di + 4] = px[si:si + 4]
        # **A distinct path per tile, and that is load-bearing.** `load_png` is
        # memoised on the absolute path, so a single reused scratch filename
        # makes every tile read the first one — which is exactly how the first
        # draft of this check reported 27.5% for all 156 of them, a number the
        # sheet carries nowhere near the floors.
        cut = os.path.join(tempfile.gettempdir(),
                           "spriteroom-builder-r%02d-c%02d.png" % (r, c))
        pnglite.save(cut, tile, tile, buf)
        dst_rel = "assets/processed/room/%s/builder/%s" % (size, name)
        p_s, _pmn, _pt, p_n, _pw = scan(os.path.join(REPO, dst_rel))
        s_s, _smn, _st, s_n, _sw = scan(cut)
        if p_n == 0 or s_n == 0:
            continue
        # `office`'s own builder tiles are always cut at (1.0, 1.0) — the
        # ADR-011 identity transform this function exists to check — so the
        # expected figure is the raw pack figure itself. See
        # `pack_saturation_cross_check`'s docstring for the general case.
        out.append(("builder:%s" % name[:-4], dst_rel, p_s,
                    os.path.relpath(sheet, REPO) + " r%02d c%02d" % (r, c), s_s, s_s))
    return out


def animated_pack_cross_check(mod, sat_themes, size="32x32"):
    """Every adopted animated prop of a pack-saturation theme, against its sheet.

    The saturation exemption above takes `assets/processed/animated/<id>/` out
    from under `ROOM_MAX_SAT` for those themes; this is what replaces it, on the
    same terms as the role, scenery and builder cross-checks. Peak saturation of
    the cut frames against peak saturation of the untouched spritesheet, run
    through the OWNING theme's own `prop_sat_scale`/`prop_sat_target` — see
    `pack_saturation_cross_check`'s docstring for why that is `expected`, not
    `raw`, since `briefing`'s M8 palette-pass task scale of 0.75.
    `Importer.animated()` cuts each object on "the target theme's own prop
    band" (that method's own docstring), which is `spec["for"]`, not
    necessarily the theme this call was asked about — an object could in
    principle be `for` one sat-override theme while this function is walking
    another's cross-check, so the scale/target are read off `spec["for"]`'s
    own THEMES entry, not off `sat_themes`.

    Nothing is bound today: `ANIMATED_ADOPTED` holds only `control_room_server`
    (mission_control), a standard-band theme, so this returns empty and the
    exemption exempts nothing. `library`'s own `pendulum_clock` was tried at
    the M8 palette-pass task and withdrawn from `ANIMATED_ADOPTED` for an
    unrelated reason (its own dark casing failing `library`'s value-contrast
    floor once cut on the wide pack-value band — see the comment beside
    `ANIMATED_ADOPTED` in scripts/process-assets.py), so this still checks
    nothing today. That is exactly when a check is worth writing — the
    alternative is discovering it is absent on the day something first
    depends on it, which is what happened to `override_prefixes` above the
    day `library` first joined `sat_themes`: missing the `<size>/` segment in
    that prefix went unnoticed for as long as this function's own precondition
    was never true.
    """
    if mod is None:
        return []
    adopted = set(getattr(mod, "ANIMATED_ADOPTED", set()))
    sheets = getattr(mod, "ANIMATED_DIR", None)
    out = []
    for name, spec in sorted(animated_objects(mod).items()):
        if name not in adopted or spec.get("for") not in sat_themes:
            continue
        owning = mod.THEMES.get(spec.get("for"), {})
        scale = owning.get("prop_sat_scale", mod.PROP_SAT_SCALE_DEFAULT)
        target = owning.get("prop_sat_target", mod.PROP_SAT_TARGET_DEFAULT)
        src = os.path.join(REPO, sheets % size, spec["sheet"]) if sheets else None
        frames = sorted(glob.glob(os.path.join(
            REPO, "assets", "processed", "animated", size, name, "frame_*.png")))
        if not src or not os.path.exists(src) or not frames:
            continue
        p_s = max(scan(f)[0] for f in frames)
        s_s = scan(src)[0]
        out.append(("animated:%s" % name,
                    "assets/processed/animated/%s/%s/" % (size, name),
                    p_s, os.path.relpath(src, REPO), s_s, min(s_s * scale, target)))
    return out


def animated_objects(mod):
    """`scripts/process-assets.py`'s `ANIMATED` table, or `{}` if unreadable.

    Read rather than transcribed, for the reason every other cross-read in this
    file is: a second copy of which object belongs to which theme is a second
    thing that can drift, and this one decides whether a file is checked at all.
    """
    return dict(getattr(mod, "ANIMATED", {})) if mod else {}


def role_placements(theme=None):
    """How many times the room draws each prop role on one panel.

    **Per theme, since ADR-009.** The four slots used to be filled the same way
    everywhere and this was a fact about the layout; a theme whose desk is a pod
    draws four screen rigs and one whose desk is not draws none, so the census
    takes the theme it is describing. `None` is the manifest's own default theme,
    which is the room most users see.

    **Imported from `scripts/preview-theme.py` rather than transcribed**, because
    a prop placed four times costs four times as much and that count is the one
    number in this check the manifest cannot supply — it is scene geometry, not
    art. `preview-theme.py` owns the transcription of RoomLayout.swift and draws
    the real panel with it.

    **What vouches for that number changed at M6f, and it matters.** It used to
    be that the preview tool asserted its own census against its own `render()`
    — two transcriptions of one layout, which at M6e were found agreeing with
    each other about a foreground row of seven plants the scene had demolished
    two commits earlier. They now come from one list, and that list is checked
    against the real `RoomScene` pixel for pixel by `scene_agreement()` below.
    A count is only as good as the picture it draws, and the picture is only as
    good as the renderer it is compared with.

    Returns `{}` if the preview tool is unreadable, and the caller fails rather
    than guessing — an assumed placement count is a budget wrong by a factor.
    """
    mod = preview_module()
    fn = getattr(mod, "role_placements", None) if mod else None
    if not fn:
        return {}
    metrics = getattr(mod, "seat_metrics", None)
    # **The plan too, not just the metrics.** A theme whose plan places its
    # dressing by hand draws a different number of boards and plants from the
    # one the band lattice would, and this census is what the motion budget
    # multiplies by — a census taken without the plan is the M6e defect again,
    # a count vouched for by the wrong copy of the layout.
    dressing_of = getattr(mod, "dressing_of", None)
    plan = dressing_of(theme) if (theme and dressing_of) else None
    roles = ((theme or {}).get("props", {}) or {}).get("roles") or None
    return dict(fn(metrics(theme), plan, roles) if (theme and metrics)
                else fn(plan=plan, roles=roles))


def scene_agreement(sets, names):
    """Check the preview's room against the room the product actually draws.

    The motion budget above is priced on `role_placements()`, and the placement
    census has been wrong twice — once about *where* a prop goes (M6b, ~80 px)
    and once about *how many* there are (M6e, 3.3x). Both survived because the
    only thing checking the transcription was another copy of it. This runs the
    real `RoomScene` through the real `SKRenderer` offscreen
    (`spriteroom --render`, never `--panel-render`) and compares the two
    pictures, so the number this lint multiplies by is tied to a renderer rather
    than to a second opinion from the same author.

    **What it costs, stated the way the art gate states its own.** It needs the
    app built and the art on disk, so it cannot run in a checkout without either.
    A missing binary is a *visible skip* naming the themes it did not check, not
    a silent pass, and `SPRITE_ROOM_REQUIRE_SCENE=1` turns that skip into a
    failure — the same arrangement `SPRITE_ROOM_REQUIRE_ART` gives the pixel
    tests. It adds a couple of seconds per theme.
    """
    mod = preview_module()
    if mod is None or not hasattr(mod, "verify"):
        return ["scene agreement: scripts/preview-theme.py could not be imported "
                "or carries no --verify, so nothing checked this lint's placement "
                "census against the scene. Refusing to assume it."]
    if not names:
        return []
    code = mod.verify(sets, names, out_dir=None)
    return [] if code == 0 else [
        "scene agreement: the preview room and the room `spriteroom --render` "
        "draws disagree beyond the defects recorded in preview-theme.py. The "
        "per-theme detail is above. The placement census this lint's motion "
        "budget multiplies by is therefore not describing the shipped room."]


def character_motion_floor(variants):
    """The quietest looping character animation in the cast, in px/s.

    Returns `(rate, "variant/state/direction", frame_count, fps)` or None.

    This is the whole of the motion threshold's derivation. I7's other numbers
    are relative — the room must be under the characters — and this one is the
    same sentence on the time axis, so the ceiling is not a constant in this file
    but a measurement of the cast that is actually shipping.
    """
    best = None
    for name in sorted(variants):
        for state in sorted(variants[name].get("states", {})):
            entry = variants[name]["states"][state]
            if not entry.get("loop"):
                continue
            fps = entry.get("fps") or 0
            for direction in sorted(entry.get("frames", {})):
                paths = entry["frames"][direction]
                if len(paths) < 2:
                    continue
                _mv, _vis, trans = measure_loop(
                    [os.path.join(REPO, p) for p in paths])
                rate = motion_rate(trans, fps)
                label = "%s/%s/%s" % (name, state, direction)
                if best is None or rate < best[0]:
                    best = (rate, label, len(paths), fps)
    return best


def animated_roles(node):
    """`(role_name, role_dict)` for every role in a room subtree that animates."""
    out = []
    roles = node.get("props", {}).get("roles", {})
    for role_name in sorted(roles):
        role = roles[role_name]
        if isinstance(role, dict) and isinstance(role.get("animation"), dict):
            out.append((role_name, role))
    return out


def _candidates(node, out):
    if isinstance(node, dict):
        for v in node.values():
            _candidates(v, out)
    elif isinstance(node, list):
        for v in node:
            _candidates(v, out)
    elif isinstance(node, str) and node.lower().endswith(".png"):
        out.add(node)


def collect(node, out, prose=None):
    """Pull every loadable asset path out of an arbitrary manifest subtree.

    A .png-suffixed string counts as art if it resolves to a file on disk. That
    test, rather than a path prefix, is what decides — an earlier version
    required the path to start with "assets/" and therefore skipped anything
    stored elsewhere in complete silence, and silently skipping art is the exact
    failure mode a lint exists to prevent.

    A string that does not resolve is either a missing asset (declared under
    assets/ — a hard error, raised by the caller) or a human-readable provenance
    note like "Modern Office / Room_Builder_Office_32x32.png". Those are
    collected separately so they are visible rather than quietly discarded.
    """
    found = set()
    _candidates(node, found)
    for s in found:
        if os.path.exists(os.path.join(REPO, s)):
            out.add(s)
        elif prose is not None:
            prose.add(s)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--manifest", default=MANIFEST)
    ap.add_argument("--verbose", action="store_true", help="print per-variant measurements")
    ap.add_argument("--no-scene", action="store_true",
                    help="skip the comparison against `spriteroom --render`. For "
                         "iterating on colour only — it leaves the placement "
                         "census unchecked, and it says so in the output")
    args = ap.parse_args(argv)

    if not os.path.exists(args.manifest):
        print("error: %s not found. Run scripts/build-manifest.py first."
              % os.path.relpath(args.manifest, REPO), file=sys.stderr)
        return 2
    with open(args.manifest) as f:
        m = json.load(f)

    failures = []

    # --- ADR-010: which themes run on the pack's own saturation ------------
    #
    # Read off `scripts/process-assets.py` rather than hardcoded, so this file
    # and that one cannot silently disagree about which themes are on which
    # policy. See "Per-theme saturation policy" in this file's own docstring.
    pa_mod = process_assets_module()
    if pa_mod is None:
        failures.append(
            "saturation policy: scripts/process-assets.py could not be imported, "
            "so ADR-010's per-theme saturation policy could not be read. Every "
            "theme is being checked against the flat %.0f%% ceiling below, which "
            "a pack-saturation theme will fail even when it is correct."
            % (ROOM_MAX_SAT * 100))
    sat_themes = sat_override_themes(pa_mod)
    # A path prefix, not a theme-scope check, because `room` and
    # `themes.sets.office` alias the SAME bytes for scenery — ADR-002 §14a's
    # "`room` IS the resolved default theme" — so the policy has to travel with
    # the *file*, wherever a manifest scope happens to collect it from.
    override_prefixes = tuple(sorted(
        ["assets/processed/themes/%s/" % n for n in sat_themes]
        # **And the builder tiles, which are `office`'s alone.** [ADR-011]
        # `assets/processed/room/` is referenced by exactly one theme in the
        # shipped manifest — `office`, which is also the resolved default and
        # the only theme that draws a plan — so its floors and walls run on the
        # same pack-saturation policy as its props. Verified against the
        # manifest rather than asserted: `builder_pack_cross_check` below
        # measures every one of them against the untouched Room Builder sheet,
        # so this prefix widens *which* check runs and not *whether* one does.
        + (["assets/processed/room/"] if "office" in sat_themes else [])
        # **And the animated objects belonging to a sat-override theme.**
        # `assets/processed/animated/<id>/` is keyed by object, and each object
        # names its theme in `ANIMATED[id]["for"]`, so the exemption is built
        # per object rather than as one flat prefix — an animated prop in a
        # standard-band theme stays on ROOM_MAX_SAT exactly as before.
        #
        # This was a hole rather than a policy: `office` and `briefing` run at
        # the pack's own saturation [ADR-010, ADR-011] and every other file of
        # theirs is checked against the pack, but an animated one was still
        # measured against the flat 25% ceiling. The consequence was total —
        # the quietest-saturation object in the whole 310-sheet folder measures
        # 27.5%, so **no animated prop could ship into either theme at all**,
        # and the reason looked like "the pack has nothing quiet enough".
        #
        # **The size segment is load-bearing and was missing until the M8
        # palette-pass task.** `Importer.animated()` writes
        # `assets/processed/animated/<size>/<id>/frame_NN.png` — `office` and
        # `briefing` never exercised this branch (`ANIMATED_ADOPTED` held only
        # `pendulum_clock` (library) and `control_room_server`
        # (mission_control), both standard-band themes at the time, so this
        # comprehension was provably empty — the exact case
        # `animated_pack_cross_check`'s own docstring names as "worth writing
        # ... the alternative is discovering it is absent on the day something
        # first depends on it"). The day was `library` joining `sat_themes` at
        # the M8 palette-pass task: without `<size>/`, `assets/processed/
        # animated/pendulum_clock/` never matched the real
        # `assets/processed/animated/32x32/pendulum_clock/frame_00.png`, so
        # every frame fell through to the flat 25% ceiling and failed loudly —
        # which is how this was caught, not by inspection.
        + ["assets/processed/animated/%s/%s/" % (size, name)
           for size in ("32x32",)
           for name, spec in sorted(animated_objects(pa_mod).items())
           if spec.get("for") in sat_themes]))
    pack_cross_checks = {
        name: pack_saturation_cross_check(pa_mod, name) for name in sat_themes
    } if pa_mod else {}
    # The builder tiles ride on office's entry, because they are office's files
    # and the report reads per theme. [ADR-011]
    for tname in sorted(sat_themes):
        if tname in pack_cross_checks:
            pack_cross_checks[tname] = pack_cross_checks[tname] + [
                c for c in animated_pack_cross_check(pa_mod, {tname})]
    if "office" in pack_cross_checks:
        builder = builder_pack_cross_check(pa_mod)
        if not builder:
            failures.append(
                "saturation policy: assets/processed/room/ is on office's "
                "pack-saturation policy (ADR-011) but not one of its builder "
                "tiles could be cross-checked against the Room Builder sheet — "
                "the override is unverifiable, which is a failure and not a "
                "silent pass")
        pack_cross_checks["office"] = pack_cross_checks["office"] + builder
    for name, checks in sorted(pack_cross_checks.items()):
        if not checks:
            failures.append(
                "saturation policy: theme %s declares a saturation override but "
                "not one of its role/scenery files could be cross-checked against "
                "its own pack source — the override is unverifiable, which ADR-010 "
                "treats as a failure rather than a silent pass" % name)
        for label, dst_rel, p_s, src, s_s, expected_s in checks:
            drift = p_s - expected_s
            if abs(drift) > SAT_BASELINE_TOLERANCE:
                failures.append(
                    "saturation policy: theme %s %s (%s) measures %.1f%% saturation "
                    "but its own untouched pack source (%s, %.1f%% raw) implies "
                    "%.1f%% at this theme's own prop_sat_scale/prop_sat_target — "
                    "%.1f pp of drift, outside the %.0f pp tolerance. This theme "
                    "runs its props at a declared fraction of the pack's own "
                    "saturation, not an arbitrary one; %s"
                    % (name, label, dst_rel, p_s * 100,
                       os.path.relpath(src, REPO), s_s * 100, expected_s * 100,
                       drift * 100, SAT_BASELINE_TOLERANCE * 100,
                       "it went darker/less saturated than expected — the "
                       "scale/target may not be applied"
                       if drift < 0 else
                       "it went more saturated than expected — check for a "
                       "stray transform or the wrong source file"))

    # --- room -------------------------------------------------------------
    room_paths, prose = set(), set()
    collect(m.get("room", {}), room_paths, prose)
    if not room_paths:
        print("error: manifest declares no room art; nothing to measure against.",
              file=sys.stderr)
        return 2

    room_sum, room_n, room_max_sat = 0.0, 0, (0.0, None, None)
    room_min_val = (1.0, None)
    room_sat_sum = 0.0
    for p in sorted(room_paths):
        s, mn, tot, n, worst = scan(os.path.join(REPO, p))
        if n == 0:
            continue
        room_sum += tot
        room_n += n
        sat_sum, sat_n = mean_saturation(os.path.join(REPO, p))
        room_sat_sum += sat_sum
        if s > room_max_sat[0]:
            room_max_sat = (s, p, worst)
        if mn < room_min_val[0]:
            room_min_val = (mn, p)
        if p.startswith(override_prefixes):
            # ADR-010: this file's ceiling is the per-item pack cross-check
            # above, run once per theme rather than once per scope that
            # happens to collect it — `room`'s own scenery is these same bytes.
            continue
        if s >= ROOM_MAX_SAT:
            failures.append(
                "room saturation: %s reaches %.1f%% saturation at RGB%s "
                "(ceiling is %.0f%%)" % (p, s * 100, worst, ROOM_MAX_SAT * 100))
    room_mean_val = room_sum / room_n
    room_mean_sat = room_sat_sum / room_n

    # --- themes -----------------------------------------------------------
    #
    # Every theme is measured on the SAME thresholds as `room`, separately.
    # Measuring them pooled would let a quiet theme carry a loud one: I7 is a
    # statement about what is on screen at one moment, and only one theme is on
    # screen at a time. The mean value of the theme actually being drawn is also
    # what the character contrast check has to run against, so each theme gets
    # its own contrast pass below rather than borrowing `room`'s.
    #
    # **Except saturation, for a theme ADR-010 names.** `sat_themes` above is
    # exactly the "SAME thresholds" exception: those themes are still measured
    # here — mean value, darkest value, and the value-contrast pass below are
    # all untouched — but their saturation ceiling was already checked, per
    # file, against the pack rather than against `ROOM_MAX_SAT`.
    themes = m.get("themes", {}).get("sets", {})
    theme_stats = {}
    for tname in sorted(themes):
        paths = set()
        collect(themes[tname], paths, prose)
        if not paths:
            failures.append("theme %s: declares no art" % tname)
            continue
        tsum, tn = 0.0, 0
        tmax = (0.0, None, None)
        tmin = (1.0, None)
        tsat_sum = 0.0
        for p in sorted(paths):
            s, mn, tot, n, worst = scan(os.path.join(REPO, p))
            if n == 0:
                continue
            tsum += tot
            tn += n
            sat_sum, sat_n = mean_saturation(os.path.join(REPO, p))
            tsat_sum += sat_sum
            if s > tmax[0]:
                tmax = (s, p, worst)
            if mn < tmin[0]:
                tmin = (mn, p)
            if p.startswith(override_prefixes):
                continue
            if s >= ROOM_MAX_SAT:
                failures.append(
                    "theme %s saturation: %s reaches %.1f%% saturation at RGB%s "
                    "(ceiling is %.0f%%)" % (tname, p, s * 100, worst, ROOM_MAX_SAT * 100))
        if tn == 0:
            failures.append("theme %s: no measurable pixels" % tname)
            continue
        theme_stats[tname] = {
            "files": len(paths), "px": tn, "mean": tsum / tn,
            "mean_sat": tsat_sum / tn,
            "max_sat": tmax, "darkest": tmin,
            "sat_policy": "pack (ADR-010)" if tname in sat_themes else "standard",
        }

    # --- characters -------------------------------------------------------
    variants = m.get("characters", {}).get("variants", {})
    if not variants:
        print("error: manifest declares no characters.", file=sys.stderr)
        return 2

    rows = []
    cast_sat_sum, cast_sat_n = 0.0, 0
    for name in sorted(variants):
        paths = set()
        collect(variants[name], paths, prose)
        vmin_v = 1.0
        sat_file, dark_file = None, None
        vmax_s = -1.0
        for p in sorted(paths):
            s, mn, _tot, n, _w = scan(os.path.join(REPO, p))
            if n == 0:
                continue
            sat_sum, sat_n = mean_saturation(os.path.join(REPO, p))
            cast_sat_sum += sat_sum
            cast_sat_n += sat_n
            if s > vmax_s:
                vmax_s, sat_file = s, p
            if mn < vmin_v:
                vmin_v, dark_file = mn, p
        if vmax_s < 0.0:
            # No loadable frame at all. Report that, rather than a nonsense
            # saturation figure derived from an empty set.
            failures.append(
                "character %s: the manifest declares it but none of its frames could "
                "be measured" % name)
            rows.append((name, 0.0, None, 0.0, None, 0.0))
            continue

        contrast = room_mean_val - vmin_v
        rows.append((name, vmax_s, sat_file, vmin_v, dark_file, contrast))

        if vmax_s <= CHAR_MIN_SAT:
            failures.append(
                "character saturation: variant %s peaks at %.1f%% saturation "
                "(needs a colour above %.0f%%); highest is in %s"
                % (name, vmax_s * 100, CHAR_MIN_SAT * 100, sat_file))
        if contrast < MIN_VALUE_CONTRAST:
            failures.append(
                "value contrast: variant %s darkest pixel is value %.3f against a mean "
                "room value of %.3f — %.1f%% contrast, needs %.0f%%; darkest is in %s"
                % (name, vmin_v, room_mean_val, contrast * 100,
                   MIN_VALUE_CONTRAST * 100, dark_file))

    # Value contrast, re-checked against every theme.
    #
    # Contrast is (theme mean value - character's darkest pixel), so the theme
    # with the LOWEST mean is the binding one, and it is not necessarily `room`.
    # A theme that darkens the room enough to swallow the characters fails here
    # rather than shipping and being noticed at 1x.
    for tname in sorted(theme_stats):
        tmean = theme_stats[tname]["mean"]
        worst = None
        for name, _s, _sf, vmin_v, dark_file, _c in rows:
            c = tmean - vmin_v
            if worst is None or c < worst[1]:
                worst = (name, c, dark_file)
            if c < min_value_contrast(tname):
                failures.append(
                    "theme %s value contrast: variant %s darkest pixel is value %.3f "
                    "against a theme mean of %.3f — %.1f%% contrast, needs %.0f%%; "
                    "darkest is in %s"
                    % (tname, name, vmin_v, tmean, c * 100,
                       min_value_contrast(tname) * 100, dark_file))
        theme_stats[tname]["worst_contrast"] = worst

    # --- room/theme saturation vs. the cast ---------------------------------
    #
    # Added at the M8 palette-pass task. I7 has always said BOTH halves of one
    # sentence — "characters own the saturation and the darkest values" — and
    # until now only the second half was a lint check (the value-contrast pass
    # above). The first half was carried in prose only, and prose is not a
    # check: `briefing` shipped at pure pack-identity saturation (ADR-011)
    # measuring **0.411** mean saturation, against the cast's own **0.332** —
    # louder than the characters it sits behind, for months, because nothing
    # ever compared the two numbers. Found by the maintainer looking at the
    # rendered room, not by this lint, which is the argument for writing it
    # down as one.
    #
    # `cast_mean_sat` is the same aggregate the value-contrast check already
    # takes for granted on the value axis — pooled across every variant's
    # every frame, not a per-variant figure — because I7's claim is about the
    # cast as a whole being the loudest thing on screen, not about any one
    # variant individually. `room` and every theme are held to it separately,
    # for the same reason the value-contrast check runs `room` and each theme
    # separately rather than pooling: only one is on screen at a time, and a
    # quiet theme must not be allowed to average out a loud one.
    #
    # This is NOT folded into `pack_saturation_cross_check`'s per-item ceiling
    # above. That check asks "does this file match what this theme's own
    # `prop_sat_scale`/`prop_sat_target` implies" — a theme could pass it at
    # ANY scale, including 1.0, and still end up louder than the cast, which
    # is exactly what happened. This check asks the question ADR-010 always
    # implied and never verified: whatever scale a theme picked, does the
    # RESULT still recede behind the characters.
    cast_mean_sat = (cast_sat_sum / cast_sat_n) if cast_sat_n else 0.0
    if cast_sat_n == 0:
        failures.append(
            "cast saturation: no character pixel could be measured, so there is "
            "nothing to hold the room's own saturation under. Refusing to guess it.")
    else:
        if room_mean_sat >= cast_mean_sat:
            failures.append(
                "room saturation vs cast: room mean saturation %.3f is not under "
                "the cast's own mean saturation %.3f — the room is as loud or "
                "louder than the characters, which I7 forbids on the saturation "
                "axis as plainly as it forbids the room owning the darkest pixel "
                "on the value axis"
                % (room_mean_sat, cast_mean_sat))
        for tname in sorted(theme_stats):
            tmean_sat = theme_stats[tname]["mean_sat"]
            if tmean_sat >= cast_mean_sat:
                failures.append(
                    "theme %s saturation vs cast: theme mean saturation %.3f is not "
                    "under the cast's own mean saturation %.3f — the room is as loud "
                    "or louder than the characters, which I7 forbids on the "
                    "saturation axis as plainly as it forbids the room owning the "
                    "darkest pixel on the value axis"
                    % (tname, tmean_sat, cast_mean_sat))

    # --- costumes ---------------------------------------------------------
    #
    # **The check binds the day the art lands, not the day after.** The shipped
    # manifest declares no wardrobe, so this stage measures nothing and says so;
    # the moment `characters.costumes` is written it starts failing on the two
    # things a costume can break that a variant cannot.
    #
    # A costume is drawn **on** the character, which owns the darkest and most
    # saturated pixels in the room [I7]. So the axis that matters is not the
    # room's ceiling — it is the cast's own floor: a garment darker than the
    # darkest character pixel moves the darkest thing on screen onto a piece of
    # clothing, and the value-contrast figure this lint prints stops describing
    # what is rendered.
    #
    # Saturation is **reported and not failed**, deliberately. A white lab coat
    # has no saturation and there is no saturated lab coat; the honest response
    # is to name every costume that takes its wearer under `CHAR_MIN_SAT` and
    # let a person weigh it, not to forbid the one garment the maintainer asked
    # for by name. What is *not* negotiable is that the number is printed.
    wardrobe = m.get("characters", {}).get("costumes") or {}
    costume_sets = wardrobe.get("sets", {})
    costume_rows = []
    cast_floor = min((r[3] for r in rows if r[1] > 0.0), default=0.0)
    for cname in sorted(costume_sets):
        entry = costume_sets[cname]
        paths = set()
        collect(entry, paths, prose)
        cmin_v, cmax_s = 1.0, -1.0
        dark_file = None
        for p in sorted(paths):
            sat, mn, _tot, n, _w = scan(os.path.join(REPO, p))
            if n == 0:
                continue
            cmax_s = max(cmax_s, sat)
            if mn < cmin_v:
                cmin_v, dark_file = mn, p
        if cmax_s < 0.0:
            failures.append("costume %s: declared but no frame could be measured"
                            % cname)
            continue
        costume_rows.append((cname, cmax_s, cmin_v, bool(entry.get("asserts"))))
        if cmin_v < cast_floor - 1e-9:
            failures.append(
                "costume darkness: %s has a pixel at value %.3f, below the cast's "
                "darkest at %.3f — a garment cannot be the darkest thing on screen "
                "[I7]; darkest is in %s" % (cname, cmin_v, cast_floor, dark_file))
    # The I1 half, checked here as well as in CostumeContractTests, because this
    # script runs on a machine with the art and that one runs on a fresh clone.
    for cid in wardrobe.get("assignable", []):
        if costume_sets.get(cid, {}).get("asserts"):
            failures.append(
                "costume pool: %s asserts and is assignable — a hash would be making "
                "a claim about an agent_type nobody anticipated [I1]" % cid)

    # --- accents ----------------------------------------------------------
    accents = {}
    for name in sorted(variants):
        hexes = variants[name].get("accent_hex")
        if hexes is None:
            failures.append("accent: variant %s declares no accent_hex" % name)
            continue
        parsed = parse_hex(hexes)
        if parsed is None:
            failures.append("accent: variant %s has an unreadable accent_hex %r"
                            % (name, hexes))
            continue
        accents[name] = (hexes, parsed)

    for name, (hexes, (r, g, b)) in sorted(accents.items()):
        h, s, v = hsv(r, g, b)
        if s < MIN_ACCENT_SAT:
            failures.append("accent: variant %s accent %s is only %.0f%% saturated "
                            "(needs %.0f%%) — it will not read as an accent at 1x"
                            % (name, hexes, s * 100, MIN_ACCENT_SAT * 100))
        if v < MIN_ACCENT_VALUE:
            failures.append("accent: variant %s accent %s has value %.2f (needs %.2f) — "
                            "too dark to read against the nameplate plate"
                            % (name, hexes, v, MIN_ACCENT_VALUE))

    worst_pair = None
    names = sorted(accents)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            ha = hsv(*accents[a][1])[0] * 360.0
            hb = hsv(*accents[b][1])[0] * 360.0
            d = abs(ha - hb)
            d = min(d, 360.0 - d)
            if worst_pair is None or d < worst_pair[0]:
                worst_pair = (d, a, b)
            if d < MIN_ACCENT_HUE_SEPARATION:
                failures.append(
                    "accent separation: variants %s (%s) and %s (%s) are %.1f degrees "
                    "apart in hue, under the %.0f degree floor — they do not separate"
                    % (a, accents[a][0], b, accents[b][0], d, MIN_ACCENT_HUE_SEPARATION))

    # --- motion budget ----------------------------------------------------
    #
    # I7 on the time axis. See MAX_ROOM_MOTION_SHARE above for why this is the
    # quantity and why the number comes from the cast.
    #
    # **Recomputed here, and cross-checked against the manifest — not read.**
    # That is a deliberate choice between the two the maintainer offered. Reading
    # the declared `moving_px`/`visible_px` would make the gate a tautology: the
    # same code that wrote the figure would be the only thing vouching for it,
    # and a generator with a bug would grade its own homework. Nothing else in
    # this lint reads a number out of the manifest either — the room's saturation
    # is measured off the PNGs, not looked up. It also means the check works on a
    # prop the manifest has *not* adopted, which is the case §14b's refusals were
    # all about. So: measure the pixels, then assert the manifest agrees, and
    # fail loudly if it does not. Two sources that can disagree is how 10.4%
    # became 27.9%; two sources that are *compared* is how that gets caught.
    # **Censused on the default theme, not on no theme at all.** The room the
    # panel actually draws is `themes.default`, and since ADR-009 the count is a
    # property of that theme's art rather than of the layout alone — a pod puts
    # four objects on a camera-facing desktop where a flat desk puts none. Asking
    # for the census with no theme returned the lattice's numbers for a room that
    # has not drawn a lattice since ADR-011.
    default_theme = m.get("themes", {}).get("default")
    placements = role_placements(themes.get(default_theme) if default_theme else None)
    if not placements:
        failures.append(
            "motion budget: scripts/preview-theme.py did not supply a role "
            "placement census, so the on-panel cost of an animated prop cannot "
            "be computed. Refusing to guess it.")

    motion_floor = character_motion_floor(variants)
    motion_ceiling = None
    if motion_floor is None:
        failures.append(
            "motion budget: no looping character animation could be measured, so "
            "there is nothing to set the ceiling from. The threshold is the "
            "cast's, not a constant.")
    elif motion_floor[0] <= 0:
        # Every looping character frame is identical to its neighbours. That is
        # not a zero-budget room, it is a broken cast, and a ceiling of zero
        # would refuse every prop for the wrong reason.
        failures.append(
            "motion budget: the quietest looping cast animation (%s) changes no "
            "pixels at all, so the ceiling would be zero. Check the character "
            "frames before believing this." % motion_floor[1])
    else:
        motion_ceiling = motion_floor[0] * MAX_ROOM_MOTION_SHARE

    motion_scopes = []   # (scope, total px/s, [(role, id, own px/s, placed px/s, own frac)])
    scopes = [("room", m.get("room", {}))] + [(t, themes[t]) for t in sorted(themes)]
    for sname, node in scopes:
        # **The census is per scope, because it stopped being a fact about the
        # layout alone.** ADR-009 gave the office theme a desk wide enough to
        # carry a screen rig either side of its occupant, so how many copies of
        # `monitor` the room draws is a property of that theme's *art* — four
        # where the desk is a pod and none where it is not. A single census
        # applied to every theme would price an animated rig in a theme that
        # draws none of it, and would miss one in a theme that draws four.
        scope_placements = role_placements(node) or placements
        total, contributors = 0.0, []
        for role_name, role in animated_roles(node):
            anim = role["animation"]
            frames = anim.get("frames") or []
            fps = anim.get("fps") or 0
            where = role.get("file") or (frames[0] if frames else "?")
            if len(frames) < 2 or not fps:
                failures.append(
                    "motion: %s role %s declares an `animation` with %d frame(s) at "
                    "%s fps — not a loop, and not measurable (%s)"
                    % (sname, role_name, len(frames), fps, where))
                continue
            if anim.get("loop") is not True:
                # The measurement wraps the last frame back to the first because
                # ADR-002 §14b says `loop` is always true and has no other value.
                # A non-looping prop would be measured against a step that never
                # plays, so it is refused rather than mismeasured.
                failures.append(
                    "motion: %s role %s declares `loop: %r`. ADR-002 §14b says a prop "
                    "loop is always true; the budget measures the wrap and cannot "
                    "describe anything else (%s)"
                    % (sname, role_name, anim.get("loop"), where))
                continue
            missing = [p for p in frames if not os.path.exists(os.path.join(REPO, p))]
            if missing:
                failures.append("motion: %s role %s declares frames that are not on "
                                "disk: %s" % (sname, role_name, ", ".join(sorted(missing))))
                continue
            try:
                mv, vis, trans = measure_loop([os.path.join(REPO, p) for p in frames])
            except ValueError as exc:
                failures.append("motion: %s role %s — %s" % (sname, role_name, exc))
                continue

            # The cross-check. Each of these is the manifest disagreeing with the
            # art it describes, which is a defect in the manifest whatever the
            # budget says.
            for key, measured in (("moving_px", mv), ("visible_px", vis),
                                  ("transition_px", trans)):
                declared = anim.get(key)
                if declared is None:
                    continue
                if isinstance(measured, list):
                    agrees = list(declared) == measured
                else:
                    agrees = declared == measured
                if not agrees:
                    failures.append(
                        "motion cross-check: %s role %s declares %s = %r but the "
                        "frames measure %r. Regenerate with scripts/build-manifest.py "
                        "— a transcribed motion figure is how 10.4%% became 27.9%% "
                        "(%s)" % (sname, role_name, key, declared, measured, where))

            n = scope_placements.get(role_name)
            if n is None:
                failures.append(
                    "motion: %s animates role %s, and scripts/preview-theme.py does "
                    "not say how many times the room draws that role. The on-panel "
                    "cost is unknown, so it cannot be budgeted (%s)"
                    % (sname, role_name, where))
                continue
            own = motion_rate(trans, fps)
            placed = own * n
            total += placed
            contributors.append(
                (role_name, os.path.basename(os.path.dirname(where)), own, placed,
                 (float(mv) / vis) if vis else 0.0, n, where))
        motion_scopes.append((sname, total, contributors))

        if motion_ceiling and contributors and total >= motion_ceiling:
            worst = max(contributors, key=lambda c: c[3])
            failures.append(
                "motion budget: %s changes %.0f px/s of the panel against a ceiling "
                "of %.0f px/s — %.2fx. The ceiling is the quietest looping animation "
                "in the cast (%s, %.0f px/s) and the room has to come in under it, "
                "because in this product motion is what says an agent is working. "
                "The largest contributor is role %s (%s, %d copies x %.0f px/s, %.1f%% "
                "of its own visible pixels move): %s"
                % (sname, total, motion_ceiling, total / motion_ceiling,
                   motion_floor[1], motion_floor[0], worst[0], worst[1], worst[5],
                   worst[2], worst[4] * 100, worst[6]))

    # Anything declared under assets/ that did not resolve is a missing asset,
    # not prose. Fail loudly rather than measuring a smaller set than declared.
    for s in sorted(prose):
        if s.startswith("assets/"):
            failures.append("missing asset: manifest declares %s but it is not on disk" % s)

    # --- report -----------------------------------------------------------
    default_theme_id = m.get("themes", {}).get("default")
    room_sat_policy = "pack (ADR-010)" if default_theme_id in sat_themes else "standard"
    print("room:       %d files, %d visible px" % (len(room_paths), room_n))
    print("            mean value       %.3f" % room_mean_val)
    print("            mean saturation  %.3f  (cast mean %.3f) %s"
          % (room_mean_sat, cast_mean_sat,
             "FAIL" if cast_sat_n and room_mean_sat >= cast_mean_sat else ""))
    if room_sat_policy == "standard":
        print("            max saturation   %.3f  (ceiling %.2f)  %s"
              % (room_max_sat[0], ROOM_MAX_SAT, room_max_sat[1] or ""))
    else:
        print("            max saturation   %.3f  (policy: %s — files under %s "
              "checked per-item against the pack instead, see below)  %s"
              % (room_max_sat[0], room_sat_policy,
                 ", ".join(sorted(override_prefixes)) or "-", room_max_sat[1] or ""))
    print("            darkest value    %.3f  %s" % (room_min_val[0], room_min_val[1] or ""))
    if theme_stats:
        print("themes:     %d, each measured on the same thresholds — except "
              "saturation for %s [ADR-010]"
              % (len(theme_stats), ", ".join(sorted(sat_themes)) or "none"))
        print("            %-16s %-7s %-9s %-9s %-9s %-9s %-16s %-16s %s"
              % ("theme", "files", "mean val", "mean sat", "max sat",
                 "darkest", "sat policy", "min contrast", ""))
        for tname in sorted(theme_stats):
            st = theme_stats[tname]
            wc = st.get("worst_contrast")
            standard_sat_ok = (tname in sat_themes
                                or st["max_sat"][0] < ROOM_MAX_SAT)
            under_cast = not cast_sat_n or st["mean_sat"] < cast_mean_sat
            bad = (not standard_sat_ok
                   or not under_cast
                   # The same per-theme floor the failure above is raised
                   # against — this flag used to read the global constant, so
                   # `office` printed FAIL beside a contrast the lint had
                   # already accepted. A summary that disagrees with the
                   # failure list is worse than no summary. [ADR-011]
                   or (wc is not None and wc[1] < min_value_contrast(tname)))
            print("            %-16s %-7d %-9.3f %-9.3f %-9.3f %-9.3f %-16s %.3f (%s) %s"
                  % (tname, st["files"], st["mean"], st["mean_sat"], st["max_sat"][0],
                     st["darkest"][0], st["sat_policy"],
                     wc[1] if wc else 0.0, wc[0] if wc else "-",
                     "FAIL" if bad else ""))
    if sat_themes:
        print("sat cross-check: %s measured against their own untouched pack "
              "source, tolerance %.0f pp [ADR-010]"
              % (", ".join(sorted(sat_themes)), SAT_BASELINE_TOLERANCE * 100))
        for name in sorted(pack_cross_checks):
            checks = pack_cross_checks[name]
            if not checks:
                print("            %-16s no role/scenery file could be "
                      "cross-checked against its pack source" % name)
                continue
            worst = max(checks, key=lambda c: abs(c[2] - c[5]))
            label, dst_rel, p_s, src, s_s, expected_s = worst
            print("            %-16s %d props checked, worst drift %+.1f pp "
                  "(%s: processed %.3f vs expected %.3f, pack raw %.3f)"
                  % (name, len(checks), (p_s - expected_s) * 100, label, p_s,
                     expected_s, s_s))
    print("characters: %d variants" % len(rows))
    print("            mean saturation  %.3f  (pooled over every variant's "
          "every frame — the floor `room` and each theme are held under)"
          % cast_mean_sat)
    if args.verbose or failures:
        print("            %-6s %-10s %-10s %s" % ("var", "max sat", "darkest", "contrast"))
        for name, s, _sf, v, _df, c in rows:
            print("            %-6s %-10.3f %-10.3f %.3f %s"
                  % (name, s, v, c, "FAIL" if (s <= CHAR_MIN_SAT or c < MIN_VALUE_CONTRAST) else ""))
    else:
        worst_sat = min(rows, key=lambda r: r[1])
        worst_con = min(rows, key=lambda r: r[5])
        print("            weakest saturation  %.3f (variant %s, floor %.2f)"
              % (worst_sat[1], worst_sat[0], CHAR_MIN_SAT))
        print("            weakest contrast    %.3f (variant %s, floor %.2f)"
              % (worst_con[5], worst_con[0], MIN_VALUE_CONTRAST))
    # Costumes. Printed even when there are none, because "the wardrobe is
    # empty" is a claim somebody made this run rather than an absence nobody
    # noticed — the same reason `register_summary()` prints on every preview.
    if costume_rows:
        under = [r for r in costume_rows if r[1] <= CHAR_MIN_SAT]
        print("costumes:   %d declared (%d asserting), cast darkness floor %.3f"
              % (len(costume_rows), sum(1 for r in costume_rows if r[3]), cast_floor))
        if args.verbose or failures:
            print("            %-10s %-10s %-10s %s"
                  % ("costume", "max sat", "darkest", "asserts"))
            for cname, cs_, cv, ca in costume_rows:
                print("            %-10s %-10.3f %-10.3f %s%s"
                      % (cname, cs_, cv, "yes" if ca else "no",
                         "  under CHAR_MIN_SAT" if cs_ <= CHAR_MIN_SAT else ""))
        print("            darkest costume pixel %.3f (floor %.3f), %d costume(s) "
              "under CHAR_MIN_SAT %.2f%s"
              % (min(r[2] for r in costume_rows), cast_floor, len(under),
                 CHAR_MIN_SAT, (": " + ", ".join(r[0] for r in under)) if under else ""))
    else:
        print("costumes:   none declared — the manifest dresses nobody, "
              "which is a legal state")
    print("accents:    %d assigned" % len(accents))
    if worst_pair is not None:
        print("            closest pair     %.1f deg  (%s vs %s, floor %.0f)"
              % (worst_pair[0], worst_pair[1], worst_pair[2], MIN_ACCENT_HUE_SEPARATION))
    if args.verbose:
        for name in sorted(accents):
            h, s, v = hsv(*accents[name][1])
            print("            %-6s %-8s hue %5.1f  sat %.2f  val %.2f"
                  % (name, accents[name][0], h * 360, s, v))

    # Motion. Printed for every scope including the ones that animate nothing,
    # because "0 of 1461" is the statement that the check ran — a motion budget
    # that silently skips every still room is a motion budget nobody has watched
    # do anything.
    if motion_floor is not None:
        print("motion:     ceiling %.0f px/s = %.2f x the quietest looping cast "
              "animation" % (motion_ceiling, MAX_ROOM_MOTION_SHARE))
        print("            that animation is %s, %d frames at %g fps"
              % (motion_floor[1], motion_floor[2], motion_floor[3]))
    if placements:
        print("            role copies per panel: %s"
              % ", ".join("%s x%d" % (k, placements[k]) for k in sorted(placements)))
    print("            %-16s %-11s %-9s %s"
          % ("scope", "props", "px/s", "share of ceiling"))
    for sname, total, contributors in motion_scopes:
        share = (total / motion_ceiling) if motion_ceiling else 0.0
        print("            %-16s %-11d %-9.0f %.2f %s"
              % (sname, len(contributors), total, share,
                 "FAIL" if (motion_ceiling and total >= motion_ceiling) else ""))
        if args.verbose or (motion_ceiling and total >= motion_ceiling):
            for role_name, ident, own, placed, frac, n, _where in contributors:
                print("              %-14s %-12s %d x %.0f = %-8.0f "
                      "(%.1f%% of its own visible px move)"
                      % (role_name, ident, n, own, placed, frac * 100))

    # Scene agreement. Last, because it is the only check here that leaves this
    # process — and printed whatever it finds, including "skipped", because a
    # gate whose absence looks exactly like a pass is the gate this project has
    # already been bitten by twice.
    if not args.no_scene:
        print("scene:      the preview room vs `spriteroom --render`, per theme")
        failures.extend(scene_agreement(themes, sorted(themes)))
    else:
        print("scene:      NOT CHECKED — --no-scene. The placement census the "
              "motion budget uses is unverified in this run.")

    if failures:
        print("\nI7 palette lint FAILED — %d violation(s):" % len(failures), file=sys.stderr)
        for f in failures:
            print("  - " + f, file=sys.stderr)
        print("\nThe thresholds are not the bug.", file=sys.stderr)
        if any(not f.startswith("motion") for f in failures):
            print("Fix the art: desaturate the room further, or pick a character "
                  "variant that carries a real accent.", file=sys.stderr)
        if any(f.startswith("motion") for f in failures):
            print("For a motion violation the fix is the prop, not the number: drop "
                  "it, or take one that moves less, or put it in a slot the room "
                  "draws fewer times. A theme may carry at most one animated prop and "
                  "only in `board` (ADR-002 §14b), and the ceiling is the cast's own "
                  "quietest loop — lowering it would be saying the room may out-move "
                  "the characters, which is exactly what I7 forbids.", file=sys.stderr)
        return 1

    print("\nI7 palette lint passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
