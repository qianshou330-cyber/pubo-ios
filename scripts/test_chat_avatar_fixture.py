"""Validate the synthetic avatar without changing the existing media fixtures."""
import base64
import hashlib
import json
import pathlib
import re
import struct
import unittest
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def native_media():
    source = (ROOT / 'App/Infrastructure/GIFTestFixtures.swift').read_text()
    return {key: base64.b64decode(value) for key, value in re.findall(
        r'static let (\w+) = Data\(base64Encoded: "([^"]+)"', source)}


class ChatAvatarFixtureTests(unittest.TestCase):
    def test_avatar_is_crc_valid_opaque_square_rgba(self):
        data = native_media()['avatar']
        self.assertEqual(hashlib.sha256(data).hexdigest(), '31cc2d4d79879640d0be7e2c7b2a4c45b05a9a636b63691f76eae728eb9ccb0b')
        self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
        offset, compressed, header = 8, b'', None
        while offset < len(data):
            length = struct.unpack('>I', data[offset:offset + 4])[0]
            kind, payload = data[offset + 4:offset + 8], data[offset + 8:offset + 8 + length]
            crc = struct.unpack('>I', data[offset + 8 + length:offset + 12 + length])[0]
            self.assertEqual(crc, zlib.crc32(kind + payload) & 0xffffffff)
            if kind == b'IHDR':
                header = struct.unpack('>IIBBBBB', payload)
            if kind == b'IDAT':
                compressed += payload
            offset += length + 12
        self.assertEqual(offset, len(data))
        self.assertEqual(header, (128, 128, 8, 6, 0, 0, 0))
        pixels = zlib.decompress(compressed)
        self.assertEqual(len(pixels), 128 * (128 * 4 + 1))
        colors = set()
        for y in range(128):
            row = pixels[y * 513:(y + 1) * 513]
            self.assertEqual(row[0], 0, 'Deterministic fixture uses unfiltered rows')
            self.assertTrue(all(alpha == 255 for alpha in row[4::4]))
            colors.update(row[i:i + 4] for i in range(1, 513, 4))
        self.assertGreaterEqual(len(colors), 3, 'An actual geometric avatar, not a generic single-pixel placeholder')

    def test_existing_still_and_animation_bytes_are_unchanged(self):
        media = native_media()
        expected = {
            'looping': '1adbec57630907ad90b11b9853f37bf9526b7af03aaec811ba1ebabeeb448457',
            'finite': '5241d5c2e362b4166245afaaffc0894c62cf549cd5c88c42063c95e6beeac870',
            'still': 'f98f71bf4fb2d3425dd858d90fb0ba7c6313e50206bc09bf3328b3e30b22dfe9',
            'large': '93fd140561df40f959760a492facf8d266a78508c0d5d6fea9bfe3ed3c7c2ae2',
        }
        for name, digest in expected.items():
            self.assertEqual(hashlib.sha256(media[name]).hexdigest(), digest, name)

    def test_every_chat_avatar_uses_dedicated_fixture(self):
        values = []
        def walk(value):
            if isinstance(value, dict):
                for key, child in value.items():
                    if key == 'avatarUrl':
                        values.append(child)
                    walk(child)
            elif isinstance(value, list):
                for child in value:
                    walk(child)
        walk(json.loads((ROOT / 'App/Resources/ChatParity.json').read_text()))
        self.assertEqual(len(values), 18)
        self.assertEqual(set(values), {'https://timeline-fixture.invalid/avatar.png'})

    def test_debug_route_and_crop_match_avatar_policy(self):
        route = (ROOT / 'App/Infrastructure/TimelineTestFixtures.swift').read_text()
        self.assertLess(route.index('if url.path == "/avatar.png" { return GIFTestFixtures.avatar }'), route.index('if url.path.hasSuffix(".png")'))
        source = (ROOT / 'App/Components/CommonViews.swift').read_text()
        avatar = source.split('struct Avatar: View {', 1)[1].split('struct RoleBadges:', 1)[0]
        debug = avatar.split('#if DEBUG', 1)[1].split('#else', 1)[0]
        self.assertIn('PublicAnimatedAsset(url: url, fit: false)', debug)
        self.assertIn('image.resizable().scaledToFill()', avatar)
        self.assertNotIn('PublicAnimatedAsset', avatar.split('#else', 1)[1].split('#endif', 1)[0])


if __name__ == '__main__':
    unittest.main()
