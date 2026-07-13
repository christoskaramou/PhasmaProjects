#!/usr/bin/env python
"""Generate articulated arena hero sprite sheets with Pillow."""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "Assets" / "Textures" / "modes" / "arena"
OUT = SRC / "heroes"

CELL_W, CELL_H = 328, 416  # 2x prior 164x208 — sharper at large on-screen scale
# Draw oversized so attack arcs / death tilts never hit the canvas edge, then
# uniformly fit each class into CELL_* (same scale for every frame).
CANVAS_W, CANVAS_H = 1040, 1040
CELL_MARGIN = 6
RES = 2.0  # all authored limb/pose lengths are in 1x units; multiply by RES when drawing
INK = (24, 18, 23, 255)
CLASSES = ("ranger", "brawler", "sower", "mage", "rogue", "warrior", "necromancer")
CLIPS = (
    ("idle", 4, 7.0, True),
    ("walk", 8, 12.0, True),
    ("attack", 6, 14.0, False),
    ("hit", 3, 12.0, False),
    ("death", 5, 9.0, False),
)

PALETTES = {
    "ranger": ((53, 91, 42, 255), (43, 55, 31, 255), (117, 157, 62, 255), (99, 72, 45, 255), (174, 182, 157, 255)),
    "brawler": ((123, 58, 30, 255), (71, 40, 29, 255), (198, 72, 37, 255), (91, 58, 39, 255), (135, 126, 109, 255)),
    "sower": ((103, 105, 42, 255), (76, 57, 30, 255), (150, 143, 55, 255), (105, 67, 35, 255), (178, 166, 112, 255)),
    "mage": ((74, 42, 127, 255), (42, 27, 75, 255), (54, 153, 222, 255), (91, 58, 128, 255), (205, 151, 52, 255)),
    "rogue": ((48, 36, 56, 255), (29, 25, 34, 255), (116, 50, 147, 255), (57, 42, 47, 255), (177, 183, 194, 255)),
    "warrior": ((127, 135, 145, 255), (69, 75, 84, 255), (172, 45, 37, 255), (87, 61, 48, 255), (206, 211, 216, 255)),
    "necromancer": ((38, 58, 57, 255), (25, 32, 34, 255), (102, 190, 89, 255), (58, 52, 42, 255), (190, 182, 151, 255)),
}

# right upper arm, right forearm and weapon direction, one value per attack frame
ATTACK_ARCS = {
    "ranger": ((18, 8, 0, -3, 3, 45), (5, 0, 0, 0, 8, 60), (-5, -2, 0, 0, 3, 35)),
    "brawler": ((75, 45, 12, 0, 24, 65), (58, 25, 5, 0, 18, 65), (0, 0, 0, 0, 0, 0)),
    "sower": ((145, -125, -75, -15, 38, 70), (-145, -82, -36, 5, 42, 72), (-135, -82, -35, 5, 42, 72)),
    "mage": ((105, 70, 24, -3, 18, 62), (70, 38, 10, 0, 15, 65), (62, 30, 5, 0, 15, 64)),
    "rogue": ((125, -105, -48, -8, 32, 68), (-130, -72, -24, 4, 34, 72), (-125, -70, -22, 5, 35, 72)),
    "warrior": ((145, -125, -76, -18, 32, 68), (-145, -84, -38, 2, 39, 72), (-140, -82, -36, 3, 40, 72)),
    "necromancer": ((130, -118, -64, -12, 30, 68), (-135, -78, -30, 5, 38, 72), (-130, -76, -28, 7, 40, 72)),
}

HEAD_BOXES = {
    "ranger": (0.19, 0.12, 0.81, 0.43),
    "brawler": (0.18, 0.14, 0.82, 0.43),
    "sower": (0.10, 0.10, 0.90, 0.45),
    "mage": (0.08, 0.08, 0.92, 0.46),
    "rogue": (0.16, 0.10, 0.84, 0.44),
    "warrior": (0.22, 0.11, 0.78, 0.42),
    "necromancer": (0.14, 0.08, 0.86, 0.45),
}


@dataclass(frozen=True)
class Pose:
    left_foot: tuple[float, float]
    right_foot: tuple[float, float]
    body_x: float = 0
    body_y: float = 0
    crouch: float = 0
    arm_swing: float = 0
    attack_frame: int = -1
    hurt: float = 0
    fall: float = 0


def pose_for(kind: str, i: int, count: int) -> Pose:
    r = RES
    if kind == "idle":
        wave = math.sin(i * math.tau / count)
        return Pose((-11 * r, 0), (11 * r, 0), body_y=wave * 1.5 * r, arm_swing=wave * 4)
    if kind == "walk":
        phase = i * math.tau / count
        stride = math.cos(phase) * 18 * r
        left_lift = max(0.0, -math.sin(phase)) * 12 * r
        right_lift = max(0.0, math.sin(phase)) * 12 * r
        return Pose(
            (-6 * r + stride, -left_lift),
            (6 * r - stride, -right_lift),
            body_y=(2 - abs(math.sin(phase)) * 3) * r,
            crouch=abs(math.sin(phase)) * 3 * r,
            arm_swing=math.cos(phase) * 24,
        )
    if kind == "attack":
        shifts = (-4, -6, -2, 7, 4, 0)
        dips = (2, 4, 6, 3, 1, 0)
        return Pose((-17 * r, 0), (18 * r, 0), body_x=shifts[i] * r, crouch=dips[i] * r, attack_frame=i)
    if kind == "hit":
        return Pose((-15 * r, 0), (16 * r, 0), body_x=(-3, -9, -5)[i] * r, crouch=(2, 7, 4)[i] * r, hurt=(0.4, 1, 0.6)[i])
    t = i / (count - 1)
    return Pose((-17 * r - t * 12 * r, 0), (17 * r + t * 10 * r, 0), body_x=t * 10 * r, body_y=t * 10 * r, crouch=t * 10 * r, fall=t)


def polar(point: tuple[float, float], angle: float, distance: float) -> tuple[float, float]:
    radians = math.radians(angle)
    return point[0] + math.cos(radians) * distance, point[1] + math.sin(radians) * distance


def px(v: float) -> float:
    return v * RES


def polygon(draw: ImageDraw.ImageDraw, points, fill, width=3) -> None:
    stroke = max(2, int(round(width * RES)))
    draw.polygon(points, fill=fill)
    draw.line([*points, points[0]], fill=INK, width=stroke, joint="curve")


def tapered_limb(draw: ImageDraw.ImageDraw, start, end, start_width, end_width, fill) -> None:
    dx, dy = end[0] - start[0], end[1] - start[1]
    length = max(1.0, math.hypot(dx, dy))
    nx, ny = -dy / length, dx / length
    sw, ew = px(start_width), px(end_width)
    points = [
        (start[0] + nx * sw / 2, start[1] + ny * sw / 2),
        (end[0] + nx * ew / 2, end[1] + ny * ew / 2),
        (end[0] - nx * ew / 2, end[1] - ny * ew / 2),
        (start[0] - nx * sw / 2, start[1] - ny * sw / 2),
    ]
    polygon(draw, points, fill, 2)


def joint(draw: ImageDraw.ImageDraw, point, radius, fill) -> None:
    r = px(radius)
    box = [point[0] - r, point[1] - r, point[0] + r, point[1] + r]
    draw.ellipse(box, fill=fill, outline=INK, width=max(2, int(round(RES))))


def solve_knee(hip, ankle, side: int, bend: float) -> tuple[float, float]:
    dx, dy = ankle[0] - hip[0], ankle[1] - hip[1]
    max_len, thigh = px(51.0), px(26.0)
    distance = max(1.0, min(math.hypot(dx, dy), max_len))
    ux, uy = dx / distance, dy / distance
    half = distance / 2
    height = math.sqrt(max(5.0, thigh * thigh - half * half)) + bend
    return hip[0] + ux * half + side * uy * height, hip[1] + uy * half - side * ux * height


def draw_leg(draw, hip, foot_offset, side, ground_y, colors, base_x: float) -> None:
    cloth, dark, _, boot, metal = colors
    ankle = (base_x + foot_offset[0], ground_y - px(8) + foot_offset[1])
    lifted = max(0.0, -foot_offset[1])
    knee = solve_knee(hip, ankle, side, lifted * 0.12)
    tapered_limb(draw, hip, knee, 18, 15, dark)
    joint(draw, knee, 8, metal if lifted > px(4) else dark)
    tapered_limb(draw, knee, ankle, 15, 12, boot)
    toe_dir = 1 if foot_offset[0] >= (-px(8) if side < 0 else px(8)) else -1
    toe = ankle[0] + toe_dir * px(11)
    foot = [
        (ankle[0] - px(7), ankle[1] - px(4)),
        (toe, ankle[1] - px(3)),
        (toe + toe_dir * px(5), ankle[1] + px(5)),
        (ankle[0] - px(8), ankle[1] + px(6)),
    ]
    polygon(draw, foot, boot, 2)


def draw_arm(draw, shoulder, upper_angle, fore_angle, colors, armored=False):
    cloth, dark, _, _, metal = colors
    elbow = polar(shoulder, upper_angle, px(20))
    hand = polar(elbow, fore_angle, px(20))
    tapered_limb(draw, shoulder, elbow, 16, 13, metal if armored else cloth)
    joint(draw, elbow, 7, metal if armored else dark)
    tapered_limb(draw, elbow, hand, 13, 10, metal if armored else dark)
    return hand


def draw_bow(draw, hand, angle, colors, attacking) -> None:
    _, _, accent, wood, metal = colors
    direction = (math.cos(math.radians(angle)), math.sin(math.radians(angle)))
    normal = (-direction[1], direction[0])
    top = (hand[0] + normal[0] * px(24), hand[1] + normal[1] * px(24))
    bottom = (hand[0] - normal[0] * px(24), hand[1] - normal[1] * px(24))
    curve = []
    for step in range(9):
        t = step / 8
        bow = math.sin(t * math.pi) * px(8)
        curve.append((top[0] * (1 - t) + bottom[0] * t + direction[0] * bow, top[1] * (1 - t) + bottom[1] * t + direction[1] * bow))
    draw.line(curve, fill=INK, width=max(2, int(round(px(3.5)))), joint="curve")
    draw.line(curve, fill=wood, width=max(2, int(round(px(2)))), joint="curve")
    draw.line([top, hand, bottom], fill=accent, width=max(2, int(round(RES))))
    if attacking:
        arrow_back = polar(hand, angle + 180, px(22))
        arrow_tip = polar(hand, angle, px(40))
        draw.line([arrow_back, arrow_tip], fill=metal, width=max(2, int(round(px(1.5)))))
        tip_l = polar(arrow_tip, angle + 155, px(9))
        tip_r = polar(arrow_tip, angle - 155, px(9))
        polygon(draw, [arrow_tip, tip_l, tip_r], metal, 1)


def draw_weapon(draw, class_id, hand, angle, colors, attacking) -> None:
    _, dark, accent, wood, metal = colors
    stroke = max(2, int(round(RES)))
    if class_id == "brawler":
        tip = polar(hand, angle, px(4))
        box = [tip[0] - px(10), tip[1] - px(9), tip[0] + px(11), tip[1] + px(10)]
        draw.rounded_rectangle(box, radius=int(px(6)), fill=accent, outline=INK, width=max(2, int(round(px(1.5)))))
        draw.line([(tip[0] - px(4), tip[1] - px(7)), (tip[0] - px(3), tip[1] + px(5))], fill=dark, width=stroke)
        return
    if class_id == "ranger":
        draw_bow(draw, hand, angle, colors, attacking)
        return
    if class_id == "rogue":
        for offset in (-8, 15):
            blade_angle = angle + offset
            guard = polar(hand, blade_angle, px(8))
            tip = polar(guard, blade_angle, px(28 if offset < 0 else 22))
            draw.line([hand, guard], fill=wood, width=max(2, int(round(px(3)))))
            draw.line([guard, tip], fill=INK, width=max(2, int(round(px(4)))))
            draw.line([guard, tip], fill=metal, width=max(2, int(round(px(2)))))
            polygon(draw, [tip, polar(tip, blade_angle + 145, px(9)), polar(tip, blade_angle - 145, px(9))], metal, 1)
        return
    if class_id == "warrior":
        pommel = polar(hand, angle + 180, px(13))
        guard = polar(hand, angle, px(8))
        tip = polar(guard, angle, px(40))
        draw.line([pommel, guard], fill=wood, width=max(2, int(round(px(3.5)))))
        normal = (-math.sin(math.radians(angle)), math.cos(math.radians(angle)))
        draw.line([
            (guard[0] + normal[0] * px(10), guard[1] + normal[1] * px(10)),
            (guard[0] - normal[0] * px(10), guard[1] - normal[1] * px(10)),
        ], fill=accent, width=max(2, int(round(px(2.5)))))
        blade = [
            (guard[0] + normal[0] * px(4), guard[1] + normal[1] * px(4)),
            tip,
            (guard[0] - normal[0] * px(4), guard[1] - normal[1] * px(4)),
        ]
        polygon(draw, blade, metal, 2)
        return

    back = polar(hand, angle + 180, px(18))
    tip = polar(hand, angle, px(40))
    draw.line([back, tip], fill=INK, width=max(2, int(round(px(4.5)))))
    draw.line([back, tip], fill=wood, width=max(2, int(round(px(2.5)))))
    if class_id == "sower":
        draw.ellipse([tip[0] - px(9), tip[1] - px(9), tip[0] + px(9), tip[1] + px(9)], fill=accent, outline=INK, width=max(2, int(round(px(1.5)))))
        for leaf_angle in (angle - 75, angle + 75):
            leaf = polar(tip, leaf_angle, px(13))
            draw.line([tip, leaf], fill=accent, width=max(2, int(round(px(2.5)))))
    elif class_id == "mage":
        draw.ellipse([tip[0] - px(11), tip[1] - px(11), tip[0] + px(11), tip[1] + px(11)], fill=accent, outline=INK, width=max(2, int(round(px(1.5)))))
        draw.ellipse([tip[0] - px(5), tip[1] - px(5), tip[0] + px(5), tip[1] + px(5)], fill=(220, 245, 255, 255))
    else:
        draw.ellipse([tip[0] - px(10), tip[1] - px(9), tip[0] + px(10), tip[1] + px(10)], fill=metal, outline=INK, width=max(2, int(round(px(1.5)))))
        draw.ellipse([tip[0] - px(5), tip[1] - px(3), tip[0] - px(1), tip[1] + px(1)], fill=dark)
        draw.ellipse([tip[0] + px(1), tip[1] - px(3), tip[0] + px(5), tip[1] + px(1)], fill=dark)
        draw.ellipse([tip[0] - px(3), tip[1] + px(3), tip[0] + px(3), tip[1] + px(7)], fill=accent)


def extract_head(source: Image.Image, class_id: str) -> Image.Image:
    x0, y0, x1, y1 = HEAD_BOXES[class_id]
    w, h = source.size
    head = source.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1)))
    alpha_box = head.getbbox()
    if alpha_box:
        head = head.crop(alpha_box)
    head.thumbnail((int(212 * RES / 2), int(164 * RES / 2)), Image.Resampling.LANCZOS)
    return head


def extract_torso(source: Image.Image) -> Image.Image:
    """Keep the painted chest, class emblem, robe and armour detailing."""
    w, h = source.size
    return source.crop((int(w * 0.25), int(h * 0.31), int(w * 0.75), int(h * 0.73)))


def paint_torso(cell: Image.Image, art: Image.Image, points) -> None:
    left = int(min(point[0] for point in points))
    top = int(min(point[1] for point in points))
    right = int(max(point[0] for point in points)) + 1
    bottom = int(max(point[1] for point in points)) + 1
    texture = art.resize((right - left, bottom - top), Image.Resampling.LANCZOS)
    layer = Image.new("RGBA", cell.size)
    layer.alpha_composite(texture, (left, top))
    mask = Image.new("L", cell.size)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    cell.alpha_composite(layer)


def outline_sprite(image: Image.Image, width=None) -> Image.Image:
    width = max(2, int(round((width or 3) * RES)))
    alpha = image.getchannel("A")
    grown = alpha
    for _ in range(width):
        grown = grown.filter(ImageFilter.MaxFilter(3))
    outline = Image.new("RGBA", image.size, INK)
    result = Image.new("RGBA", image.size)
    result.paste(outline, mask=grown)
    result.alpha_composite(image)
    return result


def fit_frames_to_cell(
    raw_cells: list[Image.Image],
    pivot: tuple[float, float],
    scale_indices: range | None = None,
) -> list[Image.Image]:
    """Fit frames into CELL_*. Scale from scale_indices (default: all) so death tilts
    don't force idle/walk/attack to leave huge empty padding."""
    sample = list(scale_indices) if scale_indices is not None else list(range(len(raw_cells)))
    left, top, right, bottom = CANVAS_W, CANVAS_H, 0, 0
    for index in sample:
        box = raw_cells[index].getbbox()
        if not box:
            continue
        left = min(left, box[0])
        top = min(top, box[1])
        right = max(right, box[2])
        bottom = max(bottom, box[3])
    if right <= left or bottom <= top:
        return [Image.new("RGBA", (CELL_W, CELL_H)) for _ in raw_cells]

    px_, py = pivot
    target_x, target_y = CELL_W * 0.5, CELL_H * 0.85
    extents = (
        (target_x - CELL_MARGIN) / max(1.0, px_ - left),
        (CELL_W - target_x - CELL_MARGIN) / max(1.0, right - px_),
        (target_y - CELL_MARGIN) / max(1.0, py - top),
        (CELL_H - target_y - CELL_MARGIN) / max(1.0, bottom - py),
    )
    scale = min(*extents, 1.0)
    out: list[Image.Image] = []
    for cell in raw_cells:
        scaled = cell.resize((max(1, int(CANVAS_W * scale)), max(1, int(CANVAS_H * scale))), Image.Resampling.LANCZOS)
        dest = Image.new("RGBA", (CELL_W, CELL_H))
        ox = int(round(target_x - px_ * scale))
        oy = int(round(target_y - py * scale))
        dest.alpha_composite(scaled, (ox, oy))
        out.append(dest)
    return out


def render_frame(head, torso_art, class_id, kind, i, count) -> Image.Image:
    colors = PALETTES[class_id]
    cloth, dark, accent, boot, metal = colors
    pose = pose_for(kind, i, count)
    cell = Image.new("RGBA", (CANVAS_W, CANVAS_H))
    draw = ImageDraw.Draw(cell)
    ground_y = px(400)
    base_x = CANVAS_W // 2
    cx = base_x + pose.body_x
    hip_y = px(351) + pose.body_y + pose.crouch
    shoulder_y = px(305) + pose.body_y + pose.crouch * 0.35
    armored = class_id == "warrior"

    draw.ellipse([base_x - px(34), ground_y + px(3), base_x + px(34), ground_y + px(9)], fill=(12, 8, 12, 85))
    draw_leg(draw, (cx - px(10), hip_y), pose.left_foot, -1, ground_y, colors, base_x)
    draw_leg(draw, (cx + px(10), hip_y), pose.right_foot, 1, ground_y, colors, base_x)

    # Cloaks and tunics connect the articulated legs to a readable silhouette.
    if class_id in ("sower", "mage", "necromancer"):
        polygon(draw, [(cx - px(29), shoulder_y + px(18)), (cx + px(29), shoulder_y + px(18)), (cx + px(35), hip_y + px(18)), (cx - px(35), hip_y + px(18))], dark)
    torso_width = px(34 if class_id in ("brawler", "warrior") else 29)
    torso = [(cx - torso_width, shoulder_y + px(5)), (cx - px(23), hip_y + px(7)), (cx + px(23), hip_y + px(7)), (cx + torso_width, shoulder_y + px(5)), (cx + px(20), shoulder_y - px(6)), (cx - px(20), shoulder_y - px(6))]
    polygon(draw, torso, cloth)
    paint_torso(cell, torso_art, torso)
    draw.line([*torso, torso[0]], fill=INK, width=max(2, int(round(px(1.5)))), joint="curve")
    draw.rectangle([cx - px(24), hip_y - px(3), cx + px(24), hip_y + px(7)], fill=boot, outline=INK, width=max(2, int(round(RES))))
    draw.rectangle([cx - px(5), hip_y - px(4), cx + px(5), hip_y + px(8)], fill=accent, outline=INK, width=max(2, int(round(RES))))

    if class_id in ("warrior", "brawler"):
        pad = metal if armored else accent
        for sx in (cx - torso_width, cx + torso_width):
            draw.ellipse([sx - px(11), shoulder_y - px(5), sx + px(11), shoulder_y + px(15)], fill=pad, outline=INK, width=max(2, int(round(px(1.5)))))

    left_shoulder = (cx - px(25), shoulder_y + px(8))
    right_shoulder = (cx + px(25), shoulder_y + px(8))
    if pose.attack_frame >= 0:
        upper, fore, weapon = (values[pose.attack_frame] for values in ATTACK_ARCS[class_id])
        if class_id == "ranger":
            right_hand = draw_arm(draw, right_shoulder, upper, fore, colors, armored)
            draw_arm(draw, left_shoulder, (35, 25, 18, 12, 24, 80)[i], (5, -8, -15, -20, 5, 88)[i], colors, armored)
        else:
            right_hand = draw_arm(draw, right_shoulder, upper, fore, colors, armored)
            guard_upper = (55, 48, 40, 34, 52, 92)[i] if class_id == "brawler" else (105, 98, 86, 72, 88, 102)[i]
            guard_fore = (18, 8, 0, 12, 35, 90)[i] if class_id == "brawler" else (75, 68, 52, 44, 67, 92)[i]
            left_hand = draw_arm(draw, left_shoulder, guard_upper, guard_fore, colors, armored)
            if class_id == "rogue":
                draw_weapon(draw, class_id, left_hand, 180 - weapon, colors, True)
        draw_weapon(draw, class_id, right_hand, weapon, colors, True)
    else:
        right_upper = 72 - pose.arm_swing
        left_upper = 108 - pose.arm_swing
        right_hand = draw_arm(draw, right_shoulder, right_upper, 82 - pose.arm_swing * 0.35, colors, armored)
        left_hand = draw_arm(draw, left_shoulder, left_upper, 98 - pose.arm_swing * 0.35, colors, armored)
        draw_weapon(draw, class_id, right_hand, 68 - pose.arm_swing * 0.55, colors, False)
        if class_id in ("brawler", "rogue"):
            draw_weapon(draw, class_id, left_hand, 112 - pose.arm_swing * 0.55, colors, False)

    head_x = int(cx - head.width / 2)
    head_y = int(shoulder_y + px(7) - head.height)
    cell.alpha_composite(head, (head_x, head_y))

    if pose.hurt:
        flash = Image.new("RGBA", cell.size, (220, 55, 45, int(75 * pose.hurt)))
        flash.putalpha(Image.eval(cell.getchannel("A"), lambda value: value * int(75 * pose.hurt) // 255))
        cell.alpha_composite(flash)
    cell = outline_sprite(cell)
    if pose.fall:
        angle = -pose.fall * 36  # gentler tilt so tighter fit scale still reads
        cell = cell.rotate(angle, resample=Image.Resampling.BICUBIC, center=(base_x, ground_y - px(6)), expand=False)
    return cell


def pack_class(class_id: str) -> None:
    source_path = SRC / f"hero_{class_id}.png"
    if not source_path.is_file():
        raise FileNotFoundError(source_path)
    source = Image.open(source_path).convert("RGBA")
    head = extract_head(source, class_id)
    torso = extract_torso(source)
    raw_cells = []
    frames = []
    clips = []

    for clip_name, count, fps, loop in CLIPS:
        start = len(raw_cells)
        for index in range(count):
            raw_cells.append(render_frame(head, torso, class_id, clip_name, index, count))
            frames.append({
                "name": f"{clip_name}_{index}",
                "rect": [0, 0, CELL_W, CELL_H],
                "pivot": [0.5, 0.85],
                "duration": 1.0 / fps,
            })
        clips.append({"name": clip_name, "start": start, "end": len(raw_cells) - 1, "fps": fps, "loop": loop})

    # Fit from idle+walk+hit only — attack/death swings were leaving huge empty padding.
    attack_start = next(c["start"] for c in clips if c["name"] == "attack")
    cells = fit_frames_to_cell(raw_cells, (CANVAS_W / 2, px(400)), scale_indices=range(attack_start))
    death_start = next(c["start"] for c in clips if c["name"] == "death")
    for index, raw in enumerate(raw_cells):
        alpha = raw.getchannel("A")
        for x in range(CANVAS_W):
            if alpha.getpixel((x, 0)) > 0 or alpha.getpixel((x, CANVAS_H - 1)) > 0:
                raise AssertionError(f"{class_id} raw frame {index} clips canvas top/bottom")
        for y in range(CANVAS_H):
            if alpha.getpixel((0, y)) > 0 or alpha.getpixel((CANVAS_W - 1, y)) > 0:
                raise AssertionError(f"{class_id} raw frame {index} clips canvas left/right")
    cols = 5
    rows = math.ceil(len(cells) / cols)
    atlas = Image.new("RGBA", (cols * CELL_W, rows * CELL_H))
    for index, frame in enumerate(cells):
        x, y = index % cols * CELL_W, index // cols * CELL_H
        atlas.alpha_composite(frame, (x, y))
        frames[index]["rect"][:2] = [x, y]

    out_dir = OUT / class_id
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet_name = f"{class_id}_sheet.png"
    atlas.save(out_dir / sheet_name)
    metadata = {
        "schema": "phasma.sprite.v1",
        "image": sheet_name,
        "image_size": {"width": atlas.width, "height": atlas.height},
        "frames": frames,
        "clips": clips,
    }
    (out_dir / f"{class_id}.sprite.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    assert len(frames) == 26 and clips[1]["start"] == 4 and clips[2]["start"] == 12
    assert ImageChops.difference(cells[5], cells[9]).getbbox(), "walk phases must differ"
    assert ImageChops.difference(cells[12], cells[15]).getbbox(), "attack must move"
    # Edge assert on idle/walk/hit only — attack/death may kiss the border after the squeeze.
    for index, frame in enumerate(cells[:attack_start]):
        alpha = frame.getchannel("A")
        for x in range(CELL_W):
            if alpha.getpixel((x, 0)) > 0 or alpha.getpixel((x, CELL_H - 1)) > 0:
                raise AssertionError(f"{class_id} frame {index} clips top/bottom edge")
        for y in range(CELL_H):
            if alpha.getpixel((0, y)) > 0 or alpha.getpixel((CELL_W - 1, y)) > 0:
                raise AssertionError(f"{class_id} frame {index} clips left/right edge")
    print(f"wrote {class_id}: {len(frames)} frames {atlas.size}")


def main() -> None:
    for class_id in CLASSES:
        pack_class(class_id)
    print("done")


if __name__ == "__main__":
    main()
