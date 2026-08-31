from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE_SCRIPT = Path(__file__).resolve().parents[1] / "validate-release-version.sh"
CURRENT_VERSION_SCRIPT = Path(__file__).resolve().parents[1] / "current-release-version.sh"


class ValidateReleaseVersionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        scripts = self.root / "scripts"
        attributes = self.root / "Sources" / "Features" / "Attributes"
        xcode_project = self.root / "Backtrace.xcodeproj"
        scripts.mkdir(parents=True)
        attributes.mkdir(parents=True)
        xcode_project.mkdir(parents=True)
        self.script = scripts / SOURCE_SCRIPT.name
        self.script.write_bytes(SOURCE_SCRIPT.read_bytes())
        self.script.chmod(0o755)
        self.current_version_script = scripts / CURRENT_VERSION_SCRIPT.name
        self.current_version_script.write_bytes(CURRENT_VERSION_SCRIPT.read_bytes())
        self.current_version_script.chmod(0o755)
        self.write_sources("9.8.7", "9.8.7", "9.8.7")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_sources(
        self,
        podspec_version: str,
        agent_version: str,
        changelog_version: str,
        *,
        older_changelog_version: str | None = None,
        xcode_versions: tuple[str, ...] | None = None,
    ) -> None:
        (self.root / "Backtrace.podspec").write_text(
            f'Pod::Spec.new do |s|\n  s.version = "{podspec_version}"\nend\n',
            encoding="utf-8",
        )
        (self.root / "Sources" / "Features" / "Attributes" / "DefaultAttributes.swift").write_text(
            f'struct LibInfo {{\n    var backtraceVersion = "{agent_version}"\n}}\n',
            encoding="utf-8",
        )
        changelog = f"# Release notes\n\n## Version {changelog_version}\n\n- Current.\n"
        if older_changelog_version is not None:
            changelog += f"\n## Version {older_changelog_version}\n\n- Older.\n"
        (self.root / "CHANGELOG.md").write_text(changelog, encoding="utf-8")
        configured_versions = xcode_versions or (podspec_version,)
        project = "\n".join(
            f"MARKETING_VERSION = {version};" for version in configured_versions
        )
        (self.root / "Backtrace.xcodeproj" / "project.pbxproj").write_text(
            project,
            encoding="utf-8",
        )

    def validate(self, version: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.script), version],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def current_version(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.current_version_script)],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_resolves_the_current_version_from_the_podspec(self) -> None:
        result = self.current_version()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "9.8.7")

    def test_rejects_a_podspec_without_a_version(self) -> None:
        (self.root / "Backtrace.podspec").write_text(
            "Pod::Spec.new do |s|\nend\n",
            encoding="utf-8",
        )

        result = self.current_version()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Backtrace.podspec version not found", result.stderr)

    def test_accepts_an_exact_matching_release_version(self) -> None:
        result = self.validate("9.8.7")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("validated release version 9.8.7", result.stdout)

    def test_rejects_non_exact_version_formats(self) -> None:
        for version in ("v9.8.7", "9.8", "9.8.7.0", "9.8.7-beta"):
            with self.subTest(version=version):
                result = self.validate(version)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid release version", result.stderr)

    def test_rejects_a_podspec_version_mismatch(self) -> None:
        self.write_sources("9.8.6", "9.8.7", "9.8.7")

        result = self.validate("9.8.7")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source=Backtrace.podspec value=9.8.6", result.stderr)

    def test_rejects_an_agent_version_mismatch(self) -> None:
        self.write_sources("9.8.7", "9.8.6", "9.8.7")

        result = self.validate("9.8.7")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source=LibInfo.backtraceVersion value=9.8.6", result.stderr)

    def test_rejects_a_current_changelog_version_mismatch(self) -> None:
        self.write_sources(
            "9.8.7",
            "9.8.7",
            "9.8.6",
            older_changelog_version="9.8.7",
        )

        result = self.validate("9.8.7")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source=CHANGELOG.md value=9.8.6", result.stderr)

    def test_rejects_a_missing_changelog_heading(self) -> None:
        (self.root / "CHANGELOG.md").write_text("# Release notes\n", encoding="utf-8")

        result = self.validate("9.8.7")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CHANGELOG.md has no current Version heading", result.stderr)

    def test_rejects_an_xcode_marketing_version_mismatch(self) -> None:
        self.write_sources(
            "9.8.7",
            "9.8.7",
            "9.8.7",
            xcode_versions=("9.8.7", "9.8.6"),
        )

        result = self.validate("9.8.7")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "source=Xcode MARKETING_VERSION value=9.8.6,9.8.7",
            result.stderr,
        )


if __name__ == "__main__":
    unittest.main()
