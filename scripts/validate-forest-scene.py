#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import struct
import sys
import zlib


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACT_PATH = (
    REPOSITORY_ROOT / "contracts/native-rebuild/v1/forest-scene.json"
)
MASTER_SIZE = (1290, 2796)
RUNTIME_SIZE = (860, 1864)
LAYER_ORDER = [
    "sky",
    "distantTrees",
    "midgroundTrees",
    "foregroundLeaves",
    "ground",
]
REFERENCE_HASHES = {
    "references/intro.png": (
        (853, 1844),
        "954f62cb4c5989d0acb24e63f731025746d9bac09266a9905def32dabd4dc365",
    ),
    "references/home.png": (
        (1672, 941),
        "94566b4593a99918d79c5f2cac1927714474c47afeadb842ade48e66e80d0ee7",
    ),
}
APPROVAL_HASHES = {
    "master-1290x2796.png": (
        "bdcac1d944964362177f4a081cb97a22333ee08c8e4ab7029564e134dcf4cc42"
    ),
    "acceptance-rest.png": (
        "d0824aa43fe7a16c5273094b45395a031d8da65473757c4490ea611287217983"
    ),
    "acceptance-max-motion.png": (
        "bc2d8a6640558884e3bfaad8456f3d8528db02bfc0f27d0db56e7adcbdf57251"
    ),
}


class PNGError(ValueError):
    pass


def read_png(path: pathlib.Path, *, decode_pixels: bool = False):
    try:
        data = path.read_bytes()
    except OSError as error:
        raise PNGError(str(error)) from error
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise PNGError("not a PNG")

    position = 8
    header = None
    compressed = bytearray()
    while position + 12 <= len(data):
        length = struct.unpack(">I", data[position : position + 4])[0]
        chunk_type = data[position + 4 : position + 8]
        payload_start = position + 8
        payload_end = payload_start + length
        crc_end = payload_end + 4
        if crc_end > len(data):
            raise PNGError("truncated PNG chunk")
        payload = data[payload_start:payload_end]
        if chunk_type == b"IHDR":
            if length != 13:
                raise PNGError("invalid IHDR")
            header = struct.unpack(">IIBBBBB", payload)
        elif chunk_type == b"IDAT":
            compressed.extend(payload)
        elif chunk_type == b"IEND":
            break
        position = crc_end

    if header is None:
        raise PNGError("missing IHDR")
    width, height, bit_depth, color_type, compression, filtering, interlace = header
    if (
        bit_depth != 8
        or color_type not in {2, 6}
        or compression != 0
        or filtering != 0
        or interlace != 0
    ):
        raise PNGError("requires non-interlaced 8-bit RGB or RGBA PNG")

    rows = None
    if decode_pixels:
        rows = decode_rows(
            bytes(compressed),
            width=width,
            height=height,
            bytes_per_pixel=3 if color_type == 2 else 4,
        )
    return (width, height, color_type, data, rows)


def decode_rows(
    compressed: bytes,
    *,
    width: int,
    height: int,
    bytes_per_pixel: int,
) -> list[bytearray]:
    try:
        raw = zlib.decompress(compressed)
    except zlib.error as error:
        raise PNGError(f"invalid compressed pixels: {error}") from error
    stride = width * bytes_per_pixel
    expected_length = height * (stride + 1)
    if len(raw) != expected_length:
        raise PNGError(
            f"unexpected pixel payload length {len(raw)}; expected {expected_length}"
        )

    rows = []
    previous = bytearray(stride)
    position = 0
    for _ in range(height):
        filter_type = raw[position]
        row = bytearray(raw[position + 1 : position + stride + 1])
        position += stride + 1
        if filter_type not in range(5):
            raise PNGError(f"unsupported PNG filter {filter_type}")
        for index in range(stride):
            left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            above = previous[index]
            upper_left = (
                previous[index - bytes_per_pixel]
                if index >= bytes_per_pixel
                else 0
            )
            if filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                predictor = paeth(left, above, upper_left)
            else:
                predictor = 0
            row[index] = (row[index] + predictor) & 0xFF
        rows.append(row)
        previous = row
    return rows


def paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def edge_has_transparency(rows: list[bytearray], width: int, edge: int = 12) -> bool:
    alpha_index = 3
    bytes_per_pixel = 4
    for y, row in enumerate(rows):
        for x in range(width):
            if (
                y < edge
                or y >= len(rows) - edge
                or x < edge
                or x >= width - edge
            ) and row[x * bytes_per_pixel + alpha_index] == 0:
                return True
    return False


def validate(root: pathlib.Path) -> list[str]:
    errors = []
    try:
        contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"forest-scene.json: {error}"]

    required_art = [
        "master-1290x2796.png",
        "acceptance-rest.png",
        "acceptance-max-motion.png",
        *[f"{name}.png" for name in LAYER_ORDER],
    ]
    for relative in required_art:
        if not (root / relative).is_file():
            errors.append(f"{relative}: missing")

    layer_hashes = []
    for name in LAYER_ORDER:
        filename = f"{name}.png"
        path = root / filename
        if not path.is_file():
            continue
        try:
            width, height, color_type, data, rows = read_png(
                path,
                decode_pixels=name != "sky",
            )
        except PNGError as error:
            errors.append(f"{filename}: {error}")
            continue
        if (width, height) != MASTER_SIZE:
            errors.append(
                f"{filename}: expected {MASTER_SIZE[0]}x{MASTER_SIZE[1]}, "
                f"found {width}x{height}"
            )
        expected_type = 2 if name == "sky" else 6
        if color_type != expected_type:
            errors.append(
                f"{filename}: expected PNG color type {expected_type}, "
                f"found {color_type}"
            )
        if name != "sky" and rows is not None and not edge_has_transparency(rows, width):
            errors.append(
                f"{filename}: outer 12px edge must retain transparent pixels"
            )
        digest = hashlib.sha256(data).hexdigest()
        layer_hashes.append(digest)
        expected_digest = contract.get("layers", {}).get(name, {}).get("masterSha256")
        if digest != expected_digest:
            errors.append(f"{filename}: SHA-256 does not match forest-scene.json")

    if len(layer_hashes) == len(LAYER_ORDER) and len(set(layer_hashes)) != len(layer_hashes):
        errors.append("layer hashes must be unique")

    for filename in [
        "master-1290x2796.png",
        "acceptance-rest.png",
        "acceptance-max-motion.png",
    ]:
        path = root / filename
        if not path.is_file():
            continue
        try:
            width, height, color_type, data, _ = read_png(path)
        except PNGError as error:
            errors.append(f"{filename}: {error}")
            continue
        if (width, height) != MASTER_SIZE:
            errors.append(
                f"{filename}: expected {MASTER_SIZE[0]}x{MASTER_SIZE[1]}, "
                f"found {width}x{height}"
            )
        if color_type != 2:
            errors.append(f"{filename}: expected PNG color type 2, found {color_type}")
        if hashlib.sha256(data).hexdigest() != APPROVAL_HASHES[filename]:
            errors.append(f"{filename}: approved SHA-256 changed")

    for relative, (expected_size, expected_hash) in REFERENCE_HASHES.items():
        path = root / relative
        if not path.is_file():
            errors.append(f"{relative}: missing")
            continue
        try:
            width, height, color_type, data, _ = read_png(path)
        except PNGError as error:
            errors.append(f"{relative}: {error}")
            continue
        if (width, height) != expected_size or color_type != 2:
            errors.append(
                f"{relative}: expected {expected_size[0]}x{expected_size[1]} RGB"
            )
        if hashlib.sha256(data).hexdigest() != expected_hash:
            errors.append(f"{relative}: immutable reference hash changed")

    memory = contract.get("memory", {})
    expected_forest = RUNTIME_SIZE[0] * RUNTIME_SIZE[1] * 4 * len(LAYER_ORDER)
    expected_mascot = 1254 * 1254 * 4 * 3
    expected_combined = expected_forest + expected_mascot
    if memory.get("forestDecodedBytes") != expected_forest:
        errors.append("forest-scene.json: forest decoded-byte calculation drifted")
    if memory.get("activeMascotDecodedBytes") != expected_mascot:
        errors.append("forest-scene.json: mascot decoded-byte calculation drifted")
    if memory.get("combinedDecodedBytes") != expected_combined:
        errors.append("forest-scene.json: combined decoded-byte calculation drifted")
    if expected_forest > memory.get("forestLimitBytes", -1):
        errors.append("forest-scene.json: forest decoded memory exceeds limit")
    if expected_combined > memory.get("combinedLimitBytes", -1):
        errors.append("forest-scene.json: combined decoded memory exceeds limit")

    runtime_roots = [
        REPOSITORY_ROOT / "NaymNaymLevelUp/Resources/ForestScene/Home",
        REPOSITORY_ROOT / "android/app/src/main/res/drawable-nodpi",
    ]
    for runtime_root in runtime_roots:
        for name in LAYER_ORDER:
            layer = contract.get("layers", {}).get(name, {})
            filename = layer.get("runtimeFilename")
            if not isinstance(filename, str):
                errors.append(f"forest-scene.json: {name} runtime filename missing")
                continue
            path = runtime_root / filename
            if not path.is_file():
                errors.append(f"{path.relative_to(REPOSITORY_ROOT)}: missing")
                continue
            try:
                width, height, color_type, data, _ = read_png(path)
            except PNGError as error:
                errors.append(f"{path.relative_to(REPOSITORY_ROOT)}: {error}")
                continue
            if (width, height) != RUNTIME_SIZE:
                errors.append(
                    f"{path.relative_to(REPOSITORY_ROOT)}: expected "
                    f"{RUNTIME_SIZE[0]}x{RUNTIME_SIZE[1]}"
                )
            if color_type != layer.get("pngColorType"):
                errors.append(
                    f"{path.relative_to(REPOSITORY_ROOT)}: PNG color type drifted"
                )
            if hashlib.sha256(data).hexdigest() != layer.get("runtimeSha256"):
                errors.append(
                    f"{path.relative_to(REPOSITORY_ROOT)}: runtime SHA-256 drifted"
                )
        if runtime_root.name == "Home":
            expected_files = {
                contract["layers"][name]["runtimeFilename"]
                for name in LAYER_ORDER
            }
            actual_files = {path.name for path in runtime_root.glob("*.png")}
            if actual_files != expected_files:
                errors.append(
                    "NaymNaymLevelUp/Resources/ForestScene/Home: "
                    "must contain only the five runtime layers"
                )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=pathlib.Path,
        default=REPOSITORY_ROOT / "art/forest-scene/home",
    )
    args = parser.parse_args()
    errors = validate(args.root.resolve())
    if errors:
        for error in errors:
            print(f"forest-scene: {error}", file=sys.stderr)
        return 1

    forest_mib = 32060800 / (1024 * 1024)
    combined_mib = 50930992 / (1024 * 1024)
    print(
        "forest-scene: PASS "
        f"(forest {forest_mib:.3f} MiB; combined {combined_mib:.3f} MiB; "
        "10 checksum-matched runtime copies)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
