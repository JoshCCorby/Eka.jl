import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "verify_release.py"
SPEC = importlib.util.spec_from_file_location("verify_release", MODULE_PATH)
release = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(release)


class ReleaseAuditTests(unittest.TestCase):
    def test_accepts_reviewed_source_package(self):
        entries = {
            "CHANGELOG.md": b"0.1.0",
            "LICENSE": b"MIT",
            "README.md": b"Materials Project attribution",
            "THIRD_PARTY_NOTICES.md": b"Seko BSD notice",
            "CITATION.cff": b"cff-version: 1.2.0",
            "src/Eka.jl": b"module Eka\nend",
            "test/fixtures/tiny_test.db": b"SQLite fixture",
        }
        result = release.audit_entries(entries)
        self.assertEqual("pass", result["status"])
        self.assertEqual([], result["problems"])

    def test_rejects_local_data_and_secret_material(self):
        entries = {
            "reports/local/rankings.tsv": b"composition\tscore\n",
            "snapshot.jsonl": b"{}\n",
            ".env": b"MP_API_KEY='" + b"a" * 32 + b"'\n",
            "notes.txt": b"/" + b"Users/example/private/run.log\n",
        }
        result = release.audit_entries(entries, require_metadata=False)
        joined = "\n".join(result["problems"])
        self.assertEqual("fail", result["status"])
        self.assertIn("forbidden release directory", joined)
        self.assertIn("unreviewed data/database file", joined)
        self.assertIn("literal MP API key", joined)
        self.assertIn("machine-specific home path", joined)

    def test_dot_path_is_normalized_without_hiding_parent_traversal(self):
        self.assertEqual("src/Eka.jl", release.normalize_path("src/./Eka.jl"))
        self.assertEqual("../secret", release.normalize_path("../secret"))


if __name__ == "__main__":
    unittest.main()
