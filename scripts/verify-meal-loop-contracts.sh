#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ANDROID_ROOT="$ROOT/android"
DEFAULT_CODEX_JDK="$HOME/.cache/codex-jdk17/extracted/Contents/Home"
ASCII_BUILD_ROOT="${TMPDIR:-/tmp}/naym-meal-loop-gradle-build"
INIT_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/naym-meal-loop.XXXXXX.init.gradle")"

cleanup() {
  rm -f "$INIT_SCRIPT"
}
trap cleanup EXIT

java_specification_version() {
  "$1/bin/java" -XshowSettings:properties -version 2>&1 |
    awk -F= '/java.specification.version/ {
      value = $2
      gsub(/[[:space:]]/, "", value)
      print value
      exit
    }'
}

if [[
  -z "${JAVA_HOME:-}" ||
  ! -x "${JAVA_HOME:-}/bin/java" ||
  "$(java_specification_version "$JAVA_HOME")" != "17"
 ]]; then
  if [[ -x "$DEFAULT_CODEX_JDK/bin/java" ]]; then
    export JAVA_HOME="$DEFAULT_CODEX_JDK"
  elif [[ -x /usr/libexec/java_home ]]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 17)"
    export JAVA_HOME
  else
    echo "meal-loop-contracts: FAIL (JDK 17 not found)" >&2
    exit 1
  fi
fi
if [[ "$(java_specification_version "$JAVA_HOME")" != "17" ]]; then
  echo "meal-loop-contracts: FAIL (JDK 17 is required)" >&2
  exit 1
fi

export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export NAYM_ASCII_GRADLE_BUILD="$ASCII_BUILD_ROOT"
if [[ ! -d "$ANDROID_SDK_ROOT" ]]; then
  echo "meal-loop-contracts: FAIL (Android SDK not found)" >&2
  exit 1
fi

cat > "$INIT_SCRIPT" <<'GRADLE'
gradle.beforeProject { project ->
    def root = System.getenv("NAYM_ASCII_GRADLE_BUILD")
    if (root == null || root.isBlank()) {
        throw new GradleException("NAYM_ASCII_GRADLE_BUILD is required")
    }
    def safeProjectName = project.path == ":"
        ? "root"
        : project.path.substring(1).replace(":", "-")
    project.layout.buildDirectory.set(
        project.file(new File(root, safeProjectName))
    )
}
GRADLE

cd "$ROOT"
python3 scripts/tests/test_native_rebuild_contracts.py
(
  cd "$ANDROID_ROOT"
  ./gradlew \
    -I "$INIT_SCRIPT" \
    -Dorg.gradle.jvmargs="-Xmx3g -Dfile.encoding=UTF-8" \
    --max-workers=1 \
    testDebugUnitTest
)
git diff --check
git diff --cached --check

echo "meal-loop-contracts: PASS"
