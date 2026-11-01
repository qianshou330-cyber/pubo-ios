"""Package a verified, unsigned iOS device app. Never accepts simulator arm64."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import struct
import subprocess
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def inspect_macho(data):
    require(len(data) >= 32, 'Truncated Mach-O')
    magic, cpu, subtype, kind, count, size, flags, reserved = struct.unpack_from('<8I', data)
    require(magic == 0xFEEDFACF and cpu == 0x100000C, 'Expected thin arm64 Mach-O')
    require(32 + size <= len(data), 'Truncated load commands')
    offset = 32
    platforms = []
    signed = False
    for _ in range(count):
        require(offset + 8 <= 32 + size, 'Invalid command header')
        command, length = struct.unpack_from('<2I', data, offset)
        require(length >= 8 and offset + length <= 32 + size, 'Invalid command length')
        if command == 0x32:  # LC_BUILD_VERSION; iOS=2, iOS Simulator=7
            require(length >= 24, 'Invalid platform command')
            platform, minimum, sdk = struct.unpack_from('<3I', data, offset + 8)
            platforms.append(platform)
        if command == 0x1D:  # LC_CODE_SIGNATURE
            signed = True
        offset += length
    require(offset == 32 + size, 'Load command size mismatch')
    require(platforms == [2], 'Mach-O is not iOS device platform')
    require(not signed, 'App must be unsigned; code signature load command found')
    return {'architecture': 'arm64', 'platform': 'iOS', 'platformID': 2, 'signed': False}


def main():
    app = Path('build/device/Build/Products/Release-iphoneos/PUBO.app')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    expected = {'CFBundleIdentifier': 'com.bolubo.native', 'CFBundleShortVersionString': '0.1.2',
                'CFBundleVersion': '4', 'MinimumOSVersion': '17.0', 'UIDeviceFamily': [1],
                'CFBundleSupportedPlatforms': ['iPhoneOS'], 'DTPlatformName': 'iphoneos'}
    for key, value in expected.items():
        require(info.get(key) == value, f'Wrong device metadata: {key}')
    require(not (app / '_CodeSignature').exists(), 'Unexpected signature directory')
    require(not (app / 'embedded.mobileprovision').exists(), 'Unexpected provisioning profile')
    executable = app / info['CFBundleExecutable']
    require(executable.name == 'PUBO' and executable.is_file(), 'Missing app executable')
    require(executable.stat().st_mode & stat.S_IXUSR, 'Executable permission missing')
    binaries = {}
    for path in app.rglob('*'):
        if path.is_file():
            data = path.read_bytes()
            if data[:4] == b'\xcf\xfa\xed\xfe':
                binaries[str(path.relative_to(app))] = inspect_macho(data)
    require('PUBO' in binaries, 'Missing verified native binary')
    codesign = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True)
    require(codesign.returncode != 0 and 'not signed at all' in codesign.stderr,
            'codesign did not confirm unsigned app')
    architectures = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).strip()
    require(architectures == 'arm64', 'Unexpected architecture')
    output = Path('build/unsigned'); output.mkdir(parents=True, exist_ok=True)
    ipa = (output / 'PUBO-0.1.2-4-iphoneos-arm64-unsigned.ipa').resolve()
    require(not ipa.exists(), 'Refusing to overwrite existing IPA')
    with tempfile.TemporaryDirectory(prefix='pubo-device-') as temporary:
        payload = Path(temporary) / 'Payload'; payload.mkdir()
        subprocess.run(['ditto', str(app), str(payload / app.name)], check=True)
        subprocess.run(['ditto', '-c', '-k', '--norsrc', '--keepParent', str(payload), str(ipa)], check=True)
    with zipfile.ZipFile(ipa) as archive:
        require(archive.testzip() is None, 'Corrupt IPA')
        names = archive.namelist()
        require(all(n.startswith('Payload/') and '..' not in Path(n).parts for n in names), 'Invalid IPA layout')
        base = 'Payload/PUBO.app/'
        require(archive.read(base + 'PUBO') == executable.read_bytes(), 'IPA executable changed')
        require(archive.read(base + 'Info.plist') == (app / 'Info.plist').read_bytes(), 'IPA metadata changed')
        require((archive.getinfo(base + 'PUBO').external_attr >> 16) & stat.S_IXUSR, 'IPA lost executable bit')
        require(not any('_CodeSignature' in n or n.endswith('embedded.mobileprovision') for n in names), 'IPA unexpectedly signed')
    result = {'status': 'PASS', 'commit': os.environ.get('GITHUB_SHA'), 'metadata': expected,
              'binaries': binaries, 'codesign': 'UNSIGNED', 'ipa': ipa.name,
              'bytes': ipa.stat().st_size, 'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
              'requiresSigningBeforeInstallation': True, 'physicalDeviceTested': False}
    Path('build/device-package.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
