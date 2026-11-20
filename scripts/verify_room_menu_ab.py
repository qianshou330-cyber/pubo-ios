"""Classify two exact synthetic observations; never an acceptance result."""
import argparse
import json
from pathlib import Path
import math
import re
import struct

from four_tabs_gate import complete
from iphone_qa_matrix import MATRIX, RUNTIME, summary_matches_device
from ui_selection import ROOM_MENU_AB_METHODS, ROOM_MENU_AB_SHARD, ROOM_MENU_AB_SUITE
from verify_navigation_shards import png, read_json, require

LABEL = '删除消息'
BLOCK = 'ROOM_MENU_AB_PRECONDITION:'
IDS = {f'{ROOM_MENU_AB_SUITE}/{method}()': arm for arm, method in ROOM_MENU_AB_METHODS.items()}
LABELS = {LABEL, '复制', '拷贝', '举报', '查找', '翻译', '全选'}
UNAVAILABLE = 'RUNNER_OR_EVIDENCE_BLOCKED'


def exact_tree(tree):
    seen = []

    def walk(nodes, suite=None, bundle=None):
        require(isinstance(nodes, list), 'Invalid xcresult tree')
        for node in nodes:
            require(isinstance(node, dict), 'Invalid xcresult node')
            typ = node.get('nodeType')
            here_suite = (node.get('name') or node.get('nodeIdentifier')) if typ == 'Test Suite' else suite
            here_bundle = (node.get('name') or node.get('nodeIdentifier')) if typ == 'Test Bundle' else bundle
            if typ == 'Test Case':
                ident = node.get('nodeIdentifier')
                require(ident in IDS and node.get('result') == 'Passed' and
                        here_suite in (None, ROOM_MENU_AB_SUITE) and here_bundle in (None, 'PUBOUITests') and
                        node.get('children', []) == [], 'Unexpected, unsuccessful, or wrong-suite test')
                seen.append(ident)
            if 'children' in node:
                walk(node['children'], here_suite, here_bundle)
    walk(tree.get('testNodes'))
    require(len(seen) == len(IDS) and set(seen) == set(IDS), 'Missing or duplicate A/B methods')


def numbers(value, count):
    require(isinstance(value, list) and len(value) == count and all(
        type(v) in (int, float) and math.isfinite(v) and abs(v) < 2000 for v in value), 'Invalid geometry')
    return value


def rect(r):
    x, y, w, h = numbers(r, 4)
    require(w > 0 and h > 0, 'Empty geometry')
    return x, y, x+w, y+h


def contains(r, p):
    return r[0] <= p[0] < r[2] and r[1] <= p[1] < r[3]


def validate_arm(receipt, arm):
    constants = {'schema': 1, 'arm': arm, 'theme': 'light', 'fixture': 'socialroom/room0002',
                 'gesture': 'ownText.press' if arm == 'text' else 'bubble-padding.press',
                 'pressCount': 1, 'pressSeconds': 1, 'deleteQueryTimeoutSeconds': 5}
    require(isinstance(receipt, dict) and all(type(receipt.get(k)) is type(v) and receipt[k] == v
                                            for k, v in constants.items()), 'Wrong fixture, arm, or gesture')
    require(type(receipt.get('deleteQueryFound')) is bool, 'Missing bounded query result')
    for key in ('preLabels', 'postLabels'):
        labels = receipt.get(key)
        require(isinstance(labels, list) and all(isinstance(s, str) and s in LABELS for s in labels) and
                labels == sorted(set(labels)), 'Malformed sampled AX labels')
    require(LABEL not in receipt['preLabels'], 'Delete was present before the press')
    w, t, m, v, c = (rect(receipt.get(k)) for k in ('window', 'text', 'overflow', 'timeline', 'composerInput'))
    p = numbers(receipt.get('intendedPoint'), 2)
    require(w == (0, 0, 402, 874) and contains(w, t[:2]) and t[2] <= w[2] and t[3] <= w[3], 'Wrong window')
    center = ((t[0]+t[2])/2, (t[1]+t[3])/2)
    padding = (t[0]-6, center[1])
    expected = center if arm == 'text' else padding
    require(all(abs(a-b) < 1e-5 for a, b in zip(p, expected)) and
            all(contains(w, point) and contains(v, point) and not contains(m, point) and point[1] < c[1]
                for point in (center, padding)) and m[2]+2 <= padding[0] and not contains(t, padding),
            'Outside intended text or safe padding lane')
    observed, snapshot = receipt['deleteQueryFound'], LABEL in receipt['postLabels']
    return 'OBSERVED' if observed and snapshot else ('NOT_OBSERVED' if not observed and not snapshot else 'INCONSISTENT')


def attachment_group(root, group, arm, udid, start, finish):
    require(isinstance(group, list), 'Invalid attachment list')
    matched, times = {}, {}
    for label, extension in [('pre-ax', '.txt'), ('post-ax', '.txt'), ('receipt', '.txt'),
                             ('pre-screen', '.png'), ('post-screen', '.png')]:
        prefix = f'room-menu-ab-{arm}-{label}_'
        entries = [a for a in group if isinstance(a, dict) and str(a.get('suggestedHumanReadableName', '')).startswith(prefix)]
        require(len(entries) == 1, f'Missing/duplicate evidence {arm}/{label}')
        entry = entries[0]
        name, stamp = entry.get('exportedFileName'), entry.get('timestamp')
        require(entry.get('deviceId') == udid and entry.get('isAssociatedWithFailure') is False and
                isinstance(name, str) and re.fullmatch(r'[0-9A-Fa-f-]{36}' + re.escape(extension), name) and
                type(stamp) in (int, float) and math.isfinite(stamp) and start <= stamp <= finish,
                'Unbound or unsafe attachment')
        path = root / name
        require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size < 20_000_000,
                'Missing or oversized attachment')
        matched[label] = path
        times[label] = stamp
    labels = ('pre-ax', 'pre-screen', 'post-ax', 'post-screen', 'receipt')
    require(len(set(matched.values())) == len(labels) and [times[key] for key in labels] == sorted(times.values()),
            'Duplicated or misordered evidence')
    require(times['post-ax'] > times['pre-screen'], 'Missing before/after chronology')
    images = {}
    for key in ('pre-screen', 'post-screen'):
        path = matched[key]
        require(struct.unpack('>II', path.read_bytes()[16:24]) == (1206, 2622), 'Wrong standard screenshot raster')
        images[key] = png(path)
    require('room.bubble.room0002' in matched['pre-ax'].read_text() and matched['post-ax'].read_text().strip(),
            'Missing pre-gesture fixture or post-gesture AX snapshot')
    receipt = read_json(matched['receipt'])
    return {'deleteAX': validate_arm(receipt, arm), 'axLabels': receipt['postLabels'],
            'imagesSHA256': images, 'intendedPoint': receipt['intendedPoint'],
            'attachments': {key: matched[key].name for key in labels}}, times


def classify(root, sha, run, attempt):
    require(isinstance(sha, str) and re.fullmatch(r'[0-9a-f]{40}', sha) and
            all(isinstance(v, str) and re.fullmatch(r'[1-9][0-9]*', v) for v in (run, attempt)), 'Invalid run identity')
    context = read_json(root / 'room-menu-ab' / 'context.json')
    pin = root / 'room-menu-ab' / 'c82-app-base.txt'
    require(pin.is_file() and pin.read_text().strip() == 'f901c5a871d423a43869f560d69b469ae82fe8b8',
            'C82 App/fixture preflight did not finish')
    require(context == {'repository': 'qianshou330-cyber/pubo-ios', 'ref': 'refs/heads/ui-four-tabs-148-20261112',
                        'commit': sha, 'runId': run, 'runAttempt': attempt}, 'Wrong run context')
    summaries = read_json(root / 'ui-0-summary.json')
    env = read_json(root / 'test-environment.json')
    require(isinstance(env, list) and len(env) == 1 and isinstance(env[0], dict), 'Missing standard-only runner')
    row = env[0]
    profile = MATRIX['small']
    udid = row.get('udid')
    require(isinstance(udid, str) and re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', udid) and
            all(row.get(k) == v for k, v in {'commit': sha, 'size': 'small', 'runtime': RUNTIME, 'device': profile['model'],
                    'deviceTypeIdentifier': profile['deviceTypeIdentifier'], 'appearance': 'light',
                    'boot': 'READY', 'selection': ROOM_MENU_AB_SHARD, 'expectedTests': 2,
                    'hostArchitecture': 'x86_64', 'xcode': 'Xcode 26.0.1\nBuild version 17A400'}.items()), 'Wrong native runner identity')
    configs = summaries.get('devicesAndConfigurations')
    require(isinstance(configs, list) and len(configs) == 1 and isinstance(configs[0], dict),
            'Missing native device configuration')
    raw_device = configs[0].get('device')
    require(isinstance(raw_device, dict) and all(raw_device.get(k) == v for k, v in
                {'deviceId': udid, 'modelName': profile['model'], 'platform': 'iOS Simulator',
                 'osVersion': MATRIX['osVersion'], 'architecture': 'x86_64'}.items()), 'Wrong raw native device')
    fixtures = [f for f in summaries.get('testFailures', []) if isinstance(f, dict) and
                f.get('testIdentifierString') in IDS and BLOCK in str(f.get('failureText', ''))]
    if fixtures:
        return {'status': 'FIXTURE_OR_PRECONDITION_BLOCKED', 'reason': fixtures[0]['failureText']}
    require(row.get('tests') == 'PASS' and summaries.get('result') == 'Passed' and summaries.get('totalTestCount') == 2
            and complete(summaries, 2) and summary_matches_device(summaries, 'small', udid, 2),
            'Required exact two native methods did not both finish')
    start, finish = summaries.get('startTime'), summaries.get('finishTime')
    require(all(type(t) in (int, float) and math.isfinite(t) for t in (start, finish))
            and 0 < start < finish, 'Missing native time bounds')
    exact_tree(read_json(root / 'room-menu-ab' / 'tests.json'))
    shots = root / 'screenshots' / '0'
    manifest = read_json(shots / 'manifest.json')
    require(isinstance(manifest, list) and all(isinstance(entry, dict) for entry in manifest), 'Invalid attachment manifest')
    groups = {entry.get('testIdentifier'): entry.get('attachments') for entry in manifest}
    require(len(manifest) == len(groups) == 2 and set(groups) == set(IDS), 'Missing/duplicate method attachments')
    arms, stamps = {}, {}
    for method, arm in IDS.items():
        arms[arm], stamps[arm] = attachment_group(shots, groups[method], arm, udid, start, finish)
    require(stamps['text']['receipt'] < stamps['padding']['pre-ax'], 'Unexpected arm order or overlapping evidence')
    filenames = [name for arm in arms.values() for name in arm['attachments'].values()]
    require(len(set(filenames)) == len(filenames), 'Reused attachment between arms')
    statuses = [arms[a]['deleteAX'] for a in ('text', 'padding')]
    status = {
        ('OBSERVED', 'OBSERVED'): 'DELETE_AX_BOTH_OBSERVED',
        ('NOT_OBSERVED', 'OBSERVED'): 'DELETE_AX_PADDING_ONLY',
        ('OBSERVED', 'NOT_OBSERVED'): 'DELETE_AX_TEXT_ONLY',
        ('NOT_OBSERVED', 'NOT_OBSERVED'): 'DELETE_AX_NEITHER_OBSERVED',
    }.get(tuple(statuses), 'DELETE_AX_INCONSISTENT')
    raw = root / 'ui-0.xcresult'
    require(raw.is_dir() and (raw / 'Info.plist').is_file(), 'Missing raw XCResult for independent review')
    video = shots / 'room-menu-ab.mp4'
    return {'status': status, 'arms': arms, 'deviceId': udid,
            'videoAvailable': video.is_file() and video.stat().st_size > 0,
            'scope': 'EXPERIMENTAL_AX_OBSERVATIONS_ONLY',
            'limits': 'Review original screenshots/video and XCResult app stdout; no presentation, gesture arbitration, delete or acceptance verdict.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build', type=Path)
    parser.add_argument('sha')
    parser.add_argument('run')
    parser.add_argument('attempt')
    args = parser.parse_args()
    try:
        report = classify(args.build, args.sha, args.run, args.attempt)
    except (ValueError, OSError, TypeError, AttributeError, KeyError, struct.error) as error:
        report = {'status': UNAVAILABLE, 'reason': str(error)}
    report.update(commit=args.sha, runId=args.run, runAttempt=args.attempt, acceptance=False)
    path = args.build / 'room-menu-ab' / 'report.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False))
    return 2 if report['status'] in (UNAVAILABLE, 'FIXTURE_OR_PRECONDITION_BLOCKED', 'DELETE_AX_INCONSISTENT') else 0


if __name__ == '__main__':
    raise SystemExit(main())
