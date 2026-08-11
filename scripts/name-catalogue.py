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

# The 24 themed interiors, keyed by catalogue group. Same method, same rules:
# inclusive ranges over the pack's own numbering, and a name here means a
# contact sheet was rendered and looked at.
#
# Progress is tracked in THEMES_DONE below — this is a long pass and it is meant
# to survive being interrupted, so an absent theme means "not yet looked at"
# rather than "nothing there".
THEMES = {
    "interiors/art": [
        (1, 4, "pot_clay"),
        (5, 11, "vase_ceramic"),
        (12, 17, "paint_bucket"),
        (18, 20, "paint_spill"),
        (21, 21, "bonsai"),
        (22, 22, "workbench_art"),
        (23, 25, "workbench_art_with_palette"),
        (26, 26, "workbench_art"),
        (27, 29, "workbench_art_with_palette"),
        (30, 33, "pottery_stand"),
        (34, 34, "easel_blank"),
        (35, 40, "easel_with_painting"),
        (41, 46, "painting_framed"),
    ],
    "interiors/conference_hall": [
        (61, 62, "curtain_red"),
        (63, 65, "door_blue"),
        (66, 68, "projection_screen"),
        (1, 20, "stage_riser"),
        (21, 24, "stage_edge"),
        (25, 26, "lectern"),
        (27, 27, "lectern_with_plant"),
        (28, 28, "lectern_with_mic"),
        (29, 30, "lectern_with_screen"),
        (31, 32, "lectern_grey_with_mic"),
        (33, 36, "stone_lump"),
        (37, 39, "chair_conference"),
        (40, 40, "step_ladder"),
        (41, 41, "exit_sign_box"),
        (42, 44, "pole"),
        (45, 46, "lectern_wood"),
        (47, 49, "shelf_edge"),
        (50, 52, "flipchart"),
        (53, 53, "mic_stand"),
        (54, 55, "poster_portrait"),
        (57, 58, "backpack"),
        (59, 59, "fire_extinguisher"),
        (60, 60, "curtain_red"),
    ],
    "interiors/television_and_film_studio": [
        (1, 7, "film_camera_tripod"),
        (8, 11, "studio_light_softbox"),
        (12, 27, "green_screen"),
        (28, 31, "armchair"),
        (32, 34, "stool_round"),
        (35, 40, "ceiling_rail"),
        (41, 47, "monitor_wall_blank"),
        (48, 53, "screen_broadcast"),
        (54, 70, "desk_news"),
        (71, 74, "script_papers"),
        (75, 80, "backdrop_striped"),
    ],
    "interiors/classroom_and_library": [
        (1, 4, "chair_school"),
        (5, 6, "desk_school"),
        (7, 24, "desk_school_with_book"),
        (25, 26, "desk_reading_with_book"),
        (27, 30, "chair_reading_green"),
        (31, 31, "map_world"),
        (32, 32, "chart_wall"),
        (33, 33, "notice_board_cork"),
        (34, 35, "globe"),
        (36, 36, "blackboard_small"),
        (37, 38, "pointer_stick"),
        (39, 39, "blackboard_large"),
        (40, 40, "lockers"),
        (41, 42, "step_ladder"),
        (43, 48, "shelf_library"),
        (49, 49, "desk_with_papers"),
        (50, 51, "desk_librarian_composite"),
        (52, 53, "counter_wood"),
        (54, 54, "copier_on_counter"),
        (55, 75, "bookcase_tall"),
    ],
    # Condominium is a stairwell set: 60 of its 86 props are flights of stairs
    # in grey, wood and red carpet, with and without banisters. Useful as
    # architecture rather than as furniture.
    "interiors/condominium": [
        (1, 22, "stairs_flight"),
        (23, 24, "arrow_marker"),
        (25, 62, "stairs_flight"),
        (63, 70, "doormat"),
        (71, 73, "parcel_box"),
        (74, 75, "wall_sign"),
        (76, 84, "mailbox_bank"),
        (85, 86, "door_wood"),
    ],
    "interiors/ice_cream_shop": [
        (1, 4, "display_rack"),
        (5, 5, "scoop"),
        (6, 11, "ice_cream_cart"),
        (12, 15, "menu_board"),
        (16, 19, "ice_cream_cone"),
        (20, 25, "freezer_cabinet"),
        (26, 73, "freezer_display_flavours"),
        (74, 74, "sign_ice_cream"),
        (75, 75, "counter_serving"),
        (76, 77, "chair_cafe"),
        (78, 79, "table_cafe_set"),
        (80, 99, "dessert_serving"),
        (100, 102, "counter_cafe"),
    ],
    "interiors/living_room": [
        (1, 11, "cabinet_ornate"),
        (12, 12, "string_lights"),
        (13, 18, "plant_potted"),
        (19, 26, "dresser_with_mirror"),
        (27, 27, "table_lamp"),
        (28, 28, "doily"),
        (29, 36, "console_low"),
        (37, 44, "wardrobe"),
        (45, 47, "side_table"),
        (48, 52, "fruit_basket"),
        (53, 62, "sideboard"),
        (63, 70, "nightstand"),
        (71, 78, "table_lamp"),
        (79, 88, "floor_lamp"),
        (89, 91, "cabinet_display"),
        (92, 93, "chair_dining"),
        (94, 102, "firewood_pile"),
        (103, 103, "cabinet_wood"),
        (104, 106, "broom"),
        (107, 114, "fireplace"),
        (115, 120, "fire_grate"),
    ],
    "interiors/japanese_interiors": [
        (1, 16, "tatami_mat"),
        (17, 18, "stone_lantern"),
        (19, 25, "stone_platform"),
        (26, 33, "weapon_rack"),
        (34, 34, "paper_lantern"),
        (35, 38, "sake_set"),
        (39, 40, "table_low"),
        (41, 44, "cushion_zabuton"),
        (45, 46, "brazier"),
        (47, 47, "pot_round"),
        (48, 55, "futon"),
        (56, 58, "bonsai"),
        (59, 60, "torii_gate"),
        (61, 62, "shoji_screen"),
        (63, 65, "post_wood"),
        (66, 76, "shrine_cabinet"),
        (77, 100, "futon"),
        (101, 104, "stepping_stone"),
        (105, 106, "hanging_scroll"),
        (107, 110, "wood_slat"),
        (111, 114, "figurine_pair"),
        (115, 116, "rock_garden"),
        (117, 131, "table_low_with_cushion"),
    ],
    "interiors/shooting_range": [
        (1, 10, "bench_shooting"),
        (11, 14, "control_panel"),
        (15, 18, "target_paper"),
        (19, 20, "pole"),
        (21, 22, "rail_barrier"),
        (23, 25, "gun_rest_rail"),
        (26, 26, "rail_barrier"),
        (27, 28, "control_box"),
    ],
    "interiors/birthday_party": [
        (1, 8, "gift_box"),
        (9, 11, "cake"),
        (12, 14, "plate_stack"),
        (15, 15, "confetti"),
        (16, 16, "bunting"),
        (17, 24, "balloon"),
        (25, 25, "party_horn"),
        (26, 29, "party_food"),
    ],
    "interiors/fishing": [
        (1, 6, "tackle_box"),
        (7, 10, "bait_bag"),
        (11, 11, "bucket"),
        (12, 14, "fishing_rod"),
        (15, 15, "rod_rack"),
        (16, 18, "landing_net"),
        (19, 26, "chair_folding_camp"),
        (27, 35, "cooler_box"),
        (36, 40, "papers_small"),
        (41, 43, "tackle_tray"),
        (44, 45, "panel_grey"),
        (46, 46, "knife"),
        (47, 49, "fishing_lure"),
        (50, 52, "picture_framed_seascape"),
        (53, 53, "aquarium"),
        (54, 57, "fish_dish"),
        (58, 63, "counter_fish_display"),
        (64, 70, "rod_rack_standing"),
        (71, 74, "trolley_cart"),
        (75, 77, "parasol"),
    ],
}

# Themes whose contact sheets have been rendered and read end to end. A theme
# absent from this list has not been looked at, which is a different thing from
# a theme with no interesting props in it.
THEMES_DONE = ["art", "conference_hall", "television_and_film_studio",
               "classroom_and_library", "fishing", "shooting_range",
               "birthday_party", "condominium", "ice_cream_shop", "living_room",
               "japanese_interiors"]

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
        elif entry["group"] in THEMES:
            m = re.search(r"_(\d+)$", stem)
            if m:
                index_no = int(m.group(1))
                for lo, hi, name in THEMES[entry["group"]]:
                    if lo <= index_no <= hi:
                        entry["name"] = name
                        entry["identified_by"] = "rendered and inspected by eye"
                        named += 1
                        break

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
