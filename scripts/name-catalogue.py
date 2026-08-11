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
    "interiors/christmas": [
        (1, 20, "christmas_tree"),
        (21, 22, "gift_pile"),
        (23, 23, "stone_small"),
        (24, 33, "gift_box"),
        (34, 53, "toy_present"),
        (54, 58, "stocking"),
        (59, 64, "wreath"),
        (65, 66, "picture_framed_festive"),
        (67, 68, "fireplace"),
        (69, 76, "nutcracker"),
        (77, 78, "christmas_tree_small"),
        (79, 82, "banner_red"),
        (83, 83, "toy_present"),
        (84, 85, "reindeer_plush"),
        (86, 87, "decoration_small"),
        (88, 88, "throne_gold"),
        (89, 90, "cushion_red"),
        (91, 100, "rug_patterned"),
        (101, 103, "snow_globe"),
        (104, 112, "bread"),
        (113, 120, "food_platter"),
        (121, 123, "sweets"),
    ],
    "interiors/bathroom": [
        (1, 14, "vanity_with_mirror"),
        (15, 20, "sink_wall"),
        (21, 56, "toilet"),
        (57, 57, "toilet_broken"),
        (58, 59, "plunger"),
        (60, 60, "brush_pole"),
        (61, 65, "shower_cubicle"),
        (66, 73, "mirror_wall"),
        (74, 81, "bath_mat"),
        (82, 86, "shelf_toiletries"),
        (87, 94, "washing_machine"),
        (95, 100, "laundry_basket"),
        (101, 108, "stool_with_towel"),
        (109, 109, "notice"),
        (110, 119, "bin"),
        (120, 137, "cabinet_bathroom"),
        (138, 140, "cotton_balls"),
        (141, 150, "towel_rack"),
        (151, 154, "sink_with_taps"),
        (155, 155, "perfume_bottle"),
        (156, 158, "shower_tray"),
    ],
    "interiors/gym": [
        (1, 63, "mat_exercise"),
        (64, 67, "punching_bag"),
        (68, 69, "speed_bag"),
        (70, 72, "skipping_rope"),
        (73, 81, "exercise_ball"),
        (82, 86, "weight_rack"),
        (87, 90, "barbell"),
        (91, 97, "gym_machine"),
        (98, 99, "dumbbell_stand"),
        (100, 101, "radio"),
        (102, 105, "weight_plate_stack"),
        (106, 107, "kettlebell"),
        (108, 113, "dumbbell"),
        (114, 116, "locker"),
        (117, 119, "mirror_wall"),
        (120, 127, "exercise_ball"),
        (128, 132, "mirror_wall"),
        (133, 154, "dumbbell"),
        (155, 163, "kettlebell"),
        (164, 165, "weight_plate_stack"),
        (166, 170, "dumbbell_rack"),
        (171, 174, "weight_bench"),
        (175, 183, "punching_bag"),
        (184, 185, "radio"),
        (186, 187, "treadmill"),
        (188, 189, "exercise_bike"),
        (190, 190, "locker"),
        (191, 194, "weight_bench"),
        (195, 209, "mat_exercise"),
    ],
    # Basement is a games-room set: pool tables, arcade cabinets, consoles and
    # bar seating, with a swimming pool at 227.
    "interiors/basement": [
        (1, 3, "table_round"),
        (4, 21, "cushion_pair"),
        (22, 26, "sparkle"),
        (27, 60, "cushion_pair"),
        (61, 63, "vase_flowers"),
        (64, 66, "crate_wood"),
        (67, 69, "table_tennis_gear"),
        (70, 75, "billiard_gear"),
        (76, 81, "pool_table"),
        (82, 84, "picnic_basket"),
        (85, 102, "bar_counter"),
        (103, 144, "stool_bar"),
        (145, 156, "stool_round_top"),
        (157, 162, "shelf_low"),
        (163, 166, "tv_flat"),
        (167, 180, "game_console"),
        (181, 182, "console_retro"),
        (183, 185, "panel"),
        (186, 193, "surfboard"),
        (194, 195, "tv_stand_composite"),
        (196, 197, "fence_wood"),
        (198, 203, "bean_bag"),
        (204, 217, "armchair"),
        (218, 224, "arcade_machine"),
        (225, 226, "picture_small"),
        (227, 228, "swimming_pool"),
        (229, 232, "picture_small"),
        (233, 240, "door"),
    ],
    "interiors/halloween": [
        (1, 3, "decoration_hanging"),
        (4, 23, "pumpkin"),
        (24, 29, "spider_web"),
        (30, 42, "rug_patterned"),
        (43, 52, "coffin"),
        (53, 54, "cauldron"),
        (55, 55, "skull_bones"),
        (56, 62, "garland_autumn"),
        (63, 64, "crate_food"),
        (65, 66, "lamp_old"),
        (67, 69, "trick_or_treat_bucket"),
        (70, 71, "candy_scatter"),
        (72, 73, "witch_hat"),
        (74, 75, "ghost"),
        (76, 80, "blood_splat"),
        (81, 90, "mirror_oval"),
        (91, 91, "skeleton_hand"),
        (92, 97, "cabinet_wood"),
        (98, 100, "poster_horror"),
        (101, 104, "bone_small"),
        (105, 113, "magic_circle"),
        (114, 119, "mask"),
        (120, 125, "spell_book"),
        (126, 129, "telephone_rotary"),
        (130, 130, "bone_small"),
        (131, 132, "voodoo_doll"),
        (133, 133, "portrait"),
        (134, 134, "papers_stacked"),
        (135, 137, "cross"),
        (138, 139, "bed"),
        (140, 140, "candy_scatter"),
        (141, 144, "teddy_damaged"),
        (145, 147, "crate_bones"),
        (148, 150, "keypad"),
        (151, 153, "picture_framed_spooky"),
        (154, 155, "shelf_jars"),
        (156, 159, "sign_small"),
        (160, 161, "window_barred"),
        (162, 164, "lectern_with_book"),
        (165, 176, "shelf_potions"),
        (177, 177, "chain_trap"),
        (178, 178, "banner_orange"),
        (179, 179, "blood_splat"),
        (180, 198, "ladder_plank"),
        (199, 200, "cage_bones"),
        (201, 204, "shackles"),
        (205, 208, "key_skeleton"),
        (209, 210, "slime"),
        (211, 213, "blood_altar"),
        (214, 215, "rug_patterned"),
        (216, 218, "stone_block"),
        (219, 222, "window_barred"),
        (223, 240, "shelf_potions"),
    ],
    "interiors/music_and_sport": [
        (1, 24, "piano_upright"),
        (25, 27, "piano_bench"),
        (28, 33, "piano_grand"),
        (34, 36, "piano_bench"),
        (37, 42, "drum_kit"),
        (43, 44, "amplifier"),
        (45, 50, "guitar_acoustic"),
        (51, 56, "guitar_electric"),
        (57, 60, "harp"),
        (61, 65, "microphone_stand"),
        (66, 68, "keyboard_toy"),
        (69, 72, "drum_marching"),
        (73, 75, "microphone"),
        (76, 76, "drum_conga"),
        (77, 82, "ball_sport"),
        (83, 85, "baseball_bat"),
        (86, 95, "ball_sport"),
        (96, 107, "poster_sport"),
        (108, 116, "medal_framed"),
        (117, 128, "rug_mat"),
        (129, 131, "medal_framed"),
        (132, 155, "trophy"),
        (156, 164, "trophy_shelf"),
        (165, 182, "keyboard_synth"),
        (183, 184, "amplifier"),
        (185, 188, "keyboard_toy"),
        (189, 198, "organ"),
        (199, 202, "piano_bench"),
        (203, 211, "guitar_on_stand"),
        (212, 215, "harp"),
        (216, 217, "tambourine"),
        (218, 235, "drum"),
        (236, 242, "drum_kit"),
        (243, 243, "basketball_hoop"),
        (244, 246, "ball_sport"),
        (247, 249, "baseball_bat"),
    ],
    # Jail is three rooms in one set: cells (1-60), an infirmary and control
    # room (61-180), and a canteen (181-344).
    "interiors/jail": [
        (1, 8, "wall_cell"),
        (9, 12, "vine"),
        (13, 18, "pill"),
        (19, 28, "cell_bars"),
        (29, 36, "baton"),
        (37, 39, "bunk_bed"),
        (40, 42, "rope"),
        (43, 45, "toilet_metal"),
        (46, 48, "sink_metal"),
        (49, 52, "papers_small"),
        (53, 58, "locker"),
        (59, 78, "table_visiting"),
        (79, 82, "handcuffs"),
        (83, 85, "sign_medical"),
        (86, 88, "first_aid_kit"),
        (89, 90, "counter_medical"),
        (91, 94, "cubicle_medical"),
        (95, 96, "counter_reception"),
        (97, 99, "bin_small"),
        (100, 102, "gurney"),
        (103, 105, "bin_small"),
        (106, 109, "iv_stand"),
        (110, 112, "monitor_medical"),
        (113, 122, "wall_panel"),
        (123, 125, "keyboard_console"),
        (126, 140, "monitor_security"),
        (141, 152, "workstation_composite"),
        (153, 156, "papers_small"),
        (157, 176, "chair_office_swivel"),
        (177, 180, "grate"),
        (181, 189, "tool_small"),
        (190, 210, "counter_serving"),
        (211, 234, "food_tray"),
        (235, 240, "bench_canteen"),
        (241, 280, "chair_canteen"),
        (281, 300, "food_tray"),
        (301, 305, "food_tray"),
        (306, 314, "drink_dispenser"),
        (315, 320, "food_display"),
        (321, 344, "food_plate"),
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
               "japanese_interiors", "christmas", "bathroom", "gym", "basement", "halloween", "music_and_sport", "jail"]

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
