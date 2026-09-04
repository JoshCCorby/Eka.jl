"""Independent full workflow and corruption checks, using no MP API or private data."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
import analyze_system_holdout as analysis


class SystemAnalysisTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.base=Path(cls.temp.name)
        subprocess.run(["julia", "--startup-file=no", f"--project={ROOT}",
                        str(ROOT/"examples/mp_recovery/make_system_snapshot.jl"), "snapshot"],
                       cwd=cls.base, check=True, capture_output=True)
        code='''using EkaCompositions
include(joinpath(ARGS[1],"src","mp_system_holdout.jl"))
audit_mp_snapshot("snapshot","audit")
split_mp_recovery("snapshot","audit","splits";synthetic=true,seeds=0:2,budgets=[1,4])
benchmark_pu("splits","snapshot","audit","pilot";synthetic=true)
MPSystemHoldout.LS.run_sensitivity("snapshot","audit","pilot","sensitivity";synthetic=true)
MPSystemHoldout.run_system_holdout("snapshot","audit","sensitivity","results";synthetic=true)
'''
        result=subprocess.run(["julia","--startup-file=no",f"--project={ROOT}","-e",code,str(ROOT)],cwd=cls.base,text=True,capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stdout+result.stderr)

    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()

    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        self.path=Path(temp.name);self.run=self.path/"run"
        shutil.copytree(self.base/"results",self.run)

    def change(self,name,field,value):
        path=self.run/name;oldhash=analysis.sha(path)
        data=analysis.rows(path);data[0][field]=value
        path.unlink();analysis.write_rows(path,data)
        config=self.run/"config.toml"
        old=f'"{name}" = "{oldhash}"';new=f'"{name}" = "{analysis.sha(path)}"'
        self.assertIn(old,config.read_text())
        config.write_text(config.read_text().replace(old,new))

    def test_complete_grid_and_no_overwrite(self):
        config,index,pops,diagnostics=analysis.validate(self.run)
        self.assertTrue(config["is_synthetic"])
        self.assertEqual((len(index),len(pops),len(diagnostics)),(108,18,54))
        analysis.analyze(self.run,self.path/"analysis")
        with self.assertRaisesRegex(ValueError,"overwrite"):analysis.analyze(self.run,self.path/"analysis")

    def test_rehashed_metrics(self):
        self.change("metrics.tsv","hits","999")
        with self.assertRaisesRegex(ValueError,"metric mismatch"):analysis.validate(self.run)

    def test_rehashed_membership(self):
        self.change("system/original/split-00/inputs/training.tsv","composition","Fe1Na1O1")
        with self.assertRaisesRegex(ValueError,"membership mismatch"):analysis.validate(self.run)

    def test_rehashed_population(self):
        self.change("populations.tsv","training_top5_system_fraction","0.123")
        with self.assertRaisesRegex(ValueError,"concentration mismatch"):analysis.validate(self.run)

    def test_rehashed_diagnostic(self):
        self.change("similarity-diagnostics.tsv","median","0.123")
        with self.assertRaisesRegex(ValueError,"diagnostic mismatch"):analysis.validate(self.run)

    def test_rehashed_selection(self):
        self.change("system/original/split-00/selected-systems.tsv","chemical_system","Fe-Na-O")
        with self.assertRaisesRegex(ValueError,"selected-system mismatch"):analysis.validate(self.run)

    def test_rehashed_popularity(self):
        self.change("system/original/split-00/popularity.tsv","score","0.123")
        with self.assertRaisesRegex(ValueError,"popularity mismatch"):analysis.validate(self.run)


if __name__=="__main__": unittest.main()
