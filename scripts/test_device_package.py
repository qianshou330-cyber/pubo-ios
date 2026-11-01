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


if __name__ == '__main__':
    unittest.main()
