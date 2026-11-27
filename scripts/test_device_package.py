import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('device_package', Path(__file__).with_name('package-device.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def binary(platform=2, signature=False):
    commands = struct.pack('<6I', 0x32, 24, platform, 17 << 16, 18 << 16, 0)
    if signature:
        commands += struct.pack('<4I', 0x1D, 16, 0, 0)
    return struct.pack('<8I', 0xFEEDFACF, 0x100000C, 0, 2, 2 if signature else 1, len(commands), 0, 0) + commands


class DevicePackageTests(unittest.TestCase):
    def test_project_and_target_versions_must_match(self):
        project = 'MARKETING_VERSION: 0.2.0\nCURRENT_PROJECT_VERSION: 21\n  MARKETING_VERSION: 0.2.0\n  CURRENT_PROJECT_VERSION: 21\n'
        self.assertEqual(module.project_version(project), ('0.2.0', '21'))
        with self.assertRaisesRegex(ValueError, 'build numbers disagree'):
            module.project_version(project.replace('  CURRENT_PROJECT_VERSION: 21', '  CURRENT_PROJECT_VERSION: 20'))
        with self.assertRaisesRegex(ValueError, 'marketing versions disagree'):
            module.project_version(project.replace('  MARKETING_VERSION: 0.2.0', '  MARKETING_VERSION: 0.1.0'))

    def test_unsigned_device(self):
        self.assertEqual(module.inspect_macho(binary())['platformID'], 2)

    def test_arm64_simulator_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'not iOS device'):
            module.inspect_macho(binary(platform=7))

    def test_signed_binary_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'code signature'):
            module.inspect_macho(binary(signature=True))

    def test_corrupt_commands_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Truncated'):
            module.inspect_macho(binary()[:-1])

    def test_other_architecture_is_rejected(self):
        data = bytearray(binary()); struct.pack_into('<I', data, 4, 0x1000007)
        with self.assertRaisesRegex(ValueError, 'arm64'):
            module.inspect_macho(data)

    def test_release_hygiene_accepts_clean_bundle_and_rejects_leaks(self):
        good_info = {
            'ITSAppUsesNonExemptEncryption': False,
            'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon'}},
        }
        module.verify_release_hygiene(good_info, {'PUBO', 'Info.plist', 'PrivacyInfo.xcprivacy', 'AdminCatalog.json'}, b'clean binary')
        with self.assertRaisesRegex(ValueError, 'ITSAppUsesNonExemptEncryption'):
            module.verify_release_hygiene({'CFBundleIcons': good_info['CFBundleIcons']}, {'PUBO'}, b'clean')
        with self.assertRaisesRegex(ValueError, 'AppIcon'):
            module.verify_release_hygiene({'ITSAppUsesNonExemptEncryption': False}, {'PUBO'}, b'clean')
        for leaked in sorted(module.FORBIDDEN_RELEASE_RESOURCES):
            with self.assertRaisesRegex(ValueError, 'leaked into Release bundle'):
                module.verify_release_hygiene(good_info, {'PUBO', leaked}, b'clean')
        for marker in module.FORBIDDEN_RELEASE_BINARY_MARKERS:
            with self.assertRaisesRegex(ValueError, 'leaked into Release binary'):
                module.verify_release_hygiene(good_info, {'PUBO'}, b'prefix ' + marker + b' suffix')

    def test_privacy_manifest_requires_no_tracking_and_user_defaults_reason(self):
        valid = {
            'NSPrivacyTracking': False,
            'NSPrivacyAccessedAPITypes': [
                {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults', 'NSPrivacyAccessedAPITypeReasons': ['CA92.1']}
            ],
        }
        module.verify_privacy_manifest(valid)
        with self.assertRaisesRegex(ValueError, 'Tracking'):
            module.verify_privacy_manifest({'NSPrivacyTracking': True, 'NSPrivacyAccessedAPITypes': valid['NSPrivacyAccessedAPITypes']})
        with self.assertRaisesRegex(ValueError, 'CA92.1'):
            module.verify_privacy_manifest({'NSPrivacyTracking': False, 'NSPrivacyAccessedAPITypes': []})

    def test_repo_pre_submission_release_contracts(self):
        root = Path(__file__).resolve().parents[1]
        project = (root / 'project.yml').read_text()
        self.assertIn('ITSAppUsesNonExemptEncryption: false', project)
        for name in (
            'NotificationVisualCases.json',
            'TimelineVisualCases.json',
            'ChatParity.json',
            'TimelineParity.json',
            'PublicPosterRedFixture.mp4',
        ):
            self.assertIn(name, project)
        transport = (root / 'App/Infrastructure/FixtureTransport.swift').read_text()
        self.assertTrue(transport.startswith('#if DEBUG\n'))
        self.assertTrue(transport.rstrip().endswith('#endif'))
        reg = (root / 'App/Features/AuthRegistration.swift').read_text()
        self.assertNotIn('misskey-hub.net', reg)
        self.assertIn('auth.agreeNotes', reg)
        profile = (root / 'App/Features/ProfileView.swift').read_text()
        self.assertIn('session.meta["privacyPolicyUrl"].string', profile)
        self.assertIn('session.meta["termsOfServiceUrl"].string', profile)


if __name__ == '__main__':
    unittest.main()
