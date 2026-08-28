#!/usr/bin/env python3
"""Validate checked-in Xcode settings for the private Unity macOS bundle."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


class ProjectValidationError(ValueError):
    """Raised when the Xcode project does not satisfy the Unity bundle contract."""


def load_project(path: Path) -> dict[str, Any]:
    """Convert an OpenStep Xcode project to a regular dictionary with Apple's parser."""
    try:
        result = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(path)],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise ProjectValidationError(f"could not run plutil: {error}") from error

    if result.returncode != 0:
        detail = result.stderr.strip() or "unknown plutil error"
        raise ProjectValidationError(f"could not parse Xcode project: {detail}")

    try:
        project = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ProjectValidationError(f"plutil returned invalid JSON: {error}") from error
    if not isinstance(project, dict):
        raise ProjectValidationError("Xcode project root is not a dictionary")
    return project


def validate_deployment_target(
    project: dict[str, Any],
    target_name: str,
    deployment_target: str,
    required_configurations: tuple[str, ...] = ("Debug", "Release"),
) -> tuple[str, ...]:
    """Validate every configuration reached from a uniquely named native target."""
    objects = project.get("objects")
    if not isinstance(objects, dict):
        raise ProjectValidationError("Xcode project has no objects dictionary")

    targets = [
        value
        for value in objects.values()
        if isinstance(value, dict)
        and value.get("isa") == "PBXNativeTarget"
        and value.get("name") == target_name
    ]
    if len(targets) != 1:
        raise ProjectValidationError(
            f"expected exactly one PBXNativeTarget named {target_name!r}; found {len(targets)}"
        )

    configuration_list_reference = targets[0].get("buildConfigurationList")
    configuration_list = objects.get(configuration_list_reference)
    if not isinstance(configuration_list, dict) or configuration_list.get("isa") != "XCConfigurationList":
        raise ProjectValidationError(f"target {target_name!r} has an invalid build configuration list")

    configuration_references = configuration_list.get("buildConfigurations")
    if not isinstance(configuration_references, list) or not configuration_references:
        raise ProjectValidationError(f"target {target_name!r} has no build configurations")

    configurations: dict[str, dict[str, Any]] = {}
    for reference in configuration_references:
        configuration = objects.get(reference)
        if not isinstance(configuration, dict) or configuration.get("isa") != "XCBuildConfiguration":
            raise ProjectValidationError(
                f"target {target_name!r} contains an invalid configuration reference: {reference!r}"
            )
        name = configuration.get("name")
        if not isinstance(name, str) or not name:
            raise ProjectValidationError(f"target {target_name!r} contains an unnamed configuration")
        if name in configurations:
            raise ProjectValidationError(f"target {target_name!r} contains duplicate configuration {name!r}")
        configurations[name] = configuration

    missing = [name for name in required_configurations if name not in configurations]
    if missing:
        raise ProjectValidationError(
            f"target {target_name!r} is missing configurations: {', '.join(missing)}"
        )

    # Validate new configurations too. Otherwise adding (for example) a Profile configuration
    # could silently bypass the single deployment-target source of truth.
    for name, configuration in sorted(configurations.items()):
        settings = configuration.get("buildSettings")
        if not isinstance(settings, dict):
            raise ProjectValidationError(
                f"target {target_name!r} configuration {name!r} has invalid build settings"
            )
        actual = settings.get("MACOSX_DEPLOYMENT_TARGET")
        if actual != deployment_target:
            raise ProjectValidationError(
                f"target {target_name!r} configuration {name!r} uses macOS {actual!r}; "
                f"expected {deployment_target!r}"
            )

    return tuple(sorted(configurations))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, type=Path, help="Path to project.pbxproj")
    parser.add_argument("--target", required=True, help="PBXNativeTarget name")
    parser.add_argument("--deployment-target", required=True, help="Required macOS version")
    arguments = parser.parse_args()

    try:
        configurations = validate_deployment_target(
            load_project(arguments.project),
            arguments.target,
            arguments.deployment_target,
        )
    except ProjectValidationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(
        f"Validated {arguments.target} deployment target {arguments.deployment_target} "
        f"for: {', '.join(configurations)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
