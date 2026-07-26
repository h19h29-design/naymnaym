#!/usr/bin/env python3

import argparse
import hashlib
import json
import pathlib
import struct
import sys
import zlib


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "contracts/native-rebuild/v1"
DEFAULT_SOURCE_ROOT = (
    ROOT / "NaymNaymLevelUp/Resources/Assets.xcassets"
)
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
CANVAS = {"width": 1254, "height": 1254}
ANCHOR = {"x": 627, "y": 1128}
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
MOTIONS = {
    "idle": {"durationMs": 6000, "loop": True},
    "tapReaction": {"durationMs": 420, "loop": False},
    "mealSuccess": {"durationMs": 1400, "loop": False},
    "levelUp": {"durationMs": 3000, "loop": False},
    "comfort": {"durationMs": 1200, "loop": False},
    "reducedMotion": {"durationMs": 250, "loop": False},
}
SOURCE_HASHES = {
    1: "e5469a7652dc91989ddbf6c11ccb6355724fb831b4dac90ee66f249939882cfa",
    2: "e99fe61d9fe6aaf6a4b85d6390f96a47de74d0420cb181dae75bc890dea90878",
    3: "4206e8ad0fd2b4822805ac1cb9468f6779af6d25e36a00137e4289d399e65ae5",
    4: "a24f6a94115ceabb67cf547b7d2934de7bc9244f0c97ffdbabf1b20d76010dd1",
    5: "4d7518d077ef0c07b884337b2646972ab03b03353a463b394c5957510238b4d2",
    6: "5351093f343254da3c36f53e15030d81bba9655749df0c94754c028944efc188",
    7: "bd68b019f9a9bf3a1d149bdd1735ac7d0dc063aad6eefa3a9d0311c5f7b09ccb",
}
EYE_BOXES = {
    1: ((375, 410, 550, 620), (590, 410, 790, 625)),
    2: ((370, 360, 565, 620), (590, 360, 810, 625)),
    3: ((380, 350, 585, 610), (590, 350, 820, 615)),
    4: ((375, 350, 585, 610), (590, 350, 820, 615)),
    5: ((375, 345, 585, 610), (590, 345, 820, 615)),
    6: ((400, 325, 585, 585), (600, 325, 820, 590)),
    7: ((410, 310, 590, 575), (610, 310, 820, 580)),
}
ACCEPTANCE_PNGS = [
    "reference-flat",
    "composite-rest",
    "composite-blink",
    "composite-celebrate",
]


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=pathlib.Path,
        default=ROOT / "art/mascot-rig",
    )
    parser.add_argument(
        "--rig-spec",
        type=pathlib.Path,
        default=CONTRACTS / "mascot-rig.json",
    )
    parser.add_argument(
        "--motion-spec",
        type=pathlib.Path,
        default=CONTRACTS / "mascot-motion.json",
    )
    parser.add_argument(
        "--domain-contract",
        type=pathlib.Path,
        default=CONTRACTS / "domain-contract.json",
    )
    parser.add_argument(
        "--source-root",
        type=pathlib.Path,
        default=DEFAULT_SOURCE_ROOT,
    )
    return parser.parse_args()


def load_json(path, errors):
    if not path.is_file():
        errors.append(f"{path.name}: missing")
        return None

    def reject_duplicate_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate key {key!r}")
            result[key] = value
        return result

    try:
        with path.open(encoding="utf-8") as file:
            return json.load(file, object_pairs_hook=reject_duplicate_keys)
    except (OSError, json.JSONDecodeError, ValueError):
        errors.append(f"{path.name}: invalid JSON")
        return None


def exact_json(actual, expected):
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return list(actual) == list(expected) and all(
            exact_json(actual[key], value) for key, value in expected.items()
        )
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(
            exact_json(actual_item, expected_item)
            for actual_item, expected_item in zip(actual, expected)
        )
    return actual == expected


def validate_specs(rig, motion, domain_motion_states):
    errors = []
    errors.extend(validate_rig_spec(rig))
    errors.extend(validate_motion_spec(motion, domain_motion_states))
    return errors


def validate_rig_spec(rig):
    if rig is None:
        return []
    if not isinstance(rig, dict):
        return ["mascot-rig.json: root must be an object"]

    errors = []
    if set(rig) != {"version", "levels"}:
        errors.append(
            "mascot-rig.json: root must contain only version and levels"
        )
    if type(rig.get("version")) is not int or rig.get("version") != 1:
        errors.append(
            "mascot-rig.json: version must be exactly integer 1"
        )

    levels = rig.get("levels")
    if not isinstance(levels, list):
        return errors + ["mascot-rig.json: levels must be an array"]
    level_numbers = [
        level.get("level") if isinstance(level, dict) else None
        for level in levels
    ]
    if level_numbers != list(range(1, 8)):
        errors.append(
            "mascot-rig.json: levels must define exact levels 1 through 7"
        )

    for index, level in enumerate(levels):
        prefix = f"mascot-rig.json: levels[{index}]"
        if not isinstance(level, dict):
            errors.append(f"{prefix} must be an object")
            continue
        if set(level) != {"level", "canvas", "parts", "anchor"}:
            errors.append(
                f"{prefix} must contain only level, canvas, parts, and anchor"
            )
        if type(level.get("level")) is not int:
            errors.append(f"{prefix}.level must be an integer")
        if not exact_json(level.get("canvas"), CANVAS):
            errors.append(f"{prefix}.canvas must be 1254x1254")
        if not exact_json(level.get("parts"), PARTS):
            errors.append(
                f"{prefix}.parts must match the exact part order"
            )
        if not exact_json(level.get("anchor"), ANCHOR):
            errors.append(f"{prefix}.anchor must be (627, 1128)")
    return errors


def validate_motion_spec(motion, domain_motion_states):
    if motion is None:
        return []
    if not isinstance(motion, dict):
        return ["mascot-motion.json: root must be an object"]

    errors = []
    if set(motion) != {"version", "states"}:
        errors.append(
            "mascot-motion.json: root must contain only version and states"
        )
    if type(motion.get("version")) is not int or motion.get("version") != 1:
        errors.append(
            "mascot-motion.json: version must be exactly integer 1"
        )

    states = motion.get("states")
    if not isinstance(states, dict):
        return errors + ["mascot-motion.json: states must be an object"]
    if (
        not isinstance(domain_motion_states, list)
        or not all(isinstance(state, str) for state in domain_motion_states)
        or list(states) != domain_motion_states
    ):
        errors.append(
            "mascot-motion.json: states must match "
            "domain-contract.json motionStates in exact order"
        )

    for name, expected in MOTIONS.items():
        if not exact_json(states.get(name), expected):
            loop = str(expected["loop"]).lower()
            errors.append(
                f"mascot-motion.json: {name} must use durationMs "
                f"{expected['durationMs']} and loop {loop}"
            )
    return errors


def validate_png(path, display_path):
    if not path.is_file():
        return [f"{display_path}: missing"]
    try:
        with path.open("rb") as file:
            header = file.read(33)
    except OSError as error:
        return [f"{display_path}: unreadable ({error})"]

    if len(header) < len(PNG_SIGNATURE) or header[:8] != PNG_SIGNATURE:
        return [f"{display_path}: invalid PNG signature"]
    if len(header) < 33:
        return [f"{display_path}: truncated IHDR header"]
    chunk_length = struct.unpack(">I", header[8:12])[0]
    if chunk_length != 13 or header[12:16] != b"IHDR":
        return [f"{display_path}: first chunk must be a 13-byte IHDR"]

    width, height, bit_depth, color_type, compression, filtering, interlace = (
        struct.unpack(">IIBBBBB", header[16:29])
    )
    errors = []
    if (width, height) != (1254, 1254):
        errors.append(
            f"{display_path}: dimensions must be 1254x1254, "
            f"got {width}x{height}"
        )
    if color_type != 6:
        errors.append(
            f"{display_path}: color type must be 6 (RGBA), got {color_type}"
        )
    if bit_depth != 8:
        errors.append(
            f"{display_path}: bit depth must be 8, got {bit_depth}"
        )
    if (compression, filtering, interlace) != (0, 0, 0):
        errors.append(
            f"{display_path}: compression, filter, and interlace "
            "methods must be 0"
        )
    return errors


def validate_asset_paths(asset_root):
    errors = []
    for level in range(1, 8):
        directory = f"level-{level:02d}"
        for part in PARTS:
            display_path = f"{directory}/{part}.png"
            errors.extend(
                validate_png(
                    asset_root / directory / f"{part}.png",
                    display_path,
                )
            )
    return errors


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_path(source_root, level):
    return (
        source_root
        / f"Squirrel_Growth_Level_{level}.imageset"
        / f"Squirrel_Growth_Level_{level}.png"
    )


def paeth(left, up, upper_left):
    estimate = left + up - upper_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= up_distance and left_distance <= upper_left_distance:
        return left
    if up_distance <= upper_left_distance:
        return up
    return upper_left


def decode_rgba_png(path):
    data = path.read_bytes()
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("invalid PNG signature")
    offset = 8
    width = height = bit_depth = color_type = interlace = None
    compressed = bytearray()
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data = data[offset + 8 : offset + 8 + length]
        if len(chunk_data) != length:
            raise ValueError("truncated PNG chunk")
        if chunk_type == b"IHDR":
            (
                width,
                height,
                bit_depth,
                color_type,
                _compression,
                _filtering,
                interlace,
            ) = struct.unpack(">IIBBBBB", chunk_data)
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break
        offset += 12 + length
    if (
        width is None
        or height is None
        or bit_depth != 8
        or color_type != 6
        or interlace != 0
    ):
        raise ValueError("unsupported PNG layout")
    raw = zlib.decompress(bytes(compressed))
    stride = width * 4
    if len(raw) != (stride + 1) * height:
        raise ValueError("unexpected decompressed PNG length")
    result = bytearray(width * height * 4)
    previous = bytearray(stride)
    source_offset = 0
    target_offset = 0
    for _row in range(height):
        filter_type = raw[source_offset]
        source_offset += 1
        current = bytearray(raw[source_offset : source_offset + stride])
        source_offset += stride
        if filter_type != 0:
            for index in range(stride):
                left = current[index - 4] if index >= 4 else 0
                up = previous[index]
                upper_left = previous[index - 4] if index >= 4 else 0
                if filter_type == 1:
                    current[index] = (current[index] + left) & 0xFF
                elif filter_type == 2:
                    current[index] = (current[index] + up) & 0xFF
                elif filter_type == 3:
                    current[index] = (
                        current[index] + ((left + up) // 2)
                    ) & 0xFF
                elif filter_type == 4:
                    current[index] = (
                        current[index] + paeth(left, up, upper_left)
                    ) & 0xFF
                else:
                    raise ValueError(
                        f"unsupported PNG filter {filter_type}"
                    )
        result[target_offset : target_offset + stride] = current
        target_offset += stride
        previous = current
    return width, height, bytes(result)


def changed_outside_eye_boxes(reference, candidate, level):
    boxes = EYE_BOXES[level]
    changed = 0
    for index in range(0, len(reference), 4):
        if reference[index : index + 4] == candidate[index : index + 4]:
            continue
        pixel = index // 4
        x = pixel % 1254
        y = pixel // 1254
        if not any(
            left <= x <= right and top <= y <= bottom
            for left, top, right, bottom in boxes
        ):
            changed += 1
    return changed


def validate_acceptance_assets(asset_root, reference_root):
    errors = []
    part_hashes = {part: [] for part in PARTS}
    source_hashes = []
    enforce_immutable_hashes = reference_root.resolve() == DEFAULT_SOURCE_ROOT.resolve()

    for level in range(1, 8):
        directory_name = f"level-{level:02d}"
        directory = asset_root / directory_name
        paths = {
            name: directory / f"{name}.png"
            for name in ACCEPTANCE_PNGS
        }
        for name, path in paths.items():
            errors.extend(
                validate_png(path, f"{directory_name}/{name}.png")
            )
        for metadata in ("source-notes.md", "acceptance-metrics.json"):
            if not (directory / metadata).is_file():
                errors.append(f"{directory_name}/{metadata}: missing")
        if level >= 2:
            for provenance in (
                "blink-imagegen-source.png",
                "mouth-neutral-imagegen-source.png",
            ):
                if not (directory / provenance).is_file():
                    errors.append(
                        f"{directory_name}/{provenance}: missing"
                    )

        original = source_path(reference_root, level)
        if not original.is_file():
            errors.append(
                f"Squirrel_Growth_Level_{level}.png: immutable source missing"
            )
        elif enforce_immutable_hashes and sha256(original) != SOURCE_HASHES[level]:
            errors.append(
                f"Squirrel_Growth_Level_{level}.png: immutable source checksum mismatch"
            )

        for part in PARTS:
            part_path = directory / f"{part}.png"
            if part_path.is_file():
                part_hashes[part].append((level, sha256(part_path)))

        if any(not path.is_file() for path in paths.values()) or not original.is_file():
            continue
        source_file_hash = sha256(original)
        source_hashes.append((level, source_file_hash))
        if sha256(paths["reference-flat"]) != source_file_hash:
            errors.append(
                f"{directory_name}/reference-flat.png: must be the exact immutable source file"
            )
        rest_file_hash = sha256(paths["composite-rest"])
        source_pixels = None
        try:
            if rest_file_hash != source_file_hash:
                source_pixels = decode_rgba_png(original)[2]
                rest_pixels = decode_rgba_png(paths["composite-rest"])[2]
                if rest_pixels != source_pixels:
                    errors.append(
                        f"{directory_name}/composite-rest.png: must match its immutable source pixels"
                    )
            source_pixels = source_pixels or decode_rgba_png(original)[2]
            blink_pixels = decode_rgba_png(paths["composite-blink"])[2]
            celebrate_pixels = decode_rgba_png(
                paths["composite-celebrate"]
            )[2]
            neutral_pixels = decode_rgba_png(
                directory / "mouthNeutral.png"
            )[2]
            smile_pixels = decode_rgba_png(
                directory / "mouthSmile.png"
            )[2]
            closed_eye_pixels = decode_rgba_png(
                directory / "eyesClosed.png"
            )[2]
        except (OSError, ValueError, zlib.error) as error:
            errors.append(
                f"{directory_name}: cannot decode acceptance PNGs ({error})"
            )
            continue
        if sha256(paths["composite-blink"]) == rest_file_hash:
            errors.append(
                f"{directory_name}/composite-blink.png: must be a distinct closed-eye pose"
            )
        outside_changes = changed_outside_eye_boxes(
            source_pixels,
            blink_pixels,
            level,
        )
        if outside_changes:
            errors.append(
                f"{directory_name}/composite-blink.png: changed "
                f"{outside_changes} pixels outside the eye ROI"
            )
        if celebrate_pixels == source_pixels:
            errors.append(
                f"{directory_name}/composite-celebrate.png: must be a distinct pose"
            )
        visible_neutral_difference = 0
        neutral_alpha_pixels = 0
        hidden_rgb_pixels = 0
        for index in range(0, len(neutral_pixels), 4):
            neutral_pixel = neutral_pixels[index : index + 4]
            smile_pixel = smile_pixels[index : index + 4]
            neutral_alpha = neutral_pixel[3]
            smile_alpha = smile_pixel[3]
            if neutral_alpha:
                neutral_alpha_pixels += 1
            elif any(neutral_pixel[:3]):
                hidden_rgb_pixels += 1
            if (
                (neutral_alpha or smile_alpha)
                and neutral_pixel != smile_pixel
            ):
                visible_neutral_difference += 1
        if visible_neutral_difference < 100:
            errors.append(
                f"{directory_name}/mouthNeutral.png: must differ meaningfully from mouthSmile.png"
            )
        if neutral_alpha_pixels == 0:
            errors.append(
                f"{directory_name}/mouthNeutral.png: alpha must not be empty"
            )
        if hidden_rgb_pixels:
            errors.append(
                f"{directory_name}/mouthNeutral.png: transparent pixels must have zero RGB"
            )
        if any(
            closed_eye_pixels[index + 3] == 0
            and any(closed_eye_pixels[index : index + 3])
            for index in range(0, len(closed_eye_pixels), 4)
        ):
            errors.append(
                f"{directory_name}/eyesClosed.png: transparent pixels must have zero RGB"
            )

    if len(source_hashes) == 7 and len({value for _, value in source_hashes}) != 7:
        errors.append("growth levels must use seven distinct immutable source images")
    reused_parts = [
        part
        for part, values in part_hashes.items()
        if len(values) == 7 and len({value for _, value in values}) != 7
    ]
    if reused_parts:
        errors.append(
            "growth levels must not reuse identical semantic part files: "
            + ", ".join(reused_parts)
        )
    return errors


def main():
    arguments = parse_arguments()
    errors = []
    rig = load_json(arguments.rig_spec, errors)
    motion = load_json(arguments.motion_spec, errors)
    domain = load_json(arguments.domain_contract, errors)
    domain_motion_states = (
        domain.get("motionStates") if isinstance(domain, dict) else None
    )
    errors.extend(validate_specs(rig, motion, domain_motion_states))
    asset_errors = validate_asset_paths(arguments.root)
    errors.extend(asset_errors)
    if not asset_errors:
        errors.extend(
            validate_acceptance_assets(arguments.root, arguments.source_root)
        )

    if errors:
        print("mascot-rig-validation: FAIL", file=sys.stderr)
        print("\n".join(errors), file=sys.stderr)
        return 1

    print("77 parts: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
