"""Synthetic end-to-end checks and rehashed-corruption checks for sensitivity."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import analyze_label_sensitivity as analysis


class SensitivityAnalysisTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.base = Path(cls.temp.name)
        subprocess.run(["julia", "--startup-file=no", f"--project={ROOT}",
                        str(ROOT / "examples/mp_recovery/make_snapshot.jl"), "snapshot"],
                       cwd=cls.base, check=True, capture_output=True)
        julia = ["julia", "--startup-file=no", f"--project={ROOT}"]
        for args in [
            [str(ROOT / "bin/eka"), "audit-mp", "--snapshot", "snapshot", "--output", "audit"],
            [str(ROOT / "bin/eka"), "split-mp", "--snapshot", "snapshot", "--audit", "audit", "--output", "splits", "--synthetic", "--budget", "1", "2"],
            [str(ROOT / "bin/eka"), "benchmark-pu", "--snapshot", "snapshot", "--audit", "audit", "--splits", "splits", "--output", "pilot", "--synthetic"],
            [str(ROOT / "scripts/run_label_sensitivity.jl"), "snapshot", "audit", "pilot", "results", "--synthetic"],
        ]:
            subprocess.run(julia + args, cwd=cls.base, check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.run = Path(self.temp.name) / "run"
        shutil.copytree(self.base / "results", self.run)

    def rehash_change(self, name, change):
        path = self.run / name
        old = analysis.sha(path)
        path.write_text(change(path.read_text()))
        config = self.run / "config.toml"
        config.write_text(config.read_text().replace(f'"{name}" = "{old}"', f'"{name}" = "{analysis.sha(path)}"'))

    def test_complete_grid_and_no_overwrite(self):
        config, index, populations = analysis.validate(self.run)
        self.assertTrue(config["is_synthetic"])
        self.assertEqual(len(index), 720)
        self.assertEqual(len(populations), 120)
        for r in populations:
            if r["mode"] == "full_pipeline" and r["policy"] != "original":
                self.assertEqual(r["mixed_training_count"], 0)
                self.assertEqual(r["heldout_count"], 1)
        output = Path(self.temp.name) / "analysis"
        analysis.analyze(self.run, output)
        with self.assertRaisesRegex(ValueError, "overwrite"):
            analysis.analyze(self.run, output)

    def test_rehashed_metric_corruption(self):
        row = analysis.rows(self.run / "metrics.tsv")[0]
        old = "\t".join(row.values())
        row["heldout_count"] = "999"
        new = "\t".join(row.values())
        self.rehash_change("metrics.tsv", lambda text: text.replace(old, new, 1))
        with self.assertRaisesRegex(ValueError, "metric mismatch"):
            analysis.validate(self.run)

    def test_rehashed_fixed_score_corruption(self):
        name = "evaluation_only/unlabel_mixed/split-00/popularity.tsv"
        row = analysis.rows(self.run / name)[0]
        old = "\t".join(row.values())
        row["score"] = "0.123456789"
        new = "\t".join(row.values())
        self.rehash_change(name, lambda text: text.replace(old, new, 1))
        with self.assertRaisesRegex(ValueError, "changed score/order/depth"):
            analysis.validate(self.run)

    def test_rehashed_membership_corruption(self):
        self.rehash_change("full_pipeline/unlabel_mixed/split-00/inputs/training.tsv", lambda text: text + "Li1Na1O1\n")
        with self.assertRaisesRegex(ValueError, "membership mismatch"):
            analysis.validate(self.run)


if __name__ == "__main__":
    unittest.main()
