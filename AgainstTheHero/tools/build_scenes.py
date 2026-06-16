# Regenerate ATH scene files with a logically-grouped node hierarchy and an
# authored (disabled) Pause Menu node tree in game.pescene.
#
# Why a generator: .pescene `parent` fields are array indices, and camera
# `node_index` references the node array too. Inserting group nodes shifts every
# index, so we rebuild each scene's node list by NAME (parents resolved after
# ordering) and recompute camera node_index. Kept nodes preserve their exact
# local_matrix / runtime_ui / mesh data; only their parent changes.

import json
import os

SCENES = r"c:\Users\Christos\repos\PhasmaProjects\AgainstTheHero\Assets\Scenes"


def identity():
    return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]


def mat(w, h, tx, ty):
    # Scale x = width px, scale y = height px, translation = (tx, ty) screen px.
    return [float(w), 0.0, 0.0, 0.0,
            0.0, float(h), 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            float(tx), float(ty), 0.0, 1.0]


def ui(wtype, wid, **o):
    d = {
        "type": wtype,
        "screen": "__scene_ui",
        "id": wid,
        "label": o.get("label", ""),
        "title": o.get("title", ""),
        "subtitle": o.get("subtitle", ""),
        "body": o.get("body", ""),
        "footer": o.get("footer", ""),
        "action": o.get("action", "click"),
        "fill": o.get("fill", [0.0, 0.0, 0.0, 0.0]),
        "border": o.get("border", [0.0, 0.0, 0.0, 0.0]),
        "accent": o.get("accent", [0.0, 0.0, 0.0, 0.0]),
        "text_color": o.get("text_color", [0.92, 0.94, 0.98, 1.0]),
        "image_tint": o.get("image_tint", [1.0, 1.0, 1.0, 1.0]),
        "anchor": o.get("anchor", [0.5, 0.5]),
        "pivot": o.get("pivot", [0.5, 0.5]),
        "font_scale": o.get("font_scale", 1.0),
        "text_align_h": o.get("text_align_h", 0),
        "text_align_v": o.get("text_align_v", 0),
        "text_offset": o.get("text_offset", [0.0, 0.0]),
        "visible": o.get("visible", True),
        "draggable": o.get("draggable", False),
        "no_input": o.get("no_input", False),
        "bring_to_front": o.get("bring_to_front", False),
    }
    if "action_function" in o:
        d["action_function"] = o["action_function"]
    if "image" in o:
        d["image"] = o["image"]
    return d


class Builder:
    """Collects (name, parent_name, node_dict) specs, then resolves parents."""

    def __init__(self, src_doc):
        self.src = {n["name"]: n for n in src_doc["nodes"]}
        self.specs = []  # list of (name, parent_name|None, dict)

    def keep(self, name, parent=None):
        node = dict(self.src[name])  # copy preserves matrix/mesh/runtime_ui/etc.
        node.pop("parent", None)
        self.specs.append((name, parent, node))

    def group(self, name, parent=None, enabled=True):
        node = {"name": name, "local_matrix": identity()}
        if not enabled:
            node["enabled"] = False
        self.specs.append((name, parent, node))

    def ui_node(self, name, parent, wtype, wid, w, h, tx, ty, flags=512,
                script=None, enabled=True, **o):
        node = {"name": name, "local_matrix": mat(w, h, tx, ty),
                "component_flags": flags, "runtime_ui": ui(wtype, wid, **o)}
        if script:
            node["script"] = script
        if not enabled:
            node["enabled"] = False
        self.specs.append((name, parent, node))

    def finish(self, doc):
        index = {name: i for i, (name, _, _) in enumerate(self.specs)}
        out = []
        for name, parent, node in self.specs:
            nd = dict(node)
            nd["name"] = name
            nd["parent"] = index[parent] if parent is not None else -1
            out.append(nd)
        doc["nodes"] = out
        for cam in doc.get("cameras", []):
            if cam.get("name") in index:
                cam["node_index"] = index[cam["name"]]
        return doc


def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save(path, doc):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=4)
        f.write("\n")


# ---------------------------------------------------------------------------
# Simple UI scenes (intro / hero_select / map): nest the runtime_ui nodes under
# a single "UI" group; keep Camera/Skybox at root.
# ---------------------------------------------------------------------------
def build_simple(path, ui_node_names):
    doc = load(path)
    b = Builder(doc)
    if "Camera_0" in b.src:
        b.keep("Camera_0")
    if "Skybox" in b.src:
        b.keep("Skybox")
    b.group("UI")
    for n in ui_node_names:
        b.keep(n, "UI")
    save(path, b.finish(doc))
    print("wrote", os.path.basename(path), "->", len(doc["nodes"]), "nodes")


# ---------------------------------------------------------------------------
# Pause Menu palette + layout (offsets are from screen CENTER; anchor/pivot 0.5).
# ---------------------------------------------------------------------------
CELL, GAP, PITCH = 110.0, 14.0, 124.0
EQ_LEFT, BAG_LEFT, ROW_TOP = -800.0, 60.0, -300.0

SLOT_BG = [0.07, 0.08, 0.11, 0.95]
SLOT_BORDER = [0.26, 0.28, 0.34, 0.95]
EQUIP_BG = [0.06, 0.10, 0.10, 0.95]
EQUIP_BORDER = [0.40, 0.62, 0.58, 0.9]
ACCENT = [0.62, 0.34, 0.86, 0.95]
STATS_BG = [0.05, 0.06, 0.09, 0.95]
TITLE_FILL = [0.06, 0.05, 0.10, 0.92]
HDR_FILL = [0.06, 0.06, 0.10, 0.80]
HDR_TEXT = [0.9, 0.92, 1.0, 1.0]
HDR_BORDER = [0.40, 0.62, 0.58, 0.9]
BACKDROP = [0.0, 0.0, 0.0, 0.72]
NW_FILL = [0.10, 0.16, 0.10, 0.95]
NW_BORDER = [0.4, 0.9, 0.5, 0.95]
NW_TEXT = [0.9, 1.0, 0.92, 1.0]
CARD_FILL = [0.09, 0.10, 0.15, 0.97]
CARD_BORDER = [0.5, 0.5, 0.6, 0.9]
SLOT_TEXT = [0.85, 0.88, 0.92, 1.0]
EMPTY_TEXT = [0.6, 0.66, 0.7, 0.9]

SLOTS = ["helmet", "body", "pants", "gloves", "weapon", "jewelry"]
SLOT_LABEL = {"helmet": "Helmet", "body": "Body", "pants": "Pants",
              "gloves": "Gloves", "weapon": "Weapon", "jewelry": "Jewelry"}
STATS_LABELS = ("TOTAL STATS\nHealth\nAttack Damage\nAttack Range\n"
                "Attacks/Hit\nAttack Rate\nMove Speed\nArmor\nLife Steal\nRegen")


def add_pause_menu(b):
    b.group("Pause Menu", None, enabled=False)

    b.ui_node("Pause Backdrop", "Pause Menu", "panel", "pause_backdrop",
              2600.0, 1500.0, 0.0, 0.0, fill=BACKDROP, no_input=True)

    # NOTE: authored nodes map to widget types Panel/Text/Button/Image. A TEXT
    # widget draws fill+border AND its `body` text centered in `text_color`
    # (Panel would draw `label` in the accent colour at the top-left), so every
    # text-bearing inventory node is type "text" driven by `body`.
    b.ui_node("Pause Title", "Pause Menu", "text", "pause_title",
              1500.0, 90.0, 0.0, -470.0, fill=TITLE_FILL, border=ACCENT,
              body="GEAR UP", text_color=[0.96, 0.92, 0.70, 1.0],
              font_scale=2.0, text_align_h=2, text_align_v=2, no_input=True,
              bring_to_front=True)

    b.group("Inventory", "Pause Menu")

    eq_hdr_x = EQ_LEFT + (3.0 * PITCH - GAP) * 0.5
    bag_hdr_x = BAG_LEFT + (6.0 * PITCH - GAP) * 0.5
    b.ui_node("Inv Equipped Header", "Inventory", "text", "inv_hdr_equipped",
              358.0, 50.0, eq_hdr_x, ROW_TOP - 70.0, fill=HDR_FILL, border=HDR_BORDER,
              body="EQUIPPED", text_color=HDR_TEXT, font_scale=1.3,
              text_align_h=2, text_align_v=2, no_input=True)
    b.ui_node("Inv Backpack Header", "Inventory", "text", "inv_hdr_backpack",
              360.0, 50.0, bag_hdr_x, ROW_TOP - 70.0, fill=HDR_FILL, border=HDR_BORDER,
              body="BACKPACK", text_color=HDR_TEXT, font_scale=1.3,
              text_align_h=2, text_align_v=2, no_input=True)

    # Paper-doll equip slots (3 cols x 2 rows). Draggable text widgets.
    for i, key in enumerate(SLOTS):
        col, row = i % 3, i // 3
        cx = EQ_LEFT + CELL * 0.5 + col * PITCH
        cy = ROW_TOP + CELL * 0.5 + row * PITCH
        b.ui_node("Inv Equip " + SLOT_LABEL[key], "Inventory", "text", "inv_eq_" + key,
                  CELL, CELL, cx, cy, fill=EQUIP_BG, border=EQUIP_BORDER,
                  body=SLOT_LABEL[key], text_color=EMPTY_TEXT, font_scale=0.85,
                  text_align_h=2, text_align_v=2, draggable=True, bring_to_front=True)

    # Backpack grid (6 cols x 4 rows).
    for idx in range(1, 25):
        col, row = (idx - 1) % 6, (idx - 1) // 6
        cx = BAG_LEFT + CELL * 0.5 + col * PITCH
        cy = ROW_TOP + CELL * 0.5 + row * PITCH
        b.ui_node("Inv Bag " + str(idx), "Inventory", "text", "inv_bag_" + str(idx),
                  CELL, CELL, cx, cy, fill=SLOT_BG, border=SLOT_BORDER,
                  body="", text_color=SLOT_TEXT, font_scale=0.85,
                  text_align_h=2, text_align_v=2, draggable=True, bring_to_front=True)

    # Live stat panel (labels static; values script-driven). Left/top aligned.
    b.ui_node("Inv Stats Panel", "Inventory", "panel", "inv_stats_bg",
              470.0, 430.0, -621.0, 180.0, fill=STATS_BG, border=ACCENT, no_input=True)
    b.ui_node("Inv Stats Labels", "Inventory", "text", "inv_stats_labels",
              250.0, 400.0, -700.0, 180.0, body=STATS_LABELS,
              text_color=[0.92, 0.94, 0.98, 1.0], font_scale=0.95, no_input=True,
              bring_to_front=True)
    b.ui_node("Inv Stats Values", "Inventory", "text", "inv_stats_values",
              220.0, 400.0, -470.0, 180.0, body="",
              text_color=[0.96, 0.92, 0.70, 1.0], font_scale=0.95, no_input=True,
              bring_to_front=True)

    # Draft cards (placeholder group; disabled until card-draft logic lands).
    b.group("Cards", "Pause Menu", enabled=False)
    for i in range(1, 4):
        cx = -260.0 + (i - 1) * 260.0
        b.ui_node("Card " + str(i), "Cards", "panel", "pause_card_" + str(i),
                  230.0, 320.0, cx, 330.0, fill=CARD_FILL, border=CARD_BORDER,
                  title="CARD " + str(i), body="(draft slot)",
                  text_color=[0.9, 0.92, 0.96, 1.0], font_scale=1.4,
                  text_align_h=2)

    # Next Wave button — its own node script resumes the active duel.
    b.ui_node("Pause Next Wave", "Pause Menu", "button", "pause_next_wave",
              360.0, 84.0, 0.0, 560.0, flags=528,
              script="Assets/Scripts/shared/hud/pause_next_wave.lua",
              title="NEXT WAVE   [Enter]", action_function="on_next_wave",
              fill=NW_FILL, border=NW_BORDER, accent=NW_BORDER, text_color=NW_TEXT,
              font_scale=1.7, text_align_h=2, text_align_v=2, bring_to_front=True)


def build_game(path):
    doc = load(path)
    b = Builder(doc)
    # Environment / systems stay at root.
    b.keep("Camera_0")
    b.keep("Skybox")
    b.keep("Stage Light")
    b.keep("GameBoot")

    # Static arena stage (existing empty "Stage" group + its children).
    b.keep("Stage")
    for n in ["Floor", "Wall_N", "Wall_S", "Wall_W", "Wall_E",
              "Spawn_1", "Spawn_2", "Spawn_3", "Spawn_4", "Spawn_5", "Spawn_6"]:
        b.keep(n, "Stage")

    # Hero rig (existing "Hero" group + sprite child).
    b.keep("Hero")
    b.keep("Hero Body", "Hero")

    # In-combat HUD widgets grouped under a new "HUD" node.
    b.group("HUD")
    for n in ["HUD HP BG", "HUD HP Fill", "HUD HP Text", "HUD Spawn BG",
              "HUD Spawn Fill", "HUD FPS", "HUD Gear", "HUD Gear Hit"]:
        b.keep(n, "HUD")

    # Authored pause/inventory screen (was script-drawn).
    add_pause_menu(b)

    save(path, b.finish(doc))
    print("wrote", os.path.basename(path), "->", len(doc["nodes"]), "nodes")


def main():
    build_simple(os.path.join(SCENES, "intro.pescene"), ["UI Title", "UI Play"])
    build_simple(os.path.join(SCENES, "hero_select.pescene"),
                 ["UI Title", "UI Ranger", "UI Brawler", "UI Sower", "UI Back"])
    build_simple(os.path.join(SCENES, "map.pescene"),
                 ["UI Title", "UI Arena", "UI Locked Spud", "UI Locked Alien", "UI Back"])
    build_game(os.path.join(SCENES, "game.pescene"))


if __name__ == "__main__":
    main()
