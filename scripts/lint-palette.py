#!/usr/bin/env python3
"""Palette separation lint over assets/manifest.json. [I7]

CLAUDE.md, I7: "The room is desaturated and low-contrast. Characters own the
saturation and the darkest values. At small sizes silhouette and value contrast
are what read — not detail. Enforced by lint over the asset manifest, not by
good intentions."

Three checks on colour, exactly the thresholds in docs/04-ART-DIRECTION.md:

  1. Every room pixel is under 25% saturation.
  2. Every character carries at least one colour above 55% saturation.
  3. At least 40% value contrast between a character's darkest pixel and the
     mean room value.

And, added after ADR-002 §14b admitted animated props, one check on motion:

  4. Everything the room animates, added together and counted once per copy the
     room draws, must change fewer pixels per second than the quietest looping
     animation in the cast.

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
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO, "assets", "manifest.json")

ROOM_MAX_SAT = 0.25
CHAR_MIN_SAT = 0.55
MIN_VALUE_CONTRAST = 0.40

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


def role_placements():
    """How many times the room draws each prop role on one panel.

    **Imported from `scripts/preview-theme.py` rather than transcribed**, because
    a prop placed four times costs four times as much and that count is the one
    number in this check the manifest cannot supply — it is scene geometry, not
    art. `preview-theme.py` owns the transcription of RoomLayout.swift, renders
    the real 720x400 panel with it, and asserts its own census against the same
    function this returns. So there is one copy of the number and something
    draws a picture with it.

    Returns `{}` if the preview tool is unreadable, and the caller fails rather
    than guessing — an assumed placement count is a budget wrong by a factor.
    """
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview-theme.py")
    if not os.path.exists(path):
        return {}
    spec = importlib.util.spec_from_file_location("_preview_theme", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    fn = getattr(mod, "role_placements", None)
    return dict(fn()) if fn else {}


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
    args = ap.parse_args(argv)

    if not os.path.exists(args.manifest):
        print("error: %s not found. Run scripts/build-manifest.py first."
              % os.path.relpath(args.manifest, REPO), file=sys.stderr)
        return 2
    with open(args.manifest) as f:
        m = json.load(f)

    failures = []

    # --- room -------------------------------------------------------------
    room_paths, prose = set(), set()
    collect(m.get("room", {}), room_paths, prose)
    if not room_paths:
        print("error: manifest declares no room art; nothing to measure against.",
              file=sys.stderr)
        return 2

    room_sum, room_n, room_max_sat = 0.0, 0, (0.0, None, None)
    room_min_val = (1.0, None)
    for p in sorted(room_paths):
        s, mn, tot, n, worst = scan(os.path.join(REPO, p))
        if n == 0:
            continue
        room_sum += tot
        room_n += n
        if s > room_max_sat[0]:
            room_max_sat = (s, p, worst)
        if mn < room_min_val[0]:
            room_min_val = (mn, p)
        if s >= ROOM_MAX_SAT:
            failures.append(
                "room saturation: %s reaches %.1f%% saturation at RGB%s "
                "(ceiling is %.0f%%)" % (p, s * 100, worst, ROOM_MAX_SAT * 100))
    room_mean_val = room_sum / room_n

    # --- themes -----------------------------------------------------------
    #
    # Every theme is measured on the SAME thresholds as `room`, separately.
    # Measuring them pooled would let a quiet theme carry a loud one: I7 is a
    # statement about what is on screen at one moment, and only one theme is on
    # screen at a time. The mean value of the theme actually being drawn is also
    # what the character contrast check has to run against, so each theme gets
    # its own contrast pass below rather than borrowing `room`'s.
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
        for p in sorted(paths):
            s, mn, tot, n, worst = scan(os.path.join(REPO, p))
            if n == 0:
                continue
            tsum += tot
            tn += n
            if s > tmax[0]:
                tmax = (s, p, worst)
            if mn < tmin[0]:
                tmin = (mn, p)
            if s >= ROOM_MAX_SAT:
                failures.append(
                    "theme %s saturation: %s reaches %.1f%% saturation at RGB%s "
                    "(ceiling is %.0f%%)" % (tname, p, s * 100, worst, ROOM_MAX_SAT * 100))
        if tn == 0:
            failures.append("theme %s: no measurable pixels" % tname)
            continue
        theme_stats[tname] = {
            "files": len(paths), "px": tn, "mean": tsum / tn,
            "max_sat": tmax, "darkest": tmin,
        }

    # --- characters -------------------------------------------------------
    variants = m.get("characters", {}).get("variants", {})
    if not variants:
        print("error: manifest declares no characters.", file=sys.stderr)
        return 2

    rows = []
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
            if c < MIN_VALUE_CONTRAST:
                failures.append(
                    "theme %s value contrast: variant %s darkest pixel is value %.3f "
                    "against a theme mean of %.3f — %.1f%% contrast, needs %.0f%%; "
                    "darkest is in %s"
                    % (tname, name, vmin_v, tmean, c * 100,
                       MIN_VALUE_CONTRAST * 100, dark_file))
        theme_stats[tname]["worst_contrast"] = worst

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
    placements = role_placements()
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

            n = placements.get(role_name)
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
    print("room:       %d files, %d visible px" % (len(room_paths), room_n))
    print("            mean value       %.3f" % room_mean_val)
    print("            max saturation   %.3f  (ceiling %.2f)  %s"
          % (room_max_sat[0], ROOM_MAX_SAT, room_max_sat[1] or ""))
    print("            darkest value    %.3f  %s" % (room_min_val[0], room_min_val[1] or ""))
    if theme_stats:
        print("themes:     %d, each measured on the same thresholds" % len(theme_stats))
        print("            %-16s %-7s %-9s %-9s %-9s %s"
              % ("theme", "files", "mean val", "max sat", "darkest", "min contrast"))
        for tname in sorted(theme_stats):
            st = theme_stats[tname]
            wc = st.get("worst_contrast")
            bad = (st["max_sat"][0] >= ROOM_MAX_SAT
                   or (wc is not None and wc[1] < MIN_VALUE_CONTRAST))
            print("            %-16s %-7d %-9.3f %-9.3f %-9.3f %.3f (%s) %s"
                  % (tname, st["files"], st["mean"], st["max_sat"][0],
                     st["darkest"][0], wc[1] if wc else 0.0, wc[0] if wc else "-",
                     "FAIL" if bad else ""))
    print("characters: %d variants" % len(rows))
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
