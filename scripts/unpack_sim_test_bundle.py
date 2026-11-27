"""Fail-closed verification and safe extraction of shared Simulator test products."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import posixpath
import re
import shutil
import subprocess
import tarfile


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_member_path(name):
    if not name or name.startswith('/') or '\x00' in name:
        raise ValueError(f'Unsafe archive member path: {name!r}')
    normalized = posixpath.normpath(name)
    parts = normalized.split('/')
    if parts[0] != 'Products' or '..' in parts:
        raise ValueError(f'Archive member escapes Products root: {name!r}')
    return normalized


def _validate_archive(archive):
    for member in archive.getmembers():
        normalized = _safe_member_path(member.name)
        if member.isdev() or member.isfifo():
            raise ValueError(f'Disallowed special file in archive: {member.name!r}')
        if member.issym():
            if not member.linkname or member.linkname.startswith('/') or '\x00' in member.linkname:
                raise ValueError(f'Unsafe absolute symlink in archive: {member.name!r} -> {member.linkname!r}')
            resolved = posixpath.normpath(posixpath.join(posixpath.dirname(normalized), member.linkname))
            if resolved != 'Products' and not resolved.startswith('Products/'):
                raise ValueError(f'Symlink escapes Products root: {member.name!r} -> {member.linkname!r}')
        elif member.islnk():
            _safe_member_path(member.linkname)


def unpack_bundle(bundle_dir, derived_data, expected_commit, expected_run_id, expected_run_attempt,
                  expected_arch, expected_xcode_version, copy_xcodegen_meta=None):
    src = Path(bundle_dir)
    manifest_path = src / 'manifest.json'
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise ValueError(f'Missing or unsafe manifest: {manifest_path}')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))

    if manifest.get('schemaVersion') != 1:
        raise ValueError('Unsupported sim test bundle schemaVersion')
    checks = [
        ('commit', expected_commit),
        ('runId', str(expected_run_id)),
        ('runAttempt', str(expected_run_attempt)),
        ('architecture', expected_arch),
        ('xcodeVersion', expected_xcode_version.strip()),
    ]
    for field, expected in checks:
        if manifest.get(field) != expected:
            raise ValueError(f'Manifest {field} mismatch: expected {expected!r}, got {manifest.get(field)!r}')

    tar_name = manifest.get('tarballName', '')
    if Path(tar_name).name != tar_name or tar_name != 'products.tar.gz':
        raise ValueError(f'Unexpected tarball name: {tar_name!r}')
    tarball = src / tar_name
    if not tarball.is_file() or tarball.is_symlink():
        raise ValueError(f'Missing or unsafe tarball: {tarball}')
    actual_tar_sha = sha256_file(tarball)
    if actual_tar_sha != manifest.get('tarballSHA256'):
        raise ValueError('Tarball SHA-256 mismatch')

    xctestrun_name = manifest.get('xctestrunName', '')
    if Path(xctestrun_name).name != xctestrun_name or not xctestrun_name.endswith('.xctestrun'):
        raise ValueError(f'Invalid xctestrunName in manifest: {xctestrun_name!r}')

    build_root = Path(derived_data) / 'Build'
    products_root = build_root / 'Products'
    if products_root.exists():
        shutil.rmtree(products_root)
    build_root.mkdir(parents=True, exist_ok=True)

    extract_kwargs = {'set_attrs': True}
    if hasattr(tarfile, 'tar_filter'):
        extract_kwargs['filter'] = 'tar'
    with tarfile.open(tarball, 'r:gz') as archive:
        _validate_archive(archive)
        for member in archive.getmembers():
            archive.extract(member, path=build_root, **extract_kwargs)

    xctestrun = products_root / xctestrun_name
    if not xctestrun.is_file() or xctestrun.is_symlink():
        raise ValueError(f'Extracted xctestrun missing or unsafe: {xctestrun}')
    if sha256_file(xctestrun) != manifest.get('xctestrunSHA256'):
        raise ValueError('Extracted xctestrun SHA-256 mismatch')

    (Path(derived_data) / 'xctestrun.path').write_text(str(xctestrun.resolve()) + '\n', encoding='utf-8')
    if copy_xcodegen_meta:
        meta_dir = Path(copy_xcodegen_meta)
        meta_dir.mkdir(parents=True, exist_ok=True)
        if not manifest.get('xcodegenVersion') or not manifest.get('xcodegenBrewPackage'):
            raise ValueError('Manifest missing xcodegen provenance metadata')
        (meta_dir / 'xcodegen-version.txt').write_text(manifest['xcodegenVersion'] + '\n', encoding='utf-8')
        (meta_dir / 'xcodegen-brew-package.txt').write_text(manifest['xcodegenBrewPackage'] + '\n', encoding='utf-8')
    return xctestrun.resolve(), manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', default='build/sim-test-bundle')
    parser.add_argument('--derived-data', default='build/debug')
    parser.add_argument('--copy-xcodegen-meta', default='')
    args = parser.parse_args()

    commit = os.environ['GITHUB_SHA']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise SystemExit('Invalid GITHUB_SHA')
    run_id = os.environ['GITHUB_RUN_ID']
    run_attempt = os.environ['GITHUB_RUN_ATTEMPT']
    arch = platform.machine()
    xcode_version = subprocess.check_output(['xcodebuild', '-version'], text=True, timeout=30).strip()

    xctestrun, manifest = unpack_bundle(
        args.bundle, args.derived_data, commit, run_id, run_attempt, arch, xcode_version,
        copy_xcodegen_meta=args.copy_xcodegen_meta or None,
    )
    github_env = os.environ.get('GITHUB_ENV')
    if github_env:
        with Path(github_env).open('a', encoding='utf-8') as handle:
            handle.write(f'PUBO_XCTESTRUN={xctestrun}\n')
    print(json.dumps({
        'status': 'VERIFIED',
        'xctestrun': str(xctestrun),
        'architecture': manifest['architecture'],
        'commit': manifest['commit'],
    }, sort_keys=True))


if __name__ == '__main__':
    main()
