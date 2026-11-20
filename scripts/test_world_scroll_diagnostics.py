from pathlib import Path
import unittest
from ui_selection import selection, PRESENTATION_PARTS, ALIGNMENT_PARTS

ROOT = Path(__file__).resolve().parents[1]

class WorldScrollDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.swift = (ROOT / 'UITests/WorldScrollDiagnosticUITests.swift').read_text()
        self.runner = (ROOT / 'scripts/simulator-tests.py').read_text()
        self.workflow = (ROOT / '.github/workflows/four-tabs.yml').read_text()

    def test_exact_separate_methods_and_unchanged_required_counts(self):
        for arm, method in [('cross-page', 'testSyntheticWorldCrossPageAndReadingPosition'),
                            ('signposts', 'testSyntheticWorldScrollSignpostSamples')]:
            self.assertEqual(selection('world-scroll-' + arm), (1, ['-only-testing:PUBOUITests/WorldScrollDiagnosticUITests/' + method]))
            self.assertIn('func ' + method + '()', self.swift)
        self.assertEqual(sum(map(len, PRESENTATION_PARTS.values())), 8)
        self.assertEqual(sum(map(len, ALIGNMENT_PARTS.values())), 10)
        self.assertEqual(selection('video-poster'), (4, ['-only-testing:PUBOUITests/PublicVideoPosterUITests']))

    def test_only_existing_synthetic_fixture_and_real_scroll(self):
        for value in ['"--ui-testing", "--timeline-align", "--gif-preview"', '"timeline.scroll"',
                      'note.open.at4tltest0025', 'note.open.at4tltest0001', 'for _ in 0..<32',
                      'press(forDuration: 0.05, thenDragTo: end)', 'oldest.tap()', 'app.navigationBars.buttons.firstMatch.tap()']:
            self.assertIn(value, self.swift)
        for value in ['scrollTo(', 'setContentOffset', '--isolated-backend', 'Thread.sleep', 'XCTSkip']:
            self.assertNotIn(value, self.swift)

    def test_target_requires_unobscured_viewport_and_hittability(self):
        for value in ['item.exists && item.isHittable', 'frame.midY > upper', 'frame.midY < lower',
                      'bar.minY - 16', 'XCTAssertTrue(visible(oldest, app: app)', 'world-oldest-after-return']:
            self.assertIn(value, self.swift)
        self.assertIn('Observed frame delta only; no pixel-exact position claim', self.swift)

    def test_measurement_has_fresh_process_each_iteration(self):
        part = self.swift.split('measure(metrics:', 1)[1]
        self.assertLess(part.index('let app = launch()'), part.index('startMeasuring()'))
        self.assertIn('observedApp?.terminate()', self.swift)
        self.assertIn('app.terminate(); observedApp = nil', part)
        self.assertIn('options.iterationCount = 3', self.swift)
        self.assertIn('[.manuallyStart, .manuallyStop]', self.swift)
        self.assertIn('persistent/OS caches are not cleared', self.swift)

    def test_metric_window_has_gestures_not_screenshots_or_query_polling(self):
        self.assertIn('XCTOSSignpostMetric.scrollingAndDecelerationMetric', self.swift)
        window = self.swift.split('            startMeasuring()', 1)[1].split('            stopMeasuring()', 1)[0]
        self.assertIn('for _ in 0..<3 { scroll.swipeUp() }', window)
        for text in ['capture(', 'snapshot(', 'debugDescription', 'isHittable', 'waitForExistence']:
            self.assertNotIn(text, window)
        self.assertNotIn('scrollDecelerationMetric', self.swift)

    def test_failure_capture_and_explicit_metric_abstention(self):
        teardown = self.swift.split('override func tearDownWithError()', 1)[1].split('private func launch', 1)[0]
        self.assertLess(teardown.index('note('), teardown.index('capture('))
        self.assertLess(teardown.index('capture('), teardown.index('app.terminate()'))
        block = self.runner.split('        if world_scroll_probe:', 2)[2].split("        if shard == 'chat-presentation-composer'", 1)[0]
        for text in ["'status': 'NOT_EVALUATED'", "'smoothnessAcceptance': 'NOT_EVALUATED'", 'UNAVAILABLE', 'recordingOverhead']:
            self.assertIn(text, block)
        self.assertNotIn('test_exit =', block)
        self.assertNotIn("record['tests'] =", block)

    def test_runner_keeps_time_budget_and_evidence(self):
        for text in ['if elapsed >= 1800:', 'world-scroll.mp4', 'and not world_scroll_probe:',
                     'back_video.send_signal(signal.SIGINT)', 'explicit QA profile']:
            self.assertIn(text, self.runner)

    def test_optional_matrix_and_artifact_scope(self):
        job = self.workflow.split('  diagnostic-world-scroll:\n', 1)[1].split('  video-poster:\n', 1)[0]
        for text in ['scenario: [cross-page, signposts]', 'size: [small, large]', 'fail-fast: false',
                     "PUBO_UI_SHARD: 'world-scroll-${{ matrix.scenario }}'", 'if: always()',
                     'diagnostic-world-scroll-${{ matrix.size }}-${{ matrix.scenario }}-', 'build/ui-*.xcresult', 'build/screenshots/']:
            self.assertIn(text, job)
        package = self.workflow.split('  package:\n', 1)[1].split('runs-on:', 1)[0]
        self.assertNotIn('diagnostic-world-scroll', package)
        self.assertIn('video-poster', package)
        self.assertIn('chat-presentation', package)
