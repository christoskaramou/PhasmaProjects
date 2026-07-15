#!/usr/bin/env python
"""Detect AABB overlaps among authored runtime_ui nodes in .pescene files.

Converts each widget into a shared screen-space rect using anchor/pivot and a
reference resolution (default 2560x1440). Hub content groups are exclusive —
Inventory vs Settings never co-visible — so those pairs are skipped. HUD is a
separate layer from Pause Menu (backdrop covers combat HUD).

Usage:
  python tools/ui_overlap.py
  python tools/ui_overlap.py --scene game.pescene --png
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCENES = ROOT / "Assets" / "Scenes"
REF_W, REF_H = 2560.0, 1440.0

HUB_CONTENT_GROUPS = {
    "Inventory", "Settings", "Town Store", "Cards", "Map", "System",
}
LAYER_PAUSE = "pause"
LAYER_HUD = "hud"
LAYER_MENU = "menu"


@dataclass
class Rect:
    name: str
    uid: str
    parent: str
    layer: str
    x0: float
    y0: float
    x1: float
    y1: float
    no_input: bool

    def overlap_area(self, o: Rect) -> float:
        ix0, iy0 = max(self.x0, o.x0), max(self.y0, o.y0)
        ix1, iy1 = min(self.x1, o.x1), min(self.y1, o.y1)
        return max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)


def contained(inner: Rect, outer: Rect, pad: float = 4.0) -> bool:
    return (inner.x0 >= outer.x0 - pad and inner.y0 >= outer.y0 - pad
            and inner.x1 <= outer.x1 + pad and inner.y1 <= outer.y1 + pad)


def screen_rect(n: dict, parent: str, layer: str) -> Rect | None:
    ru = n.get("runtime_ui")
    if not ru:
        return None
    m = n.get("local_matrix") or [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    w, h, tx, ty = float(m[0]), float(m[5]), float(m[12]), float(m[13])
    ax, ay = (ru.get("anchor") or [0.5, 0.5])[:2]
    px, py = (ru.get("pivot") or [0.5, 0.5])[:2]
    # anchor point on reference screen + local translation - pivot*size
    ox = float(ax) * REF_W + tx - w * float(px)
    oy = float(ay) * REF_H + ty - h * float(py)
    return Rect(
        name=n["name"], uid=str(ru.get("id") or ""), parent=parent, layer=layer,
        x0=ox, y0=oy, x1=ox + w, y1=oy + h,
        no_input=bool(ru.get("no_input")),
    )


def classify(nodes: list[dict], index: int) -> tuple[str, str]:
    """Return (hub_or_ui_parent, layer)."""
    names = [n["name"] for n in nodes]
    cur = index
    chain = []
    for _ in range(10):
        if not (0 <= cur < len(nodes)):
            break
        chain.append(names[cur])
        cur = nodes[cur].get("parent", -1)
    if "Pause Menu" in chain:
        for g in HUB_CONTENT_GROUPS:
            if g in chain:
                return g, LAYER_PAUSE
        return "Pause Menu", LAYER_PAUSE
    if "HUD" in chain or (chain and chain[0].startswith("HUD")):
        return "HUD", LAYER_HUD
    if "Menu Settings" in chain:
        return "Menu Settings", LAYER_MENU
    if "UI" in chain:
        return "UI", LAYER_MENU
    return chain[0] if chain else "", LAYER_MENU


def load_rects(path: Path) -> list[Rect]:
    doc = json.loads(path.read_text(encoding="utf-8"))
    nodes = doc["nodes"]
    out: list[Rect] = []
    for i, n in enumerate(nodes):
        parent, layer = classify(nodes, i)
        r = screen_rect(n, parent, layer)
        if r and n.get("enabled", True) is not False:
            out.append(r)
    return out


def find_overlaps(rects: list[Rect], min_area: float) -> list[tuple[Rect, Rect, float]]:
    hits = []
    for i, a in enumerate(rects):
        for b in rects[i + 1:]:
            if a.layer != b.layer:
                continue  # HUD under pause backdrop; skip cross-layer
            if a.parent in HUB_CONTENT_GROUPS and b.parent in HUB_CONTENT_GROUPS and a.parent != b.parent:
                continue
            if a.uid == "pause_backdrop" or b.uid == "pause_backdrop":
                continue
            area = a.overlap_area(b)
            if area < min_area:
                continue
            # Nested widgets inside a panel/header of the same group.
            if contained(a, b) or contained(b, a):
                continue
            hits.append((a, b, area))
    hits.sort(key=lambda t: -t[2])
    return hits


def write_png(tag: str, rects: list[Rect], hits: list, out_path: Path) -> None:
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("Pillow missing — skip PNG", tag)
        return
    if not rects:
        return
    scale = min(1.0, 1280.0 / REF_W, 720.0 / REF_H)
    W, H = int(REF_W * scale), int(REF_H * scale)
    img = Image.new("RGB", (W, H), (14, 16, 22))
    draw = ImageDraw.Draw(img)
    hit = {a.name for a, b, _ in hits} | {b.name for a, b, _ in hits}

    def box(r: Rect):
        return [r.x0 * scale, r.y0 * scale, r.x1 * scale, r.y1 * scale]

    for r in rects:
        outline = (255, 90, 90) if r.name in hit else (
            (100, 160, 220) if r.parent in HUB_CONTENT_GROUPS else (150, 150, 170))
        draw.rectangle(box(r), outline=outline, width=2)
        draw.text((box(r)[0] + 2, box(r)[1] + 2), r.name[:26], fill=outline)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print("wrote", out_path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene")
    ap.add_argument("--min-area", type=float, default=64.0)
    ap.add_argument("--png", action="store_true")
    ap.add_argument("--out", default=str(ROOT / "tools" / "_ui_overlap_out"))
    args = ap.parse_args()

    files = [SCENES / args.scene] if args.scene else sorted(SCENES.glob("*.pescene"))
    total = 0
    out_dir = Path(args.out)
    for path in files:
        rects = load_rects(path)
        hits = find_overlaps(rects, args.min_area)
        print(f"\n=== {path.name}: {len(rects)} ui, {len(hits)} overlaps @ {int(REF_W)}x{int(REF_H)}")
        for a, b, area in hits[:50]:
            print(f"  {area:8.0f}px  {a.name} [{a.parent}/{a.layer}]  x  {b.name} [{b.parent}/{b.layer}]")
        total += len(hits)
        if args.png:
            if path.name == "game.pescene":
                for g in sorted(HUB_CONTENT_GROUPS | {"Pause Menu", "HUD"}):
                    subset = [r for r in rects if r.parent == g or (g == "Pause Menu" and r.parent == "Pause Menu")]
                    if g in HUB_CONTENT_GROUPS:
                        subset = [r for r in rects if r.parent in (g, "Pause Menu")]
                    sub_hits = [(a, b, ar) for a, b, ar in hits if a in subset and b in subset]
                    if subset:
                        write_png(f"{path.stem}_{g}", subset, sub_hits,
                                  out_dir / f"{path.stem}_{g.replace(' ', '_')}.png")
            else:
                write_png(path.stem, rects, hits, out_dir / f"{path.stem}.png")
    print(f"\nTOTAL overlaps: {total}")
    return 1 if total else 0


if __name__ == "__main__":
    raise SystemExit(main())
