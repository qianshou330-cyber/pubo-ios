"""Exact scope for build148. No skipped or expected-failure test can pass this gate."""
import re
from pathlib import Path

SUITE = 'FourTabNavigationUITests'
EXPECTED_TESTS = 12


def declared_tests(path=Path('UITests/FourTabNavigationUITests.swift')):
    return re.findall(r'^    func (test\w+)\(', path.read_text(), re.MULTILINE)


def complete(summary):
    return (summary.get('passedTests') == EXPECTED_TESTS
            and summary.get('failedTests') == 0
            and summary.get('skippedTests') == 0
            and summary.get('expectedFailures') == 0)
