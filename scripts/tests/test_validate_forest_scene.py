import pathlib
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib
import hashlib
import json


ROOT = pathlib.Path(__file__).resolve().parents[2]
APPROVED_ROOT = ROOT / "art/forest-scene/home"
VALIDATOR = ROOT / "scripts/validate-forest-scene.py"


def write_uniform_rgba_png(
    path: pathlib.Path,
    *,
    width: int = 1290,
    height: int = 2796,
    rgba: tuple[int, int, int, int] = (31, 94, 67, 255),
) -> None:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    row = b"\x00" + bytes(rgba) * width
    payload = zlib.compress(row * height, level=9)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", payload)
        + chunk(b"IEND", b"")
    )


def read_png_header(path: pathlib.Path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"{path} is not a PNG")
    width, height, bit_depth, color_type, _, _, _ = struct.unpack(
        ">IIBBBBB", data[16:29]
    )
    if bit_depth != 8:
        raise AssertionError(f"{path} is not 8-bit")
    return width, height, color_type, data, None


class ForestSceneValidatorTests(unittest.TestCase):
    def run_validator(self, root: pathlib.Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(VALIDATOR), "--root", str(root)],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    def test_approved_scene_satisfies_asset_and_memory_contract(self):
        result = self.run_validator(APPROVED_ROOT)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("forest-scene: PASS", result.stdout)
        self.assertIn("30.576 MiB", result.stdout)
        self.assertIn("48.572 MiB", result.stdout)
        self.assertIn("10 checksum-matched runtime copies", result.stdout)

    def test_runtime_bundles_use_only_exact_860_by_1864_derivatives(self):
        contract = json.loads(
            (ROOT / "contracts/native-rebuild/v1/forest-scene.json").read_text()
        )
        bundle_roots = [
            ROOT / "NaymNaymLevelUp/Resources/ForestScene/Home",
            ROOT / "android/app/src/main/res/drawable-nodpi",
        ]

        for name in contract["layerOrder"]:
            layer = contract["layers"][name]
            expected_hash = layer["runtimeSha256"]
            for bundle_root in bundle_roots:
                path = bundle_root / layer["runtimeFilename"]
                with self.subTest(layer=name, bundle=bundle_root):
                    width, height, color_type, data, _ = read_png_header(path)
                    self.assertEqual((width, height), (860, 1864))
                    self.assertEqual(color_type, layer["pngColorType"])
                    self.assertEqual(hashlib.sha256(data).hexdigest(), expected_hash)

        ios_bundle = bundle_roots[0]
        self.assertEqual(
            sorted(path.name for path in ios_bundle.glob("*.png")),
            sorted(
                contract["layers"][name]["runtimeFilename"]
                for name in contract["layerOrder"]
            ),
        )
        self.assertFalse((ios_bundle / "master-1290x2796.png").exists())

    def test_rejects_duplicate_layer_art_instead_of_five_distinct_depth_planes(self):
        with tempfile.TemporaryDirectory() as directory:
            scene = pathlib.Path(directory) / "home"
            shutil.copytree(APPROVED_ROOT, scene)
            shutil.copy2(scene / "distantTrees.png", scene / "midgroundTrees.png")

            result = self.run_validator(scene)

        self.assertEqual(result.returncode, 1)
        self.assertIn("layer hashes must be unique", result.stderr)

    def test_rejects_opaque_non_sky_edges_that_would_reveal_motion_seams(self):
        with tempfile.TemporaryDirectory() as directory:
            scene = pathlib.Path(directory) / "home"
            shutil.copytree(APPROVED_ROOT, scene)
            write_uniform_rgba_png(scene / "foregroundLeaves.png")

            result = self.run_validator(scene)

        self.assertEqual(result.returncode, 1)
        self.assertIn("foregroundLeaves.png: outer 12px edge", result.stderr)

    def test_rejects_master_dimensions_or_layer_color_type_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            scene = pathlib.Path(directory) / "home"
            shutil.copytree(APPROVED_ROOT, scene)
            shutil.copy2(scene / "foregroundLeaves.png", scene / "sky.png")
            write_uniform_rgba_png(
                scene / "ground.png",
                width=1289,
                rgba=(98, 113, 104, 0),
            )

            result = self.run_validator(scene)

        self.assertEqual(result.returncode, 1)
        self.assertIn("sky.png: expected PNG color type 2", result.stderr)
        self.assertIn("ground.png: expected 1290x2796", result.stderr)

    def test_rejects_approval_composite_hash_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            scene = pathlib.Path(directory) / "home"
            shutil.copytree(APPROVED_ROOT, scene)
            shutil.copy2(
                scene / "master-1290x2796.png",
                scene / "acceptance-rest.png",
            )

            result = self.run_validator(scene)

        self.assertEqual(result.returncode, 1)
        self.assertIn("acceptance-rest.png: approved SHA-256 changed", result.stderr)


if __name__ == "__main__":
    unittest.main()
