"""Fail-closed aggregate for the four same-attempt navigation artifacts."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import zlib

from four_tabs_gate import SUITE, declared_tests, complete, successful_method_ids
from iphone_qa_matrix import MATRIX, RUNTIME, summary_matches_device


class GateError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise GateError(message)


def read_json(path):
    require(path.is_file() and not path.is_symlink(), f'Missing/unsafe JSON: {path}')
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(GateError('Nonfinite JSON')))


def png(path):
    require(path.is_file() and not path.is_symlink(), 'Missing/unsafe PNG')
    data = path.read_bytes()
    require(data[:8] == b'\x89PNG\r\n\x1a\n', 'Invalid PNG signature')
    offset, kinds, compressed = 8, [], b''
    while offset < len(data):
        require(offset + 12 <= len(data), 'Truncated PNG')
        length = struct.unpack('>I', data[offset:offset+4])[0]
        end = offset + 12 + length
        require(end <= len(data), 'Truncated PNG chunk')
        kind = data[offset+4:offset+8]
        body = data[offset+8:offset+8+length]
        crc = struct.unpack('>I', data[end-4:end])[0]
        require(zlib.crc32(kind + body) & 0xffffffff == crc, 'PNG CRC failure')
        if kind == b'IHDR':
            require(not kinds and length == 13, 'Invalid PNG IHDR')
            width, height = struct.unpack('>II', body[:8])
            require(0 < width <= 10000 and 0 < height <= 10000, 'Invalid PNG size')
        if kind == b'IDAT':
            compressed += body
        kinds.append(kind)
        offset = end
        if kind == b'IEND':
            require(not body and offset == len(data), 'Trailing PNG data')
            break
    require(kinds and kinds[0] == b'IHDR' and kinds[-1] == b'IEND' and compressed,
            'Incomplete PNG')
    decoder = zlib.decompressobj()
    decoded = decoder.decompress(compressed, 128 * 1024 * 1024)
    require(decoded and decoder.eof and not decoder.unused_data, 'Invalid PNG image stream')
    return hashlib.sha256(data).hexdigest()


def exact_methods(value, expected, label):
    require(isinstance(value, list) and all(isinstance(x, str) for x in value), label + ' malformed')
    require(len(value) == len(set(value)) and set(value) == set(expected), label + ' mismatched/duplicate')


def verify(artifact_root, sha, run, attempt, source=None):
    from four_tabs_gate import SHARDS
    require(isinstance(sha, str) and re.fullmatch(r'[0-9a-f]{40}', sha), 'Invalid expected SHA')
    require(re.fullmatch(r'[1-9][0-9]*', str(run)) and re.fullmatch(r'[1-9][0-9]*', str(attempt)),
            'Invalid expected run/attempt')
    require(set(SHARDS) == {'routing', 'interaction'}, 'Invalid shard definition')
    require(sorted(map(len, SHARDS.values())) == [6, 7], 'Expected strict 6/7 split')
    declared = declared_tests(Path(source)) if source else declared_tests()
    all_names = [x for values in SHARDS.values() for x in values]
    require(len(declared) == 13 and len(set(declared)) == 13, 'Source declarations duplicated/missing')
    exact_methods(all_names, declared, 'Explicit/source scope')
    root = Path(artifact_root)
    expected_dirs = {f'four-tabs-evidence-{size}-{shard}-{sha}-a{attempt}'
                     for size in ('small', 'large') for shard in SHARDS}
    require(root.is_dir() and not root.is_symlink(), 'Missing artifact root')
    require({p.name for p in root.iterdir()} == expected_dirs, 'Exact four artifact directories required')
    seen_udids = set()
    counts = {'small': 0, 'large': 0}
    for size in counts:
        for shard, names in SHARDS.items():
            directory = root / f'four-tabs-evidence-{size}-{shard}-{sha}-a{attempt}'
            require(directory.is_dir() and not directory.is_symlink(), 'Unsafe artifact directory')
            require(not any(p.is_symlink() for p in directory.rglob('*')), 'Symlink inside artifact')
            receipt = read_json(directory / 'four-tabs-environment.json')
            for key, expected in [('commit', sha), ('runId', str(run)), ('runAttempt', str(attempt)),
                                  ('size', size), ('shard', shard), ('tests', 'PASS'), ('suite', SUITE),
                                  ('schemaVersion', 2), ('repository', 'qianshou330-cyber/pubo-ios'),
                                  ('device', MATRIX[size]['model']), ('runtime', RUNTIME),
                                  ('deviceTypeIdentifier', MATRIX[size]['deviceTypeIdentifier']),
                                  ('methodGate', 'PASS'), ('testExitCode', 0), ('boot', 'READY')]:
                require(type(receipt.get(key)) is type(expected) and receipt[key] == expected, f'Receipt {key} mismatch')
            udid = receipt.get('udid')
            require(isinstance(udid, str) and re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', udid), 'Invalid UDID')
            require(udid not in seen_udids, 'Duplicate shard UDID')
            seen_udids.add(udid)
            started = receipt.get('started')
            require(type(started) in (float, int) and math.isfinite(started) and started > 0, 'Invalid start')
            ids = [f'{SUITE}/{name}()' for name in names]
            exact_methods(receipt.get('selectedMethods'), ids, 'Selected methods')
            exact_methods(receipt.get('successfulMethodIDs'), ids, 'Passing methods')
            require(type(receipt.get('expectedTests')) is int and receipt['expectedTests'] == len(ids), 'Wrong expected count')
            summary = read_json(directory / 'four-tabs-summary.json')
            require(complete(summary, len(ids)), 'Result summary failed')
            require(summary_matches_device(summary, size, udid, len(ids)), 'Result simulator identity or per-device counts mismatch')
            exact_methods(successful_method_ids(read_json(directory / 'four-tabs-tests.json'), shard), ids, 'Raw xcresult methods')
            # Only count manifest-backed exported test images, never a runner-failure snapshot.
            shots = directory / 'screenshots'
            exported = {}
            for manifest_path in shots.rglob('manifest.json'):
                manifest = read_json(manifest_path)
                require(isinstance(manifest, list), 'Malformed screenshot manifest')
                for test in manifest:
                    require(isinstance(test, dict) and test.get('testIdentifier') in ids, 'Unexpected screenshot test')
                    require(isinstance(test.get('attachments'), list), 'Missing attachments')
                    for attachment in test['attachments']:
                        filename = attachment.get('exportedFileName')
                        require(isinstance(filename, str) and Path(filename).name == filename, 'Unsafe attachment filename')
                        if not filename.lower().endswith('.png'):
                            continue
                        require(attachment.get('deviceId') == udid, 'Wrong screenshot device')
                        stamp = attachment.get('timestamp')
                        require(type(stamp) in (int, float) and math.isfinite(stamp) and stamp >= started, 'Stale screenshot')
                        require(attachment.get('isAssociatedWithFailure') is False, 'Failure screenshot')
                        path = manifest_path.parent / filename
                        require(path not in exported, 'Duplicate exported PNG')
                        exported[path] = png(path)
            require(type(receipt.get('exportedPNGs')) is int and receipt['exportedPNGs'] == len(exported), 'Export count mismatch')
            require(len(exported) >= 8, 'At least 8 real exported PNG per shard required')
            counts[size] += len(exported)
            proof = read_json(directory / 'four-tabs-badge-pixels.json')
            if shard == 'interaction':
                require(receipt.get('pixelGate') == 'NOT_APPLICABLE' and proof.get('status') == 'NOT_APPLICABLE', 'Interaction badge must be N/A')
                require(proof.get('shard') == shard and proof.get('commit') == sha and
                        proof.get('expectedDevice') == udid and proof.get('started') == started, 'Interaction proof provenance mismatch')
            else:
                require(receipt.get('pixelGate') == proof.get('status') == 'PASS', 'Routing badge failed')
                require(proof.get('commit') == sha and proof.get('expectedDevice') == proof.get('deviceId') == udid
                        and proof.get('started') == started, 'Badge provenance mismatch')
                phases = proof.get('phases')
                require(isinstance(phases, list) and [p.get('phase') for p in phases] == ['initial', 'notifications', 'returned'], 'Badge phase coverage mismatch')
                previous = started
                for phase in phases:
                    require(phase.get('ocr', {}).get('text') == '2', 'Badge OCR mismatch')
                    attachments = phase.get('attachments', {})
                    require(set(attachments) == {'screen', 'tab', 'glyphs', 'readings', 'accessibility'}, 'Incomplete badge attachments')
                    timestamps = []
                    for kind, item in attachments.items():
                        stamp = item.get('timestamp')
                        require(type(stamp) in (int, float) and math.isfinite(stamp) and stamp >= previous, 'Badge phase timing mismatch')
                        timestamps.append(stamp)
                        if kind in ('screen', 'tab', 'glyphs'):
                            matches = [p for p in exported if p.name == item.get('file')]
                            require(len(matches) == 1 and exported[matches[0]] == item.get('sha256'), 'Badge PNG provenance mismatch')
                    require(max(timestamps) - min(timestamps) <= 30, 'Badge capture timing spread')
                    previous = max(timestamps) + 0.000001
    require(all(value >= 8 for value in counts.values()), 'At least 8 exported PNG per size required')
    return {'status': 'PASS', 'commit': sha, 'runId': str(run), 'runAttempt': str(attempt), 'exportedPNGs': counts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact_root')
    parser.add_argument('--sha', default=os.environ.get('GITHUB_SHA'))
    parser.add_argument('--run', default=os.environ.get('GITHUB_RUN_ID'))
    parser.add_argument('--attempt', default=os.environ.get('GITHUB_RUN_ATTEMPT'))
    args = parser.parse_args()
    try:
        result = verify(args.artifact_root, args.sha, args.run, args.attempt)
    except (OSError, ValueError, TypeError, KeyError, AttributeError, struct.error, zlib.error) as error:
        print(json.dumps({'status': 'FAIL', 'error': str(error)}))
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
