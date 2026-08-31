from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE_SCRIPT = Path(__file__).resolve().parents[1] / "validate-release-version.sh"


class ValidateReleaseVersionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        scripts = self.root / "scripts"
        attributes = self.root / "Sources" / "Features" / "Attributes"
        scripts.mkdir(parents=True)
        attributes.mkdir(parents=True)
        self.script = scripts / SOURCE_SCRIPT.name
        self.script.write_bytes(SOURCE_SCRIPT.read_bytes())
        self.script.chmod(0o755)
        self.write_sources("2.1.1", "2.1.1", "2.1.1")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_sources(
        self,
        podspec_version: str,
        agent_version: str,
        changelog_version: str,
        *,
        older_changelog_version: str | None = None,
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

    def validate(self, version: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.script), version],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_accepts_an_exact_matching_release_version(self) -> None:
        result = self.validate("2.1.1")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("validated release version 2.1.1", result.stdout)

    def test_rejects_non_exact_version_formats(self) -> None:
        for version in ("v2.1.1", "2.1", "2.1.1.0", "2.1.1-beta"):
            with self.subTest(version=version):
                result = self.validate(version)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid release version", result.stderr)

    def test_rejects_a_podspec_version_mismatch(self) -> None:
        self.write_sources("2.1.0", "2.1.1", "2.1.1")

        result = self.validate("2.1.1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source=Backtrace.podspec value=2.1.0", result.stderr)

    def test_rejects_an_agent_version_mismatch(self) -> None:
        self.write_sources("2.1.1", "2.1.0", "2.1.1")

        result = self.validate("2.1.1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source=LibInfo.backtraceVersion value=2.1.0", result.stderr)

    def test_rejects_a_current_changelog_version_mismatch(self) -> None:
        self.write_sources(
            "2.1.1",
            "2.1.1",
            "2.1.0",
            older_changelog_version="2.1.1",
        )

        result = self.validate("2.1.1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source=CHANGELOG.md value=2.1.0", result.stderr)

    def test_rejects_a_missing_changelog_heading(self) -> None:
        (self.root / "CHANGELOG.md").write_text("# Release notes\n", encoding="utf-8")

        result = self.validate("2.1.1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CHANGELOG.md has no current Version heading", result.stderr)


if __name__ == "__main__":
    unittest.main()
