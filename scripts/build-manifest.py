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
                                    "person on it faces right, which is the way every "
                                    "seated character faces"},
    "plant": {"index": 99,  "what": "small potted plant, floor standing"},
    "board": {"index": 171, "what": "presentation board on a stand, floor standing, "
                                    "chart on the face"},
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
    return {
        "note": "Two tiers. `roles` is keyed on the exact agent_type string and "
                "may translate it — a test-engineer in a lab coat is the room "
                "repeating a name the user chose. `assignable` is the pool an "
                "unrecognised type is hashed over and nothing in it asserts, "
                "which is the question_mark rule on the character layer. [I1]",
        "sets": sets,
        "roles": roles,
        "assignable": assignable,
    }


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
            "identified_by": "rendered and inspected by eye at M5; the pack ships no "
                             "names for its singles",
            "what": spec["what"],
            "content_box": box,
        }

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
                    "bottom-aligned in their canvas." % (len(roles), len(props) - len(roles)),
            "roles": roles,
            "files": props,
        },
    }
    stations = build_stations(base)
    if stations is not None:
        out["props"]["stations"] = stations
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
                        "before/after render of all six themes, not in arithmetic."
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
                "roles": roles,
            },
        }
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
