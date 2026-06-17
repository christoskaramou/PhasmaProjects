#!/usr/bin/env python3
"""Append the HUD panel frames to the authored scene as runtime_ui nodes.

Warbound authors its whole world (terrain, units) AND its HUD panels in the scene
hierarchy; scripts only drive the dynamic content. The engine renders runtime_ui
nodes that are present in the loaded scene (script-created ones don't get a tag), so
the panel frames must live in the .pescene. This tool adds them.

Workflow:  WB_BAKE=1 -> Assets/Scenes/baked (world + units) ;  copy to skirmish.pescene
           python tools/build_hud.py            (appends the HUD frames)

Idempotent: a "UI_Root" group marks the start of the HUD block; re-running truncates
from there and re-appends, leaving the world/unit nodes (and the camera node_index)
untouched.
"""
import json
import os

SCENE = os.path.join(os.path.dirname(__file__), "..", "Assets", "Scenes", "skirmish.pescene")

PANEL = [0.06, 0.07, 0.10, 0.92]
EDGE = [0.45, 0.38, 0.22, 0.95]
INK = [0.93, 0.95, 0.99, 1.0]
GOLD = [0.95, 0.78, 0.22, 1.0]
GREEN = [0.36, 0.82, 0.40, 1.0]


def mat(w, h, tx, ty):
    # column-major: scale (w,h,1) + translation (tx,ty,0)
    return [w, 0.0, 0.0, 0.0, 0.0, h, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, tx, ty, 0.0, 1.0]


def ui_node(name, wid, w, h, anchor, pivot, tx, ty, parent, *,
            wtype="panel", fill=None, border=None, body="", title="",
            text_color=None, font_scale=1.0, align_h=2, align_v=2, no_input=True):
    return {
        "name": name,
        "local_matrix": mat(w, h, tx, ty),
        "component_flags": 512,
        "runtime_ui": {
            "type": wtype, "screen": "__scene_ui", "id": wid,
            "title": title, "body": body, "action": "click",
            "fill": fill if fill is not None else [0, 0, 0, 0],
            "border": border if border is not None else [0, 0, 0, 0],
            "accent": [0, 0, 0, 0],
            "text_color": text_color if text_color is not None else INK,
            "image_tint": [1, 1, 1, 1],
            "anchor": anchor, "pivot": pivot,
            "font_scale": font_scale,
            "text_align_h": align_h, "text_align_v": align_v,
            "text_offset": [0.0, 0.0],
            "visible": True, "draggable": False, "no_input": no_input, "bring_to_front": False,
        },
        "parent": parent,
    }


def build_hud(nodes_len_before, ui_root_index):
    # ui_root_index = index the UI_Root group will occupy; children reference it.
    g = ui_root_index
    M = 20.0  # margin
    nodes = [{"name": "UI_Root", "local_matrix": mat(1, 1, 0, 0), "parent": -1}]
    # Minimap / Portrait / Command are authored, visible panels (dark fill + edge): they
    # render their own frame so the editor (stopped) shows the real HUD chrome. The script
    # adopts each by name, reads its laid-out rect (get_ui_rect), and draws the dynamic
    # content (dots, bars, buttons, text) inside it; no_input so they never steal clicks.
    # 1=top  bottom-left minimap
    nodes.append(ui_node("HUD_Minimap", "hud_minimap", 300, 300, [0, 1], [0, 1], M, -M, g,
                         fill=PANEL, border=EDGE))
    # portrait, right of the minimap
    nodes.append(ui_node("HUD_Portrait", "hud_portrait", 560, 300, [0, 1], [0, 1], M * 2 + 300, -M, g,
                         fill=PANEL, border=EDGE))
    # command card, bottom-right
    nodes.append(ui_node("HUD_Command", "hud_command", 560, 300, [1, 1], [1, 1], -M, -M, g,
                         fill=PANEL, border=EDGE))
    # resources, top-right
    nodes.append(ui_node("HUD_Resources", "hud_resources", 440, 70, [1, 0], [1, 0], -M, M, g,
                         fill=PANEL, border=EDGE, body="Gold 0   Lumber 0   Food 0/12",
                         text_color=GOLD, font_scale=1.4, align_h=2, align_v=2))
    # fps, top-right (left of resources)
    nodes.append(ui_node("HUD_Fps", "hud_fps", 150, 70, [1, 0], [1, 0], -(M * 2 + 440), M, g,
                         fill=PANEL, border=EDGE, body="FPS --", text_color=GREEN,
                         font_scale=1.4, align_h=2, align_v=2))
    # objective banner, top-center
    nodes.append(ui_node("HUD_Objective", "hud_objective", 1000, 70, [0.5, 0], [0.5, 0], 0, M, g,
                         wtype="text", body="Clear the Wilds camp", text_color=INK,
                         font_scale=1.6, align_h=2, align_v=2))
    return nodes


def main():
    path = os.path.normpath(SCENE)
    doc = json.load(open(path, encoding="utf-8"))
    nodes = doc["nodes"]
    # idempotency: drop any existing HUD block (from UI_Root onward).
    for i, n in enumerate(nodes):
        if n.get("name") == "UI_Root":
            nodes = nodes[:i]
            break
    ui_root_index = len(nodes)
    nodes += build_hud(len(nodes), ui_root_index)
    doc["nodes"] = nodes
    json.dump(doc, open(path, "w", encoding="utf-8"), indent=2)
    print("HUD frames appended; total nodes:", len(nodes), "UI_Root at", ui_root_index)


if __name__ == "__main__":
    main()
