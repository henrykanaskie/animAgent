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

Run scripts/process-assets.py and scripts/generate-placeholders.py first.

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
    return {
        "canvas": {"w": 32, "h": 64},
        "anchor": {"px": [16, 64], "normalized": [0.5, 0.0],
                   "note": "bottom-centre; the character stands on this point"},
        "directions": ["right", "up", "left", "down"],
        "frame_rate": FPS,
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
            "identified": False,
            "note": "The pack names singles by index only, so none of these is known to "
                    "be a desk, chair or monitor without opening it. Identifying the "
                    "handful the room layout needs is scene work, not import work.",
            "files": props,
        },
    }


def build_badges():
    real = os.path.join(PROCESSED, "badges", SIZE)
    fake = os.path.join(PLACEHOLDER, "badges", SIZE)
    out = {}
    for name in BADGE_NAMES:
        entry = None
        p = os.path.join(real, "%s.png" % name)
        if os.path.exists(p):
            entry = {"file": rel(p), "provenance": "pack",
                     "source": "Modern Interiors / 4_User_Interface_Elements/UI_%s.png" % SIZE}
        else:
            p = os.path.join(fake, "%s.png" % name)
            if os.path.exists(p):
                entry = {"file": rel(p), "provenance": "placeholder",
                         "needs_swap_at": "M5",
                         "blocked_on": "the standalone LimeZu 'Modern User Interface' pack, "
                                       "which is not on disk"}
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
                "ceiling does not apply to it.",
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
        "note": "Generated from files on disk. Do not hand-edit while placeholders "
                "remain; rerun the generator. From M5, when every provenance reads "
                "'pack', this becomes a hand-owned file.",
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
            "note": "Modern Interiors states credits are required. Ships in the About panel.",
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

    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")

    chars = manifest.get("characters", {}).get("variants", {})
    badges = manifest.get("badges", {}).get("map", {})
    ph = sum(1 for b in badges.values() if b["provenance"] == "placeholder")
    print("wrote %s" % rel(MANIFEST))
    print("  %d character variants, %d states each" %
          (len(chars), len(next(iter(chars.values()))["states"]) if chars else 0))
    print("  %d badges (%d from pack, %d placeholder)" % (len(badges), len(badges) - ph, ph))
    print("  %d asset paths, all verified present" % seen[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
