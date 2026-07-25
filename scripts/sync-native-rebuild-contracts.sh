#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
