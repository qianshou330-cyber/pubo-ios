"""Pack prebuilt Debug iOS Simulator test products with a tamper-evident manifest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tarfile


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def pack_bundle(derived_data, output_dir, commit, run_id, run_attempt, arch, xcode_version,
                xcodegen_version='', xcodegen_brew_package=''):
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('commit must be a 40-character lowercase hex SHA')
    if not re.fullmatch(r'[1-9][0-9]*', str(run_id)) or not re.fullmatch(r'[1-9][0-9]*', str(run_attempt)):
        raise ValueError('runId and runAttempt must be positive integers')
    if not arch or not xcode_version.strip():
        raise ValueError('architecture and xcodeVersion are required')

    products_dir = Path(derived_data) / 'Build' / 'Products'
    if not products_dir.is_dir() or products_dir.is_symlink():
        raise ValueError(f'Missing Build/Products directory: {products_dir}')

    xctestruns = sorted(p for p in products_dir.iterdir() if p.suffix == '.xctestrun' and p.is_file() and not p.is_symlink())
    if len(xctestruns) != 1:
        raise ValueError(f'Expected exactly one .xctestrun in {products_dir}, found {len(xctestruns)}')
    xctestrun = xctestruns[0]

    sim_dir = products_dir / 'Debug-iphonesimulator'
    for required_bundle in ('PUBO.app', 'PUBOUITests-Runner.app'):
        target = sim_dir / required_bundle
        if not target.is_dir():
            raise ValueError(f'Missing built simulator bundle: {target}')

    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    tarball = out / 'products.tar.gz'
    with tarfile.open(tarball, 'w:gz', compresslevel=6) as archive:
        archive.add(products_dir, arcname='Products', recursive=True)

    manifest = {
        'schemaVersion': 1,
        'commit': commit,
        'runId': str(run_id),
        'runAttempt': str(run_attempt),
        'architecture': arch,
        'xcodeVersion': xcode_version.strip(),
        'xctestrunName': xctestrun.name,
        'xctestrunSHA256': sha256_file(xctestrun),
        'tarballName': tarball.name,
        'tarballSHA256': sha256_file(tarball),
        'tarballBytes': tarball.stat().st_size,
        'xcodegenVersion': xcodegen_version.strip(),
        'xcodegenBrewPackage': xcodegen_brew_package.strip(),
    }
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--derived-data', default='build/debug')
    parser.add_argument('--output', default='build/sim-test-bundle')
    parser.add_argument('--xcodegen-version-file', default='')
    parser.add_argument('--xcodegen-brew-file', default='')
    args = parser.parse_args()

    commit = os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True, timeout=15).strip()
    run_id = os.environ.get('GITHUB_RUN_ID', '1')
    run_attempt = os.environ.get('GITHUB_RUN_ATTEMPT', '1')
    arch = platform.machine()
    xcode_version = subprocess.check_output(['xcodebuild', '-version'], text=True, timeout=30).strip()
    xg_ver = Path(args.xcodegen_version_file).read_text(encoding='utf-8').strip() if args.xcodegen_version_file and Path(args.xcodegen_version_file).is_file() else ''
    xg_brew = Path(args.xcodegen_brew_file).read_text(encoding='utf-8').strip() if args.xcodegen_brew_file and Path(args.xcodegen_brew_file).is_file() else ''

    manifest = pack_bundle(args.derived_data, args.output, commit, run_id, run_attempt, arch, xcode_version, xg_ver, xg_brew)
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
