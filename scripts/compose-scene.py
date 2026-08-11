#!/usr/bin/env python3
"""Composes static room scenes from named catalogue props, as plain PNGs.

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

# The bar

`assets/Modern_Office_Revamped_v1.2/6_Office_Designs/Office_Design_2.gif` is a
room composed by the pack's own artist from these same props. That is the
comparison worth making, and it is the maintainer's to make.

Uses Pillow, which the app's own pipeline avoids — fine here, because nothing
in this file is part of the build. `scripts/process-assets.py` stays stdlib.
"""

import json
import os
import random
import sys

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "assets")
CATALOGUE = os.path.join(ASSETS, "catalogue.json")
BUILDER = os.path.join(ASSETS, "processed", "room", "32x32", "builder")
CHARS = os.path.join(ASSETS, "processed", "characters", "32x32")

PANEL = (720, 400)

# Floor and wall tiles, chosen by rendering the 141 builder tiles and looking.
SURFACES = {
    "grey":   ("tile_r07_c10.png", "tile_r07_c00.png"),
    "tan":    ("tile_r08_c13.png", "tile_r09_c00.png"),
    "olive":  ("tile_r09_c13.png", "tile_r10_c00.png"),
    "lilac":  ("tile_r11_c13.png", "tile_r11_c00.png"),
    "pink":   ("tile_r12_c13.png", "tile_r12_c00.png"),
    "white":  ("tile_r08_c10.png", "tile_r05_c00.png"),
}


def load_index():
    with open(CATALOGUE) as fh:
        data = json.load(fh)
    by_name = {}
    for e in data["entries"]:
        if e["size_set"] != "32x32" or "name" not in e:
            continue
        by_name.setdefault(e["name"], []).append(e)
    return by_name


def prop(by_name, name, variant=0):
    """One named prop's image and its content box, or None if absent."""
    entries = by_name.get(name)
    if not entries:
        return None
    e = entries[variant % len(entries)]
    path = os.path.join(ASSETS, os.path.relpath(e["file"], "assets")) \
        if e["file"].startswith("assets") else os.path.join(ASSETS, e["file"])
    if not os.path.exists(path):
        path = os.path.join(REPO, e["file"])
    if not os.path.exists(path):
        return None
    return Image.open(path).convert("RGBA"), e["content_box"]


def character(variant, pose, facing, frame=0):
    p = os.path.join(CHARS, variant, "%s_%s_%02d.png" % (pose, facing, frame))
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


def tiled(name, size):
    im = Image.open(os.path.join(BUILDER, name)).convert("RGBA")
    out = Image.new("RGBA", size)
    for y in range(0, size[1], im.height):
        for x in range(0, size[0], im.width):
            out.alpha_composite(im, (x, y))
    return out


def compose(spec, by_name, out_path):
    """Draw one scene. `spec` places props by name at a floor position.

    Placement is bottom-centre on the given point and depth-sorted by that
    point's y, which is the same convention the app uses — so a scene that
    reads here is telling the truth about what the app could draw.
    """
    floor_tile, wall_tile = SURFACES[spec.get("surface", "grey")]
    canvas = Image.new("RGBA", PANEL, (0, 0, 0, 255))
    wall_h = spec.get("wall", 128)
    canvas.alpha_composite(tiled(wall_tile, (PANEL[0], wall_h)), (0, 0))
    canvas.alpha_composite(tiled(floor_tile, (PANEL[0], PANEL[1] - wall_h)), (0, wall_h))

    items = []
    for entry in spec["props"]:
        name, x, y = entry[0], entry[1], entry[2]
        variant = entry[3] if len(entry) > 3 else 0
        got = prop(by_name, name, variant)
        if got is None:
            print("  missing: %s" % name)
            continue
        items.append((y, got[0], got[1], x, y))
    for entry in spec.get("people", []):
        v, pose, facing, x, y = entry
        im = character(v, pose, facing)
        if im is not None:
            items.append((y, im, None, x, y))

    for _, im, box, x, y in sorted(items, key=lambda i: i[0]):
        if box is None:
            canvas.alpha_composite(im, (x - im.width // 2, y - im.height))
        else:
            # Bottom-centre the ink, not the padded canvas.
            ox = x - (box["x"] + box["w"] // 2)
            oy = y - (box["y"] + box["h"])
            canvas.alpha_composite(im, (ox, oy))

    canvas.convert("RGB").save(out_path)
    return out_path


# Ten rooms. Each is a hand-placed composition, not a generator — the point is
# to show what the props can look like when arranged with intent.
SCENES = [
    {
        "name": "01-engineering-floor", "surface": "grey", "wall": 96,
        "props": [
            ("whiteboard_blank", 130, 96), ("chart_board", 350, 96, 1),
            ("picture_framed", 520, 90, 3), ("picture_framed", 590, 90, 7),
            ("plant_potted", 40, 170, 2), ("plant_potted", 685, 170, 5),
            # Pre-composed desk clusters, not bare counter segments.
            ("workstation_composite", 120, 230), ("workstation_composite", 300, 230, 6),
            ("workstation_composite", 480, 230, 12), ("workstation_composite", 655, 230, 18),
            ("chair_office_back", 120, 268), ("chair_office_back", 300, 268, 1),
            ("chair_office_back", 480, 268, 2), ("chair_office_back", 655, 268, 3),
            ("workstation_composite", 120, 375, 3), ("workstation_composite", 300, 375, 9),
            ("workstation_composite", 480, 375, 15), ("workstation_composite", 655, 375, 21),
            ("printer_desk_composite", 40, 320), ("water_cooler", 600, 330),
            ("coffee_machine", 660, 330, 4),
        ],
        "people": [
            ("06", "idle", "up", 120, 300), ("07", "idle", "up", 300, 300),
            ("09", "idle", "up", 480, 300), ("10", "idle", "up", 655, 300),
        ],
    },
    {
        "name": "02-control-room", "surface": "grey", "wall": 144,
        "props": [
            ("monitor_security", 90, 140), ("monitor_security", 200, 140, 3),
            ("monitor_security", 310, 140, 6), ("monitor_security", 420, 140, 9),
            ("monitor_security", 530, 140, 12), ("monitor_security", 640, 140, 2),
            ("desk_counter", 150, 250), ("desk_counter", 330, 250, 2),
            ("desk_counter", 510, 250, 4),
            ("workstation_composite", 150, 244), ("workstation_composite", 330, 244, 6),
            ("workstation_composite", 510, 244, 12),
            ("pc_tower", 60, 280, 3), ("pc_tower", 660, 280, 7),
            ("plant_potted", 30, 330, 8), ("coffee_machine", 690, 330, 3),
        ],
        "people": [
            ("06", "idle", "up", 150, 300), ("10", "idle", "up", 330, 300),
            ("19", "idle", "up", 510, 300),
        ],
    },
    {
        "name": "03-library", "surface": "tan", "wall": 128,
        "props": [
            ("bookcase_tall", 80, 128), ("bookcase_tall", 200, 128, 4),
            ("bookcase_tall", 520, 128, 8), ("bookcase_tall", 640, 128, 12),
            ("map_world", 360, 110),
            ("desk_reading_with_book", 220, 250), ("desk_reading_with_book", 420, 250, 1),
            ("chair_reading_green", 150, 260), ("chair_reading_green", 500, 260, 2),
            ("globe", 640, 250), ("plant_potted", 50, 260, 3),
            ("desk_reading_with_book", 220, 350), ("desk_reading_with_book", 420, 350),
            ("bookcase_tall", 690, 300, 16),
        ],
        "people": [("07", "idle", "down", 220, 285), ("17", "idle", "down", 420, 285)],
    },
    {
        "name": "04-art-studio", "surface": "olive", "wall": 112,
        "props": [
            ("painting_framed", 90, 108), ("painting_framed", 200, 108, 5),
            ("painting_framed", 520, 108, 11), ("painting_framed", 630, 108, 17),
            ("easel_with_painting", 160, 280), ("easel_with_painting", 360, 280, 2),
            ("easel_with_painting", 560, 280, 4),
            ("workbench_art_with_palette", 90, 360), ("workbench_art_with_palette", 620, 360, 2),
            ("pot_clay", 300, 370), ("vase_ceramic", 430, 370, 3),
            ("bonsai", 690, 250),
        ],
        "people": [("09", "idle", "down", 250, 300), ("19", "idle", "down", 470, 300)],
    },
    {
        "name": "05-tv-studio", "surface": "grey", "wall": 120,
        "props": [
            ("green_screen", 200, 120), ("green_screen", 300, 120, 3),
            ("green_screen", 400, 120, 6), ("green_screen", 500, 120, 9),
            ("studio_light_softbox", 70, 250), ("studio_light_softbox", 650, 250, 2),
            ("film_camera_tripod", 160, 340), ("film_camera_tripod", 560, 340, 3),
            ("desk_news", 360, 300), ("stool_round", 300, 330), ("stool_round", 420, 330, 2),
            ("script_papers", 250, 370),
        ],
        "people": [("06", "idle", "down", 360, 300), ("10", "idle", "left", 200, 360)],
    },
    {
        "name": "06-museum-gallery", "surface": "white", "wall": 136,
        "props": [
            ("painting_framed", 110, 130, 2), ("painting_framed", 240, 130, 8),
            ("painting_framed", 480, 130, 14), ("painting_framed", 610, 130, 20),
            ("column", 40, 260), ("column", 680, 260, 3),
            ("statue", 180, 300), ("statue", 540, 300, 5),
            ("display_case", 360, 290, 4),
            ("rope_barrier", 180, 340), ("rope_barrier", 360, 340, 3),
            ("rope_barrier", 540, 340, 6),
            ("bench", 360, 385),
        ],
        "people": [("17", "idle", "up", 260, 330), ("07", "idle", "up", 450, 330)],
    },
    {
        "name": "07-break-room", "surface": "lilac", "wall": 112,
        "props": [
            ("picture_framed", 120, 106, 11), ("picture_framed", 600, 106, 15),
            ("coffee_machine", 70, 220, 4), ("coffee_machine", 130, 220, 7),
            ("vending_machine", 640, 230, 2), ("water_cooler", 570, 230),
            ("table_cafe_set", 250, 300), ("table_cafe_set", 430, 300, 1),
            ("chair_cafe", 200, 310), ("chair_cafe", 300, 310, 1),
            ("chair_cafe", 380, 310), ("chair_cafe", 480, 310, 1),
            ("sofa", 340, 385, 3), ("plant_potted", 40, 370, 12),
        ],
        "people": [("19", "idle", "down", 250, 330), ("09", "idle", "left", 430, 330)],
    },
    {
        "name": "08-music-room", "surface": "tan", "wall": 120,
        "props": [
            ("trophy", 90, 116, 3), ("trophy", 140, 116, 8), ("medal_framed", 600, 110, 2),
            ("piano_grand", 190, 300), ("drum_kit", 520, 280, 2),
            ("guitar_on_stand", 380, 320), ("guitar_on_stand", 430, 320, 4),
            ("amplifier", 660, 320), ("harp", 90, 340, 1),
            ("piano_bench", 190, 350),
        ],
        "people": [("06", "idle", "down", 300, 360), ("10", "idle", "down", 560, 350)],
    },
    {
        "name": "09-hospital-ward", "surface": "white", "wall": 128,
        "props": [
            ("window", 150, 124, 2), ("window", 400, 124, 3), ("clock", 570, 118),
            ("hospital_bed", 140, 250), ("hospital_bed", 340, 250, 7),
            ("hospital_bed", 540, 250, 14),
            ("iv_stand", 210, 250), ("iv_stand", 410, 250, 2),
            ("nightstand", 240, 260, 4), ("nightstand", 440, 260, 8),
            ("hospital_bed", 140, 380, 21), ("hospital_bed", 340, 380, 28),
            ("privacy_screen", 640, 300), ("plant_potted", 40, 330, 15),
        ],
        "people": [("17", "idle", "down", 620, 360)],
    },
    {
        "name": "10-games-room", "surface": "pink", "wall": 112,
        "props": [
            ("arcade_machine", 90, 240), ("arcade_machine", 160, 240, 2),
            ("arcade_machine", 620, 240, 4), ("arcade_machine", 690, 240, 5),
            ("pool_table", 360, 300, 2),
            ("bar_counter", 360, 380, 6),
            ("stool_bar", 280, 385), ("stool_bar", 340, 385, 3),
            ("stool_bar", 400, 385, 6), ("stool_bar", 460, 385, 9),
            ("tv_flat", 520, 150, 1), ("bean_bag", 60, 370, 2),
        ],
        "people": [("07", "idle", "down", 280, 340), ("19", "idle", "right", 460, 340)],
    },
]


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else \
        "/Users/henrykanaskie/.claude/jobs/6d016a50/tmp/scenes"
    os.makedirs(out_dir, exist_ok=True)
    by_name = load_index()
    random.seed(7)
    for spec in SCENES:
        path = os.path.join(out_dir, spec["name"] + ".png")
        print(spec["name"])
        compose(spec, by_name, path)
    print("\n%d scenes -> %s" % (len(SCENES), out_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
