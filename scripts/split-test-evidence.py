"""Lossless stdlib archive, 240 MiB parts, SHA256 manifest; never delete originals.
Reassemble in manifest order, verify SHA256, then tar -xzf combined.tar.gz.
"""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile
import tempfile


def split_evidence(root, limit=240 * 1024 * 1024):
    output = root / 'evidence-parts'
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise RuntimeError('Refusing to mix evidence from different attempts')
    sources = sorted(root.glob('*.xcresult')) + sorted((root / 'screenshots').rglob('*.mp4'))
    manifest = {'format': 'concatenated tar.gz', 'sources': [str(p.relative_to(root)) for p in sources], 'parts': []}
    if not sources:
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
        return manifest
    whole = hashlib.sha256()
    with tempfile.TemporaryFile() as archive:
        with tarfile.open(fileobj=archive, mode='w:gz') as tar:
            for source in sources:
                tar.add(source, arcname=str(source.relative_to(root)))
        archive.seek(0)
        index = 0
        while True:
            data = archive.read(limit)
            if not data:
                break
            name = f'evidence.tar.gz.part-{index:03d}'
            (output / name).write_bytes(data)
            whole.update(data)
            manifest['parts'].append({'file': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
            index += 1
    manifest['archive_sha256'] = whole.hexdigest()
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    # The workflow uploads 16 parts independently. Overflow remains on disk and
    # is uploaded separately, but must fail the job, never silently truncate.
    if len(manifest['parts']) > 16:
        raise RuntimeError('Evidence exceeded 16 parts; overflow preserved, increase upload slots')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path('build'))
    args = parser.parse_args()
    split_evidence(args.root)
