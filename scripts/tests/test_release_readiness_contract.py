import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
READINESS = ROOT / "scripts/verify-release-readiness.sh"
SCREENSHOT_CHECKER = ROOT / "scripts/check-app-store-screenshot-manifest.sh"
LOCAL_APP_CHECKER = ROOT / "scripts/check-local-app.sh"
RELEASE_UPLOAD_CHECKER = ROOT / "scripts/check-release-upload-disabled.sh"
SCREENSHOTS = ROOT / "docs/APP_STORE_SCREENSHOTS.md"
PLAY_METADATA = ROOT / "release/GooglePlayMetadata/play-console-values.md"
IOS_METADATA = ROOT / "docs/APP_STORE_METADATA.md"
ASC_VALUES = ROOT / "release/AppStoreMetadata/app-store-connect-values.json"
KO_METADATA = ROOT / "release/AppStoreMetadata/ko-KR.md"
PRIVACY_DRAFT = ROOT / "release/AppStoreMetadata/app-privacy-draft.md"

CURRENT_IOS_SCREENSHOT_MANIFEST = [
    "01-onboarding-demo.jpg",
    "02-today-meal-icons.jpg",
    "03-weekly-meal.jpg",
    "04-monthly-meal.jpg",
    "05-selected-day-detail.jpg",
    "06-eating-status-picker.jpg",
    "07-allergy-safe-choice.jpg",
    "08-growth-stage-roadmap.jpg",
    "09-growth-next-unlock.jpg",
    "10-parent-growth-summary.jpg",
]


class ReleaseReadinessContractTests(unittest.TestCase):
    def test_screenshot_manifest_checker_accepts_an_exact_fixture(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = pathlib.Path(temporary_directory)
            (directory / "01-screen.jpg").touch()

            result = self._run_screenshot_manifest_checker(
                directory,
                expected_count=1,
                manifest=["01-screen.jpg"],
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("App Store screenshot count is 1", result.stdout)
        self.assertIn("contains only the current manifest", result.stdout)

    def test_screenshot_manifest_checker_rejects_missing_manifest_file(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = pathlib.Path(temporary_directory)
            (directory / "other.jpg").touch()

            result = self._run_screenshot_manifest_checker(
                directory,
                expected_count=1,
                manifest=["01-screen.jpg"],
            )

        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(
            f"Missing App Store screenshot file: {directory}/01-screen.jpg",
            result.stderr,
        )

    def test_screenshot_manifest_checker_rejects_option_like_extra_files(self):
        for extra_file in ("-V", "--version"):
            with self.subTest(extra_file=extra_file), tempfile.TemporaryDirectory() as temporary_directory:
                directory = pathlib.Path(temporary_directory)
                (directory / "01-screen.jpg").touch()
                (directory / extra_file).touch()

                result = self._run_screenshot_manifest_checker(
                    directory,
                    expected_count=1,
                    manifest=["01-screen.jpg"],
                )

            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn(
                "App Store screenshot file count is 2, expected exactly 1",
                result.stderr,
            )

    def test_screenshot_manifest_checker_rejects_a_single_newline_named_extra_file(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = pathlib.Path(temporary_directory)
            (directory / "01-screen.jpg").touch()
            (directory / "\n").touch()

            result = self._run_screenshot_manifest_checker(
                directory,
                expected_count=1,
                manifest=["01-screen.jpg"],
            )

        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(
            "App Store screenshot file count is 2, expected exactly 1",
            result.stderr,
        )

    def test_local_app_checker_rejects_debug_bundle_as_release(self):
        if not pathlib.Path("/usr/libexec/PlistBuddy").is_file():
            self.skipTest("PlistBuddy is required for local app identity checks")

        with tempfile.TemporaryDirectory() as temporary_directory:
            app_directory = pathlib.Path(temporary_directory) / "NaymNaymLevelUp.app"
            self._write_local_app_fixture(app_directory, "iphonesimulator")

            result = self._run_local_app_checker(app_directory, "Release")

        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(
            "DTPlatformName is 'iphonesimulator', expected 'iphoneos'",
            result.stderr,
        )

    def test_local_app_checker_accepts_matching_debug_and_release_platforms(self):
        if not pathlib.Path("/usr/libexec/PlistBuddy").is_file():
            self.skipTest("PlistBuddy is required for local app identity checks")

        for configuration, platform in (
            ("Debug", "iphonesimulator"),
            ("Release", "iphoneos"),
        ):
            with self.subTest(configuration=configuration), tempfile.TemporaryDirectory() as temporary_directory:
                app_directory = pathlib.Path(temporary_directory) / "NaymNaymLevelUp.app"
                self._write_local_app_fixture(app_directory, platform)

                result = self._run_local_app_checker(app_directory, configuration)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                f"{configuration} app matches the expected candidate",
                result.stdout,
            )

    def test_release_upload_checker_skips_artifacts_when_not_required(self):
        result = self._run_release_upload_checker()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "Signed archive, export IPA, and upload-log checks skipped because RELEASE_UPLOAD_REQUIRED=0",
            result.stdout,
        )

    def test_release_upload_checker_refuses_when_upload_is_required(self):
        environment = self._readiness_environment()
        environment["RELEASE_UPLOAD_REQUIRED"] = "1"
        result = subprocess.run(
            ["sh", str(RELEASE_UPLOAD_CHECKER)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            env=environment,
        )

        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(
            "check-release-upload-disabled.sh requires RELEASE_UPLOAD_REQUIRED=0",
            result.stderr,
        )

    def test_normal_flow_with_upload_disabled_reaches_post_upload_screenshot_gate(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            fixture = self._make_readiness_fixture(
                pathlib.Path(temporary_directory),
                screenshot_source=ROOT
                / "NaymNaymLevelUp/Resources/Assets.xcassets/"
                "AppIcon.appiconset/AppIcon-20@2x.png",
            )

            result = self._run_readiness(fixture)

        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("PASS: Debug app matches the expected candidate", result.stdout)
        self.assertIn("PASS: Release app matches the expected candidate", result.stdout)
        skip_marker = (
            "Signed archive, export IPA, and upload-log checks skipped because "
            "RELEASE_UPLOAD_REQUIRED=0"
        )
        screenshot_marker = (
            f"PASS: Found {fixture['screenshot_directory']}/"
            f"{CURRENT_IOS_SCREENSHOT_MANIFEST[0]}"
        )
        self.assertIn(skip_marker, result.stdout)
        self.assertIn(screenshot_marker, result.stdout)
        self.assertLess(result.stdout.index(skip_marker), result.stdout.index(screenshot_marker))
        self.assertIn(
            f"{fixture['screenshot_directory']}/{CURRENT_IOS_SCREENSHOT_MANIFEST[0]} "
            "width is 40, expected 1320",
            result.stderr,
        )

    def test_local_app_gate_requires_debug_and_release_platform_identity(self):
        source = LOCAL_APP_CHECKER.read_text(encoding="utf-8")

        self.assertIn('require_plist_value "$app_dir/Info.plist" "DTPlatformName" "$expected_platform"', source)
        self.assertRegex(
            source,
            r'Debug\).*expected_platform="iphonesimulator"',
        )
        self.assertRegex(source, r'Release\).*expected_platform="iphoneos"')

    def test_current_ios_screenshot_manifest_is_explicit_and_mirrored(self):
        readiness = READINESS.read_text(encoding="utf-8")
        match = re.search(
            r"APP_STORE_SCREENSHOT_MANIFEST='(.*?)'",
            readiness,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match, "readiness must declare the current screenshot manifest")
        script_manifest = [
            line.strip()
            for line in match.group(1).splitlines()
            if line.strip()
        ]
        self.assertEqual(script_manifest, CURRENT_IOS_SCREENSHOT_MANIFEST)

        docs = SCREENSHOTS.read_text(encoding="utf-8")
        table_names = re.findall(
            r"^\|\s*[0-9]+\s*\|\s*`([^`]+)`\s*\|",
            docs,
            flags=re.MULTILINE,
        )
        self.assertEqual(table_names, CURRENT_IOS_SCREENSHOT_MANIFEST)
        self.assertIn("1.2", docs)
        self.assertIn("정확히 10장", docs)

    def test_android_play_metadata_matches_authoritative_gradle_candidate(self):
        gradle = (ROOT / "android/app/build.gradle").read_text(encoding="utf-8")
        version_code = re.search(r"^\s*versionCode\s+(\d+)", gradle, re.MULTILINE)
        version_name = re.search(r'^\s*versionName\s+"([^"]+)"', gradle, re.MULTILINE)
        self.assertIsNotNone(version_code)
        self.assertIsNotNone(version_name)

        play = PLAY_METADATA.read_text(encoding="utf-8")
        self.assertIn(f"- 버전: `{version_name.group(1)}`", play)
        self.assertIn(f"- versionCode: `{version_code.group(1)}`", play)

    def test_app_store_subtitle_is_shared_by_the_three_metadata_sources(self):
        values = json.loads(ASC_VALUES.read_text(encoding="utf-8"))
        subtitle = values["appInfo"]["subtitle"]
        for path in (IOS_METADATA, KO_METADATA):
            text = path.read_text(encoding="utf-8")
            self.assertIn(f"- 부제: {subtitle}", text)

    def test_privacy_draft_uses_published_privacy_url(self):
        text = PRIVACY_DRAFT.read_text(encoding="utf-8")
        self.assertIn("https://nyam.h19h19.com/privacy.html", text)
        self.assertNotIn("https://h19h29-design.github.io/naymnaym/privacy.html", text)

    def _run_readiness(self, fixture):
        environment = self._readiness_environment()
        environment.update(
            {
                "APP_STORE_SCREENSHOT_DIR": str(fixture["screenshot_directory"]),
                "LOCAL_DEBUG_APP_PATH": str(fixture["debug_app"]),
                "LOCAL_RELEASE_APP_PATH": str(fixture["release_app"]),
            }
        )
        return subprocess.run(
            [str(READINESS)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            env=environment,
        )

    def _run_screenshot_manifest_checker(self, directory, expected_count, manifest):
        return subprocess.run(
            ["sh", str(SCREENSHOT_CHECKER), str(directory), str(expected_count)],
            cwd=ROOT,
            input="\n".join(manifest) + "\n",
            capture_output=True,
            text=True,
        )

    def _run_local_app_checker(self, app_directory, configuration):
        return subprocess.run(
            ["sh", str(LOCAL_APP_CHECKER), str(app_directory), configuration],
            cwd=ROOT,
            capture_output=True,
            text=True,
            env=self._readiness_environment(),
        )

    def _run_release_upload_checker(self):
        return subprocess.run(
            ["sh", str(RELEASE_UPLOAD_CHECKER)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            env=self._readiness_environment(),
        )

    def _readiness_environment(self):
        environment = os.environ.copy()
        environment.update(
            {
                "EXPECTED_MARKETING_VERSION": "1.2",
                "EXPECTED_BUILD_NUMBER": "33",
                "RELEASE_UPLOAD_REQUIRED": "0",
            }
        )
        return environment

    def _make_readiness_fixture(
        self,
        temporary_directory,
        *,
        release_platform="iphoneos",
        screenshot_source=None,
    ):
        screenshot_source = screenshot_source or (
            ROOT / "docs/app-store-screenshots/iphone-6-9-upload/01-today-forest.jpg"
        )
        screenshot_directory = temporary_directory / "screenshots"
        screenshot_directory.mkdir()
        for name in CURRENT_IOS_SCREENSHOT_MANIFEST:
            shutil.copyfile(screenshot_source, screenshot_directory / name)

        debug_app = temporary_directory / "Debug/NaymNaymLevelUp.app"
        release_app = temporary_directory / "Release/NaymNaymLevelUp.app"
        self._write_local_app_fixture(debug_app, "iphonesimulator")
        self._write_local_app_fixture(release_app, release_platform)
        return {
            "screenshot_directory": screenshot_directory,
            "debug_app": debug_app,
            "release_app": release_app,
        }

    def _write_local_app_fixture(self, app_directory, platform):
        app_directory.mkdir(parents=True)
        info = {
            "CFBundleIdentifier": "com.h19h29.naymnaymlevelup",
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "33",
            "CFBundleDisplayName": "급식레벨업",
            "DTPlatformName": platform,
        }
        (app_directory / "Info.plist").write_bytes(plistlib.dumps(info))


if __name__ == "__main__":
    unittest.main()
