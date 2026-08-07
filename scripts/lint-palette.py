#!/usr/bin/env python3
"""Palette separation lint over assets/manifest.json. [I7]

CLAUDE.md, I7: "The room is desaturated and low-contrast. Characters own the
saturation and the darkest values. At small sizes silhouette and value contrast
are what read — not detail. Enforced by lint over the asset manifest, not by
good intentions."

Three checks, exactly the thresholds in docs/04-ART-DIRECTION.md:

  1. Every room pixel is under 25% saturation.
  2. Every character carries at least one colour above 55% saturation.
  3. At least 40% value contrast between a character's darkest pixel and the
     mean room value.

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

# Pixels below this alpha are ignored. A near-transparent pixel is composited
# most of the way back to whatever is behind it, so judging the palette on it
# would fail files over colour the viewer never sees.
ALPHA_FLOOR = 128

_hsv_cache = {}


def hsv(r, g, b):
    key = (r, g, b)
    v = _hsv_cache.get(key)
    if v is None:
        v = _hsv_cache[key] = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    return v


def scan(path):
    """Return (max_sat, min_val, sum_val, n) over the visible pixels of one PNG."""
    w, h, px = pnglite.load(path)
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

    if failures:
        print("\nI7 palette lint FAILED — %d violation(s):" % len(failures), file=sys.stderr)
        for f in failures:
            print("  - " + f, file=sys.stderr)
        print("\nThe thresholds are not the bug. Fix the art: desaturate the room "
              "further, or pick a character variant that carries a real accent.",
              file=sys.stderr)
        return 1

    print("\nI7 palette lint passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
