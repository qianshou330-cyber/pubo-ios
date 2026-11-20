#!/usr/bin/env python3
"""Allowlist public receipts and complete synthetic screenshots; never archive raw replay files."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
from tempfile import TemporaryDirectory

HASH = re.compile(r'[a-f0-9]{64}\Z')
COMMIT = re.compile(r'[a-f0-9]{40}\Z')
SCOPE = {'fresh': 'FRESH_PUBLIC_H5_OBSERVED_SNAPSHOT', 'historical': 'C83_HISTORICAL_H5_CHAT_ATTESTED'}
PROFILE_PX = {'small': (804, 1748), 'large': (880, 1912)}
BASELINE = '414c972c73e55903cd4ddecd542218f148f3d6cd'
PNG = bytes.fromhex('89504e470d0a1a0a')
IEND = bytes.fromhex('0000000049454e44ae426082')
MAX_FILE = 12 * 1024 * 1024


def checked_bytes(path, maximum=1024 * 1024):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= maximum:
        raise ValueError('bad evidence size/type')
    return path.read_bytes()


def read_object(path):
    value = json.loads(checked_bytes(path))
    if not isinstance(value, dict):
        raise ValueError('bad evidence object')
    return value


def sha(data):
    return hashlib.sha256(data).hexdigest()


def store(path, obj):
    with path.open('x') as output:
        json.dump(obj, output, indent=2)
        output.write('\n')


def seal_receipt(scratch, candidate):
    folder = scratch / 'fresh'
    raw = checked_bytes(folder / 'snapshot.sealed.json')
    m = json.loads(raw)
    asserted = checked_bytes(folder / 'snapshot.sealed.sha256', 128).decode('ascii').strip()
    count = len(m['entries'])
    if not isinstance(m['entries'], dict) or not isinstance(m['rootChecks'], list):
        raise ValueError('bad seal objects')
    if (m['scope'] != SCOPE['fresh'] or m['status'] != 'SEALED' or m['candidateCommit'] != candidate
            or m['fixtureBaselineCommit'] != BASELINE or sha(raw) != asserted or not 1 <= count <= 160
            or type(m['round']) is not int or not 0 <= m['round'] <= 8
            or len(m['rootChecks']) != 2 * (m['round'] + 2)
            or not all(HASH.fullmatch(m[key]) for key in ('htmlSHA256', 'probeSHA256', 'sealedFromDraftSHA256'))):
        raise ValueError('bad seal receipt')
    return {'status': 'SEALED', 'referenceScope': SCOPE['fresh'], 'candidateCommit': candidate,
            'fixtureBaselineCommit': BASELINE, 'manifestSHA256': asserted, 'htmlSHA256': m['htmlSHA256'],
            'probeSHA256': m['probeSHA256'], 'sealedFromDraftSHA256': m['sealedFromDraftSHA256'],
            'assetCount': count, 'round': m['round'], 'rootCheckCount': len(m['rootChecks']),
            'rawSnapshotPublished': False}


def approved_pngs(result, replay, mode):
    cases = result['cases']
    if not isinstance(cases, list) or len(cases) != 4:
        raise ValueError('not four complete cases')
    images = {}
    receipts = []
    for case in cases:
        slot, theme = case['slot'], case['theme']
        if case['passed'] is not True or theme not in ('light', 'dark') or slot not in PROFILE_PX:
            raise ValueError('case is not approved')
        file = ('fresh-' if mode == 'fresh' else '') + f'h5-world-local-{slot}-{theme}.png'
        shot = case['screenshot']
        dims = PROFILE_PX[slot]
        if (file in images or shot['file'] != file or (shot['width'], shot['height']) != dims
                or case['deniedRequests'] != [] or case['errors'] != [] or not HASH.fullmatch(shot['sha256'])):
            raise ValueError('bad screenshot receipt')
        image = checked_bytes(replay / file, MAX_FILE)
        if (len(image) < 45 or not image.startswith(PNG) or image[12:16] != b'IHDR'
                or struct.unpack('>II', image[16:24]) != dims or not image.endswith(IEND)
                or sha(image) != shot['sha256']):
            raise ValueError('bad screenshot bytes')
        images[file] = image
        receipts.append({'slot': slot, 'theme': theme, 'file': file,
                         'sha256': shot['sha256'], 'width': dims[0], 'height': dims[1]})
    return images, receipts


def pack(evidence, scratch, public, candidate, mode, job_status):
    if mode not in SCOPE or not COMMIT.fullmatch(candidate):
        raise ValueError('bad runner identity')
    public.mkdir(mode=0o700)
    replay = evidence / 'replay'
    summary = {'candidateCommit': candidate, 'comparisonOnly': True, 'pairEligible': False,
               'referenceMode': mode, 'referenceScope': SCOPE[mode], 'rawSnapshotPublished': False,
               'resultBeforeUpload': job_status if job_status in ('success', 'failure', 'cancelled') else 'unknown',
               'status': 'BLOCKED', 'stage': 'BEFORE_FINAL_REPLAY', 'caseCount': 0, 'screenshots': []}
    seal = None
    if mode == 'fresh':
        try:
            seal = seal_receipt(scratch, candidate)
            store(public / 'seal-receipt.json', seal)
        except FileNotFoundError:
            pass
        except (ValueError, KeyError, TypeError, OSError):
            summary['stage'] = 'SEAL_RECEIPT_INVALID'
    if (replay / 'report.json').is_file():
        try:
            result = read_object(replay / 'report.json')
            if (result['referenceScope'] != SCOPE[mode] or result['candidateCommit'] != candidate
                    or result['pairEligible'] is not False or result['discoveryOnly'] is not False):
                raise ValueError('not final expected replay')
            if mode == 'fresh' and (not seal or any(result['fresh'][field] != seal[field]
                    for field in ('manifestSHA256', 'htmlSHA256', 'round'))):
                raise ValueError('final replay lacks exact seal')
            summary['caseCount'] = min(len(result['cases']), 4)
            if result['status'] == 'CAPTURED_NOT_YET_PAIRED':
                images, receipts = approved_pngs(result, replay, mode)
                with TemporaryDirectory(prefix='world-vetted-', dir=public.parent) as temp:
                    curated = Path(temp) / 'images'
                    curated.mkdir()
                    for name, content in images.items():
                        with (curated / name).open('xb') as output:
                            output.write(content)
                    curated.rename(public / 'images')
                summary.update(status='CAPTURED_NOT_YET_PAIRED', stage='FINAL_REPLAY_COMPLETE', screenshots=receipts)
            elif result['status'] == 'INCOMPLETE':
                summary.update(status='INCOMPLETE', stage='FINAL_REPLAY_INCOMPLETE')
            elif result.get('blockingAsset'):
                summary['stage'] = 'STATIC_PROVENANCE_BLOCKED'
            else:
                summary['stage'] = 'FINAL_REPLAY_BLOCKED'
        except (ValueError, KeyError, TypeError, OSError):
            summary['stage'] = 'FINAL_EVIDENCE_INVALID'
    elif mode == 'historical' and (evidence / 'mirror.json').is_file():
        try:
            summary['stage'] = ('AFTER_STATIC_VERIFICATION' if read_object(evidence / 'mirror.json').get('status') ==
                                'VERIFIED_STATIC_ONLY' else 'STATIC_PROVENANCE_BLOCKED')
        except (ValueError, OSError):
            summary['stage'] = 'STATIC_RECEIPT_INVALID'
    elif mode == 'fresh' and summary['stage'] == 'BEFORE_FINAL_REPLAY':
        if seal:
            summary['stage'] = 'AFTER_FRESH_SEAL'
        elif any((evidence / f'probe-{i}' / 'report.json').is_file() for i in range(9)):
            summary['stage'] = 'FRESH_WORLD_PROBE_BLOCKED'
        elif (evidence / 'fresh-init.json').is_file():
            summary['stage'] = 'FRESH_STATIC_ACQUISITION_BLOCKED'
    store(public / 'summary.json', summary)
    return summary


if __name__ == '__main__':
    job_status = os.environ['JOB_RESULT_BEFORE_UPLOAD']
    summary = pack(Path(os.environ['WORLD_EVIDENCE']), Path(os.environ['WORLD_SCRATCH']),
                   Path(os.environ['WORLD_PUBLIC_EVIDENCE']), os.environ['GITHUB_SHA'],
                   os.environ['WORLD_REFERENCE_MODE'], job_status)
    print(json.dumps(summary))
    if job_status == 'success' and summary['status'] != 'CAPTURED_NOT_YET_PAIRED':
        raise SystemExit(1)
