"""Validate same-run native XCTest originals, not screenshots of a design mockup."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess

from iphone_qa_matrix import MATRIX, RUNTIME, SIZES, summary_matches_device
from ui_selection import MESSAGES_REDESIGN_METHODS, MESSAGES_REDESIGN_SHARD, MESSAGES_REDESIGN_SUITE

CAPTURES = dict(zip(MESSAGES_REDESIGN_METHODS, (
    ('search-preview-private0001', 'search-preview-room0001', 'unread-after-two-read-only-previews',
     'ordinary-chats-read-positive-control'),
    ('plus-scan', 'sheet-scan', 'plus-add-username', 'sheet-add-username'),
    ('long-name-preview-unread-light', 'long-name-preview-unread-dark',
     'last-row-clear-of-tab-bar-light', 'last-row-clear-of-tab-bar-dark'),
    ('private-long-press-native-menu',),
)))


def require(condition, detail):
    if not condition:
        raise ValueError(detail)


def method_id(method):
    return f'{MESSAGES_REDESIGN_SUITE}/{method}()'


def rejected_case_shape(node, suite, bundle):
    """Project only this synthetic selector and bounded, enumerated metadata."""
    def known(value, allowed):
        return 'MISSING' if value is None else value if value in allowed else 'OTHER'

    children = node.get('children', [])
    sample = []
    if isinstance(children, list):
        kinds = ('Runtime Warning', 'Failure Message', 'Test Case Run', 'Test Case', 'Test Suite')
        for child in children[:8]:
            kind = child.get('nodeType') if isinstance(child, dict) else None
            descendants = child.get('children', []) if isinstance(child, dict) else None
            sample.append(dict(kind=known(kind, kinds), descendants=(
                'INVALID' if not isinstance(descendants, list) else 'PRESENT' if descendants else 'NONE')))
    return dict(
        method=known(node.get('nodeIdentifier'), tuple(map(method_id, CAPTURES))),
        suite=known(suite, (MESSAGES_REDESIGN_SUITE,)), bundle=known(bundle, ('PUBOUITests',)),
        result=known(node.get('result'), ('Passed', 'Failed', 'Skipped', 'Expected Failure', 'Not Run')),
        children='INVALID' if not isinstance(children, list) else 'PRESENT' if children else 'NONE',
        childCount=len(children) if isinstance(children, list) else None,
        childSample=sample, childSampleTruncated=isinstance(children, list) and len(children) > 8,
    )


def verify_methods(tree, rejection=None):
    def cases(nodes, suite=None, bundle=None):
        require(isinstance(nodes, list), 'Malformed result tree')
        for node in nodes:
            kind = node['nodeType']
            if kind == 'Test Suite':
                next_suite = node.get('name') or node.get('nodeIdentifier')
            else:
                next_suite = suite
            # xcresulttool uses "UI test bundle" on current Xcode; keep the other known spelling.
            if kind.casefold() in ('test bundle', 'ui test bundle'):
                require(bundle is None, 'Unexpected nested test bundle')
                next_bundle = node.get('name') or node.get('nodeIdentifier')
                require(next_bundle == 'PUBOUITests', 'Wrong test bundle')
            else:
                next_bundle = bundle
            if kind == 'Test Case':
                valid_case = (suite == MESSAGES_REDESIGN_SUITE and bundle == 'PUBOUITests'
                              and node.get('result') == 'Passed' and node.get('children', []) == [])
                if not valid_case and rejection is not None:
                    rejection.update(rejected_case_shape(node, suite, bundle))
                require(valid_case, 'Nonpassing, retried, or wrong-suite test')
                yield node['nodeIdentifier']
            yield from cases(node.get('children', []), next_suite, next_bundle)
    expected = sorted(method_id(method) for method in CAPTURES)
    require(sorted(cases(tree['testNodes'])) == expected, 'Exactly four distinct passing methods required')
    return expected


def verify_method_bytes(data, diagnostic, commit, run, attempt, size):
    case = {}
    try:
        return verify_methods(json.loads(data), rejection=case)
    except (ValueError, KeyError, TypeError, AttributeError, RecursionError):
        # Keep the authoritative failure. Never serialize arbitrary xcresult strings.
        report = dict(version=1, status='METHOD_TREE_REJECTED', case=case or None,
                      commit=commit if re.fullmatch(r'[0-9a-f]{40}', commit) else None,
                      run=run if re.fullmatch(r'[0-9]{1,20}', run) else None,
                      attempt=attempt if re.fullmatch(r'[0-9]{1,6}', attempt) else None,
                      profile=size if size in SIZES else None,
                      inputBytes=len(data), inputSHA256=hashlib.sha256(data).hexdigest())
        try:
            diagnostic.write_text(json.dumps(report, indent=2) + '\n', encoding='ascii')
        except OSError:
            pass
        raise


def verify_captures(rows, shots, size, udid, partial=False):
    names, ids, report = set(), set(), {}
    dims = tuple(MATRIX[size][key] * 3 for key in ('width', 'height'))
    for row in rows:
        method = row['testIdentifier']
        require(method not in ids, 'Duplicate method in attachment manifest')
        ids.add(method)
        for attachment in row['attachments']:
            name = attachment.get('suggestedHumanReadableName', '')
            expected = [(method_id(m), c) for m, cs in CAPTURES.items() for c in cs
                        if name.startswith(f'messages-redesign-{c}_')]
            if not expected:
                continue
            require(len(expected) == 1, 'Ambiguous named screenshot')
            owner, label = expected[0]
            require(owner == method and label not in report and attachment.get('deviceId') == udid
                    and type(attachment.get('isAssociatedWithFailure')) is bool
                    and (partial or not attachment['isAssociatedWithFailure']), 'Invalid screenshot provenance')
            file = attachment['exportedFileName']
            require(Path(file).name == file and file.endswith('.png') and file not in names,
                    'Unsafe or duplicate screenshot filename')
            names.add(file)
            path = shots / file
            require(path.is_file() and not path.is_symlink(), 'Missing regular native screenshot')
            data = path.read_bytes()
            require(len(data) > 33 and data[:16] == b'\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR'
                    and struct.unpack('>II', data[16:24]) == dims
                    and data[-12:] == b'\x00\x00\x00\x00IEND\xaeB\x60\x82',
                    'Original screenshot is not the exact QA device PNG size')
            report[label] = dict(method=method, file=file, sha256=hashlib.sha256(data).hexdigest(),
                                 width=dims[0], height=dims[1], associatedWithFailure=attachment['isAssociatedWithFailure'])
    require(partial or set(report) == {x for captures in CAPTURES.values() for x in captures},
            'Missing one or more of the required 13 actual screenshots')
    return report


def read(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--size', choices=SIZES, required=True)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--partial', action='store_true', help='Retain partial originals; never emit PASS')
    options = parser.parse_args()
    root, size = options.build, options.size
    sha = os.environ['GITHUB_SHA']
    run, attempt = os.environ['GITHUB_RUN_ID'], os.environ['GITHUB_RUN_ATTEMPT']
    head = (root / 'messages-redesign/source-sha.txt').read_text().strip()
    receipt = (root / 'messages-redesign/run-attempt.txt').read_text().strip()
    require(re.fullmatch(r'[0-9a-f]{40}', sha) and sha == head and receipt == f'{run}/{attempt}',
            'CI source and run identity do not match')
    env = read(root / 'test-environment.json')
    require(len(env) == 1, 'Expected one dedicated device per job')
    rec = env[0]
    require(all(rec.get(k) == v for k, v in dict(commit=sha, runtime=RUNTIME, size=size, boot='READY',
            device=MATRIX[size]['model'], deviceTypeIdentifier=MATRIX[size]['deviceTypeIdentifier'],
            selection=MESSAGES_REDESIGN_SHARD, expectedTests=len(CAPTURES)).items()), 'Runner scope mismatch')
    udid = rec['udid']
    require(re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', udid), 'Bad device identity')
    methods = []
    if not options.partial:
        require(rec.get('tests') == 'PASS', 'Simulator runner did not pass')
        require(summary_matches_device(read(root / 'ui-0-summary.json'), size, udid, len(CAPTURES)),
                'Summary device or passing counts mismatch')
        data = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests',
                                        '--path', str(root / 'ui-0.xcresult')], timeout=60)
        methods = verify_method_bytes(data, root / 'messages-redesign/method-tree-rejection.json',
                                      sha, run, attempt, size)
    shots = root / 'screenshots/0'
    captures = verify_captures(read(shots / 'manifest.json'), shots, size, udid, partial=options.partial)
    originals = root / 'messages-redesign' / ('partial-originals' if options.partial else 'originals')
    originals.mkdir(exist_ok=False)
    for item in captures.values():
        shutil.copyfile(shots / item['file'], originals / item['file'])
    result = dict(status='INCOMPLETE' if options.partial else 'PASS', scope='synthetic Debug iOS Simulator only; not pixel, H5, IPA or device acceptance',
                  commit=sha, run=run, attempt=attempt, profile=size, udid=udid, runtime=RUNTIME,
                  methods=methods, screenshots=captures)
    filename = 'partial-evidence.json' if options.partial else 'evidence.json'
    (root / 'messages-redesign' / filename).write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
