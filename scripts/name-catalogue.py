#!/usr/bin/env python3
"""Writes human names onto catalogue entries, so a prop can be found by meaning.

`import-catalogue.py` makes 12,389 props *available*. It does not make them
*findable*: the theme and office singles are numbered, not named — the office set
is `Modern_Office_Singles_32x32_137.png` and nothing else. Only the 619 animated
objects ship with descriptive filenames.

Names here come from **rendering contact sheets and looking at them**, which is
the same method that identified `desk` as office single 34 at M5 and is recorded
in the manifest as "rendered and inspected by eye". A name in this file means
somebody looked; it is not inferred from a filename, a size or a neighbour.

Ranges are inclusive and index the pack's own numbering, so they stay valid if
the catalogue is rebuilt. `catalogue.json` is gitignored, like the art it
describes, so this writes nothing into the repository.
"""

import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX = os.path.join(REPO, "assets", "catalogue.json")

# (first, last, name) — inclusive, over the Modern Office singles numbering.
# Identified from contact sheets office_p0..p5 at 3x, 60 per sheet.
OFFICE = [
    (1, 40, "desk_wood"),
    (41, 50, "desk_metal"),
    (51, 68, "desk_wood_light"),
    (69, 95, "desk_white"),
    (96, 97, "picture_framed"),
    (98, 100, "plant_potted"),
    (101, 102, "chair_office_back"),
    (103, 104, "chair_office_side"),
    (105, 106, "chair_office_front"),
    (107, 108, "chair_office_orange"),
    (109, 110, "chair_wood_side"),
    (111, 112, "armchair_orange"),
    (113, 115, "certificate"),
    (116, 116, "keyboard"),
    (117, 120, "device_small"),
    (121, 124, "monitor_dark"),
    (125, 128, "monitor_off_white"),
    (129, 134, "monitor_lit"),
    (135, 140, "laptop_open_lit"),
    (141, 146, "desk_lamp"),
    (147, 152, "printer"),
    (153, 155, "paper_stack"),
    (156, 156, "document_tray"),
    (157, 160, "portrait_framed"),
    (161, 164, "picture_framed"),
    (165, 166, "scanner_flatbed"),
    (167, 169, "pc_tower"),
    (170, 170, "whiteboard_blank"),
    (171, 172, "chart_board"),
    (173, 173, "water_cooler"),
    (174, 176, "vending_machine"),
    (177, 178, "printer_with_output"),
    (179, 180, "box_cardboard"),
    (181, 195, "desk_wood"),
    (196, 199, "chair_tub_lowback"),
    (200, 206, "sofa"),
    (207, 209, "partition"),
    (210, 224, "desk_counter"),
    (225, 236, "workstation_composite"),
    (237, 240, "tool_small"),
    (241, 243, "monitor_small_dark"),
    (244, 244, "laptop"),
    (245, 269, "desk_corner_l"),
    (270, 270, "chair_office_side"),
    (271, 274, "pc_tower"),
    (275, 276, "monitor_dual_arm_lit"),
    (277, 278, "monitor_lit"),
    (279, 280, "chair_office_back"),
    (281, 281, "chair_office_side"),
    (282, 305, "desk_corner_l"),
    (306, 307, "chair_office_side"),
    (308, 310, "pc_tower"),
    (311, 312, "monitor_dual_arm_lit"),
    (313, 314, "monitor_lit"),
    (315, 316, "printer"),
    (317, 322, "coffee_machine"),
    (323, 328, "printer_desk_composite"),
    (329, 336, "backpack"),
    (337, 339, "money_pile"),
]

# The animated objects already carry meaning in their filenames; this only
# strips the boilerplate so they sort and search alongside everything else.
ANIMATED_STRIP = re.compile(r"^animated_|_\d+x\d+$")


def office_name(index):
    for lo, hi, name in OFFICE:
        if lo <= index <= hi:
            return name
    return None


def main():
    if not os.path.exists(INDEX):
        print("no catalogue.json — run scripts/import-catalogue.py first")
        return 1
    with open(INDEX) as fh:
        index = json.load(fh)

    named = 0
    for entry in index["entries"]:
        base = os.path.basename(entry["file"])
        stem = os.path.splitext(base)[0]
        if entry["group"] == "office":
            m = re.search(r"_(\d+)$", stem)
            if m:
                name = office_name(int(m.group(1)))
                if name:
                    entry["name"] = name
                    entry["identified_by"] = "rendered and inspected by eye, office_p0..p5"
                    named += 1
        elif entry["group"] == "animated":
            entry["name"] = ANIMATED_STRIP.sub("", stem)
            entry["identified_by"] = "the pack's own filename"
            named += 1

    index["named"] = named
    with open(INDEX, "w") as fh:
        json.dump(index, fh, indent=1)

    by_name = {}
    for e in index["entries"]:
        if "name" in e:
            by_name[e["name"]] = by_name.get(e["name"], 0) + 1
    print("named %d of %d entries" % (named, index["count"]))
    print("distinct names: %d" % len(by_name))
    unnamed = index["count"] - named
    print("still unnamed: %d (the 24 themed interiors)" % unnamed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
