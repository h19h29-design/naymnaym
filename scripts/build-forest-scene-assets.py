#!/usr/bin/env python3
"""Build the approved living-forest master layers and acceptance composites."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps
except ImportError as error:  # pragma: no cover - environment guidance
    raise SystemExit(
        "Pillow and NumPy are required. Run this with the Codex workspace "
        f"Python runtime. Missing dependency: {error}"
    ) from error


MASTER_SIZE = (1290, 2796)
FOREGROUND_OVERSCAN = 1.04
NEIGHBOR_SHIFTS = (
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (1, 1),
    (1, -1),
    (-1, 1),
    (-1, -1),
)


def shifted(array: np.ndarray, dy: int, dx: int) -> np.ndarray:
    result = np.roll(np.roll(array, dy, axis=0), dx, axis=1)
    if dy > 0:
        result[:dy] = 0
    elif dy < 0:
        result[dy:] = 0
    if dx > 0:
        result[:, :dx] = 0
    elif dx < 0:
        result[:, dx:] = 0
    return result


def propagate_colors(
    colors: np.ndarray,
    valid: np.ndarray,
    target: np.ndarray,
    *,
    steps: int,
) -> tuple[np.ndarray, np.ndarray]:
    for _ in range(steps):
        needed = target & ~valid
        if not needed.any():
            break
        accumulated = np.zeros_like(colors)
        counts = np.zeros(valid.shape, dtype=np.float32)
        for dy, dx in NEIGHBOR_SHIFTS:
            neighbor_colors = shifted(colors, dy, dx)
            neighbor_valid = shifted(valid, dy, dx).astype(bool)
            usable = neighbor_valid & needed
            accumulated[usable] += neighbor_colors[usable]
            counts[usable] += 1
        accepted = needed & (counts > 0)
        if not accepted.any():
            break
        colors[accepted] = accumulated[accepted] / counts[accepted, None]
        valid[accepted] = True
    return colors, valid


def connected_foreground(
    rgb: np.ndarray,
    *,
    strong_key_cutoff: float | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    key_score = np.minimum(red, blue) - green
    key_candidate = key_score > 10
    padded = np.pad(key_candidate, 1, constant_values=True)
    flood = Image.fromarray(
        np.where(padded, 0, 255).astype(np.uint8),
        mode="L",
    ).copy()
    ImageDraw.floodfill(flood, (0, 0), 128)
    connected_background = (np.asarray(flood) == 128)[1:-1, 1:-1]
    foreground = ~connected_background
    if strong_key_cutoff is not None:
        foreground &= key_score <= strong_key_cutoff
    foreground_image = Image.fromarray(
        (foreground * 255).astype(np.uint8),
        mode="L",
    )
    foreground = (
        np.asarray(
            foreground_image.filter(ImageFilter.MaxFilter(3)).filter(
                ImageFilter.MinFilter(3)
            )
        )
        > 127
    )
    return foreground, key_score


def extract_propagated_cutout(source: Path) -> Image.Image:
    """Clean broad generated foliage while removing all connected key matte."""

    rgb = np.asarray(Image.open(source).convert("RGB")).astype(np.float32)
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    foreground, key_score = connected_foreground(rgb)
    pink = (red > green + 15) & (blue > green * 0.42)
    blue_gray = (blue > green + 8) & (red > green - 20)
    clean = foreground & (key_score <= 5) & ~pink & ~blue_gray
    colors = rgb.copy()
    colors, valid = propagate_colors(
        colors,
        clean.copy(),
        foreground,
        steps=32,
    )
    alpha_image = Image.fromarray(
        (foreground * 255).astype(np.uint8),
        mode="L",
    ).filter(ImageFilter.GaussianBlur(0.85))
    alpha = np.asarray(alpha_image)
    colors, valid = propagate_colors(
        colors,
        valid,
        alpha > 0,
        steps=12,
    )
    if ((alpha > 0) & ~valid).any():
        raise RuntimeError(f"Could not reconstruct complete matte for {source}")
    output = np.dstack((colors, alpha)).clip(0, 255).astype(np.uint8)
    output[alpha == 0, :3] = 0
    return Image.fromarray(output, mode="RGBA")


def extract_edge_preserving_cutout(source: Path) -> Image.Image:
    """Preserve opaque painted detail and repair only the connected edge matte."""

    rgb = np.asarray(Image.open(source).convert("RGB")).astype(np.float32)
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    foreground, key_score = connected_foreground(
        rgb,
        strong_key_cutoff=40,
    )
    background = ~foreground
    near_background = np.asarray(
        Image.fromarray(
            (background * 255).astype(np.uint8),
            mode="L",
        ).filter(ImageFilter.MaxFilter(5))
    ) > 0
    boundary = foreground & near_background

    colors = rgb.copy()
    pink = (red > green + 22) & (blue > green * 0.72)
    blue_spill = (blue > green + 14) & (red > green - 12)
    spill = foreground & (pink | blue_spill | (key_score > 5))
    colors[spill, 0] = np.minimum(colors[spill, 0], colors[spill, 1] + 20)
    colors[spill, 2] = np.minimum(
        colors[spill, 2],
        np.maximum(0, colors[spill, 1] * 0.62),
    )

    valid = foreground & ~boundary
    for _ in range(5):
        needed = boundary & ~valid
        if not needed.any():
            break
        accumulated = np.zeros_like(colors)
        counts = np.zeros(valid.shape, dtype=np.float32)
        for dy, dx in NEIGHBOR_SHIFTS:
            neighbor_colors = shifted(colors, dy, dx)
            neighbor_valid = shifted(valid, dy, dx).astype(bool)
            usable = neighbor_valid & needed
            accumulated[usable] += neighbor_colors[usable]
            counts[usable] += 1
        accepted = needed & (counts > 0)
        replace = accepted & spill
        colors[replace] = accumulated[replace] / counts[replace, None]
        valid[accepted] = True

    alpha_image = Image.fromarray(
        (foreground * 255).astype(np.uint8),
        mode="L",
    ).filter(ImageFilter.GaussianBlur(0.72))
    alpha = np.asarray(alpha_image)
    colors, valid = propagate_colors(
        colors,
        foreground.copy(),
        alpha > 0,
        steps=12,
    )
    if ((alpha > 0) & ~valid).any():
        raise RuntimeError(f"Could not reconstruct complete matte for {source}")
    output = np.dstack((colors, alpha)).clip(0, 255).astype(np.uint8)
    output[alpha == 0, :3] = 0
    return Image.fromarray(output, mode="RGBA")


def fit(image: Image.Image, mode: str) -> Image.Image:
    return ImageOps.fit(
        image.convert(mode),
        MASTER_SIZE,
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )


def composite(
    root: Path,
    offsets: dict[str, tuple[int, int]],
    *,
    production_overscan: bool,
) -> Image.Image:
    canvas = Image.open(root / "sky.png").convert("RGBA")
    for layer_name in (
        "distantTrees",
        "midgroundTrees",
        "foregroundLeaves",
        "ground",
    ):
        layer = Image.open(root / f"{layer_name}.png").convert("RGBA")
        dx, dy = offsets.get(layer_name, (0, 0))
        if layer_name == "foregroundLeaves" and production_overscan:
            width, height = layer.size
            layer = layer.resize(
                (
                    round(width * FOREGROUND_OVERSCAN),
                    round(height * FOREGROUND_OVERSCAN),
                ),
                Image.Resampling.LANCZOS,
            )
            position = (
                (MASTER_SIZE[0] - layer.width) // 2 + dx,
                (MASTER_SIZE[1] - layer.height) // 2 + dy,
            )
        else:
            position = (dx, dy)
        canvas.alpha_composite(layer, position)
    return canvas.convert("RGB")


def build_comparison(root: Path) -> None:
    panel_size = (430, 932)
    header_height = 52
    labels_and_paths = (
        ("INTRO REFERENCE", root / "references" / "intro.png"),
        ("HOME REFERENCE", root / "references" / "home.png"),
        ("APPROVED LIVING FOREST", root / "acceptance-rest.png"),
    )
    canvas = Image.new("RGB", (1310, 932), "#F5EEDC")
    font = ImageFont.load_default(size=18)
    for index, (label, path) in enumerate(labels_and_paths):
        panel = Image.new("RGB", panel_size, "#FFF9EC")
        visual = ImageOps.contain(
            Image.open(path).convert("RGB"),
            (panel_size[0], panel_size[1] - header_height),
            Image.Resampling.LANCZOS,
        )
        panel.paste(
            visual,
            (
                (panel_size[0] - visual.width) // 2,
                header_height
                + (panel_size[1] - header_height - visual.height) // 2,
            ),
        )
        draw = ImageDraw.Draw(panel)
        text_box = draw.textbbox((0, 0), label, font=font)
        draw.text(
            ((panel_size[0] - (text_box[2] - text_box[0])) / 2, 16),
            label,
            fill="#183127",
            font=font,
        )
        canvas.paste(panel, (index * 440, 0))
    canvas.save(root / "reference-comparison.png", optimize=True)


def build(root: Path) -> None:
    sources = root / "generated-sources"
    fit(Image.open(sources / "sky-source.png"), "RGB").save(
        root / "sky.png",
        optimize=True,
    )
    for layer_name in ("distantTrees", "foregroundLeaves"):
        fit(
            extract_propagated_cutout(sources / f"{layer_name}-source.png"),
            "RGBA",
        ).save(root / f"{layer_name}.png", optimize=True)
    for layer_name in ("midgroundTrees", "ground"):
        fit(
            extract_edge_preserving_cutout(
                sources / f"{layer_name}-source.png"
            ),
            "RGBA",
        ).save(root / f"{layer_name}.png", optimize=True)

    composite(root, {}, production_overscan=False).save(
        root / "master-1290x2796.png",
        optimize=True,
    )
    composite(root, {}, production_overscan=True).save(
        root / "acceptance-rest.png",
        optimize=True,
    )
    composite(
        root,
        {
            "distantTrees": (0, -6),
            "midgroundTrees": (0, -12),
            "foregroundLeaves": (18, -9),
        },
        production_overscan=True,
    ).save(root / "acceptance-max-motion.png", optimize=True)
    build_comparison(root)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("art/forest-scene/home"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    build(args.root.resolve())
    print(f"Built living forest assets under {args.root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
