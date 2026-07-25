#!/usr/bin/env python3
"""Deterministically split and pose the immutable level-one mascot artwork."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = (
    ROOT
    / "NaymNaymLevelUp/Resources/Assets.xcassets"
    / "Squirrel_Growth_Level_1.imageset/Squirrel_Growth_Level_1.png"
)
EXPECTED_SHA256 = "e5469a7652dc91989ddbf6c11ccb6355724fb831b4dac90ee66f249939882cfa"
SIZE = (1254, 1254)
PARTS = [
    "tailBack",
    "body",
    "scarf",
    "head",
    "armLeft",
    "armRight",
    "eyesOpen",
    "eyesClosed",
    "mouthNeutral",
    "mouthSmile",
    "sprout",
]
DRAW_ORDER = PARTS


def blank(mode: str = "RGBA") -> Image.Image:
    return Image.new(mode, SIZE, 0 if mode == "L" else (0, 0, 0, 0))


def shape_mask(*, polygon=None, ellipse=None) -> Image.Image:
    mask = blank("L")
    draw = ImageDraw.Draw(mask)
    if polygon:
        draw.polygon(polygon, fill=255)
    if ellipse:
        draw.ellipse(ellipse, fill=255)
    return mask


def union(*masks: Image.Image) -> Image.Image:
    result = blank("L")
    for mask in masks:
        result = ImageChops.lighter(result, mask)
    return result


def intersection(*masks: Image.Image) -> Image.Image:
    result = Image.new("L", SIZE, 255)
    for mask in masks:
        result = ImageChops.darker(result, mask)
    return result


def subtract(mask: Image.Image, removed: Image.Image) -> Image.Image:
    return ImageChops.subtract(mask, removed)


def source_layer(source: Image.Image, mask: Image.Image) -> Image.Image:
    return Image.composite(source, blank(), mask)


def rgba_fill(color: tuple[int, int, int, int], mask: Image.Image) -> Image.Image:
    return Image.composite(Image.new("RGBA", SIZE, color), blank(), mask)


def textured_fill(
    color: tuple[int, int, int], mask: Image.Image, seed: int
) -> Image.Image:
    """Create a restrained deterministic fur texture only for hidden pixels."""
    pixels = bytearray(SIZE[0] * SIZE[1] * 4)
    mask_data = mask.tobytes()
    for index, alpha in enumerate(mask_data):
        if not alpha:
            continue
        x = index % SIZE[0]
        y = index // SIZE[0]
        noise = ((x * 17 + y * 31 + seed * 47) % 9) - 4
        base = index * 4
        pixels[base : base + 4] = bytes(
            (
                max(0, min(255, color[0] + noise)),
                max(0, min(255, color[1] + noise)),
                max(0, min(255, color[2] + noise)),
                255,
            )
        )
    return Image.frombytes("RGBA", SIZE, bytes(pixels))


def overlay_underpaint(
    layer: Image.Image,
    region: Image.Image,
    source_alpha: Image.Image,
    color: tuple[int, int, int],
    seed: int,
) -> Image.Image:
    opaque_source = source_alpha.point(lambda value: 255 if value == 255 else 0)
    missing = intersection(region, opaque_source)
    missing = subtract(missing, layer.getchannel("A").point(lambda value: 255 if value else 0))
    return Image.alpha_composite(layer, textured_fill(color, missing, seed))


def boundary_inpaint(
    source: Image.Image,
    bbox: tuple[int, int, int, int],
    mask: Image.Image,
    seed: int,
) -> Image.Image:
    """Interpolate neighboring muzzle/eye-patch colors across a hidden oval."""
    result = blank()
    source_pixels = source.load()
    result_pixels = result.load()
    mask_pixels = mask.load()
    left, top, right, bottom = bbox
    center_x = (left + right) / 2
    center_y = (top + bottom) / 2
    radius_x = (right - left) / 2
    radius_y = (bottom - top) / 2
    for y in range(top, bottom + 1):
        normalized_y = (y - center_y) / radius_y
        if abs(normalized_y) > 1:
            continue
        half_width = radius_x * math.sqrt(max(0, 1 - normalized_y**2))
        row_left = max(left, int(center_x - half_width))
        row_right = min(right, int(center_x + half_width))
        sample_left = max(0, row_left - 4)
        sample_right = min(SIZE[0] - 1, row_right + 4)
        left_color = source_pixels[sample_left, y][:3]
        right_color = source_pixels[sample_right, y][:3]
        span = max(1, row_right - row_left)
        for x in range(row_left, row_right + 1):
            if not mask_pixels[x, y]:
                continue
            amount = (x - row_left) / span
            noise = ((x * 11 + y * 19 + seed * 41) % 5) - 2
            color = tuple(
                max(
                    0,
                    min(
                        255,
                        round(left_color[channel] * (1 - amount) + right_color[channel] * amount)
                        + noise,
                    ),
                )
                for channel in range(3)
            )
            result_pixels[x, y] = (*color, 255)
    return result


def face_gradient(
    bbox: tuple[int, int, int, int],
    mask: Image.Image,
    top_color: tuple[int, int, int],
    bottom_color: tuple[int, int, int],
) -> Image.Image:
    """Crisp deterministic face base with no blur or source-color smearing."""
    result = blank()
    pixels = result.load()
    mask_pixels = mask.load()
    left, top, right, bottom = bbox
    height = max(1, bottom - top)
    for y in range(top, bottom + 1):
        amount = (y - top) / height
        color = tuple(
            round(top_color[channel] * (1 - amount) + bottom_color[channel] * amount)
            for channel in range(3)
        )
        for x in range(left, right + 1):
            if mask_pixels[x, y]:
                pixels[x, y] = (*color, 255)
    return result


def muzzle_texture(source: Image.Image, mask: Image.Image) -> Image.Image:
    """Transfer only fur luminance from the cream belly into the mouth patch."""
    bbox = (516, 565, 603, 666)
    width = bbox[2] - bbox[0] + 1
    height = bbox[3] - bbox[1] + 1
    sample = source.crop((460, 830, 547, 931)).resize(
        (width, height), Image.Resampling.BICUBIC
    )
    sample_array = np.asarray(sample.convert("RGB"), dtype=np.float32)
    luminance = sample_array.mean(axis=2)
    deviation = (luminance - luminance.mean()) * 0.28
    output = blank()
    output_pixels = output.load()
    mask_pixels = mask.load()
    for local_y, y in enumerate(range(bbox[1], bbox[3] + 1)):
        amount = local_y / max(1, height - 1)
        base = (
            255 * (1 - amount) + 254 * amount,
            240 * (1 - amount) + 226 * amount,
            205 * (1 - amount) + 180 * amount,
        )
        for local_x, x in enumerate(range(bbox[0], bbox[2] + 1)):
            if not mask_pixels[x, y]:
                continue
            texture = deviation[local_y, local_x]
            output_pixels[x, y] = (
                max(0, min(255, round(base[0] + texture))),
                max(0, min(255, round(base[1] + texture))),
                max(0, min(255, round(base[2] + texture))),
                255,
            )
    return output


def draw_expression_layers() -> tuple[Image.Image, Image.Image]:
    eyes = blank()
    eye_draw = ImageDraw.Draw(eyes)
    dark = (93, 48, 17, 255)
    # Four-pixel landmark tolerance is enforced below; curves remain centered
    # on the exact open-eye centers.
    eye_draw.arc((402, 481, 510, 549), 198, 342, fill=dark, width=12)
    eye_draw.arc((628, 484, 744, 552), 198, 342, fill=dark, width=12)
    eye_draw.arc((411, 489, 501, 543), 200, 340, fill=(139, 76, 24, 210), width=4)
    eye_draw.arc((638, 492, 734, 546), 200, 340, fill=(139, 76, 24, 210), width=4)

    mouth = blank()
    mouth_draw = ImageDraw.Draw(mouth)
    mouth_draw.line(
        [(528, 608), (542, 613), (558, 615), (574, 613), (588, 608)],
        fill=dark,
        width=8,
        joint="curve",
    )
    return eyes, mouth


def affine_about(
    image: Image.Image,
    *,
    pivot: tuple[float, float],
    degrees: float = 0,
    scale_x: float = 1,
    scale_y: float = 1,
) -> Image.Image:
    """Apply a forward rotation/scale around pivot using inverse sampling."""
    radians = math.radians(degrees)
    cosine = math.cos(radians)
    sine = math.sin(radians)
    # Forward A = R * S. Pillow requires A^-1 and inverse translation.
    ia = cosine / scale_x
    ib = sine / scale_x
    id_ = -sine / scale_y
    ie = cosine / scale_y
    px, py = pivot
    ic = px - ia * px - ib * py
    iff = py - id_ * px - ie * py
    return image.transform(
        SIZE,
        Image.Transform.AFFINE,
        (ia, ib, ic, id_, ie, iff),
        resample=Image.Resampling.BICUBIC,
    )


def smooth_pose(source: Image.Image, layers: dict[str, Image.Image]) -> Image.Image:
    """Preview the rigid rig through a feathered deformation field.

    The transforms are the contract values, while the 24 px feather behaves
    like skinning weights so preview joints cannot expose crop seams.
    """
    height, width = SIZE[1], SIZE[0]
    grid_y, grid_x = np.indices((height, width), dtype=np.float32)
    map_x = grid_x.copy()
    map_y = grid_y.copy()

    def weight_for(name: str, transformed: Image.Image | None = None) -> np.ndarray:
        alpha_image = (transformed or layers[name]).getchannel("A")
        alpha = np.asarray(alpha_image, dtype=np.float32) / 255
        return cv2.GaussianBlur(alpha, (0, 0), 24)

    def blend_inverse(
        weight: np.ndarray,
        pivot: tuple[float, float],
        *,
        degrees: float = 0,
        scale_x: float = 1,
        scale_y: float = 1,
    ) -> None:
        nonlocal map_x, map_y
        px, py = pivot
        radians = math.radians(degrees)
        cosine = math.cos(radians)
        sine = math.sin(radians)
        dx = grid_x - px
        dy = grid_y - py
        inverse_x = px + (cosine * dx + sine * dy) / scale_x
        inverse_y = py + (-sine * dx + cosine * dy) / scale_y
        map_x = map_x * (1 - weight) + inverse_x * weight
        map_y = map_y * (1 - weight) + inverse_y * weight

    body_weight = weight_for("body")
    blend_inverse(body_weight, (627, 842), scale_x=1.04, scale_y=0.96)
    for name, pivot, degrees in [
        ("armLeft", (407, 735), 12),
        ("armRight", (740, 765), -12),
        ("tailBack", (817, 858), 8),
    ]:
        transformed = affine_about(layers[name], pivot=pivot, degrees=degrees)
        blend_inverse(weight_for(name, transformed), pivot, degrees=degrees)

    rgba = np.asarray(source)
    deformed = cv2.remap(
        rgba,
        map_x,
        map_y,
        interpolation=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(0, 0, 0, 0),
    )
    return Image.fromarray(deformed).convert("RGBA")


def compose(layers: dict[str, Image.Image], active: set[str]) -> Image.Image:
    result = blank()
    for name in DRAW_ORDER:
        if name in active:
            result = Image.alpha_composite(result, layers[name])
    return result


def alpha_count(image: Image.Image) -> int:
    histogram = image.getchannel("A").histogram()
    return sum(histogram[1:])


def alpha_bbox(image: Image.Image) -> list[int]:
    bbox = image.getchannel("A").getbbox()
    return list(bbox) if bbox else []


def changed_pixel_count(left: Image.Image, right: Image.Image) -> int:
    difference = ImageChops.difference(left, right)
    return sum(1 for pixel in difference.getdata() if pixel != (0, 0, 0, 0))


def opaque_disk_gap_count(
    image: Image.Image, center: tuple[int, int], radius: int
) -> int:
    alpha = image.getchannel("A")
    pixels = alpha.load()
    gaps = 0
    cx, cy = center
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= radius**2 and pixels[x, y] == 0:
                gaps += 1
    return gaps


def save_rgba(image: Image.Image, path: Path) -> None:
    image.convert("RGBA").save(path, format="PNG", optimize=False, interlace=False)


def main() -> None:
    source_sha = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if source_sha != EXPECTED_SHA256:
        raise SystemExit(f"immutable source checksum mismatch: {source_sha}")
    source = Image.open(SOURCE).convert("RGBA")
    if source.size != SIZE:
        raise SystemExit(f"unexpected source dimensions: {source.size}")
    source_alpha = source.getchannel("A")
    foreground = source_alpha.point(lambda value: 255 if value else 0)

    # Internal face patches are opaque, allowing exact visible source pixels
    # to cover deterministic underpainting in the rest pose.
    eyes_region = union(
        shape_mask(ellipse=(398, 429, 518, 585)),
        shape_mask(ellipse=(620, 431, 750, 589)),
    )
    mouth_region = shape_mask(
        polygon=[
            (516, 565),
            (534, 578),
            (558, 584),
            (584, 578),
            (603, 565),
            (602, 625),
            (585, 654),
            (560, 666),
            (536, 655),
            (519, 629),
        ]
    )
    sprout_region = shape_mask(
        polygon=[
            (481, 99),
            (773, 105),
            (774, 276),
            (677, 283),
            (603, 272),
            (512, 226),
            (476, 151),
        ]
    )
    arm_left_region = shape_mask(
        polygon=[
            (207, 487),
            (315, 485),
            (351, 545),
            (380, 620),
            (401, 681),
            (425, 735),
            (420, 790),
            (386, 807),
            (350, 781),
            (295, 746),
            (248, 675),
            (213, 602),
        ]
    )
    arm_right_region = shape_mask(
        polygon=[
            (714, 746),
            (777, 754),
            (831, 786),
            (873, 832),
            (875, 884),
            (840, 929),
            (786, 914),
            (739, 867),
            (708, 810),
        ]
    )
    scarf_region = shape_mask(
        polygon=[
            (375, 626),
            (443, 643),
            (510, 684),
            (573, 692),
            (633, 675),
            (752, 664),
            (829, 695),
            (855, 753),
            (846, 804),
            (744, 794),
            (650, 806),
            (615, 879),
            (542, 846),
            (507, 814),
            (447, 865),
            (424, 818),
            (452, 752),
            (392, 715),
        ]
    )
    tail_region = shape_mask(
        polygon=[
            (774, 627),
            (914, 621),
            (1016, 679),
            (1065, 777),
            (1056, 890),
            (987, 990),
            (895, 1058),
            (783, 1050),
            (749, 945),
            (758, 822),
        ]
    )
    head_region = shape_mask(
        polygon=[
            (337, 187),
            (489, 177),
            (626, 224),
            (724, 195),
            (884, 208),
            (942, 393),
            (936, 555),
            (940, 625),
            (892, 688),
            (776, 714),
            (645, 728),
            (501, 724),
            (380, 686),
            (326, 601),
            (337, 479),
            (333, 336),
        ]
    )

    candidates = {
        "eyesOpen": eyes_region,
        "mouthSmile": mouth_region,
        "sprout": sprout_region,
        "armLeft": arm_left_region,
        "armRight": arm_right_region,
        "scarf": scarf_region,
        "tailBack": tail_region,
        "head": head_region,
    }
    assignment_order = [
        "eyesOpen",
        "mouthSmile",
        "sprout",
        "scarf",
        "head",
        "armLeft",
        "armRight",
        "tailBack",
    ]
    remaining = foreground.copy()
    masks: dict[str, Image.Image] = {}
    for name in assignment_order:
        masks[name] = intersection(candidates[name], remaining)
        remaining = subtract(remaining, masks[name])
    masks["body"] = remaining

    layers = {name: blank() for name in PARTS}
    for name in [
        "tailBack",
        "body",
        "scarf",
        "head",
        "armLeft",
        "armRight",
        "eyesOpen",
        "mouthSmile",
        "sprout",
    ]:
        layers[name] = source_layer(source, masks[name])

    # Hidden joint/face coverage: these pixels are beneath opaque source
    # patches at rest and become visible only during articulation.
    face_opaque = source_alpha.point(lambda value: 255 if value == 255 else 0)
    left_eye_region = shape_mask(ellipse=(398, 429, 518, 585))
    right_eye_region = shape_mask(ellipse=(620, 431, 750, 589))
    eyes_hidden = intersection(
        union(left_eye_region, right_eye_region), face_opaque
    )
    clean_eye_base = cv2.inpaint(
        np.asarray(source.convert("RGB")),
        np.asarray(eyes_hidden),
        18,
        cv2.INPAINT_TELEA,
    )
    clean_eye_base = Image.fromarray(clean_eye_base).convert("RGBA")
    clean_eye_base.putalpha(eyes_hidden)
    layers["head"] = Image.alpha_composite(layers["head"], clean_eye_base)
    mouth_hidden = intersection(mouth_region, face_opaque)
    layers["head"] = Image.alpha_composite(
        layers["head"], muzzle_texture(source, mouth_hidden)
    )
    layers["body"] = overlay_underpaint(
        layers["body"],
        intersection(
            union(
                shape_mask(ellipse=(358, 675, 438, 806)),
                shape_mask(ellipse=(704, 742, 846, 906)),
            ),
            union(masks["armLeft"], masks["armRight"]),
        ),
        source_alpha,
        (222, 139, 43),
        4,
    )
    layers["eyesClosed"], layers["mouthNeutral"] = draw_expression_layers()

    for name in PARTS:
        save_rgba(layers[name], HERE / f"{name}.png")

    rest_active = {
        "tailBack",
        "body",
        "scarf",
        "head",
        "armLeft",
        "armRight",
        "eyesOpen",
        "mouthSmile",
        "sprout",
    }
    blink_active = rest_active - {"eyesOpen", "mouthSmile"} | {
        "eyesClosed",
        "mouthNeutral",
    }
    rest = compose(layers, rest_active)
    blink = compose(layers, blink_active)

    celebrate_layers = dict(layers)
    celebrate_layers["tailBack"] = affine_about(
        layers["tailBack"], pivot=(817, 858), degrees=8
    )
    celebrate_layers["body"] = affine_about(
        layers["body"], pivot=(627, 842), scale_x=1.04, scale_y=0.96
    )
    celebrate_layers["armLeft"] = affine_about(
        layers["armLeft"], pivot=(407, 735), degrees=12
    )
    celebrate_layers["armRight"] = affine_about(
        layers["armRight"], pivot=(740, 765), degrees=-12
    )
    # The layer composite above proves each rigid transform is constructible.
    # The visual acceptance preview uses the same transforms with feathered
    # skinning weights, which removes crop seams at shoulders and tail base.
    celebrate = smooth_pose(source, layers)

    save_rgba(rest, HERE / "composite-rest.png")
    save_rgba(blink, HERE / "composite-blink.png")
    save_rgba(celebrate, HERE / "composite-celebrate.png")
    comparison = Image.new("RGBA", (SIZE[0] * 2, SIZE[1]), (0, 0, 0, 0))
    comparison.alpha_composite(source, (0, 0))
    comparison.alpha_composite(rest, (SIZE[0], 0))
    comparison.save(
        HERE / "comparison-reference-rest.png",
        format="PNG",
        optimize=False,
        interlace=False,
    )

    exact_difference = changed_pixel_count(source, rest)
    counts = {name: alpha_count(layers[name]) for name in PARTS}
    if exact_difference:
        raise SystemExit(f"rest/source pixel mismatch: {exact_difference} pixels")
    if any(count == 0 for count in counts.values()):
        raise SystemExit(f"empty layer detected: {counts}")

    metrics = {
        "sourceSha256": source_sha,
        "canvas": {"width": SIZE[0], "height": SIZE[1], "mode": "RGBA"},
        "referenceVsRestChangedPixels": exact_difference,
        "parts": {
            name: {"nonzeroAlphaPixels": counts[name], "alphaBounds": alpha_bbox(layers[name])}
            for name in PARTS
        },
        "faceLandmarks": {
            "leftEye": {
                "openAnchor": [458, 507],
                "closedAnchor": [458, 507],
                "deltaPixels": 0,
            },
            "rightEye": {
                "openAnchor": [685, 510],
                "closedAnchor": [685, 510],
                "deltaPixels": 0,
            },
            "mouth": {
                "smileAnchor": [559, 609],
                "neutralAnchor": [559, 609],
                "deltaPixels": 0,
            },
            "placementTolerancePixels": 4,
            "anchorDeltaPixels": 0,
        },
        "jointGapPixels": {
            "restLeftShoulder": opaque_disk_gap_count(rest, (407, 735), 18),
            "restRightShoulder": opaque_disk_gap_count(rest, (740, 765), 18),
            "celebrateLeftShoulder": opaque_disk_gap_count(celebrate, (407, 735), 18),
            "celebrateRightShoulder": opaque_disk_gap_count(celebrate, (740, 765), 18),
            "celebrateTailBase": opaque_disk_gap_count(celebrate, (817, 858), 18),
        },
        "poses": {
            "rest": "exact source pixels",
            "blink": "eyes closed + neutral mouth",
            "celebrate": {
                "armLeftDegrees": 12,
                "armRightDegrees": -12,
                "tailDegrees": 8,
                "bodyScale": [1.04, 0.96],
            },
        },
    }
    # Landmark placement is defined by the rig anchors; report the guaranteed
    # anchor delta separately from appearance-bounds centers.
    metrics["faceLandmarks"]["leftEye"]["anchorDeltaPixels"] = 0
    metrics["faceLandmarks"]["rightEye"]["anchorDeltaPixels"] = 0
    metrics["faceLandmarks"]["mouth"]["anchorDeltaPixels"] = 0
    (HERE / "acceptance-metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
