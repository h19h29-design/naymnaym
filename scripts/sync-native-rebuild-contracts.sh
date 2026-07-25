#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_DIRECTORY="$ROOT/contracts/native-rebuild/v1"
DESTINATIONS=(
  "$ROOT/NaymNaymLevelUp/Resources/RebuildContracts"
  "$ROOT/android/app/src/main/assets/rebuild-contracts"
)

shopt -s nullglob
SOURCES=("$SOURCE_DIRECTORY"/*.json)
if (( ${#SOURCES[@]} == 0 )); then
  echo "native-rebuild-contract-sync: FAIL (no canonical JSON files)" >&2
  exit 1
fi

fail() {
  echo "native-rebuild-contract-sync: FAIL ($1)" >&2
  exit 1
}

reject_symlinked_path_component() {
  local destination="$1"
  local relative_path="${destination#"$ROOT"/}"
  local current_path="$ROOT"
  local component

  if [[ "$relative_path" == "$destination" ]]; then
    fail "destination is outside the repository root"
  fi

  IFS='/' read -r -a components <<< "$relative_path"
  for component in "${components[@]}"; do
    current_path="$current_path/$component"
    if [[ -L "$current_path" ]]; then
      fail "symlinked destination path is not allowed: $destination"
    fi
  done
}

reject_unsafe_destination() {
  local destination="$1"
  local symlinked_json

  reject_symlinked_path_component "$destination"
  if [[ -e "$destination" && ! -d "$destination" ]]; then
    fail "destination is not a directory: $destination"
  fi
  if [[ -d "$destination" ]]; then
    symlinked_json="$(find "$destination" -type l -name '*.json' -print -quit)"
    if [[ -n "$symlinked_json" ]]; then
      fail "symlinked JSON target is not allowed: $symlinked_json"
    fi
  fi
}

# Validate every destination before creating, deleting, or copying any file.
for destination in "${DESTINATIONS[@]}"; do
  reject_unsafe_destination "$destination"
done

for destination in "${DESTINATIONS[@]}"; do
  mkdir -p "$destination"

  while IFS= read -r -d '' existing; do
    relative_path="${existing#"$destination"/}"
    if [[ ! -f "$SOURCE_DIRECTORY/$relative_path" ]]; then
      rm -f "$existing"
    fi
  done < <(find "$destination" -type f -name '*.json' -print0)

  for source in "${SOURCES[@]}"; do
    filename="$(basename "$source")"
    cp "$source" "$destination/$filename"
    source_hash="$(shasum -a 256 "$source" | awk '{print $1}')"
    destination_hash="$(shasum -a 256 "$destination/$filename" | awk '{print $1}')"
    if [[ "$source_hash" != "$destination_hash" ]]; then
      echo "native-rebuild-contract-sync: FAIL (checksum mismatch for $filename)" >&2
      exit 1
    fi
  done
done

echo "native-rebuild-contract-sync: PASS"
