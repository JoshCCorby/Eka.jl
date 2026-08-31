"""Synthetic learned-evaluation coverage and rehashed-corruption checks."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import analyze_element_pair as analysis
import test_system_holdout_analysis as system_fixture

class ElementPairAnalysisTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        system_fixture.SystemAnalysisTests.setUpClass()
        cls.base=system_fixture.SystemAnalysisTests.base
        command=['julia','--startup-file=no',f'--project={ROOT}',str(ROOT/'scripts/run_element_pair.jl'),'snapshot','audit','results','learned','--synthetic']
        r=subprocess.run(command,cwd=cls.base,text=True,capture_output=True)
        if r.returncode:raise RuntimeError(r.stdout+r.stderr)

    @classmethod
    def tearDownClass(cls):system_fixture.SystemAnalysisTests.tearDownClass()

    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup);self.path=Path(temp.name);self.run=self.path/'run'
        shutil.copytree(self.base/'learned',self.run)

    def change(self,name,field,value):
        p=self.run/name;old=analysis.sha(p);data=analysis.rows(p);data[0][field]=value;p.unlink();analysis.write_rows(p,data)
        cfg=self.run/'config.toml';oldline=f'"{name}" = "{old}"'
        self.assertIn(oldline,cfg.read_text());cfg.write_text(cfg.read_text().replace(oldline,f'"{name}" = "{analysis.sha(p)}"'))

    def test_complete_and_no_overwrite(self):
        cfg,index,_,diagnostics=analysis.validate(self.run)
        self.assertEqual((len(index),len(diagnostics)),(36,18))
        analysis.analyze(self.run,self.path/'analysis')
        with self.assertRaisesRegex(ValueError,'overwrite'):analysis.analyze(self.run,self.path/'analysis')
        r=subprocess.run(['julia','--startup-file=no',f'--project={ROOT}',str(ROOT/'scripts/run_element_pair.jl'),'snapshot','audit','results','learned','--synthetic'],cwd=self.base,text=True,capture_output=True)
        self.assertNotEqual(r.returncode,0);self.assertIn('refusing to overwrite',r.stderr)

    def test_rehashed_factor_corruption(self):
        self.change('system/original/split-00/factors.tsv','value','0.314159')
        with self.assertRaises(ValueError):analysis.validate(self.run)

    def test_rehashed_score_corruption(self):
        self.change('system/original/split-00/ranking.tsv','score','0.123')
        with self.assertRaisesRegex(ValueError,'factor score'):analysis.validate(self.run)

    def test_rehashed_metric_corruption(self):
        self.change('metrics.tsv','hits','999')
        with self.assertRaisesRegex(ValueError,'metric mismatch'):analysis.validate(self.run)

    def test_rehashed_coverage_corruption(self):
        self.change('system/original/split-00/ranking.tsv','coverage','invented')
        with self.assertRaisesRegex(ValueError,'coverage mismatch'):analysis.validate(self.run)

    def test_rehashed_diagnostic_corruption(self):
        self.change('fit-diagnostics.tsv','termination','invented')
        with self.assertRaisesRegex(ValueError,'termination mismatch'):analysis.validate(self.run)

if __name__=='__main__':unittest.main()
