from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "validate_unity_xcode_project.py"
SPEC = importlib.util.spec_from_file_location("validate_unity_xcode_project", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {SCRIPT_PATH}")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


def project_fixture(
    configurations: tuple[tuple[str, str, str], ...] = (
        ("debug-reference", "Debug", "12.0"),
        ("release-reference", "Release", "12.0"),
    ),
) -> dict:
    objects = {
        "bundle-target": {
            "isa": "PBXNativeTarget",
            "name": "Backtrace-bundle",
            "buildConfigurationList": "bundle-configuration-list",
        },
        "bundle-configuration-list": {
            "isa": "XCConfigurationList",
            "buildConfigurations": [reference for reference, _, _ in configurations],
        },
    }
    for reference, name, deployment_target in configurations:
        objects[reference] = {
            "isa": "XCBuildConfiguration",
            "name": name,
            "buildSettings": {"MACOSX_DEPLOYMENT_TARGET": deployment_target},
        }
    return {"objects": objects}


class ValidateUnityXcodeProjectTests(unittest.TestCase):
    def validate(self, project: dict) -> tuple[str, ...]:
        return VALIDATOR.validate_deployment_target(project, "Backtrace-bundle", "12.0")

    def test_resolves_target_and_configurations_by_semantic_names(self) -> None:
        project = project_fixture(
            (
                ("unrelated-order-release", "Release", "12.0"),
                ("unrelated-order-debug", "Debug", "12.0"),
            )
        )

        self.assertEqual(self.validate(project), ("Debug", "Release"))

    def test_rejects_a_missing_required_configuration(self) -> None:
        project = project_fixture((("debug", "Debug", "12.0"),))

        with self.assertRaisesRegex(VALIDATOR.ProjectValidationError, "missing configurations: Release"):
            self.validate(project)

    def test_rejects_duplicate_target_names(self) -> None:
        project = project_fixture()
        project["objects"]["another-target"] = dict(project["objects"]["bundle-target"])

        with self.assertRaisesRegex(VALIDATOR.ProjectValidationError, "exactly one PBXNativeTarget"):
            self.validate(project)

    def test_rejects_duplicate_configuration_names(self) -> None:
        project = project_fixture(
            (
                ("debug-one", "Debug", "12.0"),
                ("debug-two", "Debug", "12.0"),
                ("release", "Release", "12.0"),
            )
        )

        with self.assertRaisesRegex(VALIDATOR.ProjectValidationError, "duplicate configuration 'Debug'"):
            self.validate(project)

    def test_rejects_a_dangling_configuration_reference(self) -> None:
        project = project_fixture()
        project["objects"]["bundle-configuration-list"]["buildConfigurations"].append("missing")

        with self.assertRaisesRegex(VALIDATOR.ProjectValidationError, "invalid configuration reference"):
            self.validate(project)

    def test_rejects_deployment_target_drift(self) -> None:
        project = project_fixture(
            (
                ("debug", "Debug", "12.0"),
                ("release", "Release", "13.0"),
            )
        )

        with self.assertRaisesRegex(VALIDATOR.ProjectValidationError, "'Release' uses macOS '13.0'"):
            self.validate(project)

    def test_validates_new_configurations_instead_of_silently_ignoring_them(self) -> None:
        project = project_fixture(
            (
                ("debug", "Debug", "12.0"),
                ("release", "Release", "12.0"),
                ("profile", "Profile", "13.0"),
            )
        )

        with self.assertRaisesRegex(VALIDATOR.ProjectValidationError, "'Profile' uses macOS '13.0'"):
            self.validate(project)


if __name__ == "__main__":
    unittest.main()
