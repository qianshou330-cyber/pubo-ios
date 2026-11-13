import base64
import pathlib
import re
import runpy
import struct
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
load_native_media = runpy.run_path(str(ROOT / 'scripts/h5-chat/fixture_media.py'))['load_native_media']


class H5ChatMediaTests(unittest.TestCase):
    def test_fixture_bytes_match_native_source_not_generic_placeholder(self):
        source = ROOT / 'App/Infrastructure/GIFTestFixtures.swift'
        media = load_native_media(source)
        for key in ('still', 'looping', 'finite', 'avatar'):
            literal = re.search(r'static let ' + key + r' = Data\(base64Encoded: "([^"]+)"', source.read_text()).group(1)
            self.assertEqual(media[key], base64.b64decode(literal))
        self.assertEqual(media['still'][:8], b'\x89PNG\r\n\x1a\n')
        self.assertEqual(struct.unpack('>II', media['still'][16:24]), (320, 180))
        self.assertTrue(media['looping'].startswith(b'GIF'))
        self.assertEqual(struct.unpack('>II', media['avatar'][16:24]), (128, 128))
        server = (ROOT / 'scripts/h5-chat/server.py').read_text()
        self.assertLess(server.index("p=='/fixture/avatar.png'"), server.index("p.endswith('.png')"))

    def test_missing_fixture_fails_instead_of_substituting(self):
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / 'missing.swift'
            source.write_text('')
            with self.assertRaisesRegex(ValueError, 'Missing native media fixture'):
                load_native_media(source)


if __name__ == '__main__':
    unittest.main()
