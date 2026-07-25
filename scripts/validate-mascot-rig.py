#!/usr/bin/env python3

import argparse
import json
import pathlib
import struct
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "contracts/native-rebuild/v1"
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
    errors.extend(validate_asset_paths(arguments.root))

    if errors:
        print("mascot-rig-validation: FAIL", file=sys.stderr)
        print("\n".join(errors), file=sys.stderr)
        return 1

    print("77 parts: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
