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
    t = i / (count - 1)
    return Pose(
        (-17 * r - t * 12 * r, 0),
        (17 * r + t * 10 * r, 0),
        body_x=t * 10 * r,
        body_y=t * 10 * r,
        crouch=t * 10 * r,
        fall=t,
    )


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
    angle = attack_swing(pose, 135, -12)
    right = draw_arm(draw, (cx + px(50), shoulder_y + px(7)), angle, angle - 4, base, dark, leather, heavy=True)
    draw_arm(draw, (cx - px(50), shoulder_y + px(7)), 112 - pose.arm_swing, 96, base, dark, leather, heavy=True)
    draw_pitchfork(draw, right, angle - 10, 83, gold, leather, crown=True)
    head_box = paste_part(cell, "gourd_king", "head", (cx, shoulder_y - px(34)), 128)
    draw_crown(draw, cx, head_box[1] - px(7), 34, gold, royal)
    draw.line([(cx - px(34), shoulder_y + px(10)), (cx + px(26), hip_y + px(8))], fill=gold, width=max(4, int(px(5))))


def draw_wasp_queen(cell, pose, kind, index, count):
    base, dark, light, royal, gold, leather = PALETTES["wasp_queen"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    bob = pose.body_y - px(22)
    cy = px(315) + bob + pose.crouch * 0.1
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 52)
    flap = math.sin(index * math.tau / count) if kind in ("idle", "walk") else 0.0
    if pose.attack_frame >= 0:
        flap = math.sin((pose.attack_frame + 1) * math.pi / 6) * 1.2
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
    if pose.attack_frame >= 0:
        stinger = (cx + px(62 + pose.attack_frame * 7), cy + px(17 - pose.attack_frame * 6))
        polygon(draw, [(cx + px(19), cy + px(20)), stinger, (cx + px(14), cy + px(31))], gold, 2)


def draw_corn_colossus(cell, pose, kind, index, count):
    base, dark, light, green, brass, leather = PALETTES["corn_colossus"]
    draw = ImageDraw.Draw(cell)
    ground, cx = px(400), CANVAS_W / 2 + pose.body_x
    recoil = px(15 * math.sin((pose.attack_frame + 1) * math.pi / 6)) if pose.attack_frame >= 0 else 0
    body_y = px(318) + pose.body_y + pose.crouch * 0.2 + recoil
    draw_ground_shadow(draw, CANVAS_W / 2, ground, 75)
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
    if pose.attack_frame in (2, 3):
        for offset in (-25, 0, 25):
            top = (cx + px(offset), body_y - px(98))
            polygon(draw, [top, (top[0] - px(10), top[1] - px(22)), (top[0], top[1] - px(15)), (top[0] + px(11), top[1] - px(23))], light, 1)


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
    for clip_name, count, fps, loop in CLIPS:
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

    assert len(frames) == 26 and clips[1]["start"] == 4 and clips[2]["start"] == 12
    assert ImageChops.difference(cells[5], cells[9]).getbbox(), f"{actor_id} walk phases must differ"
    assert ImageChops.difference(cells[12], cells[15]).getbbox(), f"{actor_id} attack frames must differ"
    print(f"wrote {actor_id}: {len(frames)} frames {atlas.size}")


def main() -> None:
    for actor_id in ACTORS:
        pack_actor(actor_id)
    print("done")


if __name__ == "__main__":
    main()
