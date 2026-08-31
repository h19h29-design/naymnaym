#!/usr/bin/env python3
"""Validate an App Store screenshot directory against an exact filename manifest."""

from __future__ import annotations

import os
import stat
import sys


def fail(message: str) -> "NoReturn":
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def pass_message(message: str) -> None:
    print(f"PASS: {message}")


def read_manifest() -> list[str]:
    raw_manifest = sys.stdin.buffer.read()
    if raw_manifest and not raw_manifest.endswith(b"\0"):
        fail("App Store screenshot manifest must be NUL-delimited")

    if not raw_manifest:
        return []

    raw_entries = raw_manifest[:-1].split(b"\0")
    try:
        return [entry.decode("utf-8") for entry in raw_entries]
    except UnicodeDecodeError:
        fail("App Store screenshot manifest must contain UTF-8 filenames")


def main() -> None:
    if len(sys.argv) != 3:
        fail(f"Usage: {sys.argv[0]} DIRECTORY EXPECTED_FILE_COUNT < NUL-delimited manifest")

    directory = sys.argv[1]
    try:
        expected_count = int(sys.argv[2])
    except ValueError:
        fail("expected file count must be an integer")
    if expected_count < 0:
        fail("expected file count must not be negative")

    try:
        directory_stat = os.lstat(directory)
    except FileNotFoundError:
        fail(f"Missing App Store screenshot directory: {directory}")
    except OSError as error:
        fail(f"Could not inspect App Store screenshot directory {directory}: {error}")

    if stat.S_ISLNK(directory_stat.st_mode):
        fail(f"App Store screenshot directory must not be a symlink: {directory}")
    if not stat.S_ISDIR(directory_stat.st_mode):
        fail(f"App Store screenshot path is not a directory: {directory}")

    manifest = read_manifest()
    if len(manifest) != expected_count:
        fail(
            "App Store screenshot manifest contains "
            f"{len(manifest)} entries, expected exactly {expected_count}"
        )
    if len(set(manifest)) != len(manifest):
        fail("App Store screenshot manifest contains duplicate entries")

    path_separators = {"/", "\\"}
    for name in manifest:
        if not name or name in {".", ".."} or any(separator in name for separator in path_separators):
            fail(f"App Store screenshot manifest entry must be a plain filename: {name!r}")

    actual_names: list[str] = []
    try:
        with os.scandir(directory) as directory_entries:
            for entry in directory_entries:
                entry_stat = entry.stat(follow_symlinks=False)
                if stat.S_ISLNK(entry_stat.st_mode):
                    fail(f"App Store screenshot entry {entry.name!r} must be a regular file, not a symlink")
                if not stat.S_ISREG(entry_stat.st_mode):
                    fail(f"App Store screenshot entry {entry.name!r} must be a regular file")
                actual_names.append(entry.name)
    except OSError as error:
        fail(f"Could not inspect App Store screenshot directory {directory}: {error}")

    jpg_count = sum(name.endswith(".jpg") for name in actual_names)
    if jpg_count != expected_count:
        fail(
            f"App Store screenshot count is {jpg_count}, expected exactly {expected_count}"
        )
    pass_message(f"App Store screenshot count is {jpg_count}")

    file_count = len(actual_names)
    if file_count != expected_count:
        fail(
            f"App Store screenshot file count is {file_count}, expected exactly {expected_count}"
        )
    pass_message(f"App Store screenshot file count is {file_count}")

    actual_name_set = set(actual_names)
    for name in manifest:
        if name not in actual_name_set:
            fail(f"Missing App Store screenshot file: {os.path.join(directory, name)}")

    manifest_name_set = set(manifest)
    for name in actual_names:
        if name not in manifest_name_set:
            fail(f"Unexpected App Store screenshot file: {name!r}")

    pass_message("App Store screenshot directory contains only the current manifest")


if __name__ == "__main__":
    main()
