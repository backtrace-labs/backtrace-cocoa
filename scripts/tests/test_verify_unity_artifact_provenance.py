from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "verify-unity-artifact-provenance.py"


class VerifyUnityArtifactProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.provenance = Path(self.temporary_directory.name) / "artifact-provenance.json"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_validator(
        self,
        *,
        head: str = "a" * 40,
        version: str = "2.2.0",
        dirty: bool = False,
        expected_head: str = "a" * 40,
        expected_version: str = "2.2.0",
    ) -> subprocess.CompletedProcess[str]:
        self.provenance.write_text(
            json.dumps(
                {
                    "backtrace_cocoa": {
                        "head": head,
                        "version": version,
                        "dirty": dirty,
                    }
                }
            ),
            encoding="utf-8",
        )
        return subprocess.run(
            [str(SCRIPT), str(self.provenance), expected_head, expected_version],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_accepts_the_expected_clean_source(self) -> None:
        result = self.run_validator()

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_a_different_source_head(self) -> None:
        result = self.run_validator(head="b" * 40)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("validated commit", result.stderr)

    def test_rejects_a_different_version(self) -> None:
        result = self.run_validator(version="2.1.0")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("validated version", result.stderr)

    def test_rejects_dirty_release_provenance(self) -> None:
        result = self.run_validator(dirty=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dirty Backtrace Cocoa source", result.stderr)


if __name__ == "__main__":
    unittest.main()
