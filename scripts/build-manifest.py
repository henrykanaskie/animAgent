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

    return {
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
    if os.path.exists(extra):
        result["states"] = {
            "attention": {"file": rel(extra), "provenance": "pack",
                          "note": "for Notification. Badge only — docs/04-ART-DIRECTION.md "
                                  "rules out a body animation here [I1]."}
        }
    return result


def main():
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
                    ("badges", build_badges)):
        section = fn()
        if section is not None:
            manifest[key] = section

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
        print("       %s is left untouched." % rel(MANIFEST), file=sys.stderr)
        return 2

    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")

    chars = manifest.get("characters", {}).get("variants", {})
    badges = manifest.get("badges", {}).get("map", {})
    ph = sum(1 for b in badges.values() if b["provenance"] == "placeholder")
    au = sum(1 for b in badges.values() if b["provenance"] == "authored")
    print("wrote %s" % rel(MANIFEST))
    print("  %d character variants, %d states each" %
          (len(chars), len(next(iter(chars.values()))["states"]) if chars else 0))
    print("  %d badges (%d from pack, %d authored, %d placeholder)"
          % (len(badges), len(badges) - ph - au, au, ph))
    print("  %d asset paths, all verified present" % seen[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
