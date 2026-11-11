import hashlib, importlib.util, io, json, pathlib, tarfile, tempfile, unittest
spec = importlib.util.spec_from_file_location('split_evidence', pathlib.Path(__file__).with_name('split-test-evidence.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
class EvidenceTests(unittest.TestCase):
    def test_parts_reassemble_exactly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary); (root/'sample.xcresult').mkdir(); (root/'sample.xcresult'/'result').write_bytes(b'original evidence')
            (root/'screenshots').mkdir(); (root/'screenshots'/'recording.mp4').write_bytes(bytes(range(256)))
            result=module.split_evidence(root,limit=100)
            parts=[]
            for part in result['parts']:
                data=(root/'evidence-parts'/part['file']).read_bytes();self.assertEqual(len(data),part['bytes']);self.assertEqual(hashlib.sha256(data).hexdigest(),part['sha256']);parts.append(data)
            archive=b''.join(parts);self.assertEqual(hashlib.sha256(archive).hexdigest(),result['archive_sha256'])
            with tarfile.open(fileobj=io.BytesIO(archive),mode='r:gz') as tar:
                self.assertEqual(tar.extractfile('sample.xcresult/result').read(),b'original evidence')
                self.assertEqual(tar.extractfile('screenshots/recording.mp4').read(),bytes(range(256)))
            self.assertTrue((root/'sample.xcresult'/'result').exists())
            with self.assertRaises(RuntimeError): module.split_evidence(root)
    def test_empty_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);result=module.split_evidence(root);self.assertEqual(result['parts'],[]);self.assertTrue((root/'evidence-parts'/'manifest.json').exists())
if __name__=='__main__': unittest.main()
