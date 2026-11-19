"""Exact navigation scope; no skipped, retried or substitute method can pass."""
import re
from pathlib import Path

SUITE = 'FourTabNavigationUITests'
EXPECTED_TESTS = 13
SHARDS = {
    'routing': (
        'testAccountSwitchClearsPreviousNavigationStacks',
        'testChatAndFriendStacksSurviveTabSwitches',
        'testMigratedDiscoveryAndAccountEntriesRemainReachable',
        'testSyntheticPushRoutesUseCorrectTabNotGlobalSheet',
        'testGuestLandingStillLoadsPublicPanels',
        'testOpeningNotificationsDoesNotClearChatBadge',
    ),
    'interaction': (
        'testFourRootsAndExclusiveComposerInBothThemes',
        'testMessageMenuSearchAndKeyboardReturn',
        'testScannerSyntheticFallbackDoesNotRequestCamera',
        'testWorldComposerKeyboardAndCloseWithoutSending',
        'testFollowRequestPendingCancelAndLoadingStayTruthful',
        'testFriendsEmptyAndFailedReadCanRetry',
        'testWorldLoadingFailureAndLargeTextRemainNavigable',
    ),
}


def declared_tests(path=Path('UITests/FourTabNavigationUITests.swift')):
    return re.findall(r'^    func (test\w+)\(', path.read_text(), re.MULTILINE)


def selected_methods(shard='all'):
    if shard == 'all':
        return tuple(name for names in SHARDS.values() for name in names)
    if shard not in SHARDS:
        raise ValueError('Unknown navigation shard')
    return SHARDS[shard]


def validate_scope(names):
    manifest = selected_methods()
    if (len(manifest) != EXPECTED_TESTS or len(set(manifest)) != EXPECTED_TESTS
            or len(names) != EXPECTED_TESTS or set(names) != set(manifest)):
        raise ValueError('UI declarations must equal the disjoint 6/7 navigation manifest')


def expected_method_ids(shard='all'):
    return [SUITE + '/' + name + '()' for name in selected_methods(shard)]


def selectors(shard='all'):
    return ['-only-testing:PUBOUITests/' + SUITE + '/' + name
            for name in selected_methods(shard)]


def complete(summary, expected=EXPECTED_TESTS):
    return (isinstance(summary, dict)
            and all(type(summary.get(key)) is int and summary[key] == value
                    for key, value in [('passedTests', expected), ('failedTests', 0),
                                       ('skippedTests', 0), ('expectedFailures', 0)]))


def successful_method_ids(tree, shard='all'):
    """Read xcresulttool get test-results tests JSON, never console log text.

    Xcode16+ uses testNodes/recursive children, nodeType='Test Case',
    nodeIdentifier and result='Passed'. See Chromium's primary implementation:
    ios/build/bots/scripts/xcode_log_parser.py (Xcode16LogParser).
    Unknown identifiers/layouts fail closed. Duplicate cases/retries cannot pass.
    A canonical identifier itself binds the case to the required suite; a named
    enclosing suite or test bundle must not contradict it.
    """
    if not isinstance(tree, dict) or not isinstance(tree.get('testNodes'), list):
        raise ValueError('Missing xcresult testNodes')
    expected = set(expected_method_ids(shard))
    observed = []

    def walk(nodes, suite=None, bundle=None):
        if not isinstance(nodes, list):
            raise ValueError('Malformed xcresult children')
        for node in nodes:
            if not isinstance(node, dict):
                raise ValueError('Malformed xcresult node')
            kind = node.get('nodeType')
            current_suite, current_bundle = suite, bundle
            if kind == 'Test Suite':
                current_suite = node.get('name') or node.get('nodeIdentifier')
            if kind == 'Test Bundle':
                current_bundle = node.get('name') or node.get('nodeIdentifier')
            if kind == 'Test Case':
                identifier = node.get('nodeIdentifier')
                if (identifier not in expected or node.get('result') != 'Passed'
                        or current_suite not in (None, SUITE)
                        or current_bundle not in (None, 'PUBOUITests')
                        or node.get('children', []) != []):
                    raise ValueError('Unexpected, unsuccessful, or wrong-suite test case')
                observed.append(identifier)
            if 'children' in node:
                walk(node['children'], current_suite, current_bundle)
    walk(tree['testNodes'])
    if len(observed) != len(expected) or set(observed) != expected:
        raise ValueError('Missing or duplicate navigation methods')
    return sorted(observed)
