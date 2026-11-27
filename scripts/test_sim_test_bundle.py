"""Offline unit and static contract tests for C107 timeout remediation pillars."""
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import tarfile
import tempfile
import unittest

from pack_sim_test_bundle import pack_bundle
from unpack_sim_test_bundle import unpack_bundle

ROOT = Path(__file__).resolve().parents[1]
COMMIT = 'a' * 40
XCODE = 'Xcode 26.0.1\nBuild version 17A400'


def make_fake_derived_data(base):
    products = Path(base) / 'Build' / 'Products'
    sim = products / 'Debug-iphonesimulator'
    app_bin = sim / 'PUBO.app' / 'PUBO'
    runner_fw = sim / 'PUBOUITests-Runner.app' / 'Frameworks' / 'Demo.framework'
    (runner_fw / 'Versions' / 'A').mkdir(parents=True)
    (runner_fw / 'Versions' / 'A' / 'Demo').write_bytes(b'binary')
    (runner_fw / 'Versions' / 'Current').symlink_to('A')
    (runner_fw / 'Demo').symlink_to('Versions/Current/Demo')
    app_bin.parent.mkdir(parents=True)
    app_bin.write_bytes(b'#!/bin/sh\nexit 0\n')
    app_bin.chmod(0o755)
    xctestrun = products / 'PUBO_iphonesimulator26.0-arm64.xctestrun'
    xctestrun.write_text('<plist/>', encoding='utf-8')
    return xctestrun


class SimTestBundleTests(unittest.TestCase):
    def test_pack_and_unpack_roundtrip_preserves_symlinks_mode_and_metadata(self):
        with tempfile.TemporaryDirectory() as d:
            dd = Path(d) / 'src-dd'
            bundle = Path(d) / 'bundle'
            dst_dd = Path(d) / 'dst-dd'
            meta_dst = Path(d) / 'messages-meta'
            make_fake_derived_data(dd)
            manifest = pack_bundle(
                dd, bundle, COMMIT, '42', '2', 'arm64', XCODE,
                xcodegen_version='Version: 2.45.3', xcodegen_brew_package='xcodegen 2.45.3',
            )
            self.assertEqual(manifest['architecture'], 'arm64')
            xctestrun, verified = unpack_bundle(
                bundle, dst_dd, COMMIT, '42', '2', 'arm64', XCODE,
                copy_xcodegen_meta=meta_dst,
            )
            self.assertEqual(verified['commit'], COMMIT)
            self.assertTrue(xctestrun.is_file())
            self.assertEqual(xctestrun.name, 'PUBO_iphonesimulator26.0-arm64.xctestrun')
            restored_bin = dst_dd / 'Build' / 'Products' / 'Debug-iphonesimulator' / 'PUBO.app' / 'PUBO'
            self.assertTrue(bool(restored_bin.stat().st_mode & stat.S_IXUSR))
            restored_link = dst_dd / 'Build' / 'Products' / 'Debug-iphonesimulator' / 'PUBOUITests-Runner.app' / 'Frameworks' / 'Demo.framework' / 'Demo'
            self.assertTrue(restored_link.is_symlink())
            self.assertEqual(os.readlink(restored_link), 'Versions/Current/Demo')
            self.assertEqual((meta_dst / 'xcodegen-version.txt').read_text().strip(), 'Version: 2.45.3')
            self.assertEqual((meta_dst / 'xcodegen-brew-package.txt').read_text().strip(), 'xcodegen 2.45.3')

    def test_unpack_rejects_mismatched_provenance_and_tampering(self):
        with tempfile.TemporaryDirectory() as d:
            dd = Path(d) / 'src-dd'
            bundle = Path(d) / 'bundle'
            dst_dd = Path(d) / 'dst-dd'
            make_fake_derived_data(dd)
            pack_bundle(dd, bundle, COMMIT, '42', '2', 'arm64', XCODE)
            for args in [
                ('b' * 40, '42', '2', 'arm64', XCODE),
                (COMMIT, '43', '2', 'arm64', XCODE),
                (COMMIT, '42', '3', 'arm64', XCODE),
                (COMMIT, '42', '2', 'x86_64', XCODE),
                (COMMIT, '42', '2', 'arm64', 'Xcode 26.0.0\nBuild version 17A000'),
            ]:
                with self.subTest(args=args), self.assertRaisesRegex(ValueError, 'mismatch'):
                    unpack_bundle(bundle, dst_dd, *args)
            tarball = bundle / 'products.tar.gz'
            tarball.write_bytes(tarball.read_bytes() + b'tampered')
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                unpack_bundle(bundle, dst_dd, COMMIT, '42', '2', 'arm64', XCODE)

    def test_unpack_rejects_path_traversal_and_escaping_symlinks(self):
        for case, member_name, linkname in [
            ('traversal', 'Products/../escape.txt', None),
            ('outside-root', 'Other/file.txt', None),
            ('abs-symlink', 'Products/badlink', '/etc/passwd'),
            ('rel-escape-symlink', 'Products/sub/badlink', '../../../etc/passwd'),
        ]:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as d:
                bundle = Path(d) / 'bundle'
                bundle.mkdir()
                tarball = bundle / 'products.tar.gz'
                with tarfile.open(tarball, 'w:gz') as archive:
                    info = tarfile.TarInfo(name=member_name)
                    if linkname is not None:
                        info.type = tarfile.SYMTYPE
                        info.linkname = linkname
                        archive.addfile(info)
                    else:
                        data = b'x'
                        info.size = len(data)
                        archive.addfile(info, io.BytesIO(data))
                manifest = {
                    'schemaVersion': 1, 'commit': COMMIT, 'runId': '1', 'runAttempt': '1',
                    'architecture': 'arm64', 'xcodeVersion': XCODE,
                    'xctestrunName': 'PUBO.xctestrun', 'xctestrunSHA256': '0' * 64,
                    'tarballName': 'products.tar.gz',
                    'tarballSHA256': hashlib.sha256(tarball.read_bytes()).hexdigest(),
                }
                (bundle / 'manifest.json').write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    unpack_bundle(bundle, Path(d) / 'dst', COMMIT, '1', '1', 'arm64', XCODE)


class C107TimeoutRemediationContracts(unittest.TestCase):
    def test_world_media_concurrency_and_announcement_60hz_fix(self):
        media = (ROOT / 'App/Components/TimelineMedia.swift').read_text(encoding='utf-8')
        self.assertIn('actor PublicImageDecodeBudget', media)
        self.assertIn('while active >= 4', media)
        self.assertIn('Task<UIImage, Error>.detached(priority: .utility)', media)
        self.assertIn('if next != visible { visible = next }', media)
        poster = (ROOT / 'App/Components/PublicMediaPoster.swift').read_text(encoding='utf-8')
        self.assertIn('await Task.yield()', poster)
        marquee = (ROOT / 'App/Components/RollingAnnouncementTitles.swift').read_text(encoding='utf-8')
        timeline_body = marquee.split('SwiftUI.TimelineView(', 1)[1].split('.background {', 1)[0]
        self.assertNotIn('AnnouncementWidth', timeline_body)
        self.assertNotIn('GeometryReader', timeline_body)
        self.assertIn('AnnouncementWidth.self', marquee.split('.background {', 1)[1])

    def test_workflow_standard_jobs_use_arm64_and_historical_probes_stay_intel(self):
        workflow = (ROOT / '.github/workflows/four-tabs.yml').read_text(encoding='utf-8')
        standard, historical = workflow.split('  diagnostic-world-page2-poster:\n', 1)
        self.assertNotIn('macos-15-intel', standard)
        self.assertIn('runs-on: macos-15', standard)
        self.assertIn('test "$(uname -m)" = arm64', standard)
        self.assertIn('macos-15-intel', historical)
        self.assertEqual(historical.count('runs-on: macos-15-intel'), 4)


if __name__ == '__main__':
    unittest.main()
