#!/usr/bin/env python
"""Generate articulated arena creep, boss, and minion sprite sheets."""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SPUD = ROOT / "Assets" / "Textures" / "modes" / "spud_fields"
ARENA = ROOT / "Assets" / "Textures" / "modes" / "arena"
OUT = ARENA / "creeps"

CELL_W, CELL_H = 328, 416
CANVAS_W, CANVAS_H = 1040, 1040
CELL_MARGIN = 6
RES = 2.0
INK = (24, 18, 23, 255)
CLIPS = (
    ("idle", 4, 7.0, True),
    ("walk", 8, 12.0, True),
    ("attack", 6, 14.0, False),
    ("hit", 3, 12.0, False),
    ("death", 5, 9.0, False),
)
BOSS_SKILLS = {
    "gourd_king": ("royal_furrows",),
    "wasp_queen": ("honey_dive", "honey_stuck"),
    "corn_colossus": ("kernel_mortar", "heatwave"),
    "briar_matriarch": ("thorn_leash", "leash_snap"),
    "bog_cantor": ("call", "response"),
    "millwright_spectre": ("grind_schedule",),
    "fox": ("vanish", "pounce"),
    "feast_warden": ("dinner_bell",),
    "weathervane_horror": ("gale_shift",),
    "pale_scarecrow": ("record_path", "reap_echo"),
    "wyrmroot_ascetic": ("rosary_gather", "rosary_volley", "rosary_break"),
    "corn_court_herald": ("royal_writ",),
    "king_of_ovrevand": ("tribute_medicine", "tribute_haste", "tribute_armor"),
}
ACTORS = (
    "sprout",
    "seed_spitter",
    "husk_knight",
    "pumpkin_brute",
    "crow",
    "beetle",
    "corn_mortar",
    "wasp",
    "gourd_king",
    "wasp_queen",
    "corn_colossus",
    "briar_matriarch",
    "bog_cantor",
    "millwright_spectre",
    "fox",
    "feast_warden",
    "weathervane_horror",
    "pale_scarecrow",
    "wyrmroot_ascetic",
    "corn_court_herald",
    "king_of_ovrevand",
    "skeleton",
    "imp",
)

# base, dark, light, accent, metal, leather
PALETTES = {
    "sprout": ((91, 139, 48, 255), (46, 72, 29, 255), (155, 190, 73, 255), (210, 164, 54, 255), (184, 174, 112, 255), (91, 57, 30, 255)),
    "seed_spitter": ((79, 91, 42, 255), (44, 49, 25, 255), (150, 137, 53, 255), (222, 170, 45, 255), (178, 123, 43, 255), (91, 58, 31, 255)),
    "husk_knight": ((190, 139, 45, 255), (89, 59, 28, 255), (238, 198, 82, 255), (222, 163, 47, 255), (168, 116, 42, 255), (100, 61, 32, 255)),
    "pumpkin_brute": ((185, 76, 26, 255), (80, 42, 27, 255), (235, 126, 38, 255), (106, 111, 48, 255), (112, 105, 96, 255), (79, 49, 32, 255)),
    "crow": ((46, 48, 55, 255), (19, 22, 28, 255), (84, 88, 96, 255), (117, 80, 134, 255), (92, 91, 100, 255), (55, 42, 38, 255)),
    "beetle": ((99, 51, 39, 255), (43, 28, 29, 255), (159, 82, 55, 255), (188, 126, 44, 255), (118, 84, 59, 255), (62, 39, 32, 255)),
    "corn_mortar": ((204, 157, 42, 255), (72, 64, 31, 255), (242, 204, 74, 255), (92, 136, 52, 255), (170, 128, 42, 255), (78, 55, 29, 255)),
    "wasp": ((223, 164, 33, 255), (35, 34, 38, 255), (252, 207, 69, 255), (219, 99, 30, 255), (125, 128, 139, 255), (68, 48, 31, 255)),
    "gourd_king": ((201, 80, 24, 255), (74, 35, 26, 255), (248, 142, 36, 255), (121, 53, 142, 255), (226, 175, 50, 255), (74, 45, 31, 255)),
    "wasp_queen": ((229, 170, 34, 255), (42, 30, 49, 255), (255, 218, 83, 255), (153, 54, 151, 255), (205, 178, 91, 255), (66, 43, 32, 255)),
    "corn_colossus": ((207, 155, 39, 255), (66, 55, 30, 255), (251, 209, 70, 255), (76, 126, 50, 255), (184, 139, 49, 255), (77, 51, 29, 255)),
    "briar_matriarch": ((137, 43, 70, 255), (59, 39, 30, 255), (202, 76, 108, 255), (83, 126, 52, 255), (221, 204, 156, 255), (79, 48, 38, 255)),
    "bog_cantor": ((100, 119, 57, 255), (27, 65, 65, 255), (222, 215, 157, 255), (190, 59, 138, 255), (164, 139, 75, 255), (73, 52, 34, 255)),
    "millwright_spectre": ((221, 218, 192, 255), (48, 58, 67, 255), (103, 217, 220, 255), (166, 77, 43, 255), (115, 119, 119, 255), (76, 57, 43, 255)),
    "fox": ((190, 74, 35, 255), (55, 36, 34, 255), (241, 202, 151, 255), (111, 133, 54, 255), (122, 113, 101, 255), (89, 52, 32, 255)),
    "feast_warden": ((122, 36, 57, 255), (54, 29, 31, 255), (215, 132, 45, 255), (229, 179, 55, 255), (129, 116, 106, 255), (83, 49, 34, 255)),
    "weathervane_horror": ((61, 128, 118, 255), (42, 50, 58, 255), (184, 101, 51, 255), (93, 198, 229, 255), (119, 122, 119, 255), (71, 46, 35, 255)),
    "pale_scarecrow": ((215, 207, 173, 255), (54, 46, 48, 255), (211, 163, 54, 255), (118, 221, 187, 255), (125, 126, 123, 255), (84, 57, 38, 255)),
    "wyrmroot_ascetic": ((105, 67, 43, 255), (45, 39, 31, 255), (83, 126, 61, 255), (166, 49, 45, 255), (220, 171, 55, 255), (75, 49, 35, 255)),
    "corn_court_herald": ((218, 165, 47, 255), (43, 35, 47, 255), (235, 219, 171, 255), (115, 62, 150, 255), (139, 130, 115, 255), (166, 47, 47, 255)),
    "king_of_ovrevand": ((61, 36, 67, 255), (27, 25, 31, 255), (220, 205, 166, 255), (151, 40, 55, 255), (221, 171, 52, 255), (105, 112, 115, 255)),
    "skeleton": ((207, 197, 158, 255), (35, 40, 64, 255), (242, 232, 197, 255), (83, 184, 235, 255), (109, 94, 155, 255), (62, 47, 40, 255)),
    "imp": ((208, 42, 31, 255), (68, 27, 29, 255), (249, 82, 45, 255), (247, 163, 34, 255), (82, 75, 79, 255), (52, 37, 36, 255)),
}

SOURCE_IDS = {
    "gourd_king": "pumpkin_brute",
    "wasp_queen": "wasp",
    "corn_colossus": "corn_mortar",
}
HEAD_BOXES = {
    "sprout": (0.08, 0.03, 0.92, 0.37),
    "seed_spitter": (0.08, 0.03, 0.92, 0.39),
    "husk_knight": (0.27, 0.01, 0.73, 0.38),
    "pumpkin_brute": (0.27, 0.02, 0.73, 0.44),
    "crow": (0.22, 0.02, 0.78, 0.38),
    "beetle": (0.29, 0.05, 0.71, 0.43),
    "corn_mortar": (0.23, 0.01, 0.77, 0.31),
    "wasp": (0.25, 0.01, 0.75, 0.32),
    "skeleton": (0.15, 0.02, 0.85, 0.37),
    "imp": (0.08, 0.00, 0.92, 0.39),
}
TORSO_BOXES = {
    "sprout": (0.20, 0.30, 0.80, 0.68),
    "seed_spitter": (0.17, 0.29, 0.83, 0.70),
    "pumpkin_brute": (0.24, 0.40, 0.76, 0.70),
    "crow": (0.14, 0.29, 0.86, 0.70),
    "corn_mortar": (0.17, 0.27, 0.83, 0.71),
    "skeleton": (0.15, 0.29, 0.85, 0.73),
    "imp": (0.18, 0.30, 0.82, 0.68),
}


@dataclass(frozen=True)
class Pose:
    left_foot: tuple[float, float]
    right_foot: tuple[float, float]
    body_x: float = 0.0
    body_y: float = 0.0
    crouch: float = 0.0
    arm_swing: float = 0.0
    attack_frame: int = -1
    hurt: float = 0.0
    fall: float = 0.0


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
        return Pose(
            (-17 * r, 0),
            (18 * r, 0),
            body_x=(-4, -6, -2, 7, 4, 0)[i] * r,
            crouch=(2, 4, 6, 3, 1, 0)[i] * r,
            attack_frame=i,
        )
    if kind == "hit":
        return Pose(
            (-15 * r, 0),
            (16 * r, 0),
            body_x=(-3, -9, -5)[i] * r,
            crouch=(2, 7, 4)[i] * r,
            hurt=(0.4, 1.0, 0.6)[i],
        )
    if kind == "death":
        t = i / (count - 1)
        return Pose(
            (-17 * r - t * 12 * r, 0),
            (17 * r + t * 10 * r, 0),
            body_x=t * 10 * r,
            body_y=t * 10 * r,
            crouch=t * 10 * r,
            fall=t,
        )
    motion = (0, -3, 5, 11, 5, 0)[i]
    crouch = (1, 5, 8, 3, 2, 0)[i]
    return Pose((-17 * r, 0), (18 * r, 0), body_x=motion * r, crouch=crouch * r, attack_frame=i)


def clips_for(actor_id: str):
    skills = BOSS_SKILLS.get(actor_id)
    if not skills:
        return CLIPS
    extras = (("phase2", 6, 12.0, False),) + tuple((name, 6, 12.0, False) for name in skills)
    return CLIPS + extras


def px(value: float) -> float:
    return value * RES


def polar(point: tuple[float, float], angle: float, distance: float) -> tuple[float, float]:
    radians = math.radians(angle)
    return point[0] + math.cos(radians) * distance, point[1] + math.sin(radians) * distance


def polygon(draw: ImageDraw.ImageDraw, points, fill, width=3) -> None:
    stroke = max(2, int(round(width * RES)))
    draw.polygon(points, fill=fill)
    draw.line([*points, points[0]], fill=INK, width=stroke, joint="curve")


def ellipse(draw: ImageDraw.ImageDraw, box, fill, width=2) -> None:
    draw.ellipse(box, fill=fill, outline=INK, width=max(2, int(round(width * RES))))


def rounded(draw: ImageDraw.ImageDraw, box, radius, fill, width=2) -> None:
    draw.rounded_rectangle(
        box,
        radius=max(1, int(round(px(radius)))),
        fill=fill,
        outline=INK,
        width=max(2, int(round(width * RES))),
    )


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
    draw.line(
        [(start[0] - nx * sw * 0.22, start[1] - ny * sw * 0.22), (end[0] - nx * ew * 0.22, end[1] - ny * ew * 0.22)],
        fill=(255, 255, 255, 42),
        width=max(1, int(RES)),
    )


def joint(draw: ImageDraw.ImageDraw, point, radius, fill) -> None:
    r = px(radius)
    ellipse(draw, [point[0] - r, point[1] - r, point[0] + r, point[1] + r], fill)


def draw_ground_shadow(draw: ImageDraw.ImageDraw, cx: float, ground: float, width: float) -> None:
    draw.ellipse(
        [cx - px(width), ground + px(4), cx + px(width), ground + px(12)],
        fill=(12, 8, 12, 90),
    )


def solve_knee(hip, ankle, side: int, bend: float) -> tuple[float, float]:
    dx, dy = ankle[0] - hip[0], ankle[1] - hip[1]
    distance = max(1.0, min(math.hypot(dx, dy), px(60)))
    ux, uy = dx / distance, dy / distance
    half = distance / 2
    height = math.sqrt(max(5.0, px(31) ** 2 - half * half)) + bend
    return hip[0] + ux * half + side * uy * height, hip[1] + uy * half - side * ux * height


def draw_leg(draw, hip, foot_offset, side, ground, upper, lower, boot, heavy=False) -> None:
    ankle = (CANVAS_W / 2 + foot_offset[0], ground - px(8) + foot_offset[1])
    knee = solve_knee(hip, ankle, side, max(0.0, -foot_offset[1]) * 0.12)
    scale = 1.25 if heavy else 1.0
    tapered_limb(draw, hip, knee, 19 * scale, 16 * scale, upper)
    joint(draw, knee, 8 * scale, lower)
    tapered_limb(draw, knee, ankle, 16 * scale, 12 * scale, lower)
    toe_dir = 1 if foot_offset[0] * side >= 0 else -1
    toe = ankle[0] + toe_dir * px(12 * scale)
    polygon(
        draw,
        [
            (ankle[0] - px(8 * scale), ankle[1] - px(5)),
            (toe, ankle[1] - px(4)),
            (toe + toe_dir * px(5), ankle[1] + px(5)),
            (ankle[0] - px(9 * scale), ankle[1] + px(7)),
        ],
        boot,
        2,
    )


def draw_arm(draw, shoulder, upper_angle, fore_angle, upper, lower, hand, heavy=False):
    scale = 1.3 if heavy else 1.0
    elbow = polar(shoulder, upper_angle, px(23 * scale))
    palm = polar(elbow, fore_angle, px(22 * scale))
    tapered_limb(draw, shoulder, elbow, 18 * scale, 14 * scale, upper)
    joint(draw, elbow, 7 * scale, lower)
    tapered_limb(draw, elbow, palm, 14 * scale, 10 * scale, lower)
    joint(draw, palm, 6 * scale, hand)
    return palm


def source_path(actor_id: str) -> Path:
    source_id = SOURCE_IDS.get(actor_id, actor_id)
    if source_id == "skeleton":
        return ARENA / "minion_skeleton.png"
    if source_id == "imp":
        return ARENA / "minion_imp.png"
    return SPUD / f"{source_id}.png"


@lru_cache(maxsize=None)
def source_part(actor_id: str, part: str) -> Image.Image:
    source_id = SOURCE_IDS.get(actor_id, actor_id)
    boxes = HEAD_BOXES if part == "head" else TORSO_BOXES
    source = Image.open(source_path(actor_id)).convert("RGBA")
    x0, y0, x1, y1 = boxes[source_id]
    w, h = source.size
    image = source.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1)))
    if box := image.getbbox():
        image = image.crop(box)
    return image


def paste_part(cell: Image.Image, actor_id: str, part: str, center, width: float, height: float | None = None) -> tuple[int, int, int, int]:
    image = source_part(actor_id, part).copy()
    target_w = max(1, int(px(width)))
    if height is None:
        target_h = max(1, int(image.height * target_w / image.width))
    else:
        target_h = max(1, int(px(height)))
    image = image.resize((target_w, target_h), Image.Resampling.LANCZOS)
    x, y = int(center[0] - target_w / 2), int(center[1] - target_h / 2)
    cell.alpha_composite(image, (x, y))
    return x, y, x + target_w, y + target_h


def paint_torso(cell: Image.Image, actor_id: str, points) -> None:
    if SOURCE_IDS.get(actor_id, actor_id) not in TORSO_BOXES:
        return
    art = source_part(actor_id, "torso")
    left, top = int(min(p[0] for p in points)), int(min(p[1] for p in points))
    right, bottom = int(max(p[0] for p in points)) + 1, int(max(p[1] for p in points)) + 1
    texture = art.resize((right - left, bottom - top), Image.Resampling.LANCZOS)
    layer = Image.new("RGBA", cell.size)
    layer.alpha_composite(texture, (left, top))
    mask = Image.new("L", cell.size)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    cell.alpha_composite(layer)


def draw_torso(cell, draw, actor_id, cx, shoulder_y, hip_y, width, base, dark, accent, skirt=False):
    if skirt:
        polygon(
            draw,
            [
                (cx - px(width + 5), shoulder_y + px(14)),
                (cx + px(width + 5), shoulder_y + px(14)),
                (cx + px(width + 10), hip_y + px(18)),
                (cx - px(width + 10), hip_y + px(18)),
            ],
            dark,
        )
    points = [
        (cx - px(width), shoulder_y),
        (cx - px(width - 6), hip_y + px(7)),
        (cx + px(width - 6), hip_y + px(7)),
        (cx + px(width), shoulder_y),
        (cx + px(width - 8), shoulder_y - px(8)),
        (cx - px(width - 8), shoulder_y - px(8)),
    ]
    polygon(draw, points, base)
    paint_torso(cell, actor_id, points)
    draw.line([*points, points[0]], fill=INK, width=max(2, int(px(2))), joint="curve")
    draw.line([(cx - px(width - 7), shoulder_y + px(3)), (cx - px(width - 11), hip_y - px(3))], fill=(255, 255, 255, 55), width=max(1, int(RES)))
    rounded(draw, [cx - px(width - 5), hip_y - px(3), cx + px(width - 5), hip_y + px(8)], 3, dark)
    rounded(draw, [cx - px(5), hip_y - px(4), cx + px(5), hip_y + px(9)], 2, accent)
    return points


def draw_pitchfork(draw, hand, angle, length, metal, wood, crown=False) -> None:
    back = polar(hand, angle + 180, px(15))
    tip = polar(hand, angle, px(length))
    draw.line([back, tip], fill=INK, width=max(3, int(px(5))))
    draw.line([back, tip], fill=wood, width=max(2, int(px(2.7))))
    normal = (-math.sin(math.radians(angle)), math.cos(math.radians(angle)))
    for offset in (-9, 0, 9):
        tine_base = (tip[0] + normal[0] * px(offset), tip[1] + normal[1] * px(offset))
        tine_tip = polar(tine_base, angle, px(18 if offset == 0 else 14))
        draw.line([tine_base, tine_tip], fill=INK, width=max(3, int(px(3.5))))
        draw.line([tine_base, tine_tip], fill=metal, width=max(2, int(px(1.8))))
    draw.line(
        [(tip[0] - normal[0] * px(9), tip[1] - normal[1] * px(9)), (tip[0] + normal[0] * px(9), tip[1] + normal[1] * px(9))],
        fill=metal,
        width=max(2, int(px(2.5))),
    )
    if crown:
        joint(draw, back, 7, metal)


def attack_swing(pose: Pose, start=105.0, end=-25.0) -> float:
    if pose.attack_frame < 0:
        return 74.0 - pose.arm_swing * 0.45
    t = pose.attack_frame / 5
    eased = 0.5 - 0.5 * math.cos(t * math.pi)
    return start + (end - start) * eased


def action_power(index: int) -> float:
    return (0.12, 0.45, 1.0, 0.78, 0.34, 0.0)[index]


def draw_burst(draw, center, radius, color, points=8) -> None:
    outer, inner = px(radius), px(radius * 0.48)
    polygon(
        draw,
        [
            polar(center, -90 + step * 180 / points, outer if step % 2 == 0 else inner)
            for step in range(points * 2)
        ],
        color,
        1,
    )


def draw_note(draw, center, scale, color, flipped=False) -> None:
    direction = -1 if flipped else 1
    ellipse(draw, [center[0] - px(5 * scale), center[1] - px(4 * scale), center[0] + px(5 * scale), center[1] + px(4 * scale)], color, 1)
    top = (center[0] + direction * px(4 * scale), center[1] - px(19 * scale))
    draw.line([(center[0] + direction * px(4 * scale), center[1]), top], fill=INK, width=max(2, int(px(3 * scale))))
    draw.line([top, (top[0] + direction * px(9 * scale), top[1] + px(4 * scale))], fill=color, width=max(2, int(px(3 * scale))))


def draw_sprout(cell, pose, kind, index, count):
    base, dark, light, accent, metal, leather = PALETTES["sprout"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    hip_y, shoulder_y = px(350) + pose.body_y + pose.crouch, px(303) + pose.body_y + pose.crouch * 0.35
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 43)
    draw_leg(draw, (cx - px(11), hip_y), pose.left_foot, -1, ground, base, dark, leather)
    draw_leg(draw, (cx + px(11), hip_y), pose.right_foot, 1, ground, base, dark, leather)
    draw_torso(cell, draw, "sprout", cx, shoulder_y, hip_y, 31, dark, leather, accent, skirt=True)
    for side in (-1, 1):
        shoulder = (cx + side * px(29), shoulder_y + px(6))
        leaf = [(shoulder[0], shoulder[1] - px(11)), (shoulder[0] + side * px(22), shoulder[1] - px(3)), (shoulder[0] + side * px(6), shoulder[1] + px(13))]
        polygon(draw, leaf, light)
    angle = attack_swing(pose, 125, 5)
    right = draw_arm(draw, (cx + px(29), shoulder_y + px(7)), angle, angle + 8, base, dark, base)
    draw_arm(draw, (cx - px(29), shoulder_y + px(7)), 108 - pose.arm_swing, 92, base, dark, base)
    draw_pitchfork(draw, right, angle - 8, 67, accent, leather)
    paste_part(cell, "sprout", "head", (cx, shoulder_y - px(25)), 112)


def draw_seed_spitter(cell, pose, kind, index, count):
    base, dark, light, accent, brass, leather = PALETTES["seed_spitter"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    hip_y, shoulder_y = px(351) + pose.body_y + pose.crouch, px(300) + pose.body_y + pose.crouch * 0.3
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 45)
    draw_leg(draw, (cx - px(12), hip_y), pose.left_foot, -1, ground, base, dark, leather)
    draw_leg(draw, (cx + px(12), hip_y), pose.right_foot, 1, ground, base, dark, leather)
    draw_torso(cell, draw, "seed_spitter", cx, shoulder_y, hip_y, 32, base, dark, accent, skirt=True)
    angle = attack_swing(pose, 98, -5)
    left = draw_arm(draw, (cx - px(29), shoulder_y + px(8)), 74 + pose.arm_swing * 0.25, 24, base, dark, leather)
    right = draw_arm(draw, (cx + px(29), shoulder_y + px(8)), 63 - pose.arm_swing * 0.25, 20, base, dark, leather)
    muzzle = polar((cx, shoulder_y + px(23)), angle, px(75))
    back = polar((cx, shoulder_y + px(23)), angle + 180, px(26))
    draw.line([back, muzzle], fill=INK, width=max(8, int(px(13))))
    draw.line([back, muzzle], fill=brass, width=max(5, int(px(8))))
    draw.line([back, muzzle], fill=(245, 202, 78, 255), width=max(2, int(px(2))))
    for hand in (left, right):
        joint(draw, hand, 6, leather)
    ellipse(draw, [muzzle[0] - px(10), muzzle[1] - px(10), muzzle[0] + px(10), muzzle[1] + px(10)], dark)
    ellipse(draw, [muzzle[0] - px(5), muzzle[1] - px(5), muzzle[0] + px(5), muzzle[1] + px(5)], INK, 1)
    if pose.attack_frame in (2, 3):
        for spread in (-18, 0, 17):
            seed = polar(muzzle, angle + spread, px(19 + abs(spread) * 0.35))
            ellipse(draw, [seed[0] - px(4), seed[1] - px(3), seed[0] + px(4), seed[1] + px(3)], accent, 1)
    paste_part(cell, "seed_spitter", "head", (cx, shoulder_y - px(27)), 119)


def draw_husk_knight(cell, pose, kind, index, count):
    base, dark, light, accent, bronze, leather = PALETTES["husk_knight"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    hip_y, shoulder_y = px(353) + pose.body_y + pose.crouch, px(294) + pose.body_y + pose.crouch * 0.25
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 58)
    draw_leg(draw, (cx - px(16), hip_y), pose.left_foot, -1, ground, base, bronze, leather, heavy=True)
    draw_leg(draw, (cx + px(16), hip_y), pose.right_foot, 1, ground, base, bronze, leather, heavy=True)
    for side in (-1, 1):
        shoulder = cx + side * px(42)
        for layer in range(3):
            y = shoulder_y - px(7) + layer * px(9)
            polygon(draw, [(shoulder, y), (shoulder + side * px(31 - layer * 4), y + px(8)), (shoulder, y + px(19))], light if layer == 0 else base, 2)
    draw_torso(cell, draw, "husk_knight", cx, shoulder_y, hip_y, 42, base, dark, accent)
    angle = attack_swing(pose, 142, -18)
    hand = draw_arm(draw, (cx + px(37), shoulder_y + px(8)), angle, angle - 4, base, bronze, leather, heavy=True)
    draw_pitchfork(draw, hand, angle - 12, 76, bronze, leather)
    shield_x = cx - px(39)
    shield = [(shield_x - px(35), shoulder_y + px(6)), (shield_x + px(28), shoulder_y + px(2)), (shield_x + px(30), hip_y + px(24)), (shield_x, hip_y + px(42)), (shield_x - px(34), hip_y + px(23))]
    polygon(draw, shield, dark, 4)
    inset = [(x + (cx - x) * 0.13, y + (hip_y - y) * 0.08) for x, y in shield]
    polygon(draw, inset, light, 2)
    draw.line([(shield_x, shoulder_y + px(14)), (shield_x, hip_y + px(29))], fill=bronze, width=max(3, int(px(3))))
    for y in (shoulder_y + px(14), hip_y + px(22)):
        joint(draw, (shield_x, y), 4, accent)
    paste_part(cell, "husk_knight", "head", (cx, shoulder_y - px(22)), 96)


def draw_pumpkin_brute(cell, pose, kind, index, count):
    base, dark, light, accent, metal, leather = PALETTES["pumpkin_brute"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    hip_y, shoulder_y = px(355) + pose.body_y + pose.crouch, px(294) + pose.body_y + pose.crouch * 0.25
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 62)
    draw_leg(draw, (cx - px(18), hip_y), pose.left_foot, -1, ground, dark, metal, leather, heavy=True)
    draw_leg(draw, (cx + px(18), hip_y), pose.right_foot, 1, ground, dark, metal, leather, heavy=True)
    torso = [(cx - px(49), shoulder_y), (cx - px(39), hip_y + px(12)), (cx + px(39), hip_y + px(12)), (cx + px(49), shoulder_y), (cx + px(33), shoulder_y - px(13)), (cx - px(33), shoulder_y - px(13))]
    polygon(draw, torso, leather)
    paint_torso(cell, "pumpkin_brute", torso)
    draw.line([*torso, torso[0]], fill=INK, width=max(2, int(px(2))), joint="curve")
    rounded(draw, [cx - px(43), hip_y - px(5), cx + px(43), hip_y + px(10)], 4, dark)
    angle = attack_swing(pose, 120, -8)
    if pose.attack_frame >= 0:
        right_angles, left_angles = (angle, angle + 8), (180 - angle, 172 - angle)
    else:
        right_angles, left_angles = (67 - pose.arm_swing, 45), (113 - pose.arm_swing, 135)
    right = draw_arm(draw, (cx + px(43), shoulder_y + px(4)), *right_angles, base, dark, leather, heavy=True)
    left = draw_arm(draw, (cx - px(43), shoulder_y + px(4)), *left_angles, base, dark, leather, heavy=True)
    for palm in (right, left):
        rounded(draw, [palm[0] - px(13), palm[1] - px(11), palm[0] + px(13), palm[1] + px(12)], 6, leather, 3)
        draw.line([(palm[0] - px(8), palm[1]), (palm[0] + px(8), palm[1])], fill=metal, width=max(2, int(px(2))))
    for sx in (-1, 1):
        rounded(draw, [cx + sx * px(37) - px(17), shoulder_y - px(13), cx + sx * px(37) + px(17), shoulder_y + px(16)], 9, metal, 3)
        joint(draw, (cx + sx * px(37), shoulder_y), 4, light)
    paste_part(cell, "pumpkin_brute", "head", (cx, shoulder_y - px(28)), 112)


def draw_crow(cell, pose, kind, index, count):
    base, dark, light, accent, metal, leather = PALETTES["crow"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    bob = pose.body_y - px(17)
    shoulder_y, hip_y = px(292) + bob + pose.crouch * 0.15, px(348) + bob
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 43)
    flap = math.sin(index * math.tau / count) if kind in ("idle", "walk") else 0.0
    if pose.attack_frame >= 0:
        flap = math.sin((pose.attack_frame + 1) * math.pi / 6) * 1.3
    for side in (-1, 1):
        root = (cx + side * px(24), shoulder_y + px(5))
        tip = (cx + side * px(76), shoulder_y + px(10 - flap * 28))
        lower = (cx + side * px(43), hip_y + px(42))
        polygon(draw, [root, tip, lower], dark, 4)
        for feather in range(4):
            t = feather / 3
            start = (root[0] * (1 - t) + tip[0] * t, root[1] * (1 - t) + tip[1] * t)
            end = (cx + side * px(37 + feather * 10), hip_y + px(34 + feather * 5))
            tapered_limb(draw, start, end, 13, 4, base if feather % 2 else light)
    for side, foot in ((-1, pose.left_foot), (1, pose.right_foot)):
        ankle = (CANVAS_W / 2 + foot[0] * 0.5, ground - px(22) + foot[1] * 0.4)
        tapered_limb(draw, (cx + side * px(10), hip_y), ankle, 8, 4, leather)
        for toe_angle in (45, 75, 105):
            toe = polar(ankle, toe_angle if side > 0 else 180 - toe_angle, px(10))
            draw.line([ankle, toe], fill=metal, width=max(2, int(px(2))))
    draw_torso(cell, draw, "crow", cx, shoulder_y, hip_y, 28, base, dark, accent, skirt=True)
    paste_part(cell, "crow", "head", (cx, shoulder_y - px(28)), 103)


def draw_beetle(cell, pose, kind, index, count):
    base, dark, light, accent, metal, leather = PALETTES["beetle"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    cy = px(344) + pose.body_y + pose.crouch * 0.25
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 68)
    phase = index * math.tau / count if kind == "walk" else 0.0
    for side in (-1, 1):
        for leg in range(3):
            root = (cx + side * px(34), cy + px(-22 + leg * 20))
            stride = math.sin(phase + leg * 1.8) * px(9)
            knee = (cx + side * px(64), cy + px(-32 + leg * 25) + stride)
            foot = (cx + side * px(82), ground - px(8 + leg * 2) - stride * 0.3)
            tapered_limb(draw, root, knee, 11, 8, dark)
            tapered_limb(draw, knee, foot, 8, 4, metal)
    ellipse(draw, [cx - px(58), cy - px(60), cx + px(58), cy + px(54)], dark, 4)
    ellipse(draw, [cx - px(50), cy - px(54), cx + px(50), cy + px(45)], base, 3)
    draw.pieslice([cx - px(43), cy - px(47), cx + px(43), cy + px(39)], 195, 325, fill=light)
    draw.line([(cx, cy - px(49)), (cx, cy + px(41))], fill=INK, width=max(3, int(px(3))))
    for y in (-25, 0, 24):
        draw.arc([cx - px(46), cy + px(y - 18), cx + px(46), cy + px(y + 18)], 5, 175, fill=accent, width=max(2, int(px(2))))
    head_y = cy - px(47)
    paste_part(cell, "beetle", "head", (cx, head_y), 73)
    reach = px(24 + (pose.attack_frame if pose.attack_frame >= 0 else 0) * 7)
    for side in (-1, 1):
        start = (cx + side * px(20), cy - px(46))
        tip = (cx + side * px(15), cy - px(62) - reach)
        mid = (cx + side * px(38), cy - px(64) - reach * 0.45)
        polygon(draw, [start, mid, tip, (cx + side * px(6), cy - px(54))], metal, 2)


def draw_corn_mortar(cell, pose, kind, index, count):
    base, dark, light, green, brass, leather = PALETTES["corn_mortar"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    recoil = px(12 * math.sin((pose.attack_frame + 1) * math.pi / 6)) if pose.attack_frame >= 0 else 0
    hip_y, shoulder_y = px(353) + pose.body_y + pose.crouch, px(298) + pose.body_y + pose.crouch * 0.3 + recoil
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 52)
    draw_leg(draw, (cx - px(14), hip_y), pose.left_foot, -1, ground, green, dark, leather, heavy=True)
    draw_leg(draw, (cx + px(14), hip_y), pose.right_foot, 1, ground, green, dark, leather, heavy=True)
    draw_torso(cell, draw, "corn_mortar", cx, shoulder_y, hip_y, 37, base, green, brass, skirt=True)
    for side in (-1, 1):
        rack_x = cx + side * px(43)
        for row in range(3):
            y = shoulder_y + px(31 + row * 15)
            ellipse(draw, [rack_x - px(7), y - px(10), rack_x + px(7), y + px(9)], light, 1)
            draw.line([(rack_x - px(5), y), (rack_x + px(5), y)], fill=green, width=max(2, int(px(2))))
    left = draw_arm(draw, (cx - px(34), shoulder_y + px(8)), 45, 16, base, green, leather)
    right = draw_arm(draw, (cx + px(34), shoulder_y + px(8)), 135, 164, base, green, leather)
    tube_bottom, tube_top = (cx, hip_y + px(32) + recoil), (cx, shoulder_y - px(55) + recoil)
    draw.line([tube_bottom, tube_top], fill=INK, width=max(12, int(px(24))))
    draw.line([tube_bottom, tube_top], fill=brass, width=max(9, int(px(17))))
    draw.line([(tube_bottom[0] - px(5), tube_bottom[1]), (tube_top[0] - px(5), tube_top[1])], fill=light, width=max(2, int(px(2.5))))
    ellipse(draw, [tube_top[0] - px(18), tube_top[1] - px(9), tube_top[0] + px(18), tube_top[1] + px(9)], dark, 3)
    for hand in (left, right):
        joint(draw, hand, 6, leather)
    if pose.attack_frame in (2, 3):
        for angle in (220, 250, 290, 320):
            spark = polar(tube_top, angle, px(18 + abs(270 - angle) * 0.12))
            draw.line([tube_top, spark], fill=(255, 222, 91, 220), width=max(2, int(px(2))))
    paste_part(cell, "corn_mortar", "head", (cx, shoulder_y - px(29)), 88)


def draw_wasp(cell, pose, kind, index, count):
    base, dark, light, orange, metal, leather = PALETTES["wasp"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    bob = pose.body_y - px(19)
    cy = px(323) + bob + pose.crouch * 0.12
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 41)
    flap = math.sin(index * math.tau / count) if kind in ("idle", "walk") else 0.0
    if pose.attack_frame >= 0:
        flap = math.sin((pose.attack_frame + 1) * math.pi / 6)
    for side in (-1, 1):
        for upper in (-1, 1):
            root = (cx + side * px(17), cy - px(30))
            tip = (cx + side * px(72), cy + upper * px(31 + flap * 16))
            wing = [root, (tip[0], tip[1] - px(13)), (tip[0] + side * px(10), tip[1]), (tip[0], tip[1] + px(13))]
            polygon(draw, wing, (225, 232, 201, 180), 2)
            draw.line([root, tip], fill=(126, 111, 72, 180), width=max(1, int(RES)))
    ellipse(draw, [cx - px(30), cy - px(54), cx + px(30), cy + px(18)], dark, 3)
    for row in range(4):
        y0 = cy - px(44) + row * px(15)
        rounded(draw, [cx - px(27 - row * 2), y0, cx + px(27 - row * 2), y0 + px(13)], 6, base if row % 2 == 0 else dark, 1)
    abdomen = [(cx - px(18), cy + px(11)), (cx + px(18), cy + px(11)), (cx + px(11), cy + px(54)), (cx, cy + px(72)), (cx - px(11), cy + px(54))]
    polygon(draw, abdomen, base)
    for y in (cy + px(25), cy + px(43)):
        draw.line([(cx - px(14), y), (cx + px(14), y)], fill=dark, width=max(2, int(px(3))))
    attack = pose.attack_frame if pose.attack_frame >= 0 else 0
    for side in (-1, 1):
        root = (cx + side * px(19), cy - px(8))
        tip = (cx + side * px(40 + attack * 5), cy + px(22 - attack * 5))
        tapered_limb(draw, root, tip, 8, 4, dark)
        blade = polar(tip, -45 if side > 0 else 225, px(18))
        polygon(draw, [tip, blade, (tip[0] + side * px(5), tip[1] - px(3))], metal, 1)
    paste_part(cell, "wasp", "head", (cx, cy - px(59)), 82)


def draw_crown(draw, cx, y, width, gold, jewel):
    points = [
        (cx - px(width), y + px(22)),
        (cx - px(width * 0.8), y),
        (cx - px(width * 0.35), y + px(13)),
        (cx, y - px(9)),
        (cx + px(width * 0.35), y + px(13)),
        (cx + px(width * 0.8), y),
        (cx + px(width), y + px(22)),
    ]
    polygon(draw, points, gold, 3)
    rounded(draw, [cx - px(width), y + px(19), cx + px(width), y + px(30)], 3, gold, 2)
    joint(draw, (cx, y + px(22)), 4, jewel)


def draw_gourd_king(cell, pose, kind, index, count):
    base, dark, light, royal, gold, leather = PALETTES["gourd_king"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    hip_y, shoulder_y = px(356) + pose.body_y + pose.crouch, px(288) + pose.body_y + pose.crouch * 0.2
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 72)
    if kind == "phase2":
        power = action_power(index)
        draw.arc([cx - px(86 + 18 * power), shoulder_y - px(105), cx + px(86 + 18 * power), shoulder_y + px(80)], 195, 345, fill=gold, width=max(3, int(px(5))))
        for side in (-1, 1):
            polygon(draw, [(cx + side * px(50), shoulder_y - px(54)), (cx + side * px(78), shoulder_y - px(79 - 18 * power)), (cx + side * px(68), shoulder_y - px(42))], royal, 2)
    cape = [(cx - px(67), shoulder_y - px(4)), (cx + px(67), shoulder_y - px(4)), (cx + px(58), ground - px(10)), (cx, ground - px(28)), (cx - px(58), ground - px(10))]
    polygon(draw, cape, royal, 4)
    for side, foot in ((-1, pose.left_foot), (1, pose.right_foot)):
        draw_leg(draw, (cx + side * px(19), hip_y), foot, side, ground, dark, gold, leather, heavy=True)
    torso = [(cx - px(55), shoulder_y), (cx - px(43), hip_y + px(14)), (cx + px(43), hip_y + px(14)), (cx + px(55), shoulder_y), (cx + px(38), shoulder_y - px(14)), (cx - px(38), shoulder_y - px(14))]
    polygon(draw, torso, base)
    paint_torso(cell, "gourd_king", torso)
    draw.line([*torso, torso[0]], fill=INK, width=max(2, int(px(2))), joint="curve")
    rounded(draw, [cx - px(45), hip_y - px(7), cx + px(45), hip_y + px(11)], 4, gold)
    for side in (-1, 1):
        shoulder = (cx + side * px(51), shoulder_y + px(2))
        ellipse(draw, [shoulder[0] - px(22), shoulder[1] - px(18), shoulder[0] + px(22), shoulder[1] + px(20)], gold, 3)
        for spike_angle in (-95, -65, -35):
            tip = polar(shoulder, spike_angle if side > 0 else 180 - spike_angle, px(32))
            polygon(draw, [polar(shoulder, spike_angle - 10, px(13)), tip, polar(shoulder, spike_angle + 10, px(13))], light, 2)
    angle = (123, 102, 82, 4, 28, 74)[index] if kind == "royal_furrows" else attack_swing(pose, 135, -12)
    right = draw_arm(draw, (cx + px(50), shoulder_y + px(7)), angle, angle - 4, base, dark, leather, heavy=True)
    draw_arm(draw, (cx - px(50), shoulder_y + px(7)), 112 - pose.arm_swing, 96, base, dark, leather, heavy=True)
    draw_pitchfork(draw, right, angle - 10, 83, gold, leather, crown=True)
    head_box = paste_part(cell, "gourd_king", "head", (cx, shoulder_y - px(34)), 128)
    draw_crown(draw, cx, head_box[1] - px(7), 34, gold, royal)
    draw.line([(cx - px(34), shoulder_y + px(10)), (cx + px(26), hip_y + px(8))], fill=gold, width=max(4, int(px(5))))
    if kind == "royal_furrows":
        power = action_power(index)
        fork_tip = polar(right, angle - 10, px(101))
        if index < 3:
            draw.line([(fork_tip[0] - px(33), ground + px(1)), (fork_tip[0] + px(22), ground + px(1))], fill=leather, width=max(3, int(px(4))))
        else:
            for step in range(4):
                dirt = (cx - px(62 + step * 26), ground - px(2 + (step % 2) * 10) * power)
                ellipse(draw, [dirt[0] - px(8), dirt[1] - px(6), dirt[0] + px(8), dirt[1] + px(6)], leather, 1)
            draw.line([(cx - px(105), ground + px(3)), (cx + px(65), ground + px(3))], fill=dark, width=max(3, int(px(5))))
    elif kind == "phase2" and index in (2, 3):
        for ray in range(7):
            start = polar((cx, head_box[1]), -155 + ray * 17, px(44))
            end = polar((cx, head_box[1]), -155 + ray * 17, px(63))
            draw.line([start, end], fill=gold, width=max(2, int(px(3))))


def draw_wasp_queen(cell, pose, kind, index, count):
    base, dark, light, royal, gold, leather = PALETTES["wasp_queen"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    bob = pose.body_y - px(22)
    dive = (-4, -22, -42, 28, 13, 0)[index] if kind == "honey_dive" else 0
    struggle = math.sin(index * math.pi / 2) * 5 if kind == "honey_stuck" else 0
    cy = px(315 + dive) + bob + pose.crouch * 0.1
    cx += px(struggle)
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 52)
    flap = math.sin(index * math.tau / count) if kind in ("idle", "walk") else 0.0
    if pose.attack_frame >= 0:
        flap = math.sin((pose.attack_frame + 1) * math.pi / 6) * 1.2
    if kind == "honey_dive":
        flap = (-0.2, -0.8, -1.1, 1.1, 0.55, 0.0)[index]
    for side in (-1, 1):
        for wing_index, yoff in enumerate((-52, -8, 35)):
            root = (cx + side * px(17), cy - px(27) + wing_index * px(7))
            tip = (cx + side * px(92 - wing_index * 7), cy + px(yoff + flap * (19 if wing_index != 1 else -15)))
            wing = [root, (tip[0] - side * px(7), tip[1] - px(15)), (tip[0] + side * px(9), tip[1]), (tip[0] - side * px(7), tip[1] + px(15))]
            polygon(draw, wing, (239, 220, 188, 185), 2)
            draw.line([root, tip], fill=gold, width=max(1, int(px(1.5))))
            joint(draw, tip, 3, royal)
    ellipse(draw, [cx - px(37), cy - px(60), cx + px(37), cy + px(15)], dark, 3)
    for row in range(4):
        y = cy - px(50) + row * px(17)
        rounded(draw, [cx - px(34 - row * 3), y, cx + px(34 - row * 3), y + px(14)], 6, base if row % 2 == 0 else dark, 1)
    abdomen = [(cx - px(24), cy + px(7)), (cx + px(24), cy + px(7)), (cx + px(17), cy + px(63)), (cx, cy + px(96)), (cx - px(17), cy + px(63))]
    polygon(draw, abdomen, base, 3)
    for y in (cy + px(27), cy + px(48), cy + px(67)):
        draw.line([(cx - px(18), y), (cx + px(18), y)], fill=dark, width=max(3, int(px(3))))
    for side in (-1, 1):
        for leg in range(2):
            root = (cx + side * px(22), cy - px(5) + leg * px(23))
            tip = (cx + side * px(51 + leg * 8), cy + px(24 + leg * 26))
            tapered_limb(draw, root, tip, 8, 4, dark)
    head_box = paste_part(cell, "wasp_queen", "head", (cx, cy - px(65)), 92)
    draw_crown(draw, cx, head_box[1] - px(4), 25, gold, royal)
    if kind == "honey_stuck":
        power = action_power(index)
        for side in (-1, 1):
            anchor = (cx + side * px(94), ground - px(15))
            draw.line([(cx + side * px(22), cy + px(8)), anchor], fill=gold, width=max(2, int(px(3 + power * 3))))
            for knot in range(1, 4):
                t = knot / 4
                point = (cx * (1 - t) + anchor[0] * t, (cy + px(8)) * (1 - t) + anchor[1] * t)
                joint(draw, point, 3 + power * 2, light)
        if index >= 4:
            for side in (-1, 1):
                draw.line([(cx + side * px(34), cy), (cx + side * px(65), cy - px(24))], fill=light, width=max(2, int(px(2))))
    elif pose.attack_frame >= 0:
        stinger = (cx + px(62 + pose.attack_frame * 7), cy + px(17 - pose.attack_frame * 6))
        polygon(draw, [(cx + px(19), cy + px(20)), stinger, (cx + px(14), cy + px(31))], gold, 2)
    if kind == "honey_dive":
        power = action_power(index)
        for drop in range(3):
            dx = (drop - 1) * 17
            y = cy - px(55 + drop * 11) if index < 3 else ground - px(11 + drop * 7)
            ellipse(draw, [cx + px(dx - 5), y - px(7 * power), cx + px(dx + 5), y + px(7)], gold, 1)
        if index == 3:
            draw_burst(draw, (cx, ground - px(10)), 37, light, 7)
    elif kind == "phase2":
        power = action_power(index)
        for side in (-1, 1):
            draw.arc([cx + side * px(20) - px(70), cy - px(102), cx + side * px(20) + px(70), cy + px(38)], 200 if side < 0 else 110, 330 if side < 0 else 240, fill=royal, width=max(2, int(px(3 + 3 * power))))


def draw_corn_colossus(cell, pose, kind, index, count):
    base, dark, light, green, brass, leather = PALETTES["corn_colossus"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    recoil = px(15 * math.sin((pose.attack_frame + 1) * math.pi / 6)) if pose.attack_frame >= 0 else 0
    body_y = px(318) + pose.body_y + pose.crouch * 0.2 + recoil
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 75)
    if kind == "phase2":
        power = action_power(index)
        for ring in range(3):
            radius = px(61 + ring * 14 + power * 8)
            draw.arc([cx - radius, body_y - radius, cx + radius, body_y + radius], 205 + ring * 19, 335 + ring * 17, fill=green if ring % 2 else brass, width=max(2, int(px(3))))
    for side, foot in ((-1, pose.left_foot), (1, pose.right_foot)):
        hip = (cx + side * px(34), body_y + px(37))
        ankle = (CANVAS_W / 2 + foot[0] * 1.25, ground - px(8) + foot[1])
        knee = (cx + side * px(53), body_y + px(74) - max(0, -foot[1]) * 0.25)
        tapered_limb(draw, hip, knee, 25, 20, green)
        joint(draw, knee, 12, brass)
        tapered_limb(draw, knee, ankle, 20, 15, dark)
        rounded(draw, [ankle[0] - px(18), ankle[1] - px(9), ankle[0] + px(21), ankle[1] + px(9)], 5, leather, 3)
    rounded(draw, [cx - px(65), body_y - px(42), cx + px(65), body_y + px(55)], 18, dark, 4)
    rounded(draw, [cx - px(57), body_y - px(35), cx + px(57), body_y + px(47)], 15, base, 3)
    for side in (-1, 1):
        drum_x = cx + side * px(67)
        ellipse(draw, [drum_x - px(22), body_y - px(28), drum_x + px(22), body_y + px(30)], brass, 3)
        for y in (-16, 0, 16):
            draw.line([(drum_x - px(18), body_y + px(y)), (drum_x + px(18), body_y + px(y))], fill=light, width=max(2, int(px(2))))
        banner = [(drum_x, body_y - px(29)), (drum_x + side * px(31), body_y - px(76)), (drum_x + side * px(20), body_y - px(17))]
        polygon(draw, banner, green, 2)
    paste_part(cell, "corn_colossus", "head", (cx, body_y - px(41)), 82)
    for offset in (-25, 0, 25):
        tube_x = cx + px(offset)
        tube_bottom, tube_top = (tube_x, body_y + px(47)), (tube_x, body_y - px(91))
        draw.line([tube_bottom, tube_top], fill=INK, width=max(10, int(px(18))))
        draw.line([tube_bottom, tube_top], fill=brass if offset == 0 else dark, width=max(7, int(px(12))))
        draw.line([(tube_x - px(4), tube_bottom[1]), (tube_x - px(4), tube_top[1])], fill=light, width=max(2, int(px(2))))
        ellipse(draw, [tube_x - px(14), tube_top[1] - px(7), tube_x + px(14), tube_top[1] + px(7)], dark, 2)
    if kind == "kernel_mortar":
        power = action_power(index)
        for offset in (-25, 0, 25):
            top = (cx + px(offset), body_y - px(98))
            lid = polar(top, -115 if offset < 0 else -65, px(15 + 8 * power))
            draw.line([top, lid], fill=green, width=max(3, int(px(5))))
            if index in (2, 3):
                kernel = (top[0] + px(offset * 0.35), top[1] - px(25 + abs(offset) * 0.2))
                ellipse(draw, [kernel[0] - px(7), kernel[1] - px(11), kernel[0] + px(7), kernel[1] + px(11)], light, 2)
        if index >= 3:
            for puff in range(3):
                point = (cx + px((puff - 1) * 29), body_y - px(113 + puff * 7))
                ellipse(draw, [point[0] - px(9), point[1] - px(8), point[0] + px(9), point[1] + px(8)], (222, 215, 178, 190), 1)
    elif kind == "heatwave":
        power = action_power(index)
        for offset in (-25, 0, 25):
            tube_x, top_y = cx + px(offset), body_y - px(98)
            for wave in range(2):
                radius = px(17 + wave * 12 + power * 8)
                draw.arc([tube_x - radius, top_y - radius, tube_x + radius, top_y + radius], 205, 335, fill=(244, 106 + wave * 38, 35, 230), width=max(2, int(px(3))))
        if index in (2, 3):
            rounded(draw, [cx - px(49), body_y - px(21), cx + px(49), body_y + px(25)], 11, (225, 91, 31, 180), 2)
    elif pose.attack_frame in (2, 3):
        for offset in (-25, 0, 25):
            top = (cx + px(offset), body_y - px(98))
            polygon(draw, [top, (top[0] - px(10), top[1] - px(22)), (top[0], top[1] - px(15)), (top[0] + px(11), top[1] - px(23))], light, 1)
    if kind == "phase2" and index in (2, 3):
        for offset in (-25, 0, 25):
            top = (cx + px(offset), body_y - px(101))
            draw_burst(draw, top, 14, light, 6)


def draw_briar_matriarch(cell, pose, kind, index, count):
    rose, bark, bloom, vine, bone, leather = PALETTES["briar_matriarch"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    cy = px(316) + pose.body_y + pose.crouch * 0.3
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 59)
    for side in (-1, 1):
        root = (cx + side * px(17), cy + px(49))
        knee = (cx + side * px(35), ground - px(36))
        foot = (CANVAS_W / 2 + pose.left_foot[0] if side < 0 else CANVAS_W / 2 + pose.right_foot[0], ground)
        tapered_limb(draw, root, knee, 17, 10, bark)
        tapered_limb(draw, knee, foot, 10, 4, vine)
        polygon(draw, [foot, (foot[0] + side * px(25), foot[1] + px(3)), (foot[0] + side * px(9), foot[1] - px(8))], vine, 2)
    skirt = [(cx - px(54), cy - px(4)), (cx - px(42), cy + px(66)), (cx, cy + px(47)), (cx + px(42), cy + px(66)), (cx + px(54), cy - px(4))]
    polygon(draw, skirt, bark, 4)
    rounded(draw, [cx - px(38), cy - px(51), cx + px(38), cy + px(31)], 20, rose, 4)
    rounded(draw, [cx - px(13), cy - px(39), cx + px(13), cy + px(27)], 8, bloom, 2)
    for side in (-1, 1):
        shoulder = (cx + side * px(35), cy - px(35))
        if kind == "thorn_leash":
            tip = (cx + side * px(78 + 38 * power), cy - px(8 - 20 * power))
        elif kind == "leash_snap":
            tip = (cx + side * px(75 - 31 * power), cy + px(13 - 37 * power))
        else:
            angle = (74 if side > 0 else 106) + side * pose.arm_swing * 0.35
            if pose.attack_frame >= 0:
                angle += side * (-64 + index * 22)
            tip = polar(shoulder, angle, px(67))
        tapered_limb(draw, shoulder, tip, 15, 5, vine)
        for thorn in range(1, 4):
            t = thorn / 4
            point = (shoulder[0] * (1 - t) + tip[0] * t, shoulder[1] * (1 - t) + tip[1] * t)
            spike = (point[0] + side * px(8), point[1] - px(8 + thorn * 2))
            polygon(draw, [point, spike, (point[0] - side * px(3), point[1] - px(1))], bone, 1)
        if kind in ("thorn_leash", "leash_snap"):
            radius = px(14 + 30 * power)
            draw.arc([tip[0] - radius, tip[1] - radius, tip[0] + radius, tip[1] + radius], 25, 335, fill=vine, width=max(3, int(px(5))))
    for petal in range(7):
        angle = -90 + petal * 360 / 7
        root = (cx, cy - px(60))
        tip = polar(root, angle, px(25 + (8 * power if kind == "phase2" else 0)))
        polygon(draw, [root, polar(root, angle - 16, px(12)), tip, polar(root, angle + 16, px(12))], bloom if petal % 2 else rose, 2)
    ellipse(draw, [cx - px(17), cy - px(77), cx + px(17), cy - px(43)], bark, 2)
    joint(draw, (cx - px(6), cy - px(60)), 3, bone)
    joint(draw, (cx + px(6), cy - px(60)), 3, bone)
    if kind == "phase2":
        for side in (-1, 1):
            draw.arc([cx - px(96), cy - px(116), cx + px(96), cy + px(76)], 175 if side < 0 else 5, 285 if side < 0 else 115, fill=bloom, width=max(3, int(px(4 + power * 2))))


def draw_bog_cantor(cell, pose, kind, index, count):
    bog, teal, cream, song, brass, leather = PALETTES["bog_cantor"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    cy = px(326) + pose.body_y + pose.crouch * 0.25
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    inhale = power if kind in ("call", "response") else 0.0
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 61)
    for side, foot in ((-1, pose.left_foot), (1, pose.right_foot)):
        hip = (cx + side * px(39), cy + px(31))
        ankle = (CANVAS_W / 2 + foot[0], ground - px(2) + foot[1])
        tapered_limb(draw, hip, (cx + side * px(62), ground - px(23)), 24, 17, bog)
        tapered_limb(draw, (cx + side * px(62), ground - px(23)), ankle, 17, 10, teal)
        rounded(draw, [ankle[0] - px(19), ankle[1] - px(7), ankle[0] + px(20), ankle[1] + px(7)], 5, bog, 2)
    ellipse(draw, [cx - px(62 + 8 * inhale), cy - px(43), cx + px(62 + 8 * inhale), cy + px(55)], bog, 4)
    rounded(draw, [cx - px(45), cy + px(5), cx + px(45), cy + px(33 + 7 * inhale)], 13, cream, 2)
    mouth_h = px(8 + 18 * inhale)
    rounded(draw, [cx - px(31), cy - mouth_h * 0.25, cx + px(31), cy + mouth_h], 7, teal, 3)
    for side in (-1, 1):
        eye = (cx + side * px(35), cy - px(48))
        ellipse(draw, [eye[0] - px(17), eye[1] - px(16), eye[0] + px(17), eye[1] + px(16)], bog, 3)
        joint(draw, (eye[0] + side * px(3), eye[1] - px(2)), 5, cream)
        joint(draw, (eye[0] + side * px(4), eye[1] - px(2)), 2, teal)
    baton_angle = (128, 105, 72, 28, 57, 91)[index] if kind in ("call", "response") else attack_swing(pose, 120, 15)
    hand = draw_arm(draw, (cx + px(50), cy - px(10)), baton_angle, baton_angle - 8, bog, teal, cream, heavy=True)
    tip = polar(hand, baton_angle - 5, px(55))
    draw.line([hand, tip], fill=INK, width=max(4, int(px(5))))
    draw.line([hand, tip], fill=brass, width=max(2, int(px(2))))
    draw_arm(draw, (cx - px(50), cy - px(10)), 112 - pose.arm_swing, 88, bog, teal, cream, heavy=True)
    if kind in ("call", "response"):
        direction = 1 if kind == "call" else -1
        for note in range(3):
            center = (cx + direction * px(50 + note * 25), cy - px(27 + note * 20 + power * 9))
            draw_note(draw, center, 0.8 + note * 0.12, song if note % 2 == 0 else cream, flipped=direction < 0)
        if kind == "response" and index in (2, 3):
            for ring in range(2):
                radius = px(53 + ring * 18)
                draw.arc([cx - radius, cy - radius, cx + radius, cy + radius], 195, 345, fill=song, width=max(2, int(px(3))))
    if kind == "phase2":
        for reed in range(-3, 4):
            x = cx + px(reed * 17)
            top = cy - px(76 + abs(reed) * 5 + power * 13)
            draw.line([(x, cy - px(37)), (x, top)], fill=teal, width=max(3, int(px(4))))
            polygon(draw, [(x, top), (x + px(9), top + px(11)), (x, top + px(16))], song, 1)


def draw_millwright_spectre(cell, pose, kind, index, count):
    flour, iron, ghost, rust, metal, leather = PALETTES["millwright_spectre"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    cy = px(318) + pose.body_y + pose.crouch * 0.15
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 58)
    radius = px(65)
    ellipse(draw, [cx - radius, cy - radius, cx + radius, cy + radius], iron, 5)
    ellipse(draw, [cx - px(48), cy - px(48), cx + px(48), cy + px(48)], (30, 42, 47, 255), 3)
    spoke_offset = index * (25 if kind == "grind_schedule" else 8)
    for spoke in range(8):
        angle = spoke * 45 + spoke_offset
        draw.line([polar((cx, cy), angle, px(14)), polar((cx, cy), angle, px(47))], fill=metal, width=max(3, int(px(5))))
    ellipse(draw, [cx - px(16), cy - px(16), cx + px(16), cy + px(16)], rust, 3)
    hood = [(cx - px(38), cy - px(30)), (cx - px(28), cy - px(102)), (cx, cy - px(126)), (cx + px(28), cy - px(102)), (cx + px(38), cy - px(30))]
    polygon(draw, hood, flour, 4)
    ellipse(draw, [cx - px(23), cy - px(105), cx + px(23), cy - px(62)], iron, 2)
    joint(draw, (cx - px(8), cy - px(84)), 4, ghost)
    joint(draw, (cx + px(8), cy - px(84)), 4, ghost)
    for side in (-1, 1):
        shoulder = (cx + side * px(33), cy - px(72))
        hand = polar(shoulder, 65 if side > 0 else 115, px(58))
        tapered_limb(draw, shoulder, hand, 12, 4, ghost)
        joint(draw, hand, 5, flour)
    if kind == "grind_schedule":
        pendulum_x = cx + px((-43, -27, 0, 29, 44, 0)[index])
        pivot = (cx, cy - px(135))
        bob = (pendulum_x, cy - px(19))
        draw.line([pivot, bob], fill=metal, width=max(3, int(px(4))))
        ellipse(draw, [bob[0] - px(16), bob[1] - px(16), bob[0] + px(16), bob[1] + px(16)], rust, 3)
        if index == 3:
            draw_burst(draw, (cx + px(47), cy - px(20)), 24, ghost, 7)
    else:
        pendulum = polar((cx, cy - px(132)), 73 + pose.arm_swing, px(76))
        draw.line([(cx, cy - px(132)), pendulum], fill=metal, width=max(3, int(px(4))))
        joint(draw, pendulum, 11, rust)
    if kind == "phase2":
        for ring in range(3):
            r = px(77 + ring * 13 + power * 5)
            draw.arc([cx - r, cy - r, cx + r, cy + r], 202 + ring * 25, 338 + ring * 20, fill=ghost, width=max(2, int(px(3))))
    tail = [(cx - px(45), cy + px(48)), (cx - px(27), ground - px(10)), (cx, ground - px(29)), (cx + px(25), ground - px(10)), (cx + px(45), cy + px(48))]
    polygon(draw, tail, (103, 217, 220, 155), 2)


def draw_fox(cell, pose, kind, index, count):
    russet, dark, cream, leaf, metal, leather = PALETTES["fox"]
    draw = ImageDraw.Draw(cell)
    ground = px(400)
    leap = (0, -5, -24, -48, -17, 0)[index] if kind == "pounce" else 0
    cx = CANVAS_W / 2 + pose.body_x + (px((0, -6, 12, 37, 18, 0)[index]) if kind == "pounce" else 0)
    cy = px(337 + leap) + pose.body_y + pose.crouch * 0.15
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    draw_ground_shadow(draw, CANVAS_W / 2 + (px(20 * power) if kind == "pounce" else 0), ground, 67)
    hidden = kind == "vanish" and index in (2, 3)
    tail_root = (cx - px(54), cy - px(4))
    tail_tip = (cx - px(121 - 18 * power), cy - px(43 + 22 * power))
    if hidden:
        for trace in range(3):
            offset = px(trace * 15)
            draw.arc([tail_tip[0] - px(10) - offset, tail_tip[1] - px(24), tail_root[0] + offset, tail_root[1] + px(25)], 210, 352, fill=cream if trace == 0 else leaf, width=max(2, int(px(3))))
        joint(draw, (cx + px(53), cy - px(17)), 4, cream)
        joint(draw, (cx + px(65), cy - px(16)), 4, cream)
        for spark in range(5):
            point = (cx + px((spark - 2) * 27), cy + px((-1) ** spark * 22))
            polygon(draw, [point, (point[0] - px(7), point[1] + px(11)), (point[0] + px(7), point[1] + px(9))], leaf, 1)
        return
    tapered_limb(draw, tail_root, tail_tip, 39, 9, russet)
    joint(draw, tail_tip, 12, cream)
    body_w = 70 + (25 * power if kind == "pounce" else 0)
    rounded(draw, [cx - px(body_w), cy - px(35), cx + px(52), cy + px(29)], 27, russet, 4)
    rounded(draw, [cx - px(43), cy + px(2), cx + px(38), cy + px(27)], 12, cream, 2)
    for leg, xoff in enumerate((-43, -16, 24, 47)):
        trail = px(19 * power) if kind == "pounce" else 0
        gait = pose.left_foot if leg % 2 == 0 else pose.right_foot
        hip = (cx + px(xoff), cy + px(20))
        paw = (
            cx + px(xoff + (-10 if leg < 2 else 9)) + gait[0] * 0.35 - trail,
            ground - px(4 if leap == 0 else 17 + leg * 3) + gait[1],
        )
        tapered_limb(draw, hip, paw, 13, 7, dark if leg % 2 else russet)
        rounded(draw, [paw[0] - px(11), paw[1] - px(5), paw[0] + px(13), paw[1] + px(5)], 4, dark, 2)
    head_x = cx + px(61 + (29 * power if kind == "pounce" else 0))
    head_y = cy - px(18)
    ellipse(draw, [head_x - px(31), head_y - px(29), head_x + px(31), head_y + px(28)], russet, 4)
    for side in (-1, 1):
        ear = [(head_x + side * px(18), head_y - px(19)), (head_x + side * px(30), head_y - px(50)), (head_x + side * px(4), head_y - px(31))]
        polygon(draw, ear, dark, 2)
    muzzle = (head_x + px(28), head_y + px(8))
    ellipse(draw, [muzzle[0] - px(13), muzzle[1] - px(10), muzzle[0] + px(20), muzzle[1] + px(11)], cream, 2)
    joint(draw, (muzzle[0] + px(17), muzzle[1] - px(1)), 4, dark)
    joint(draw, (head_x + px(10), head_y - px(9)), 3, cream)
    if kind == "pounce" and index == 4:
        draw_burst(draw, (head_x + px(37), ground - px(15)), 28, leaf, 7)
    if kind == "phase2":
        for echo in range(3):
            ex = tail_tip[0] - px(14 + echo * 15)
            draw.arc([ex - px(31), tail_tip[1] - px(28 - echo * 4), ex + px(35), tail_tip[1] + px(31 + echo * 4)], 200, 345, fill=leaf if echo % 2 else cream, width=max(2, int(px(3 + power))))


def draw_feast_warden(cell, pose, kind, index, count):
    wine, dark, amber, gold, metal, leather = PALETTES["feast_warden"]
    parchment = (240, 221, 171, 255)
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    cy = px(323) + pose.body_y + pose.crouch * 0.2
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 73)
    for side, foot in ((-1, pose.left_foot), (1, pose.right_foot)):
        draw_leg(draw, (cx + side * px(30), cy + px(48)), foot, side, ground, wine, dark, leather, heavy=True)
    body = [(cx - px(42), cy - px(65)), (cx - px(72), cy - px(10)), (cx - px(62), cy + px(61)), (cx, cy + px(78)), (cx + px(62), cy + px(61)), (cx + px(72), cy - px(10)), (cx + px(42), cy - px(65))]
    polygon(draw, body, wine, 5)
    rounded(draw, [cx - px(48), cy - px(29), cx + px(48), cy + px(57)], 25, amber, 3)
    polygon(draw, [(cx - px(26), cy - px(56)), (cx + px(26), cy - px(56)), (cx + px(18), cy + px(5)), (cx, cy + px(24)), (cx - px(18), cy + px(5))], parchment, 2)
    rounded(draw, [cx - px(58), cy + px(39), cx + px(58), cy + px(56)], 5, gold, 3)
    for stud in (-36, -12, 12, 36):
        joint(draw, (cx + px(stud), cy + px(47)), 3, dark)
    ellipse(draw, [cx - px(34), cy - px(107), cx + px(34), cy - px(45)], wine, 4)
    rounded(draw, [cx - px(24), cy - px(88), cx + px(24), cy - px(61)], 9, dark, 2)
    joint(draw, (cx - px(9), cy - px(75)), 3, gold)
    joint(draw, (cx + px(9), cy - px(75)), 3, gold)
    bell_angle = (128, 103, 73, 28, 53, 88)[index] if kind == "dinner_bell" else attack_swing(pose, 121, 10)
    bell_hand = draw_arm(draw, (cx + px(56), cy - px(39)), bell_angle, bell_angle - 8, wine, dark, parchment, heavy=True)
    bell = polar(bell_hand, bell_angle - 4, px(20))
    polygon(draw, [(bell[0] - px(17), bell[1] - px(11)), (bell[0] + px(17), bell[1] - px(11)), (bell[0] + px(25), bell[1] + px(17)), (bell[0] - px(25), bell[1] + px(17))], gold, 3)
    joint(draw, (bell[0], bell[1] + px(20)), 5, dark)
    purse_hand = draw_arm(draw, (cx - px(56), cy - px(39)), 116 - pose.arm_swing, 93, wine, dark, parchment, heavy=True)
    rounded(draw, [purse_hand[0] - px(22), purse_hand[1] - px(2), purse_hand[0] + px(22), purse_hand[1] + px(31)], 10, leather, 3)
    if kind == "dinner_bell":
        for ring in range(3):
            radius = px(28 + ring * 17 + power * 9)
            draw.arc([bell[0] - radius, bell[1] - radius, bell[0] + radius, bell[1] + radius], 205, 337, fill=gold if ring % 2 == 0 else amber, width=max(2, int(px(3))))
        for crumb in range(4):
            start = (cx + px((crumb - 1.5) * 42), cy + px(79 + (crumb % 2) * 10))
            end = (cx + px((crumb - 1.5) * 15), cy + px(34))
            point = (start[0] * (1 - power) + end[0] * power, start[1] * (1 - power) + end[1] * power)
            joint(draw, point, 4, amber)
    if kind == "phase2":
        for plate in range(5):
            angle = -160 + plate * 80 + index * 12
            point = polar((cx, cy), angle, px(88 + power * 8))
            ellipse(draw, [point[0] - px(12), point[1] - px(5), point[0] + px(12), point[1] + px(5)], parchment, 2)


def draw_weathervane_horror(cell, pose, kind, index, count):
    verdigris, storm, copper, lightning, metal, leather = PALETTES["weathervane_horror"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    cy = px(305) + pose.body_y + pose.crouch * 0.1
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    angle = (-35, -10, 20, 90, 55, 0)[index] if kind == "gale_shift" else (pose.arm_swing * 0.5)
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 51)
    polygon(draw, [(cx - px(32), ground), (cx - px(13), cy + px(44)), (cx + px(13), cy + px(44)), (cx + px(32), ground)], storm, 4)
    draw.line([(cx, ground - px(5)), (cx, cy - px(100))], fill=INK, width=max(9, int(px(12))))
    draw.line([(cx, ground - px(5)), (cx, cy - px(100))], fill=metal, width=max(5, int(px(7))))
    pivot = (cx, cy - px(33))
    joint(draw, pivot, 17, copper)
    for spoke in range(4):
        spoke_angle = angle + spoke * 90
        inner = polar(pivot, spoke_angle, px(13))
        tip = polar(pivot, spoke_angle, px(89))
        draw.line([inner, tip], fill=INK, width=max(7, int(px(9))))
        draw.line([inner, tip], fill=verdigris, width=max(3, int(px(5))))
        blade_left = polar(tip, spoke_angle + 151, px(27))
        blade_right = polar(tip, spoke_angle - 151, px(27))
        polygon(draw, [tip, blade_left, blade_right], copper if spoke % 2 else verdigris, 2)
        ribbon_tip = (tip[0] - px(31 + 25 * power), tip[1] + px(15 + spoke * 3))
        draw.line([tip, ribbon_tip], fill=lightning if kind == "gale_shift" else leather, width=max(2, int(px(3))))
    rooster_y = cy - px(112)
    body = [(cx - px(36), rooster_y), (cx - px(8), rooster_y - px(25)), (cx + px(34), rooster_y - px(16)), (cx + px(49), rooster_y), (cx + px(22), rooster_y + px(16)), (cx - px(22), rooster_y + px(18))]
    polygon(draw, body, verdigris, 4)
    ellipse(draw, [cx + px(20), rooster_y - px(43), cx + px(55), rooster_y - px(9)], copper, 3)
    polygon(draw, [(cx + px(52), rooster_y - px(31)), (cx + px(75), rooster_y - px(23)), (cx + px(52), rooster_y - px(14))], lightning, 2)
    for feather in range(3):
        polygon(draw, [(cx - px(28), rooster_y - px(4)), (cx - px(65 + feather * 11), rooster_y - px(35 - feather * 19)), (cx - px(47), rooster_y + px(10))], storm if feather % 2 else copper, 2)
    joint(draw, (cx + px(40), rooster_y - px(29)), 3, lightning)
    if kind == "gale_shift" and index in (2, 3, 4):
        for gust in range(3):
            y = cy + px(19 + gust * 24)
            draw.arc([cx - px(123), y - px(18), cx + px(119), y + px(18)], 198, 341, fill=lightning, width=max(2, int(px(3))))
    if kind == "phase2":
        for bolt in (-1, 1):
            start = (cx + bolt * px(24), cy - px(77))
            polygon(draw, [start, (start[0] + bolt * px(18), start[1] + px(25)), (start[0] + bolt * px(7), start[1] + px(25)), (start[0] + bolt * px(28), start[1] + px(52))], lightning, 2)


def draw_pale_scarecrow(cell, pose, kind, index, count):
    linen, dark, straw, ghost, metal, leather = PALETTES["pale_scarecrow"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    cy = px(302) + pose.body_y + pose.crouch * 0.2
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 54)
    for side, foot in ((-1, pose.left_foot), (1, pose.right_foot)):
        hip = (cx + side * px(15), cy + px(54))
        ankle = (CANVAS_W / 2 + foot[0] + side * px(7), ground - px(3) + foot[1])
        tapered_limb(draw, hip, ankle, 11 if side < 0 else 8, 4, straw)
        polygon(draw, [ankle, (ankle[0] + side * px(24), ankle[1] + px(5)), (ankle[0] - side * px(7), ankle[1] + px(6))], dark, 2)
    coat = [(cx - px(31), cy - px(58)), (cx - px(43), cy + px(65)), (cx - px(8), cy + px(46)), (cx + px(38), cy + px(72)), (cx + px(31), cy - px(58))]
    polygon(draw, coat, linen, 4)
    for seam in (-17, 12):
        draw.line([(cx + px(seam), cy - px(47)), (cx + px(seam + 8), cy + px(42))], fill=leather, width=max(2, int(px(2))))
    crossbar_y = cy - px(38)
    draw.line([(cx - px(91), crossbar_y), (cx + px(91), crossbar_y)], fill=INK, width=max(9, int(px(11))))
    draw.line([(cx - px(91), crossbar_y), (cx + px(91), crossbar_y)], fill=straw, width=max(5, int(px(6))))
    for side in (-1, 1):
        sleeve = [(cx + side * px(23), crossbar_y - px(18)), (cx + side * px(80), crossbar_y - px(13)), (cx + side * px(71), crossbar_y + px(19)), (cx + side * px(29), crossbar_y + px(17))]
        polygon(draw, sleeve, linen if side < 0 else dark, 3)
        if kind == "phase2":
            echo_y = crossbar_y - px(25 + 16 * power)
            draw.line([(cx + side * px(26), echo_y), (cx + side * px(111), echo_y - px(21))], fill=ghost, width=max(3, int(px(5))))
    head_y = cy - px(96)
    polygon(draw, [(cx - px(31), head_y - px(30)), (cx + px(26), head_y - px(34)), (cx + px(34), head_y + px(28)), (cx - px(26), head_y + px(33))], linen, 4)
    draw.line([(cx - px(20), head_y - px(12)), (cx + px(17), head_y + px(14))], fill=leather, width=max(2, int(px(2))))
    eye_open = power if kind == "record_path" else (0.8 if kind in ("reap_echo", "phase2") else 0.25)
    ellipse(draw, [cx - px(18), head_y - px(8 + 5 * eye_open), cx + px(18), head_y + px(8 + 5 * eye_open)], dark, 2)
    joint(draw, (cx, head_y), 4 + 3 * eye_open, ghost)
    scythe_angle = (131, 107, 64, -12, 23, 78)[index] if kind == "reap_echo" else attack_swing(pose, 132, -18)
    hand = (cx + px(72), crossbar_y + px(4))
    shaft_end = polar(hand, scythe_angle, px(104))
    draw.line([polar(hand, scythe_angle + 180, px(20)), shaft_end], fill=INK, width=max(5, int(px(7))))
    draw.line([polar(hand, scythe_angle + 180, px(20)), shaft_end], fill=leather, width=max(2, int(px(3))))
    blade_tip = polar(shaft_end, scythe_angle - 75, px(49))
    polygon(draw, [shaft_end, blade_tip, polar(shaft_end, scythe_angle - 54, px(22))], metal, 3)
    if kind == "record_path":
        for step in range(index + 1):
            foot = (cx - px(98) + px(step * 34), ground - px(8 + (step % 2) * 9))
            ellipse(draw, [foot[0] - px(8), foot[1] - px(4), foot[0] + px(8), foot[1] + px(4)], ghost, 1)
            joint(draw, (foot[0] + px(8), foot[1] - px(7)), 2, ghost)
    if kind == "reap_echo" and index in (2, 3, 4):
        offset = px(17 + (4 - index) * 8)
        echo_end = (shaft_end[0] - offset, shaft_end[1] - px(7))
        draw.line([(hand[0] - offset, hand[1]), echo_end], fill=ghost, width=max(2, int(px(4))))
        echo_tip = polar(echo_end, scythe_angle - 75, px(41))
        draw.line([echo_end, echo_tip], fill=ghost, width=max(2, int(px(3))))


def draw_wyrmroot_ascetic(cell, pose, kind, index, count):
    root, dark, moss, red, gold, leather = PALETTES["wyrmroot_ascetic"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    cy = px(315) + pose.body_y + pose.crouch * 0.1
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 55)
    halo_radius = 83 - (24 * power if kind == "rosary_gather" else 0)
    for bead in range(12):
        angle = -90 + bead * 30 + pose.arm_swing * 0.35
        radius = halo_radius
        if kind == "rosary_volley":
            radius += max(0, math.cos(math.radians(angle))) * 59 * power
        elif kind == "rosary_break":
            radius += (20 + (bead % 4) * 12) * power
            angle += (-1 if bead % 2 else 1) * 17 * power
        point = polar((cx, cy - px(12)), angle, px(radius))
        color = gold if kind == "phase2" and bead % 3 == 0 else (red if bead % 3 == 1 else root)
        joint(draw, point, 8 if bead % 3 == 0 else 6, color)
        if kind in ("rosary_gather", "rosary_volley"):
            draw.line([point, (cx, cy - px(10))], fill=gold if bead % 2 else moss, width=max(1, int(px(1.5))))
    for side in (-1, 1):
        root_tip = (cx + side * px(58), ground - px(2))
        tapered_limb(draw, (cx + side * px(22), cy + px(44)), root_tip, 15, 4, root)
        for branch in range(2):
            start = (root_tip[0] - side * px(17 + branch * 9), ground - px(5 + branch * 7))
            tip = (start[0] + side * px(34), start[1] - px(13 + branch * 9))
            draw.line([start, tip], fill=moss, width=max(2, int(px(3))))
    robe = [(cx - px(40), cy - px(29)), (cx - px(58), cy + px(49)), (cx, cy + px(67)), (cx + px(58), cy + px(49)), (cx + px(40), cy - px(29))]
    polygon(draw, robe, root, 4)
    polygon(draw, [(cx - px(34), cy - px(25)), (cx, cy + px(47)), (cx + px(34), cy - px(25)), (cx + px(20), cy - px(38)), (cx - px(20), cy - px(38))], red, 2)
    ellipse(draw, [cx - px(29), cy - px(85), cx + px(29), cy - px(28)], root, 4)
    draw.arc([cx - px(16), cy - px(66), cx + px(16), cy - px(38)], 15, 165, fill=gold, width=max(2, int(px(3))))
    joint(draw, (cx - px(8), cy - px(58)), 3, gold)
    joint(draw, (cx + px(8), cy - px(58)), 3, gold)
    for side in (-1, 1):
        hand = (cx + side * px(16 + 12 * power), cy + px(6 - 17 * power))
        tapered_limb(draw, (cx + side * px(31), cy - px(14)), hand, 11, 5, moss)
        joint(draw, hand, 6, root)
    if kind == "rosary_gather" and index in (2, 3):
        draw_burst(draw, (cx, cy - px(8)), 25, gold, 8)
    if kind == "rosary_volley" and index in (2, 3):
        for streak in range(3):
            y = cy - px(44) + streak * px(31)
            draw.line([(cx + px(71), y), (cx + px(124), y - px(11))], fill=gold, width=max(2, int(px(3))))
    if kind == "rosary_break":
        polygon(draw, [(cx - px(3), cy - px(102)), (cx + px(9), cy - px(46)), (cx - px(7), cy - px(5)), (cx + px(6), cy + px(54))], red, 2)


def draw_corn_court_herald(cell, pose, kind, index, count):
    corn, dark, parchment, violet, metal, seal = PALETTES["corn_court_herald"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    hip_y = px(354) + pose.body_y + pose.crouch
    shoulder_y = px(289) + pose.body_y + pose.crouch * 0.25
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 47)
    if kind == "phase2":
        for side in (-1, 1):
            banner = [(cx + side * px(20), shoulder_y - px(25)), (cx + side * px(104), shoulder_y - px(73 - 18 * power)), (cx + side * px(88), shoulder_y + px(28)), (cx + side * px(31), shoulder_y + px(12))]
            polygon(draw, banner, parchment if side < 0 else violet, 3)
    for side, foot in ((-1, pose.left_foot), (1, pose.right_foot)):
        draw_leg(draw, (cx + side * px(13), hip_y), foot, side, ground, corn, dark, dark)
    draw_torso(cell, draw, "corn_court_herald", cx, shoulder_y, hip_y, 29, violet, dark, seal, skirt=True)
    ellipse(draw, [cx - px(28), shoulder_y - px(74), cx + px(28), shoulder_y - px(20)], corn, 4)
    for plume in range(-2, 3):
        tip = (cx + px(plume * 10), shoulder_y - px(91 - abs(plume) * 8))
        polygon(draw, [(cx + px(plume * 7 - 7), shoulder_y - px(63)), tip, (cx + px(plume * 7 + 7), shoulder_y - px(62))], parchment if plume % 2 else corn, 2)
    joint(draw, (cx - px(8), shoulder_y - px(48)), 3, dark)
    joint(draw, (cx + px(8), shoulder_y - px(48)), 3, dark)
    spear_angle = (119, 98, 76, 22, 47, 83)[index] if kind == "royal_writ" else attack_swing(pose, 128, -8)
    hand = draw_arm(draw, (cx + px(28), shoulder_y + px(5)), spear_angle, spear_angle - 7, corn, dark, parchment)
    tip = polar(hand, spear_angle - 5, px(89))
    draw.line([polar(hand, spear_angle + 175, px(20)), tip], fill=INK, width=max(5, int(px(6))))
    draw.line([polar(hand, spear_angle + 175, px(20)), tip], fill=metal, width=max(2, int(px(2.5))))
    polygon(draw, [tip, polar(tip, spear_angle - 157, px(24)), polar(tip, spear_angle + 157, px(24))], parchment, 2)
    draw_arm(draw, (cx - px(28), shoulder_y + px(5)), 111 - pose.arm_swing, 92, corn, dark, parchment)
    scroll_w = 25 + (61 * power if kind == "royal_writ" else 0)
    scroll_y = hip_y + px(6)
    rounded(draw, [cx - px(scroll_w), scroll_y - px(25), cx + px(scroll_w), scroll_y + px(30)], 7, parchment, 3)
    draw.line([(cx - px(scroll_w - 10), scroll_y - px(11)), (cx + px(scroll_w - 10), scroll_y - px(11))], fill=dark, width=max(2, int(px(2))))
    draw.line([(cx - px(scroll_w - 10), scroll_y), (cx + px(scroll_w - 16), scroll_y)], fill=dark, width=max(2, int(px(2))))
    if kind == "royal_writ":
        for stamp in range(3):
            if index >= 1 + stamp:
                joint(draw, (cx + px((stamp - 1) * 25), scroll_y + px(18)), 7, seal)
        if index >= 4:
            for side in (-1, 1):
                tear = (cx + side * px(scroll_w), scroll_y + px(22))
                polygon(draw, [tear, (tear[0] + side * px(19), tear[1] + px(14)), (tear[0] + side * px(5), tear[1] + px(24))], parchment, 1)


def draw_king_of_ovrevand(cell, pose, kind, index, count):
    plum, dark, bone, crimson, gold, steel = PALETTES["king_of_ovrevand"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x + pose.arm_swing * 0.6
    cy = px(300) + pose.body_y + pose.crouch * 0.12
    power = action_power(index) if pose.attack_frame >= 0 else 0.0
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 76)
    if kind == "phase2":
        for ray in range(9):
            angle = -166 + ray * 19
            start = polar((cx, cy - px(76)), angle, px(72))
            end = polar((cx, cy - px(76)), angle, px(102 + 15 * power))
            draw.line([start, end], fill=gold if ray % 2 else crimson, width=max(2, int(px(3))))
    for leg, xoff in enumerate((-49, -23, 23, 49)):
        hip = (cx + px(xoff), cy + px(68))
        bend = (cx + px(xoff + (-16 if leg < 2 else 16)), ground - px(47 + (leg % 2) * 8))
        foot = (cx + px(xoff + (-23 if leg < 2 else 23)), ground - px(2))
        tapered_limb(draw, hip, bend, 18, 13, steel)
        joint(draw, bend, 8, gold)
        tapered_limb(draw, bend, foot, 13, 7, dark)
        rounded(draw, [foot[0] - px(14), foot[1] - px(6), foot[0] + px(16), foot[1] + px(6)], 4, steel, 2)
    throne = [(cx - px(67), cy - px(117)), (cx - px(52), cy + px(73)), (cx + px(52), cy + px(73)), (cx + px(67), cy - px(117)), (cx + px(40), cy - px(144)), (cx, cy - px(127)), (cx - px(40), cy - px(144))]
    polygon(draw, throne, dark, 5)
    rounded(draw, [cx - px(51), cy - px(93), cx + px(51), cy + px(57)], 16, plum, 4)
    for side in (-1, 1):
        post_x = cx + side * px(62)
        draw.line([(post_x, cy + px(63)), (post_x, cy - px(135))], fill=gold, width=max(5, int(px(7))))
        draw_crown(draw, post_x, cy - px(148), 12, gold, crimson)
    rounded(draw, [cx - px(40), cy + px(37), cx + px(40), cy + px(70)], 8, steel, 3)
    ruler_y = cy - px(30)
    polygon(draw, [(cx - px(25), ruler_y - px(12)), (cx - px(35), ruler_y + px(56)), (cx + px(35), ruler_y + px(56)), (cx + px(25), ruler_y - px(12))], crimson, 3)
    ellipse(draw, [cx - px(24), ruler_y - px(61), cx + px(24), ruler_y - px(15)], bone, 3)
    joint(draw, (cx - px(8), ruler_y - px(42)), 3, dark)
    joint(draw, (cx + px(8), ruler_y - px(42)), 3, dark)
    draw_crown(draw, cx, ruler_y - px(74), 25, gold, crimson)
    for side in (-1, 1):
        shoulder = (cx + side * px(22), ruler_y)
        hand = (cx + side * px(37 + 16 * power), ruler_y + px(26 - 24 * power))
        tapered_limb(draw, shoulder, hand, 9, 4, bone)
        joint(draw, hand, 5, bone)
    if kind == "tribute_medicine":
        chalice = (cx + px(52 + 14 * power), ruler_y + px(9 - 42 * power))
        polygon(draw, [(chalice[0] - px(16), chalice[1] - px(13)), (chalice[0] + px(16), chalice[1] - px(13)), (chalice[0] + px(8), chalice[1] + px(8)), (chalice[0] - px(8), chalice[1] + px(8))], gold, 2)
        draw.line([(chalice[0], chalice[1] + px(8)), (chalice[0], chalice[1] + px(24))], fill=gold, width=max(2, int(px(3))))
        draw.line([(chalice[0] - px(10), chalice[1] + px(24)), (chalice[0] + px(10), chalice[1] + px(24))], fill=gold, width=max(2, int(px(3))))
        if index in (2, 3):
            draw.line([(chalice[0] - px(14), chalice[1] - px(35)), (chalice[0] + px(14), chalice[1] - px(35))], fill=(103, 217, 220, 255), width=max(3, int(px(5))))
            draw.line([(chalice[0], chalice[1] - px(49)), (chalice[0], chalice[1] - px(21))], fill=(103, 217, 220, 255), width=max(3, int(px(5))))
    elif kind == "tribute_haste":
        pole_x = cx - px(49)
        top_y = ruler_y - px(63)
        draw.line([(pole_x, ruler_y + px(41)), (pole_x, top_y)], fill=gold, width=max(3, int(px(4))))
        width = px(25 + 37 * power)
        polygon(draw, [(pole_x, top_y), (pole_x - width, top_y + px(12)), (pole_x - width * 0.77, top_y + px(47)), (pole_x, top_y + px(39))], crimson, 3)
        for streak in range(3):
            y = top_y + px(60 + streak * 14)
            draw.line([(cx - px(86), y), (cx - px(121 + 13 * power), y + px(4))], fill=gold, width=max(2, int(px(3))))
    elif kind == "tribute_armor":
        door_w = px(12 + 42 * power)
        left = [(cx - px(66), cy - px(83)), (cx - px(66), cy + px(42)), (cx - px(66) + door_w, cy + px(27)), (cx - px(66) + door_w, cy - px(68))]
        right = [(cx + px(66), cy - px(83)), (cx + px(66), cy + px(42)), (cx + px(66) - door_w, cy + px(27)), (cx + px(66) - door_w, cy - px(68))]
        polygon(draw, left, steel, 4)
        polygon(draw, right, steel, 4)
        joint(draw, (cx - px(37), cy - px(19)), 7, gold)
        joint(draw, (cx + px(37), cy - px(19)), 7, gold)
    else:
        hand = (cx + px(38), ruler_y + px(19))
        tip = polar(hand, attack_swing(pose, 116, -4), px(64))
        draw.line([hand, tip], fill=gold, width=max(3, int(px(4))))
        joint(draw, tip, 7, crimson)


def draw_skeleton(cell, pose, kind, index, count):
    bone, dark, light, soul, purple, leather = PALETTES["skeleton"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    hip_y, shoulder_y = px(352) + pose.body_y + pose.crouch, px(298) + pose.body_y + pose.crouch * 0.3
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 43)
    draw_leg(draw, (cx - px(10), hip_y), pose.left_foot, -1, ground, bone, light, dark)
    draw_leg(draw, (cx + px(10), hip_y), pose.right_foot, 1, ground, bone, light, dark)
    draw_torso(cell, draw, "skeleton", cx, shoulder_y, hip_y, 34, dark, purple, soul, skirt=True)
    for side in (-1, 1):
        for rib in range(3):
            y = shoulder_y + px(18 + rib * 9)
            draw.arc([cx - px(27), y - px(8), cx + px(27), y + px(10)], 7, 173, fill=bone, width=max(2, int(px(2))))
    angle = attack_swing(pose, 128, -16)
    hand = draw_arm(draw, (cx + px(30), shoulder_y + px(7)), angle, angle - 5, bone, light, bone)
    draw_arm(draw, (cx - px(30), shoulder_y + px(7)), 110 - pose.arm_swing, 94, bone, light, bone)
    draw_pitchfork(draw, hand, angle - 10, 72, soul, leather)
    paste_part(cell, "skeleton", "head", (cx, shoulder_y - px(30)), 102)
    if pose.attack_frame in (2, 3):
        orb = polar(hand, angle - 10, px(84))
        ellipse(draw, [orb[0] - px(9), orb[1] - px(9), orb[0] + px(9), orb[1] + px(9)], soul, 1)
        ellipse(draw, [orb[0] - px(4), orb[1] - px(4), orb[0] + px(4), orb[1] + px(4)], (220, 250, 255, 255), 1)


def draw_imp(cell, pose, kind, index, count):
    base, dark, light, fire, metal, leather = PALETTES["imp"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    hip_y, shoulder_y = px(354) + pose.body_y + pose.crouch, px(303) + pose.body_y + pose.crouch * 0.35
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 42)
    tail_phase = math.sin(index * math.tau / count) if kind in ("idle", "walk") else 0
    tail = [(cx + px(18), hip_y), (cx + px(49), hip_y + px(16)), (cx + px(60), hip_y - px(8 + tail_phase * 8))]
    draw.line(tail, fill=INK, width=max(6, int(px(7))), joint="curve")
    draw.line(tail, fill=base, width=max(3, int(px(4))), joint="curve")
    tip = tail[-1]
    polygon(draw, [tip, (tip[0] - px(11), tip[1] - px(5)), (tip[0] - px(6), tip[1] + px(9))], fire, 1)
    draw_leg(draw, (cx - px(10), hip_y), pose.left_foot, -1, ground, base, dark, leather)
    draw_leg(draw, (cx + px(10), hip_y), pose.right_foot, 1, ground, base, dark, leather)
    draw_torso(cell, draw, "imp", cx, shoulder_y, hip_y, 30, dark, leather, fire, skirt=True)
    angle = attack_swing(pose, 135, -20)
    hand = draw_arm(draw, (cx + px(28), shoulder_y + px(8)), angle, angle - 6, base, dark, base)
    draw_arm(draw, (cx - px(28), shoulder_y + px(8)), 110 - pose.arm_swing, 92, base, dark, base)
    draw_pitchfork(draw, hand, angle - 11, 74, metal, dark)
    paste_part(cell, "imp", "head", (cx, shoulder_y - px(31)), 112)
    if pose.attack_frame in (2, 3):
        flame = polar(hand, angle - 11, px(86))
        polygon(draw, [flame, (flame[0] - px(10), flame[1] + px(17)), (flame[0], flame[1] + px(11)), (flame[0] + px(10), flame[1] + px(17))], fire, 1)


DRAWERS = {
    "sprout": draw_sprout,
    "seed_spitter": draw_seed_spitter,
    "husk_knight": draw_husk_knight,
    "pumpkin_brute": draw_pumpkin_brute,
    "crow": draw_crow,
    "beetle": draw_beetle,
    "corn_mortar": draw_corn_mortar,
    "wasp": draw_wasp,
    "gourd_king": draw_gourd_king,
    "wasp_queen": draw_wasp_queen,
    "corn_colossus": draw_corn_colossus,
    "briar_matriarch": draw_briar_matriarch,
    "bog_cantor": draw_bog_cantor,
    "millwright_spectre": draw_millwright_spectre,
    "fox": draw_fox,
    "feast_warden": draw_feast_warden,
    "weathervane_horror": draw_weathervane_horror,
    "pale_scarecrow": draw_pale_scarecrow,
    "wyrmroot_ascetic": draw_wyrmroot_ascetic,
    "corn_court_herald": draw_corn_court_herald,
    "king_of_ovrevand": draw_king_of_ovrevand,
    "skeleton": draw_skeleton,
    "imp": draw_imp,
}


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


def fit_frames_to_cell(raw_cells: list[Image.Image], pivot: tuple[float, float], scale_indices: range | None = None) -> list[Image.Image]:
    sample = list(scale_indices) if scale_indices is not None else list(range(len(raw_cells)))
    left, top, right, bottom = CANVAS_W, CANVAS_H, 0, 0
    for index in sample:
        if box := raw_cells[index].getbbox():
            left, top = min(left, box[0]), min(top, box[1])
            right, bottom = max(right, box[2]), max(bottom, box[3])
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
    out = []
    for cell in raw_cells:
        frame_scale = scale
        if box := cell.getbbox():
            left, top, right, bottom = box
            frame_scale = min(
                frame_scale,
                (target_x - CELL_MARGIN) / max(1.0, px_ - left),
                (CELL_W - target_x - CELL_MARGIN) / max(1.0, right - px_),
                (target_y - CELL_MARGIN) / max(1.0, py - top),
                (CELL_H - target_y - CELL_MARGIN) / max(1.0, bottom - py),
            )
        scaled = cell.resize((max(1, int(CANVAS_W * frame_scale)), max(1, int(CANVAS_H * frame_scale))), Image.Resampling.LANCZOS)
        dest = Image.new("RGBA", (CELL_W, CELL_H))
        dest.alpha_composite(scaled, (int(round(target_x - px_ * frame_scale)), int(round(target_y - py * frame_scale))))
        out.append(dest)
    return out


def render_frame(actor_id: str, kind: str, index: int, count: int) -> Image.Image:
    pose = pose_for(kind, index, count)
    cell = Image.new("RGBA", (CANVAS_W, CANVAS_H))
    DRAWERS[actor_id](cell, pose, kind, index, count)
    if pose.hurt:
        flash = Image.new("RGBA", cell.size, (226, 54, 38, int(92 * pose.hurt)))
        flash.putalpha(Image.eval(cell.getchannel("A"), lambda value: value * int(92 * pose.hurt) // 255))
        cell.alpha_composite(flash)
    cell = outline_sprite(cell)
    if pose.fall:
        cell = cell.rotate(
            -pose.fall * 34,
            resample=Image.Resampling.BICUBIC,
            center=(CANVAS_W / 2, px(394)),
            expand=False,
        )
    return cell


def assert_no_clipping(actor_id: str, cells: list[Image.Image], stage: str) -> None:
    for index, cell in enumerate(cells):
        if box := cell.getchannel("A").getbbox():
            if box[0] == 0 or box[1] == 0 or box[2] == cell.width or box[3] == cell.height:
                raise AssertionError(f"{actor_id} {stage} frame {index} clips an edge")


def pack_actor(actor_id: str) -> None:
    raw_cells: list[Image.Image] = []
    frames, clips = [], []
    actor_clips = clips_for(actor_id)
    for clip_name, count, fps, loop in actor_clips:
        start = len(raw_cells)
        for index in range(count):
            raw_cells.append(render_frame(actor_id, clip_name, index, count))
            frames.append(
                {
                    "name": f"{clip_name}_{index}",
                    "rect": [0, 0, CELL_W, CELL_H],
                    "pivot": [0.5, 0.85],
                    "duration": 1.0 / fps,
                }
            )
        clips.append({"name": clip_name, "start": start, "end": len(raw_cells) - 1, "fps": fps, "loop": loop})

    assert_no_clipping(actor_id, raw_cells, "raw")
    attack_start = next(clip["start"] for clip in clips if clip["name"] == "attack")
    cells = fit_frames_to_cell(raw_cells, (CANVAS_W / 2, px(400)), scale_indices=range(attack_start))
    assert_no_clipping(actor_id, cells, "packed")
    atlas = Image.new("RGBA", (5 * CELL_W, math.ceil(len(cells) / 5) * CELL_H))
    for index, frame in enumerate(cells):
        x, y = index % 5 * CELL_W, index // 5 * CELL_H
        atlas.alpha_composite(frame, (x, y))
        frames[index]["rect"][:2] = [x, y]

    out_dir = OUT / actor_id
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet_name = f"{actor_id}_sheet.png"
    atlas.save(out_dir / sheet_name)
    metadata = {
        "schema": "phasma.sprite.v1",
        "image": sheet_name,
        "image_size": {"width": atlas.width, "height": atlas.height},
        "frames": frames,
        "clips": clips,
    }
    (out_dir / f"{actor_id}.sprite.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    assert len(frames) == sum(count for _, count, _, _ in actor_clips)
    assert clips[1]["start"] == 4 and clips[2]["start"] == 12
    assert ImageChops.difference(cells[5], cells[9]).getbbox(), f"{actor_id} walk phases must differ"
    assert ImageChops.difference(cells[12], cells[15]).getbbox(), f"{actor_id} attack frames must differ"
    if actor_id in BOSS_SKILLS:
        extras = clips[len(CLIPS) :]
        assert [clip["name"] for clip in extras] == ["phase2", *BOSS_SKILLS[actor_id]]
        assert all(not clip["loop"] for clip in extras)
        peaks = []
        for clip in extras:
            assert ImageChops.difference(cells[clip["start"]], cells[clip["start"] + 2]).getbbox(), f"{actor_id} {clip['name']} frames must differ"
            peaks.append((clip["name"], cells[clip["start"] + 2]))
        for left_index, (left_name, left_frame) in enumerate(peaks):
            for right_name, right_frame in peaks[left_index + 1 :]:
                assert ImageChops.difference(left_frame, right_frame).getbbox(), f"{actor_id} {left_name}/{right_name} must be unique"
    print(f"wrote {actor_id}: {len(frames)} frames {atlas.size}")


def main() -> None:
    for actor_id in ACTORS:
        pack_actor(actor_id)
    print("done")


if __name__ == "__main__":
    main()
