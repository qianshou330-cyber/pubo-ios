import importlib.util
from pathlib import Path
import tempfile
import unittest
spec=importlib.util.spec_from_file_location("probe",Path(__file__).with_name("probe.py"))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
class Contracts(unittest.TestCase):
 def test_identical_source_fixture(self):
  with tempfile.TemporaryDirectory() as t:
   a,b=Path(t)/"a",Path(t)/"b"
   p.fixture(a);p.fixture(b)
   self.assertEqual({str(f.relative_to(a)):f.read_bytes() for f in a.rglob("*") if f.is_file()},
                    {str(f.relative_to(b)):f.read_bytes() for f in b.rglob("*") if f.is_file()})
 def test_only_derived_path_changes(self):
  a=p.command(Path("/fixture"),Path("/outside"),True)
  b=p.command(Path("/fixture"),Path("/outside"),False)
  diff=[i for i in range(len(a)) if a[i]!=b[i]]
  self.assertEqual(diff,[a.index("-derivedDataPath")+1])
 def test_success_text_does_not_override_timeout(self):
  import sys
  with tempfile.TemporaryDirectory() as t:
   result=p.run([sys.executable,"-c","import time; print('TEST EXECUTE SUCCEEDED',flush=True);time.sleep(3)"],
                t,Path(t)/"log.jsonl",0.1)
   self.assertTrue(result["timedOut"]);self.assertNotEqual(result["returncode"],0)
 def test_clean_exit_recorded(self):
  import sys
  with tempfile.TemporaryDirectory() as t:
   result=p.run([sys.executable,"-c","print('ok')"],t,Path(t)/"log.jsonl",2)
   self.assertFalse(result["timedOut"]);self.assertEqual(result["returncode"],0)
 def test_writer_exception_is_evidence_not_silence(self):
  import sys
  with tempfile.TemporaryDirectory() as t:
   root=Path(t); blocked=root/"file";blocked.write_text("not a directory")
   result=p.run([sys.executable,"-c","import time;print('Resolved source packages:',flush=True);time.sleep(0.5)"],
                t,root/"log.jsonl",2,blocked)
   self.assertTrue(result["writeErrors"]);self.assertEqual(result["writeCount"],0)
   self.assertTrue(result["writerFinished"])
 def test_reader_exception_is_explicit(self):
  import sys
  with tempfile.TemporaryDirectory() as t:
   result=p.run([sys.executable,"-c","print('ok')"],t,Path(t)/"missing/log.jsonl",2)
   self.assertTrue(result["readErrors"]);self.assertTrue(result["readerFinished"])
 def test_missing_package_marker_does_not_write(self):
  import sys
  with tempfile.TemporaryDirectory() as t:
   root=Path(t)
   result=p.run([sys.executable,"-c","import time;time.sleep(0.3)"],
                t,root/"log.jsonl",2,root/"pulses")
   self.assertEqual(result["writeCount"],0)
   self.assertFalse(result["pulseStatus"]["markerSeen"])
   self.assertIn("before package marker",result["pulseStatus"]["skipReason"])
if __name__=="__main__":unittest.main()
