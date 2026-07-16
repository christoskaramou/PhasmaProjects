# Regenerate ATH scene files with a logically-grouped node hierarchy and an
# authored (disabled) Pause Menu node tree in game.pescene.
#
# Why a generator: .pescene `parent` fields are array indices, and camera
# `node_index` references the node array too. Inserting group nodes shifts every
# index, so we rebuild each scene's node list by NAME (parents resolved after
# ordering) and recompute camera node_index. Kept nodes preserve their exact
# local_matrix / runtime_ui / mesh data; only their parent changes.

import copy
import json
import os

SCENES = r"c:\Users\Christos\repos\PhasmaProjects\AgainstTheHero\Assets\Scenes"
# Component_SceneSettings = 1 << 14 — enables the editor Scene Settings node.
COMPONENT_SCENE_SETTINGS = 16384


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
        if name not in self.src:
            return
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

    def scene_settings(self):
        """Root Scene Settings node (editor-owned render/post toggles)."""
        self.specs.append(("Scene Settings", None, {
            "name": "Scene Settings",
            "local_matrix": identity(),
            "component_flags": COMPONENT_SCENE_SETTINGS,
        }))

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


def load_intro_settings():
    """Canonical Scene Settings — authored on intro.pescene in the editor."""
    intro = load(os.path.join(SCENES, "intro.pescene"))
    return copy.deepcopy(intro["settings"])


def apply_scene_settings(doc, settings):
    doc["settings"] = copy.deepcopy(settings)


# ---------------------------------------------------------------------------
# Shared palette + scripts (menu scenes + Pause Menu).
# ---------------------------------------------------------------------------
CELL, GAP, PITCH = 150.0, 14.0, 164.0
# Content sits below hub tabs (tab_y=-420, h=52 → bottom ≈ -446).
EQ_LEFT, BAG_LEFT, ROW_TOP = -700.0, -100.0, -250.0
GEAR_SCRIPT_GAME = "Assets/Scripts/shared/hud/hud_gear.lua"
GEAR_SCRIPT_MENU = "Assets/Scripts/shared/hud/menu_gear.lua"
SETTINGS_SCRIPT = "Assets/Scripts/shared/hud/hub_settings.lua"
FLOW_SCRIPT = "Assets/Scripts/shared/flow.lua"

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


# ---------------------------------------------------------------------------
# Simple UI scenes (intro / hero_select): nest the runtime_ui nodes under
# a single "UI" group; keep Camera/Skybox at root.
# ---------------------------------------------------------------------------
def add_menu_gear_and_settings(b):
    """Top-right gear + compact Menu Settings panel on intro/hero_select."""
    b.ui_node("UI Gear", "UI", "image", "ui_gear",
              96.0, 96.0, -48.0, 48.0, flags=528, script=GEAR_SCRIPT_MENU,
              action_function="on_toggle_gear", image="../Textures/gear.png",
              image_tint=[1.0, 1.0, 1.0, 1.0], bring_to_front=True,
              anchor=[1.0, 0.0], pivot=[1.0, 0.0])

    b.group("Menu Settings", "UI", enabled=False)
    b.ui_node("Menu Settings Panel", "Menu Settings", "panel", "menu_set_panel",
              420.0, 360.0, -240.0, 180.0, fill=STATS_BG, border=ACCENT, no_input=True,
              anchor=[1.0, 0.0], pivot=[0.5, 0.0])

    def menu_btn(name, wid, action, title, x, y, w=180.0, h=48.0, fill=None, border=None,
                 accent=None, text_color=None):
        b.ui_node(name, "Menu Settings", "button", wid, w, h, x, y, flags=528,
                  script=SETTINGS_SCRIPT, action_function=action, title=title,
                  fill=fill or HDR_FILL, border=border or HDR_BORDER,
                  accent=accent or ACCENT, text_color=text_color or HDR_TEXT,
                  font_scale=0.95, text_align_h=2, text_align_v=2, bring_to_front=True,
                  anchor=[1.0, 0.0], pivot=[0.5, 0.0])

    menu_btn("Menu Lang EN", "menu_lang_en", "on_lang_en", "EN", -340.0, 220.0, 100.0, 48.0)
    menu_btn("Menu Lang EL", "menu_lang_el", "on_lang_el", "EL", -200.0, 220.0, 100.0, 48.0)
    menu_btn("Menu Damage Text", "menu_damage_text", "on_damage_text", "DAMAGE TEXT",
             -270.0, 290.0, 280.0, 48.0)
    menu_btn("Menu Shake", "menu_shake", "on_shake", "SCREEN SHAKE",
             -270.0, 360.0, 280.0, 48.0)
    menu_btn("Menu Quit", "menu_quit", "on_quit_app", "QUIT",
             -270.0, 430.0, 280.0, 48.0,
             fill=[0.20, 0.08, 0.08, 0.95], border=[0.9, 0.3, 0.3, 0.95],
             accent=[0.9, 0.3, 0.3, 0.95], text_color=[1.0, 0.85, 0.85, 1.0])


def build_simple(path, ui_node_names, scene_settings=None):
    doc = load(path)
    if scene_settings is not None:
        apply_scene_settings(doc, scene_settings)
    b = Builder(doc)
    if "Camera_0" in b.src:
        b.keep("Camera_0")
    if "Skybox" in b.src:
        b.keep("Skybox")
    b.group("UI")
    for n in ui_node_names:
        if n in b.src:
            b.keep(n, "UI")
    # Intro-only fallbacks when Load/Quit were never authored.
    if os.path.basename(path) == "intro.pescene":
        play_fill = [0.12, 0.14, 0.17, 0.96]
        play_border = [0.96, 0.74, 0.22, 0.95]
        play_text = [0.97, 0.98, 1.0, 1.0]
        if "UI Continue" not in b.src and "UI Load" not in b.src:
            b.ui_node("UI Continue", "UI", "button", "intro_continue",
                      420.0, 110.0, 1280.0, 820.0, flags=528, script=FLOW_SCRIPT,
                      action_function="on_continue", title="Continue",
                      fill=play_fill, border=play_border, accent=play_border,
                      text_color=play_text, font_scale=2.1,
                      text_align_h=2, text_align_v=2, anchor=[0.0, 0.0], pivot=[0.5, 0.5])
        if "UI Load Pick" not in b.src:
            b.ui_node("UI Load Pick", "UI", "button", "intro_load_pick",
                      420.0, 110.0, 1280.0, 940.0, flags=528, script=FLOW_SCRIPT,
                      action_function="on_load_pick", title="Load",
                      fill=play_fill, border=play_border, accent=play_border,
                      text_color=play_text, font_scale=2.1,
                      text_align_h=2, text_align_v=2, anchor=[0.0, 0.0], pivot=[0.5, 0.5])
        if "UI Quit" not in b.src:
            b.ui_node("UI Quit", "UI", "button", "intro_quit",
                      420.0, 110.0, 1280.0, 1060.0, flags=528, script=FLOW_SCRIPT,
                      action_function="on_quit", title="Quit",
                      fill=[0.20, 0.08, 0.08, 0.95], border=[0.9, 0.3, 0.3, 0.95],
                      accent=[0.9, 0.3, 0.3, 0.95], text_color=[1.0, 0.85, 0.85, 1.0],
                      font_scale=2.1, text_align_h=2, text_align_v=2,
                      anchor=[0.0, 0.0], pivot=[0.5, 0.5])
    add_menu_gear_and_settings(b)
    b.scene_settings()
    save(path, b.finish(doc))
    print("wrote", os.path.basename(path), "->", len(doc["nodes"]), "nodes")


# ---------------------------------------------------------------------------
# Pause Menu layout (offsets are from screen CENTER; anchor/pivot 0.5).
# ---------------------------------------------------------------------------
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
                "Attacks/Hit\nAttack Rate\nMove Speed\nEquip Load\nArmor\nLife Steal\nRegen")
STORE_SCRIPT = "Assets/Scripts/shared/hud/town_store.lua"
HUB_TABS_SCRIPT = "Assets/Scripts/shared/hud/hub_tabs.lua"
SYSTEM_SCRIPT = "Assets/Scripts/shared/hud/hub_system.lua"
SKILLS_SCRIPT = "Assets/Scripts/shared/hud/hub_skills.lua"
TAB_DEFS = [
    ("map", "MAP", "on_tab_map"),
    ("inventory", "INVENTORY", "on_tab_inventory"),
    ("store", "STORE", "on_tab_store"),
    ("skills", "SKILLS", "on_tab_skills"),
    ("settings", "SETTINGS", "on_tab_settings"),
    ("system", "SYSTEM", "on_tab_system"),
]
LOOT_RARITY = [
    ("common", "COM", [0.55, 0.55, 0.58, 0.95], [0.85, 0.86, 0.90, 1.0]),
    ("uncommon", "UNC", [0.20, 0.40, 0.28, 0.95], [0.33, 0.67, 0.33, 1.0]),
    ("rare", "RARE", [0.15, 0.28, 0.55, 0.95], [0.28, 0.55, 0.93, 1.0]),
    ("epic", "EPIC", [0.35, 0.22, 0.55, 0.95], [0.65, 0.45, 0.93, 1.0]),
    ("legendary", "LEG", [0.45, 0.35, 0.10, 0.95], [0.79, 0.64, 0.15, 1.0]),
]
CONTROLS_HELP = (
    "Move · WASD / stick\n"
    "Attack · LMB / RT\n"
    "Dodge · Space / A\n"
    "Gear hub · Gear btn / Esc"
)

SETTINGS_SUBTABS = [
    ("game", "GAME", "on_sub_game"),
    ("audio", "AUDIO", "on_sub_audio"),
    ("graphics", "GRAPHICS", "on_sub_graphics"),
    ("controls", "CONTROLS", "on_sub_controls"),
]


def add_hub_settings(b):
    """Settings with GAME / AUDIO / GRAPHICS / CONTROLS sub-tabs (one page at a time)."""
    b.group("Settings", "Pause Menu", enabled=False)

    # Sub-tab bar just under the main hub tabs (tab_y=-420).
    sub_y = -340.0
    sub_w, sub_h, sub_pitch = 200.0, 44.0, 220.0
    sub_left = -((len(SETTINGS_SUBTABS) - 1) * sub_pitch) * 0.5
    for i, (key, label, action) in enumerate(SETTINGS_SUBTABS):
        cx = sub_left + i * sub_pitch
        b.ui_node("Set Sub " + label.title(), "Settings", "button", "set_sub_" + key,
                  sub_w, sub_h, cx, sub_y, flags=528, script=SETTINGS_SCRIPT,
                  action_function=action, title=label,
                  fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
                  font_scale=0.9, text_align_h=2, text_align_v=2, bring_to_front=True)

    # Shared full-width page frame (one visible subgroup at a time).
    page_w, page_h = 920.0, 500.0
    page_x, page_y = 0.0, -20.0
    top = page_y - page_h * 0.5

    def page(group_name, enabled, header, border=HDR_BORDER):
        b.group(group_name, "Settings", enabled=enabled)
        b.ui_node(group_name + " Panel", group_name, "panel", group_name.lower().replace(" ", "_") + "_panel",
                  page_w, page_h, page_x, page_y, fill=STATS_BG, border=border, no_input=True)
        b.ui_node(group_name + " Header", group_name, "text", group_name.lower().replace(" ", "_") + "_hdr",
                  page_w - 40.0, 36.0, page_x, top + 30.0,
                  body=header, text_color=[0.96, 0.90, 0.66, 1.0], font_scale=1.2,
                  text_align_h=2, text_align_v=2, no_input=True, bring_to_front=True)
        return top + 80.0  # first content row y

    # --- GAME ---
    y0 = page("Set Game", True, "GAME", ACCENT)
    b.ui_node("Set Lang EN", "Set Game", "button", "set_lang_en",
              100.0, 44.0, -220.0, y0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_lang_en", title="EN",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=1.0, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Set Lang EL", "Set Game", "button", "set_lang_el",
              100.0, 44.0, -90.0, y0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_lang_el", title="EL",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=1.0, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Set Damage Text", "Set Game", "button", "set_damage_text",
              220.0, 44.0, 140.0, y0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_damage_text", title="DAMAGE",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=0.95, text_align_h=2, text_align_v=2, bring_to_front=True)

    b.ui_node("Set Loot Header", "Set Game", "text", "set_loot_hdr",
              700.0, 32.0, 0.0, y0 + 70.0, body="LOOT FILTER",
              text_color=[0.72, 0.74, 0.80, 1.0], font_scale=1.0,
              text_align_h=2, text_align_v=2, no_input=True, bring_to_front=True)
    loot_w, loot_gap = 120.0, 14.0
    loot_span = 5 * loot_w + 4 * loot_gap
    loot_x0 = -loot_span * 0.5 + loot_w * 0.5
    for i, (key, btn_title, fill, text_color) in enumerate(LOOT_RARITY):
        cx = loot_x0 + i * (loot_w + loot_gap)
        b.ui_node("Set Loot " + key.title(), "Set Game", "button", "set_loot_" + key,
                  loot_w, 44.0, cx, y0 + 120.0, flags=528, script=SETTINGS_SCRIPT,
                  action_function="on_loot_" + key, title=btn_title,
                  fill=fill, border=text_color, accent=text_color, text_color=text_color,
                  font_scale=0.9, text_align_h=2, text_align_v=2, bring_to_front=True)

    b.ui_node("Set Shake", "Set Game", "button", "set_shake",
              280.0, 48.0, 0.0, y0 + 200.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_shake", title="SCREEN SHAKE",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=0.95, text_align_h=2, text_align_v=2, bring_to_front=True)

    # --- AUDIO ---
    y0 = page("Set Audio", False, "AUDIO")
    for i, (key, label) in enumerate([("master", "MASTER"), ("music", "MUSIC"), ("sfx", "SFX")]):
        row_y = y0 + i * 70.0
        b.ui_node("Set Vol " + label + " Label", "Set Audio", "text", "set_vol_" + key + "_lbl",
                  280.0, 40.0, -160.0, row_y, body=label,
                  text_color=HDR_TEXT, font_scale=1.1, text_align_h=0, text_align_v=2,
                  no_input=True, bring_to_front=True)
        b.ui_node("Set Vol " + label + " Down", "Set Audio", "button", "set_vol_" + key + "_down",
                  56.0, 48.0, 120.0, row_y, flags=528, script=SETTINGS_SCRIPT,
                  action_function="on_vol_" + key + "_down", title="-",
                  fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
                  font_scale=1.3, text_align_h=2, text_align_v=2, bring_to_front=True)
        b.ui_node("Set Vol " + label + " Up", "Set Audio", "button", "set_vol_" + key + "_up",
                  56.0, 48.0, 220.0, row_y, flags=528, script=SETTINGS_SCRIPT,
                  action_function="on_vol_" + key + "_up", title="+",
                  fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
                  font_scale=1.3, text_align_h=2, text_align_v=2, bring_to_front=True)

    # --- GRAPHICS ---
    y0 = page("Set Graphics", False, "GRAPHICS")
    bw, bh = 280.0, 48.0
    b.ui_node("Set Gfx Fxaa", "Set Graphics", "button", "set_gfx_fxaa",
              bw, bh, -160.0, y0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_gfx_fxaa", title="FXAA",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=0.95, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Set Gfx Taa", "Set Graphics", "button", "set_gfx_taa",
              bw, bh, 160.0, y0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_gfx_taa", title="TAA",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=0.95, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Set Gfx Grade", "Set Graphics", "button", "set_gfx_grade",
              bw, bh, -160.0, y0 + 70.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_gfx_grade", title="COLOR GRADE",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=0.9, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Set Gfx Disney", "Set Graphics", "button", "set_gfx_disney",
              bw, bh, 160.0, y0 + 70.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_gfx_disney", title="DISNEY PBR",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=0.9, text_align_h=2, text_align_v=2, bring_to_front=True)

    b.ui_node("Set Gfx Scale Label", "Set Graphics", "text", "set_gfx_scale_lbl",
              280.0, 40.0, -160.0, y0 + 160.0, body="SCALE  100%",
              text_color=HDR_TEXT, font_scale=1.05, text_align_h=0, text_align_v=2,
              no_input=True, bring_to_front=True)
    b.ui_node("Set Gfx Scale Down", "Set Graphics", "button", "set_gfx_scale_down",
              56.0, 48.0, 120.0, y0 + 160.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_gfx_scale_down", title="-",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=1.3, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Set Gfx Scale Up", "Set Graphics", "button", "set_gfx_scale_up",
              56.0, 48.0, 220.0, y0 + 160.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_gfx_scale_up", title="+",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=1.3, text_align_h=2, text_align_v=2, bring_to_front=True)

    b.ui_node("Set Gfx Time Label", "Set Graphics", "text", "set_gfx_time_lbl",
              280.0, 40.0, -160.0, y0 + 230.0, body="TIME  100%",
              text_color=HDR_TEXT, font_scale=1.05, text_align_h=0, text_align_v=2,
              no_input=True, bring_to_front=True)
    b.ui_node("Set Gfx Time Down", "Set Graphics", "button", "set_gfx_time_down",
              56.0, 48.0, 120.0, y0 + 230.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_gfx_time_down", title="-",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=1.3, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Set Gfx Time Up", "Set Graphics", "button", "set_gfx_time_up",
              56.0, 48.0, 220.0, y0 + 230.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_gfx_time_up", title="+",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=1.3, text_align_h=2, text_align_v=2, bring_to_front=True)

    b.ui_node("Set Gfx Present", "Set Graphics", "button", "set_gfx_present",
              520.0, 48.0, 0.0, y0 + 310.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_gfx_present", title="PRESENT  VSYNC",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=0.95, text_align_h=2, text_align_v=2, bring_to_front=True)

    # --- CONTROLS ---
    y0 = page("Set Controls", False, "CONTROLS & HELPERS")
    b.ui_node("Set Controls Help", "Set Controls", "text", "set_controls_help",
              700.0, 160.0, 0.0, y0 + 40.0, body=CONTROLS_HELP,
              text_color=[0.78, 0.80, 0.86, 1.0], font_scale=1.05,
              text_align_h=2, text_align_v=0, no_input=True, bring_to_front=True)
    b.ui_node("Set Show Fps", "Set Controls", "button", "set_show_fps",
              280.0, 48.0, -160.0, y0 + 220.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_show_fps", title="SHOW FPS",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=0.95, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Set Dev Mode", "Set Controls", "button", "set_dev_mode",
              280.0, 48.0, 160.0, y0 + 220.0, flags=528, script=SETTINGS_SCRIPT,
              action_function="on_dev_mode", title="DEV MODE",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=0.95, text_align_h=2, text_align_v=2, bring_to_front=True)


def add_hub_skills(b):
    """Three specialization icons — small hit targets; frame/icon/level from Lua."""
    b.group("Skills", "Pause Menu", enabled=False)
    b.ui_node("Skills Header", "Skills", "text", "skills_header",
              900.0, 50.0, 0.0, -340.0, fill=HDR_FILL, border=ACCENT,
              body="SKILLS", text_color=HDR_TEXT, font_scale=1.5,
              text_align_h=2, text_align_v=2, no_input=True)
    cols = 3
    card = 72.0
    pitch_x = 110.0
    grid_left = -((cols - 1) * pitch_x) * 0.5
    top_y = -220.0
    clear = [0.0, 0.0, 0.0, 0.0]
    for i in range(1, cols + 1):
        cx = grid_left + (i - 1) * pitch_x
        b.ui_node("Skill Node " + str(i), "Skills", "button", "hub_skill_" + str(i),
                  card, card, cx, top_y, flags=528, script=SKILLS_SCRIPT,
                  action_function="on_skill_" + str(i), title=" ", body="",
                  fill=clear, border=clear, accent=clear,
                  text_color=clear, font_scale=0.01,
                  text_align_h=2, text_align_v=2, bring_to_front=True)


def add_pause_menu(b):
    b.group("Pause Menu", None, enabled=False)

    b.ui_node("Pause Backdrop", "Pause Menu", "panel", "pause_backdrop",
              2600.0, 1500.0, 0.0, 0.0, fill=BACKDROP, no_input=True)

    # NOTE: authored nodes map to widget types Panel/Text/Button/Image. A TEXT
    # widget draws fill+border AND its `body` text centered in `text_color`
    # (Panel would draw `label` in the accent colour at the top-left), so every
    # text-bearing inventory node is type "text" driven by `body`.
    b.ui_node("Pause Title", "Pause Menu", "text", "pause_title",
              # Keep clear of the authored top-right FPS clock (~340px + margin).
              1100.0, 72.0, 0.0, -500.0, fill=TITLE_FILL, border=ACCENT,
              body="GEAR HUB", text_color=[0.96, 0.92, 0.70, 1.0],
              font_scale=1.8, text_align_h=2, text_align_v=2, no_input=True,
              bring_to_front=True)

    tab_y = -420.0
    tab_w, tab_h = 168.0, 52.0
    tab_pitch = 176.0
    tab_left = -((len(TAB_DEFS) - 1) * tab_pitch) * 0.5
    for i, (key, label, action) in enumerate(TAB_DEFS):
        cx = tab_left + i * tab_pitch
        b.ui_node("Hub Tab " + label.title(), "Pause Menu", "button", "hub_tab_" + key,
                  tab_w, tab_h, cx, tab_y, flags=528, script=HUB_TABS_SCRIPT,
                  action_function=action, title=label,
                  fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
                  font_scale=0.95, text_align_h=2, text_align_v=2, bring_to_front=True)

    b.group("Inventory", "Pause Menu", enabled=False)

    eq_hdr_x = EQ_LEFT + (3.0 * PITCH - GAP) * 0.5
    bag_hdr_x = BAG_LEFT + (6.0 * PITCH - GAP) * 0.5
    b.ui_node("Inv Equipped Header", "Inventory", "text", "inv_hdr_equipped",
              3.0 * PITCH - GAP, 50.0, eq_hdr_x, ROW_TOP - 70.0, fill=HDR_FILL, border=HDR_BORDER,
              body="EQUIPPED", text_color=HDR_TEXT, font_scale=1.8,
              text_align_h=2, text_align_v=2, no_input=True)
    b.ui_node("Inv Backpack Header", "Inventory", "text", "inv_hdr_backpack",
              6.0 * PITCH - GAP, 50.0, bag_hdr_x, ROW_TOP - 70.0, fill=HDR_FILL, border=HDR_BORDER,
              body="BACKPACK", text_color=HDR_TEXT, font_scale=1.8,
              text_align_h=2, text_align_v=2, no_input=True)

    # Paper-doll equip slots (3 cols x 2 rows). Draggable text widgets.
    for i, key in enumerate(SLOTS):
        col, row = i % 3, i // 3
        cx = EQ_LEFT + CELL * 0.5 + col * PITCH
        cy = ROW_TOP + CELL * 0.5 + row * PITCH
        b.ui_node("Inv Equip " + SLOT_LABEL[key], "Inventory", "text", "inv_eq_" + key,
                  CELL, CELL, cx, cy, fill=EQUIP_BG, border=EQUIP_BORDER,
                  body=SLOT_LABEL[key], text_color=EMPTY_TEXT, font_scale=1.3,
                  text_align_h=2, text_align_v=2, draggable=True, bring_to_front=True)

    # Backpack grid (6 cols x 4 rows).
    for idx in range(1, 25):
        col, row = (idx - 1) % 6, (idx - 1) // 6
        cx = BAG_LEFT + CELL * 0.5 + col * PITCH
        cy = ROW_TOP + CELL * 0.5 + row * PITCH
        b.ui_node("Inv Bag " + str(idx), "Inventory", "text", "inv_bag_" + str(idx),
                  CELL, CELL, cx, cy, fill=SLOT_BG, border=SLOT_BORDER,
                   body="", text_color=SLOT_TEXT, font_scale=1.3,
                  text_align_h=2, text_align_v=2, draggable=True, bring_to_front=True)

    # Live stat panel — labels + values fully inside the panel bounds.
    b.ui_node("Inv Stats Panel", "Inventory", "panel", "inv_stats_bg",
              478.0, 400.0, -461.0, 320.0, fill=STATS_BG, border=ACCENT, no_input=True)
    b.ui_node("Inv Stats Labels", "Inventory", "text", "inv_stats_labels",
              240.0, 360.0, -560.0, 320.0, body=STATS_LABELS,
              text_color=[0.92, 0.94, 0.98, 1.0], font_scale=1.15, no_input=True,
              bring_to_front=True)
    b.ui_node("Inv Stats Values", "Inventory", "text", "inv_stats_values",
              200.0, 360.0, -330.0, 320.0, body="",
              text_color=[0.96, 0.92, 0.70, 1.0], font_scale=1.15, no_input=True,
              bring_to_front=True)

    # Town-only shop is a separate hub tab view.
    b.group("Town Store", "Pause Menu", enabled=False)
    store_x, store_y = -504.0, -260.0
    b.ui_node("Store Header", "Town Store", "text", "store_header",
              1008.0, 58.0, 0.0, ROW_TOP - 40.0, fill=HDR_FILL, border=ACCENT,
              body="GEAR FOR SALE", text_color=HDR_TEXT, font_scale=1.5,
              text_align_h=2, text_align_v=2, no_input=True)
    actions = {
        "helmet": "on_buy_helmet", "body": "on_buy_body", "pants": "on_buy_pants",
        "gloves": "on_buy_gloves", "weapon": "on_buy_weapon", "jewelry": "on_buy_jewelry",
    }
    for i, key in enumerate(SLOTS):
        col, row = i % 3, i // 3
        cx, cy = store_x + col * 344.0 + 160.0, store_y + row * 224.0 + 100.0
        b.ui_node("Store " + SLOT_LABEL[key], "Town Store", "button", "store_" + key,
                  320.0, 200.0, cx, cy, flags=528, script=STORE_SCRIPT,
                  action_function=actions[key], title=SLOT_LABEL[key], body="",
                  fill=CARD_FILL, border=CARD_BORDER, accent=ACCENT,
                  text_color=SLOT_TEXT, font_scale=1.15, bring_to_front=True)
    b.ui_node("Store Gold", "Town Store", "text", "store_gold",
              320.0, 68.0, 0.0, 260.0, fill=HDR_FILL, border=ACCENT,
              body="GOLD  0", text_color=[0.96, 0.82, 0.30, 1.0], font_scale=1.2,
              text_align_h=2, text_align_v=2, no_input=True)

    add_hub_settings(b)
    add_hub_skills(b)

    b.group("Map", "Pause Menu", enabled=False)
    # +Y is down: info → ENTER → EXIT TO MAP. Same width, stacked with gaps.
    map_w = 360.0
    b.ui_node("Map Dest", "Map", "text", "map_dest",
              map_w, 110.0, 0.0, -160.0, fill=HDR_FILL, border=[0.75, 0.62, 0.35, 0.9],
              body="MAP\nROUND 1", text_color=HDR_TEXT, font_scale=1.25,
              text_align_h=2, text_align_v=2, no_input=True, bring_to_front=True)
    b.ui_node("Map Enter", "Map", "button", "map_enter",
              map_w, 84.0, 0.0, -20.0, flags=528, script=STORE_SCRIPT,
              action_function="on_enter_map", title="ENTER",
              fill=NW_FILL, border=NW_BORDER, accent=NW_BORDER, text_color=NW_TEXT,
              font_scale=1.15, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Map Exit", "Map", "button", "map_exit",
              map_w, 84.0, 0.0, 100.0, flags=528, script=SYSTEM_SCRIPT,
              action_function="on_exit_map", title="EXIT TO MAP",
              fill=[0.20, 0.08, 0.08, 0.95], border=[0.9, 0.3, 0.3, 0.95],
              accent=[0.9, 0.3, 0.3, 0.95], text_color=[1.0, 0.85, 0.85, 1.0],
              font_scale=1.05, text_align_h=2, text_align_v=2, bring_to_front=True)

    b.group("System", "Pause Menu", enabled=False)
    b.ui_node("Sys Resume", "System", "button", "sys_resume",
              360.0, 84.0, 0.0, -80.0, flags=528, script=SYSTEM_SCRIPT,
              action_function="on_resume", title="RESUME",
              fill=HDR_FILL, border=HDR_BORDER, accent=ACCENT, text_color=HDR_TEXT,
              font_scale=1.2, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Sys Next Wave", "System", "button", "sys_next_wave",
              360.0, 84.0, 0.0, 40.0, flags=528, script=SYSTEM_SCRIPT,
              action_function="on_next_wave", title="NEXT WAVE   [Enter]",
              fill=NW_FILL, border=NW_BORDER, accent=NW_BORDER, text_color=NW_TEXT,
              font_scale=1.2, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Sys Quit", "System", "button", "sys_quit",
              360.0, 84.0, 0.0, 160.0, flags=528, script=SYSTEM_SCRIPT,
              action_function="on_quit_menu", title="QUIT TO MENU",
              fill=[0.20, 0.08, 0.08, 0.95], border=[0.9, 0.3, 0.3, 0.95],
              accent=[0.9, 0.3, 0.3, 0.95], text_color=[1.0, 0.85, 0.85, 1.0],
              font_scale=1.05, text_align_h=2, text_align_v=2, bring_to_front=True)
    b.ui_node("Sys Quit App", "System", "button", "sys_quit_app",
              360.0, 84.0, 0.0, 280.0, flags=528, script=SYSTEM_SCRIPT,
              action_function="on_quit_app", title="QUIT",
              fill=[0.20, 0.08, 0.08, 0.95], border=[0.9, 0.3, 0.3, 0.95],
              accent=[0.9, 0.3, 0.3, 0.95], text_color=[1.0, 0.85, 0.85, 1.0],
              font_scale=1.05, text_align_h=2, text_align_v=2, bring_to_front=True)


def build_game(path, scene_settings=None):
    doc = load(path)
    # Keep game.pescene Scene Settings (authored / in-game saved). Do not stamp
    # intro settings over graphics knobs players persist via scene.save.
    if scene_settings is not None and "settings" not in doc:
        apply_scene_settings(doc, scene_settings)
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
        if n in b.src:
            b.keep(n, "Stage")

    # Hero rig (existing "Hero" group + sprite child).
    b.keep("Hero")
    b.keep("Hero Body", "Hero")

    # In-combat HUD widgets grouped under a new "HUD" node.
    b.group("HUD")
    for n in ["HUD HP BG", "HUD HP Fill", "HUD HP Text",
              "HUD FPS", "HUD Gear", "HUD Gear Hit"]:
        if n in b.src:
            b.keep(n, "HUD")
    # HP fill must match BG width (authoring drift left fill short).
    bg_w = 920.0
    for name, _parent, node in b.specs:
        if name == "HUD HP BG":
            m = list(node["local_matrix"])
            bg_w = m[0] or bg_w
            break
    for name, _parent, node in b.specs:
        if name == "HUD HP Fill":
            m = list(node["local_matrix"])
            m[0] = bg_w
            m[12] = -bg_w * 0.5  # left edge of centered BG
            node["local_matrix"] = m
            break
    # Gear hub title is bring_to_front; keep the FPS frame + gear above it.
    # FPS panel: half prior 340x96 (label stays font_scale 0.5 in hud_fps.lua).
    # Gear: 2/3 of prior 120px, tucked under FPS so it clears arena borders.
    for name, _parent, node in b.specs:
        if name in ("HUD FPS", "HUD Gear", "HUD Gear Hit"):
            ui = node.get("runtime_ui")
            if isinstance(ui, dict):
                ui["bring_to_front"] = True
        if name == "HUD FPS":
            m = list(node["local_matrix"])
            m[0], m[5] = 170.0, 48.0
            m[12], m[13] = -40.0, 24.0
            node["local_matrix"] = m
        if name == "HUD Gear":
            m = list(node["local_matrix"])
            m[0], m[5] = 80.0, 80.0
            m[12], m[13] = -40.0, 80.0
            node["local_matrix"] = m

    # Authored pause/inventory screen (was script-drawn).
    add_pause_menu(b)

    # Opaque veil until game_boot finishes (Plan C). Ships DISABLED so the
    # editor viewport stays usable; ATH_FLUSH_SCENE enables it on load, and
    # game_boot disables it again once the arena is ready.
    if "Boot Cover" in b.src:
        b.keep("Boot Cover")
    else:
        b.ui_node("Boot Cover", None, "panel", "boot_cover",
                  8000.0, 8000.0, 0.0, 0.0, enabled=False,
                  fill=[0.04, 0.05, 0.08, 1.0], no_input=True, bring_to_front=True)

    b.scene_settings()

    save(path, b.finish(doc))
    print("wrote", os.path.basename(path), "->", len(doc["nodes"]), "nodes")


def _reposition_hero_select(path):
    """7 heroes: 4 on row 1, 3 on row 2 — avoids right-edge clipping/overlap."""
    doc = load(path)
    by = {n["name"]: n for n in doc["nodes"]}
    row1 = ["UI Ranger", "UI Brawler", "UI Sower", "UI Mage"]
    row2 = ["UI Rogue", "UI Warrior", "UI Necromancer"]
    y1, y2 = 620.0, 980.0
    w = 330.0
    gap = 40.0

    def place(names, y):
        n = len(names)
        total = n * w + (n - 1) * gap
        x0 = 1280.0 - total * 0.5 + w * 0.5
        for i, name in enumerate(names):
            node = by.get(name)
            if not node:
                continue
            m = list(node["local_matrix"])
            m[12] = x0 + i * (w + gap)
            m[13] = y
            node["local_matrix"] = m

    place(row1, y1)
    place(row2, y2)
    back = by.get("UI Back")
    if back:
        m = list(back["local_matrix"])
        m[13] = 1280.0
        back["local_matrix"] = m
    save(path, doc)
    print("repositioned hero_select cards")


def main():
    # Scene Settings authored on intro in the editor — stamp onto every scene.
    settings = load_intro_settings()
    build_simple(os.path.join(SCENES, "intro.pescene"),
                 ["UI Title", "UI Play", "UI Continue", "UI Load", "UI Load Pick", "UI Quit"],
                 scene_settings=settings)
    build_simple(os.path.join(SCENES, "hero_select.pescene"),
                 ["UI Title", "UI Ranger", "UI Brawler", "UI Sower", "UI Mage", "UI Rogue",
                  "UI Warrior", "UI Necromancer", "UI Back"], scene_settings=settings)
    _reposition_hero_select(os.path.join(SCENES, "hero_select.pescene"))
    build_game(os.path.join(SCENES, "game.pescene"), scene_settings=settings)


if __name__ == "__main__":
    main()
