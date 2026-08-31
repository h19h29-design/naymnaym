import json
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
READINESS = ROOT / "scripts/verify-release-readiness.sh"
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

    def test_local_app_gate_requires_debug_and_release_platform_identity(self):
        source = READINESS.read_text(encoding="utf-8")
        function = source.split("check_local_app() {", 1)[1].split("\ngit diff --check", 1)[0]

        self.assertIn('require_plist_value "$app_dir/Info.plist" "DTPlatformName" "$expected_platform"', function)
        self.assertRegex(
            function,
            r'Debug\).*expected_platform="iphonesimulator"',
        )
        self.assertRegex(function, r'Release\).*expected_platform="iphoneos"')

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


if __name__ == "__main__":
    unittest.main()
