"""Offline integration checks for the independent pilot report validator."""

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("analysis", ROOT / "scripts/analyze_pu_pilot.py")
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)


class PilotAnalysisTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.base = Path(cls.temp.name)
        subprocess.run(["julia", "--startup-file=no", f"--project={ROOT}",
                        str(ROOT / "examples/mp_recovery/make_snapshot.jl"),
                        str(cls.base / "snapshot")], check=True, capture_output=True)
        commands = [
            ["audit-mp", "--snapshot", "snapshot", "--output", "audit"],
            ["split-mp", "--snapshot", "snapshot", "--audit", "audit", "--output", "splits", "--synthetic", "--budget", "1", "4"],
            ["benchmark-pu", "--snapshot", "snapshot", "--audit", "audit", "--splits", "splits", "--output", "results", "--synthetic"],
        ]
        for command in commands:
            subprocess.run(["julia", "--startup-file=no", f"--project={ROOT}", str(ROOT / "bin/eka"), *command], cwd=cls.base, check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.case = tempfile.TemporaryDirectory()
        self.addCleanup(self.case.cleanup)
        self.run = Path(self.case.name) / "run"
        shutil.copytree(self.base / "results", self.run)

    def rewrite_and_rehash(self, name, before, after):
        path = self.run / name
        old = analysis.sha(path)
        text = path.read_text()
        self.assertIn(before, text)
        path.write_text(text.replace(before, after, 1))
        config = self.run / "config.toml"
        config.write_text(config.read_text().replace(f'"{name}" = "{old}"', f'"{name}" = "{analysis.sha(path)}"'))

    def test_complete_fixture_and_no_overwrite(self):
        output = Path(self.case.name) / "analysis"
        summary = analysis.analyze(self.run, output)
        self.assertEqual(summary[1]["budget"], 4)
        # All four candidates are selected; both holdouts must be recovered.
        self.assertEqual([summary[1][f"{m}_mean"] for m in analysis.METHODS], [2, 2, 2])
        self.assertEqual(json.loads((output / "validation.json").read_text())["metric_rows"], 120)
        with self.assertRaisesRegex(ValueError, "overwrite"):
            analysis.analyze(self.run, output)

    def test_rehashed_incorrect_metric_is_rejected(self):
        name = "metrics.tsv"
        row = analysis.rows(self.run / name)[0]
        before = "\t".join(row.values())
        row["hits"] = str(int(row["hits"]) + 1)
        self.rewrite_and_rehash(name, before, "\t".join(row.values()))
        with self.assertRaisesRegex(ValueError, "metric mismatch"):
            analysis.validate(self.run)

    def test_rehashed_incorrect_popularity_score_is_rejected(self):
        name = "split-00/popularity.tsv"
        row = analysis.rows(self.run / name)[0]
        before = "\t".join(row.values())
        row["score"] = "0.123456789"
        self.rewrite_and_rehash(name, before, "\t".join(row.values()))
        with self.assertRaisesRegex(ValueError, "popularity mismatch"):
            analysis.validate(self.run)

    def test_rehashed_duplicate_ranking_is_rejected(self):
        name = "split-00/random.tsv"
        data = analysis.rows(self.run / name)
        self.rewrite_and_rehash(name, "\t".join(data[1].values()), "\t".join(data[0].values()))
        with self.assertRaisesRegex(ValueError, "duplicate ranking"):
            analysis.validate(self.run)

    def test_wrong_membership_is_rejected(self):
        path = self.run / "inputs/split-00/inputs/training.tsv"
        path.write_text("composition\nBa1O3Ti1\n")
        with self.assertRaisesRegex(ValueError, "membership mismatch"):
            analysis.validate(self.run)


if __name__ == "__main__":
    unittest.main()
