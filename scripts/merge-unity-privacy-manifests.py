#!/usr/bin/env python3
"""Deterministically merge Apple privacy manifests for the Unity macOS bundle."""

from __future__ import annotations

import argparse
import plistlib
from pathlib import Path
from typing import Any


TOP_LEVEL_KEYS = {
    "NSPrivacyAccessedAPITypes",
    "NSPrivacyCollectedDataTypes",
    "NSPrivacyTracking",
    "NSPrivacyTrackingDomains",
}


def load(path: Path) -> dict[str, Any]:
    with path.open("rb") as stream:
        value = plistlib.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"{path} is not a dictionary")
    unknown = set(value) - TOP_LEVEL_KEYS
    if unknown:
        raise ValueError(f"{path} contains unsupported keys: {sorted(unknown)}")
    return value


def strings(value: Any, context: str) -> set[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise ValueError(f"{context} must be an array of non-empty strings")
    return set(value)


def merge(manifests: list[dict[str, Any]]) -> dict[str, Any]:
    accessed: dict[str, set[str]] = {}
    collected: dict[tuple[str, bool, bool], set[str]] = {}
    tracking = False
    domains: set[str] = set()

    for manifest_index, manifest in enumerate(manifests):
        tracking_value = manifest.get("NSPrivacyTracking", False)
        if not isinstance(tracking_value, bool):
            raise ValueError(f"manifest[{manifest_index}].NSPrivacyTracking must be a boolean")
        tracking = tracking or tracking_value
        domains.update(strings(manifest.get("NSPrivacyTrackingDomains", []), "tracking domains"))

        accessed_items = manifest.get("NSPrivacyAccessedAPITypes", [])
        if not isinstance(accessed_items, list):
            raise ValueError("NSPrivacyAccessedAPITypes must be an array")
        for item in accessed_items:
            if not isinstance(item, dict):
                raise ValueError("privacy accessed API entry must be a dictionary")
            api_type = item.get("NSPrivacyAccessedAPIType")
            if not isinstance(api_type, str) or not api_type:
                raise ValueError("privacy accessed API type must be a non-empty string")
            accessed.setdefault(api_type, set()).update(
                strings(item.get("NSPrivacyAccessedAPITypeReasons", []), f"reasons for {api_type}")
            )

        collected_items = manifest.get("NSPrivacyCollectedDataTypes", [])
        if not isinstance(collected_items, list):
            raise ValueError("NSPrivacyCollectedDataTypes must be an array")
        for item in collected_items:
            if not isinstance(item, dict):
                raise ValueError("privacy collected-data entry must be a dictionary")
            data_type = item.get("NSPrivacyCollectedDataType")
            linked = item.get("NSPrivacyCollectedDataTypeLinked")
            item_tracking = item.get("NSPrivacyCollectedDataTypeTracking")
            if not isinstance(data_type, str) or not data_type:
                raise ValueError("privacy collected-data type must be a non-empty string")
            if not isinstance(linked, bool) or not isinstance(item_tracking, bool):
                raise ValueError(f"privacy flags for {data_type} must be booleans")
            collected.setdefault((data_type, linked, item_tracking), set()).update(
                strings(item.get("NSPrivacyCollectedDataTypePurposes", []), f"purposes for {data_type}")
            )

    return {
        "NSPrivacyAccessedAPITypes": [
            {
                "NSPrivacyAccessedAPIType": api_type,
                "NSPrivacyAccessedAPITypeReasons": sorted(reasons),
            }
            for api_type, reasons in sorted(accessed.items())
        ],
        "NSPrivacyCollectedDataTypes": [
            {
                "NSPrivacyCollectedDataType": data_type,
                "NSPrivacyCollectedDataTypeLinked": linked,
                "NSPrivacyCollectedDataTypePurposes": sorted(purposes),
                "NSPrivacyCollectedDataTypeTracking": item_tracking,
            }
            for (data_type, linked, item_tracking), purposes in sorted(collected.items())
        ],
        "NSPrivacyTracking": tracking,
        "NSPrivacyTrackingDomains": sorted(domains),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("inputs", nargs="+", type=Path)
    arguments = parser.parse_args()

    result = merge([load(path) for path in arguments.inputs])
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    with arguments.output.open("wb") as stream:
        plistlib.dump(result, stream, fmt=plistlib.FMT_XML, sort_keys=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
