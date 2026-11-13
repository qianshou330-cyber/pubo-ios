import json
import unittest
from refresh_lifecycle import complete_lifecycle


def event(pid=42, **changes):
    c = dict(captureStarted=1, sceneBackground=1, sceneActive=1, rowsApplied=2, fixtureGeneration=2)
    c.update(changes)
    return {'processID': pid, 'eventMessage': 'PUBO_REFRESH_DIAG ' + ';'.join(f'{k}={v}' for k, v in c.items())}


def sequence(pid=42):
    return [event(pid), event(pid, sceneActive=2), event(pid, sceneActive=2, rowsApplied=3, fixtureGeneration=3)]


def valid(events):
    return complete_lifecycle(json.dumps(events))


class LifecycleTests(unittest.TestCase):
    def test_real_order(self): self.assertTrue(valid(sequence()))
    def test_no_background(self): self.assertFalse(valid([event(sceneBackground=0), event(sceneBackground=0, sceneActive=2, rowsApplied=3, fixtureGeneration=3)]))
    def test_no_resume(self): self.assertFalse(valid([event(), event(rowsApplied=3, fixtureGeneration=3)]))
    def test_no_applied_third_generation(self): self.assertFalse(valid(sequence()[:2]))
    def test_restart_does_not_count(self):
        s = sequence(); s[-1]['processID'] = 43; self.assertFalse(valid(s))
    def test_malformed_json(self):
        for raw in ('bad', '{}', '[]', 'null', '42'): self.assertFalse(complete_lifecycle(raw))
    def test_missing_capture(self):
        s = sequence(); s[1]['eventMessage'] = s[1]['eventMessage'].replace('captureStarted=1;', ''); self.assertFalse(valid(s))
    def test_old_counts_before_background_not_application(self):
        self.assertFalse(valid([event(sceneBackground=0, rowsApplied=3, fixtureGeneration=3), event(rowsApplied=3, fixtureGeneration=3), event(sceneActive=2, rowsApplied=3, fixtureGeneration=3), event(sceneActive=2, rowsApplied=3, fixtureGeneration=3)]))
    def test_resume_same_snapshot_cannot_pass(self):
        self.assertFalse(valid([event(), event(sceneActive=2, rowsApplied=3, fixtureGeneration=3)]))
    def test_both_counters_must_grow_after_resume(self):
        for rows, gen in [(3, 2), (2, 3)]: self.assertFalse(valid(sequence()[:2] + [event(sceneActive=2, rowsApplied=rows, fixtureGeneration=gen)]))
    def test_threshold_three(self):
        self.assertFalse(valid([event(rowsApplied=0, fixtureGeneration=0), event(sceneActive=2, rowsApplied=0, fixtureGeneration=0), event(sceneActive=2, rowsApplied=2, fixtureGeneration=2)]))
    def test_new_background_resets_resume(self):
        self.assertFalse(valid(sequence()[:2] + [event(sceneBackground=2, sceneActive=2), event(sceneBackground=2, sceneActive=2, rowsApplied=3, fixtureGeneration=3)]))
    def test_second_cycle_can_pass(self):
        self.assertTrue(valid(sequence()[:2] + [event(sceneBackground=2, sceneActive=2), event(sceneBackground=2, sceneActive=3), event(sceneBackground=2, sceneActive=3, rowsApplied=3, fixtureGeneration=3)]))
    def test_counter_regression_discards_phase(self):
        for key in ['sceneBackground', 'sceneActive', 'rowsApplied', 'fixtureGeneration']:
            bad = dict(sceneActive=2); bad[key] = 0
            self.assertFalse(valid(sequence()[:2] + [event(**bad), sequence()[-1]]))
    def test_fractional_signed_and_exponent_counts_rejected(self):
        for value in ['2.5', '-2', '+2', '2e0', 'NaN']:
            s = sequence(); s[1]['eventMessage'] = s[1]['eventMessage'].replace('rowsApplied=2', 'rowsApplied=' + value); self.assertFalse(valid(s))
    def test_malformed_tokens_and_trailing_garbage(self):
        for suffix in ['garbage', ';', ';broken', ';x=3garbage', ';x=', ';x= 3']:
            s = sequence(); s[1]['eventMessage'] += suffix; self.assertFalse(valid(s))
    def test_duplicate_token_rejected(self):
        s = sequence(); s[1]['eventMessage'] += ';rowsApplied=2'; self.assertFalse(valid(s))
    def test_missing_required_token_rejected(self):
        for key in ['sceneBackground', 'sceneActive', 'rowsApplied', 'fixtureGeneration']:
            s = sequence(); s[1]['eventMessage'] = ';'.join(t for t in s[1]['eventMessage'].split(';') if not t.startswith(key + '=')); self.assertFalse(valid(s))
    def test_pid_and_capture_are_exact(self):
        for pid in [True, 42.0, '42', None, -1]: self.assertFalse(valid(sequence(pid)))
        s = sequence(); s[1]['eventMessage'] = s[1]['eventMessage'].replace('captureStarted=1', 'captureStarted=2'); self.assertFalse(valid(s))
    def test_interleaving_and_full_counter_payload(self):
        s = sequence(); s.insert(1, event(43))
        for e in s: e['eventMessage'] += ';requestStarted=2;requestReturned=2;cancelledResult=0'
        self.assertTrue(valid(s))


if __name__ == '__main__': unittest.main()
