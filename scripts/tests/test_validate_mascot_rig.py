import json
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib


ROOT = pathlib.Path(__file__).resolve().parents[2]
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
ACCEPTANCE_FILES = [
    "reference-flat.png",
    "composite-rest.png",
    "composite-blink.png",
    "composite-celebrate.png",
    "source-notes.md",
    "acceptance-metrics.json",
]


class MascotRigValidatorTests(unittest.TestCase):
    def test_reports_missing_parts_for_every_level(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = self._run_validator(pathlib.Path(temporary_directory))

        self.assertNotEqual(result.returncode, 0)
        diagnostics = result.stderr.splitlines()
        self.assertEqual(diagnostics[0], "mascot-rig-validation: FAIL")
        self.assertEqual(diagnostics[1], "level-01/tailBack.png: missing")
        self.assertEqual(diagnostics[-1], "level-07/sprout.png: missing")
        self.assertEqual(len(diagnostics), 78)
        self.assertNotIn("Traceback", result.stderr)

    def test_accepts_seven_complete_unique_growth_rig_fixtures(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            asset_root = pathlib.Path(temporary_directory)
            self._populate_valid_assets(asset_root)

            result = self._run_validator(asset_root)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "77 parts: PASS\n")
        self.assertEqual(result.stderr, "")

    def test_rejects_reused_part_files_across_growth_levels(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            asset_root = pathlib.Path(temporary_directory)
            self._populate_valid_assets(
                asset_root,
                unique_parts=False,
            )

            result = self._run_validator(asset_root)

        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "growth levels must not reuse identical semantic part files",
            result.stderr,
        )

    def test_rejects_missing_acceptance_composites_and_reference_sources(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            asset_root = pathlib.Path(temporary_directory)
            self._populate_valid_assets(asset_root)
            for level in range(1, 8):
                directory = asset_root / f"level-{level:02d}"
                for name in ACCEPTANCE_FILES:
                    (directory / name).unlink()

            result = self._run_validator(asset_root)

        self.assertEqual(result.returncode, 1)
        self.assertIn("level-01/reference-flat.png: missing", result.stderr)
        self.assertIn("level-07/composite-celebrate.png: missing", result.stderr)

    def test_rejects_visually_identical_neutral_and_smile_mouths(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            asset_root = pathlib.Path(temporary_directory)
            self._populate_valid_assets(asset_root)
            directory = asset_root / "level-03"
            shutil.copy2(
                directory / "mouthSmile.png",
                directory / "mouthNeutral.png",
            )

            result = self._run_validator(asset_root)

        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "level-03/mouthNeutral.png: must differ meaningfully",
            result.stderr,
        )

    def test_reports_all_signature_dimension_color_and_missing_errors(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            asset_root = pathlib.Path(temporary_directory)
            self._populate_valid_assets(asset_root)
            self._write_png(
                asset_root / "level-01/tailBack.png",
                signature=b"not-png!",
            )
            self._write_png(
                asset_root / "level-02/body.png",
                width=1253,
                height=1255,
            )
            self._write_png(
                asset_root / "level-03/scarf.png",
                color_type=2,
            )
            (asset_root / "level-04/head.png").unlink()

            result = self._run_validator(asset_root)

        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            result.stderr.splitlines(),
            [
                "mascot-rig-validation: FAIL",
                "level-01/tailBack.png: invalid PNG signature",
                "level-02/body.png: dimensions must be 1254x1254, got 1253x1255",
                "level-03/scarf.png: color type must be 6 (RGBA), got 2",
                "level-04/head.png: missing",
            ],
        )
        self.assertNotIn("Traceback", result.stderr)

    def test_rejects_every_non_exact_rig_field_without_skipping_asset_paths(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = pathlib.Path(temporary_directory)
            asset_root = temporary / "assets"
            self._populate_valid_assets(asset_root)
            rig = self._rig_spec()
            rig["version"] = True
            rig["levels"][0]["canvas"]["width"] = 1253
            rig["levels"][1]["parts"] = PARTS[:-1]
            rig["levels"][2]["anchor"]["x"] = 626
            rig["levels"][3]["level"] = 3
            rig["levels"][4]["extra"] = "not allowed"
            rig_path = temporary / "mascot-rig.json"
            rig_path.write_text(json.dumps(rig), encoding="utf-8")

            result = self._run_validator(asset_root, rig_spec=rig_path)

        self.assertEqual(result.returncode, 1)
        for diagnostic in (
            "mascot-rig.json: version must be exactly integer 1",
            "mascot-rig.json: levels must define exact levels 1 through 7",
            "mascot-rig.json: levels[0].canvas must be 1254x1254",
            "mascot-rig.json: levels[1].parts must match the exact part order",
            "mascot-rig.json: levels[2].anchor must be (627, 1128)",
            "mascot-rig.json: levels[4] must contain only level, canvas, parts, and anchor",
        ):
            self.assertIn(diagnostic, result.stderr)
        self.assertNotIn("missing", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_motion_spec_requires_exact_domain_states_timing_and_loop_values(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = pathlib.Path(temporary_directory)
            asset_root = temporary / "assets"
            self._populate_valid_assets(asset_root)
            motion = self._motion_spec()
            motion["states"]["idle"]["loop"] = False
            motion["states"]["tapReaction"]["durationMs"] = 421
            motion["states"].pop("comfort")
            motion["states"]["spin"] = {"durationMs": 1, "loop": True}
            motion_path = temporary / "mascot-motion.json"
            motion_path.write_text(json.dumps(motion), encoding="utf-8")

            result = self._run_validator(asset_root, motion_spec=motion_path)

        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "mascot-motion.json: states must match domain-contract.json motionStates in exact order",
            result.stderr,
        )
        self.assertIn(
            "mascot-motion.json: idle must use durationMs 6000 and loop true",
            result.stderr,
        )
        self.assertIn(
            "mascot-motion.json: tapReaction must use durationMs 420 and loop false",
            result.stderr,
        )
        self.assertIn(
            "mascot-motion.json: comfort must use durationMs 1200 and loop false",
            result.stderr,
        )
        self.assertNotIn("Traceback", result.stderr)

    def test_motion_state_cross_check_rejects_domain_drift(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = pathlib.Path(temporary_directory)
            asset_root = temporary / "assets"
            self._populate_valid_assets(asset_root)
            domain = json.loads(
                (ROOT / "contracts/native-rebuild/v1/domain-contract.json").read_text(
                    encoding="utf-8"
                )
            )
            domain["motionStates"] = domain["motionStates"][:-1]
            domain_path = temporary / "domain-contract.json"
            domain_path.write_text(json.dumps(domain), encoding="utf-8")

            result = self._run_validator(
                asset_root,
                domain_contract=domain_path,
            )

        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "mascot-motion.json: states must match domain-contract.json motionStates in exact order",
            result.stderr,
        )
        self.assertNotIn("Traceback", result.stderr)

    def test_missing_and_malformed_contracts_have_complete_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = pathlib.Path(temporary_directory)
            malformed_domain = temporary / "domain-contract.json"
            malformed_domain.write_text("{", encoding="utf-8")

            result = self._run_validator(
                temporary / "assets",
                rig_spec=temporary / "missing-rig.json",
                motion_spec=temporary / "missing-motion.json",
                domain_contract=malformed_domain,
            )

        self.assertEqual(result.returncode, 1)
        self.assertIn("missing-rig.json: missing", result.stderr)
        self.assertIn("missing-motion.json: missing", result.stderr)
        self.assertIn("domain-contract.json: invalid JSON", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_native_contract_validator_rejects_mascot_motion_drift(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = pathlib.Path(temporary_directory)
            shutil.copytree(
                ROOT / "contracts/native-rebuild",
                project / "contracts/native-rebuild",
            )
            scripts = project / "scripts"
            scripts.mkdir()
            for name in (
                "validate-native-rebuild-contracts.py",
                "validate-mascot-rig.py",
            ):
                shutil.copy2(ROOT / "scripts" / name, scripts / name)
            motion_path = (
                project / "contracts/native-rebuild/v1/mascot-motion.json"
            )
            motion = json.loads(motion_path.read_text(encoding="utf-8"))
            motion["states"]["levelUp"]["durationMs"] = 2999
            motion_path.write_text(json.dumps(motion), encoding="utf-8")

            result = subprocess.run(
                [sys.executable, "scripts/validate-native-rebuild-contracts.py"],
                cwd=project,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "mascot-motion.json: levelUp must use durationMs 3000 and loop false",
            result.stderr,
        )
        self.assertNotIn("Traceback", result.stderr)

    def _run_validator(
        self,
        asset_root,
        rig_spec=None,
        motion_spec=None,
        domain_contract=None,
    ):
        arguments = [
            sys.executable,
            "scripts/validate-mascot-rig.py",
            "--root",
            str(asset_root),
        ]
        for flag, path in (
            ("--rig-spec", rig_spec),
            ("--motion-spec", motion_spec),
            ("--domain-contract", domain_contract),
        ):
            if path is not None:
                arguments.extend((flag, str(path)))
        fixture_sources = pathlib.Path(asset_root) / "fixture-sources"
        if fixture_sources.is_dir():
            arguments.extend(("--source-root", str(fixture_sources)))
        return subprocess.run(
            arguments,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    def _populate_valid_assets(self, asset_root, unique_parts=True):
        source_root = asset_root / "fixture-sources"
        for level in range(1, 8):
            directory = asset_root / f"level-{level:02d}"
            for part_index, part in enumerate(PARTS):
                level_color = level if unique_parts else 1
                self._write_rgba_png(
                    directory / f"{part}.png",
                    (
                        (level_color * 29 + part_index * 7) % 255,
                        (level_color * 41 + part_index * 11) % 255,
                        (level_color * 53 + part_index * 13) % 255,
                        255,
                    ),
                )
            source = (
                source_root
                / f"Squirrel_Growth_Level_{level}.imageset"
                / f"Squirrel_Growth_Level_{level}.png"
            )
            self._write_rgba_png(
                source,
                (level * 20, level * 23, level * 27, 255),
            )
            shutil.copy2(source, directory / "reference-flat.png")
            shutil.copy2(source, directory / "composite-rest.png")
            self._write_rgba_png(
                directory / "composite-blink.png",
                (level * 20, level * 23, level * 27, 255),
                edits={(450, 450): (1, 2, 3, 255)},
            )
            self._write_rgba_png(
                directory / "composite-celebrate.png",
                (level * 20, level * 23, level * 27, 255),
                edits={(600, 700): (3, 2, 1, 255)},
            )
            (directory / "source-notes.md").write_text(
                "fixture\n",
                encoding="utf-8",
            )
            (directory / "acceptance-metrics.json").write_text(
                json.dumps(
                    {
                        "parts": {
                            "mouthNeutral": {
                                "nonzeroAlphaPixels": 1254 * 1254
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            if level >= 2:
                (directory / "blink-imagegen-source.png").write_bytes(
                    b"fixture provenance"
                )
                (
                    directory / "mouth-neutral-imagegen-source.png"
                ).write_bytes(b"fixture provenance")

    def _write_rgba_png(self, path, color, edits=None):
        path.parent.mkdir(parents=True, exist_ok=True)
        width = height = 1254
        row = bytearray([0]) + bytearray(color) * width
        raw = bytearray(row * height)
        for (x, y), edit_color in (edits or {}).items():
            offset = y * (width * 4 + 1) + 1 + x * 4
            raw[offset : offset + 4] = bytes(edit_color)
        ihdr = struct.pack(
            ">IIBBBBB",
            width,
            height,
            8,
            6,
            0,
            0,
            0,
        )

        def chunk(name, data):
            payload = name + data
            return (
                struct.pack(">I", len(data))
                + payload
                + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)
            )

        path.write_bytes(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), level=9))
            + chunk(b"IEND", b"")
        )

    def _write_png(
        self,
        path,
        width=1254,
        height=1254,
        color_type=6,
        signature=b"\x89PNG\r\n\x1a\n",
    ):
        path.parent.mkdir(parents=True, exist_ok=True)
        ihdr = struct.pack(
            ">IIBBBBB",
            width,
            height,
            8,
            color_type,
            0,
            0,
            0,
        )
        path.write_bytes(
            signature
            + struct.pack(">I", len(ihdr))
            + b"IHDR"
            + ihdr
            + b"\x00\x00\x00\x00"
        )

    def _rig_spec(self):
        return {
            "version": 1,
            "levels": [
                {
                    "level": level,
                    "canvas": {"width": 1254, "height": 1254},
                    "parts": PARTS.copy(),
                    "anchor": {"x": 627, "y": 1128},
                }
                for level in range(1, 8)
            ],
        }

    def _motion_spec(self):
        return {
            "version": 1,
            "states": {
                name: values.copy() for name, values in MOTIONS.items()
            },
        }


if __name__ == "__main__":
    unittest.main()
