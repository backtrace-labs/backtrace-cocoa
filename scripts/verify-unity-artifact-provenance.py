#!/usr/bin/env python3
"""Verify that a Unity archive was built from the expected Cocoa source."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"error: {message}")


def main() -> None:
    if len(sys.argv) != 4:
        fail(
            "usage: verify-unity-artifact-provenance.py "
            "PROVENANCE EXPECTED_HEAD EXPECTED_VERSION"
        )

    path = Path(sys.argv[1])
    expected_head = sys.argv[2]
    expected_version = sys.argv[3]

    try:
        provenance = json.loads(path.read_text(encoding="utf-8"))
        cocoa = provenance["backtrace_cocoa"]
    except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError) as error:
        fail(f"unable to read Backtrace Cocoa provenance: {error}")

    if not isinstance(cocoa, dict):
        fail("Backtrace Cocoa provenance is not an object")

    if cocoa.get("head") != expected_head:
        fail(
            "Unity archive provenance does not match the validated commit: "
            f"{cocoa.get('head')!r} != {expected_head!r}"
        )
    if cocoa.get("version") != expected_version:
        fail(
            "Unity archive provenance does not match the validated version: "
            f"{cocoa.get('version')!r} != {expected_version!r}"
        )
    if cocoa.get("dirty") is not False:
        fail("release archive provenance reports a dirty Backtrace Cocoa source")


if __name__ == "__main__":
    main()
