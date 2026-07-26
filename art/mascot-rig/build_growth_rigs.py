#!/usr/bin/env python3
"""Build deterministic level 2-7 semantic mascot rigs from immutable art."""

from __future__ import annotations

import hashlib
import json
import math
import shutil
from pathlib import Path

import numpy as np
import PIL
from PIL import Image, ImageChops, ImageDraw, ImageFilter


if np.__version__ != "2.0.2" or PIL.__version__ != "11.3.0":
    raise SystemExit(
        "Expected NumPy 2.0.2 and Pillow 11.3.0; install "
        "art/mascot-rig/level-01/requirements.txt"
    )


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
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
REST_PARTS = [
    "tailBack",
    "body",
    "scarf",
    "head",
    "armLeft",
    "armRight",
    "eyesOpen",
    "mouthSmile",
    "sprout",
]
SOURCE_HASHES = {
    2: "e99fe61d9fe6aaf6a4b85d6390f96a47de74d0420cb181dae75bc890dea90878",
    3: "4206e8ad0fd2b4822805ac1cb9468f6779af6d25e36a00137e4289d399e65ae5",
    4: "a24f6a94115ceabb67cf547b7d2934de7bc9244f0c97ffdbabf1b20d76010dd1",
    5: "4d7518d077ef0c07b884337b2646972ab03b03353a463b394c5957510238b4d2",
    6: "5351093f343254da3c36f53e15030d81bba9655749df0c94754c028944efc188",
    7: "bd68b019f9a9bf3a1d149bdd1735ac7d0dc063aad6eefa3a9d0311c5f7b09ccb",
}
EYE_BOXES = {
    2: ((370, 360, 565, 620), (590, 360, 810, 625)),
    3: ((380, 350, 585, 610), (590, 350, 820, 615)),
    4: ((375, 350, 585, 610), (590, 350, 820, 615)),
    5: ((375, 345, 585, 610), (590, 345, 820, 615)),
    6: ((400, 325, 585, 585), (600, 325, 820, 590)),
    7: ((410, 310, 590, 575), (610, 310, 820, 580)),
}
MOUTH_BOXES = {
    2: (500, 500, 650, 690),
    3: (510, 485, 660, 665),
    4: (510, 470, 662, 652),
    5: (510, 468, 662, 650),
    6: (512, 445, 665, 630),
    7: (515, 440, 670, 625),
}
PIVOTS = {
    2: ((350, 655), (815, 790), (905, 790)),
    3: ((360, 650), (820, 790), (900, 790)),
    4: ((360, 640), (825, 785), (905, 775)),
    5: ((355, 635), (820, 785), (910, 775)),
    6: ((355, 620), (875, 750), (915, 760)),
    7: ((355, 615), (875, 745), (920, 750)),
}
VISUAL_LEVELS = (1, 4, 7)
VIEWPORT = (390, 844)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def blank(mode: str = "RGBA") -> Image.Image:
    return Image.new(mode, SIZE, 0 if mode == "L" else (0, 0, 0, 0))


def rectangle(box: tuple[int, int, int, int]) -> Image.Image:
    mask = blank("L")
    ImageDraw.Draw(mask).rectangle(box, fill=255)
    return mask


def ellipse(box: tuple[int, int, int, int]) -> Image.Image:
    mask = blank("L")
    ImageDraw.Draw(mask).ellipse(box, fill=255)
    return mask


def polygon(points: list[tuple[int, int]]) -> Image.Image:
    mask = blank("L")
    ImageDraw.Draw(mask).polygon(points, fill=255)
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


def generated_patch(
    generated: Image.Image,
    source_alpha: Image.Image,
    mask: Image.Image,
) -> Image.Image:
    final_alpha = intersection(source_alpha, mask)
    rgba = np.asarray(generated.convert("RGB"), dtype=np.uint8)
    alpha = np.asarray(final_alpha, dtype=np.uint8)
    output = np.zeros((SIZE[1], SIZE[0], 4), dtype=np.uint8)
    output[:, :, :3] = rgba
    output[:, :, 3] = alpha
    output[alpha == 0, :3] = 0
    return Image.fromarray(output)


def localized_edit(
    source: Image.Image,
    generated: Image.Image,
    boxes: tuple[tuple[int, int, int, int], ...],
) -> tuple[Image.Image, Image.Image]:
    outer = union(*(ellipse(box) for box in boxes))
    inner_boxes = tuple(
        (left + 7, top + 7, right - 7, bottom - 7)
        for left, top, right, bottom in boxes
    )
    inner = union(*(ellipse(box) for box in inner_boxes))
    feather = ImageChops.lighter(
        inner,
        outer.filter(ImageFilter.GaussianBlur(9)),
    )
    safe_opaque = source.getchannel("A").point(
        lambda value: 255 if value == 255 else 0
    ).filter(ImageFilter.MinFilter(7))
    feather = ImageChops.multiply(feather, safe_opaque)

    source_array = np.asarray(source.convert("RGB"), dtype=np.int16)
    generated_array = np.asarray(generated.convert("RGB"), dtype=np.int16)
    feather_array = np.asarray(feather)
    source_alpha = np.asarray(source.getchannel("A"))
    transition = (
        (feather_array >= 16)
        & (feather_array <= 208)
        & (source_alpha == 255)
    )
    if transition.any():
        adjustment = np.median(
            source_array[transition] - generated_array[transition],
            axis=0,
        )
        adjustment = np.clip(np.rint(adjustment), -24, 24)
    else:
        adjustment = np.zeros(3)
    adjusted = np.clip(
        generated_array + adjustment.astype(np.int16),
        0,
        255,
    ).astype(np.uint8)
    adjusted_rgba = np.zeros((SIZE[1], SIZE[0], 4), dtype=np.uint8)
    adjusted_rgba[:, :, :3] = adjusted
    adjusted_rgba[:, :, 3] = source_alpha
    adjusted_image = Image.fromarray(adjusted_rgba)
    return Image.composite(adjusted_image, source, feather), outer


def overlay(base: Image.Image, layer: Image.Image) -> Image.Image:
    return Image.alpha_composite(base, layer)


def alpha_count(image: Image.Image) -> int:
    return sum(image.getchannel("A").histogram()[1:])


def changed_pixels(left: Image.Image, right: Image.Image) -> int:
    difference = ImageChops.difference(left, right)
    return sum(pixel != (0, 0, 0, 0) for pixel in difference.getdata())


def changed_outside_mask(
    source: Image.Image,
    candidate: Image.Image,
    allowed: Image.Image,
) -> int:
    protected = ImageChops.invert(allowed)
    return changed_pixels(
        source_layer(source, protected),
        source_layer(candidate, protected),
    )


def save_rgba(image: Image.Image, path: Path) -> None:
    image.convert("RGBA").save(
        path,
        format="PNG",
        optimize=False,
        interlace=False,
    )


def semantic_masks(source: Image.Image, level: int) -> dict[str, Image.Image]:
    source_array = np.asarray(source)
    source_alpha = source.getchannel("A")
    foreground = source_alpha.point(lambda value: 255 if value else 0)
    red = source_array[:, :, 0].astype(np.int16)
    green = source_array[:, :, 1].astype(np.int16)
    blue = source_array[:, :, 2].astype(np.int16)
    green_pixels = (
        (source_array[:, :, 3] > 0)
        & (green > 45)
        & (green > blue + 8)
        & (green > (red * 0.66))
        & (red < 205)
    )
    green_mask = Image.fromarray(
        np.where(green_pixels, 255, 0).astype(np.uint8),
        mode="L",
    ).filter(ImageFilter.MaxFilter(5))

    eye_mask = union(*(ellipse(box) for box in EYE_BOXES[level]))
    mouth_mask = ellipse(MOUTH_BOXES[level])
    candidates = {
        "eyesOpen": eye_mask,
        "mouthSmile": mouth_mask,
        "sprout": rectangle((470, 65, 805, 285)),
        "armLeft": polygon(
            [(175, 420), (390, 410), (460, 725), (385, 850), (225, 720)]
        ),
        "armRight": polygon(
            [(720, 610), (1005, 610), (1015, 945), (745, 965), (700, 760)]
        ),
        "tailBack": polygon(
            [(815, 480), (1135, 500), (1135, 995), (820, 1050), (760, 760)]
        ),
        "scarf": green_mask,
        "head": polygon(
            [
                (310, 135),
                (915, 135),
                (970, 570),
                (870, 720),
                (655, 765),
                (400, 720),
                (285, 575),
            ]
        ),
    }
    assignment_order = [
        "eyesOpen",
        "mouthSmile",
        "sprout",
        "armLeft",
        "armRight",
        "tailBack",
        "scarf",
        "head",
    ]
    remaining = foreground.copy()
    result: dict[str, Image.Image] = {}
    for name in assignment_order:
        result[name] = intersection(candidates[name], remaining)
        remaining = subtract(remaining, result[name])
    result["body"] = remaining
    return result


def compose(
    layers: dict[str, Image.Image],
    active_parts: list[str],
) -> Image.Image:
    result = blank()
    for name in PARTS:
        if name in active_parts:
            result = overlay(result, layers[name])
    return result


def soft_skinned_celebrate(
    source: Image.Image,
    layers: dict[str, Image.Image],
    level: int,
) -> Image.Image:
    height, width = SIZE[1], SIZE[0]
    grid_y, grid_x = np.indices((height, width), dtype=np.float32)
    map_x = grid_x.copy()
    map_y = grid_y.copy()

    def weight_for(name: str) -> np.ndarray:
        feathered = layers[name].getchannel("A").filter(
            ImageFilter.GaussianBlur(24)
        )
        return np.asarray(feathered, dtype=np.float32) / 255

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

    blend_inverse(
        weight_for("body"),
        (627, 842),
        scale_x=1.04,
        scale_y=0.96,
    )
    left_pivot, right_pivot, tail_pivot = PIVOTS[level]
    blend_inverse(weight_for("armLeft"), left_pivot, degrees=12)
    blend_inverse(weight_for("armRight"), right_pivot, degrees=-12)
    blend_inverse(weight_for("tailBack"), tail_pivot, degrees=8)

    rgba = np.asarray(source, dtype=np.float32)
    x0 = np.floor(map_x).astype(np.int32)
    y0 = np.floor(map_y).astype(np.int32)
    x1 = x0 + 1
    y1 = y0 + 1
    valid = (x0 >= 0) & (y0 >= 0) & (x1 < width) & (y1 < height)
    x0c = np.clip(x0, 0, width - 1)
    x1c = np.clip(x1, 0, width - 1)
    y0c = np.clip(y0, 0, height - 1)
    y1c = np.clip(y1, 0, height - 1)
    xf = (map_x - x0)[..., None]
    yf = (map_y - y0)[..., None]
    top = rgba[y0c, x0c] * (1 - xf) + rgba[y0c, x1c] * xf
    bottom = rgba[y1c, x0c] * (1 - xf) + rgba[y1c, x1c] * xf
    deformed = top * (1 - yf) + bottom * yf
    deformed[~valid] = 0
    return Image.fromarray(
        np.clip(np.rint(deformed), 0, 255).astype(np.uint8),
        mode="RGBA",
    )


def build_level(level: int) -> None:
    directory = HERE / f"level-{level:02d}"
    source_path = (
        ROOT
        / "NaymNaymLevelUp/Resources/Assets.xcassets"
        / f"Squirrel_Growth_Level_{level}.imageset"
        / f"Squirrel_Growth_Level_{level}.png"
    )
    if sha256(source_path) != SOURCE_HASHES[level]:
        raise SystemExit(f"level {level}: immutable source checksum mismatch")
    reference_path = directory / "reference-flat.png"
    if sha256(reference_path) != SOURCE_HASHES[level]:
        raise SystemExit(f"level {level}: reference copy checksum mismatch")

    source = Image.open(source_path).convert("RGBA")
    blink_source_path = directory / "blink-imagegen-source.png"
    neutral_source_path = directory / "mouth-neutral-imagegen-source.png"
    blink_source = Image.open(blink_source_path).convert("RGB")
    neutral_source = Image.open(neutral_source_path).convert("RGB")
    if source.size != SIZE or blink_source.size != SIZE or neutral_source.size != SIZE:
        raise SystemExit(f"level {level}: source dimensions must be 1254x1254")

    masks = semantic_masks(source, level)
    source_alpha = source.getchannel("A")
    blink_localized, eye_mask = localized_edit(
        source,
        blink_source,
        EYE_BOXES[level],
    )
    neutral_localized, mouth_mask = localized_edit(
        source,
        neutral_source,
        (MOUTH_BOXES[level],),
    )
    opaque_source = source_alpha.point(lambda value: 255 if value == 255 else 0)

    layers = {name: blank() for name in PARTS}
    for name in (
        "tailBack",
        "body",
        "scarf",
        "head",
        "armLeft",
        "armRight",
        "eyesOpen",
        "mouthSmile",
        "sprout",
    ):
        layers[name] = source_layer(source, masks[name])

    # Hidden-area paint stays beneath fully opaque expression and joint layers.
    face_underpaint = generated_patch(
        blink_localized,
        source_alpha,
        intersection(eye_mask, opaque_source),
    )
    mouth_underpaint = generated_patch(
        neutral_localized,
        source_alpha,
        intersection(mouth_mask, opaque_source),
    )
    layers["head"] = overlay(layers["head"], face_underpaint)
    layers["head"] = overlay(layers["head"], mouth_underpaint)
    for joint_name in ("armLeft", "armRight", "scarf"):
        underpaint_mask = intersection(
            masks[joint_name],
            opaque_source,
        )
        layers["body"] = overlay(
            layers["body"],
            source_layer(source, underpaint_mask),
        )

    layers["eyesClosed"] = generated_patch(
        blink_localized,
        source_alpha,
        masks["eyesOpen"],
    )
    layers["mouthNeutral"] = generated_patch(
        neutral_localized,
        source_alpha,
        masks["mouthSmile"],
    )

    for name in PARTS:
        if alpha_count(layers[name]) == 0:
            raise SystemExit(f"level {level}: empty semantic layer {name}")
        save_rgba(layers[name], directory / f"{name}.png")

    composed_rest = compose(layers, REST_PARTS)
    if changed_pixels(source, composed_rest) != 0:
        raise SystemExit(f"level {level}: semantic rest composition drifted")
    shutil.copyfile(reference_path, directory / "composite-rest.png")

    blink = compose(
        layers,
        [
            part
            for part in REST_PARTS
            if part != "eyesOpen"
        ]
        + ["eyesClosed"],
    )
    celebrate = soft_skinned_celebrate(source, layers, level)
    save_rgba(blink, directory / "composite-blink.png")
    save_rgba(celebrate, directory / "composite-celebrate.png")

    outside_eye_changes = changed_outside_mask(source, blink, eye_mask)
    mouth_changes = changed_pixels(
        source_layer(source, masks["mouthSmile"]),
        source_layer(blink, masks["mouthSmile"]),
    )
    neutral_difference = changed_pixels(
        layers["mouthSmile"],
        layers["mouthNeutral"],
    )
    if outside_eye_changes != 0 or mouth_changes != 0:
        raise SystemExit(
            f"level {level}: blink changed non-eye or mouth pixels "
            f"(outside={outside_eye_changes}, mouth={mouth_changes})"
        )
    if neutral_difference == 0:
        raise SystemExit(f"level {level}: neutral mouth is not meaningful")

    part_hashes = {
        name: sha256(directory / f"{name}.png")
        for name in PARTS
    }
    metrics = {
        "level": level,
        "canvas": {"width": 1254, "height": 1254, "mode": "RGBA"},
        "anchor": {"x": 627, "y": 1128},
        "sourceSha256": SOURCE_HASHES[level],
        "referenceVsRestChangedPixels": 0,
        "blinkAcceptance": {
            "outsideEyeRoiChangedPixels": outside_eye_changes,
            "immutableSourceMouthChangedPixels": mouth_changes,
            "imageGenSourceSha256": sha256(blink_source_path),
        },
        "neutralMouthAcceptance": {
            "differsFromSmilePixels": neutral_difference,
            "imageGenSourceSha256": sha256(neutral_source_path),
        },
        "parts": {
            name: {
                "sha256": part_hashes[name],
                "nonzeroAlphaPixels": alpha_count(layers[name]),
            }
            for name in PARTS
        },
        "poses": {
            "rest": "exact immutable source pixels",
            "blink": "closed eyes only; source mouth is byte-for-byte unchanged",
            "celebrate": {
                "renderMethod": "semantic part-weight-map soft skinning keyframe",
                "armLeftDegrees": 12,
                "armRightDegrees": -12,
                "tailDegrees": 8,
                "bodyScale": [1.04, 0.96],
            },
        },
    }
    (directory / "acceptance-metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (directory / "source-notes.md").write_text(
        "\n".join(
            [
                f"# Level {level:02d} source notes",
                "",
                "- Immutable reference: "
                f"`Squirrel_Growth_Level_{level}.png`",
                f"- Immutable reference SHA-256: `{SOURCE_HASHES[level]}`",
                "- Canvas and anchor: `1254×1254`, `(627, 1128)`",
                "- Blink source: built-in ImageGen precise-object edit; only "
                "the localized eye ROI is consumed.",
                "- Neutral-mouth source: built-in ImageGen precise-object "
                "edit; only the localized mouth ROI is consumed.",
                "- Checker-backed generated source files are provenance only "
                "and are never copied to either app bundle.",
                "- REST is pixel-identical to the immutable source. BLINK "
                "preserves every source mouth pixel. CELEBRATE uses semantic "
                "part-weight-map soft skinning.",
                "",
            ]
        ),
        encoding="utf-8",
    )


def build_visual_comparison() -> None:
    viewport_width, viewport_height = VIEWPORT
    comparison = Image.new(
        "RGB",
        (viewport_width * len(VISUAL_LEVELS), viewport_height),
        (255, 249, 236),
    )
    character_size = 300
    character_top = 190
    anchor_y = character_top + round(1128 / 1254 * character_size)

    for panel, level in enumerate(VISUAL_LEVELS):
        panel_left = panel * viewport_width
        draw = ImageDraw.Draw(comparison)
        draw.rectangle(
            (
                panel_left,
                0,
                panel_left + viewport_width - 1,
                viewport_height - 1,
            ),
            outline=(245, 238, 220),
            width=2,
        )
        draw.text(
            (panel_left + 24, 36),
            f"LEVEL {level}",
            fill=(24, 49, 39),
        )
        draw.text(
            (panel_left + 24, 64),
            "390 x 844 / anchor (627, 1128)",
            fill=(98, 113, 104),
        )
        draw.line(
            (
                panel_left + 24,
                anchor_y,
                panel_left + viewport_width - 24,
                anchor_y,
            ),
            fill=(47, 138, 97),
            width=2,
        )
        draw.text(
            (panel_left + 24, anchor_y + 8),
            "shared anchor baseline",
            fill=(47, 138, 97),
        )

        rest_path = HERE / f"level-{level:02d}" / "composite-rest.png"
        rest = Image.open(rest_path).convert("RGBA").resize(
            (character_size, character_size),
            Image.Resampling.LANCZOS,
        )
        comparison.paste(
            rest,
            (
                panel_left + (viewport_width - character_size) // 2,
                character_top,
            ),
            rest,
        )

    comparison.save(
        HERE / "visual-comparison-levels-01-04-07.png",
        format="PNG",
        optimize=False,
        interlace=False,
    )


def main() -> None:
    for level in range(2, 8):
        build_level(level)
    build_visual_comparison()
    print("growth-rig-build: PASS (levels 2-7)")


if __name__ == "__main__":
    main()
