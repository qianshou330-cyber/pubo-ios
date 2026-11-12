import json
import unittest
from refresh_lifecycle import complete_lifecycle


def event(pid, **counts):
    return {'processID': pid, 'eventMessage': 'PUBO_REFRESH_DIAG ' + ';'.join(f'{k}={v}' for k,v in counts.items())}

def sequence(pid=42):
    return [event(pid, captureStarted=1, sceneBackground=1, sceneActive=1, rowsApplied=2, fixtureGeneration=2),
            event(pid, captureStarted=1, sceneBackground=1, sceneActive=2, rowsApplied=2, fixtureGeneration=2),
            event(pid, captureStarted=1, sceneBackground=1, sceneActive=2, rowsApplied=3, fixtureGeneration=3)]

class LifecycleTests(unittest.TestCase):
    def test_real_order(self): self.assertTrue(complete_lifecycle(json.dumps(sequence())))
    def test_no_background(self): self.assertFalse(complete_lifecycle(json.dumps([sequence()[-1]])))
    def test_no_resume(self): self.assertFalse(complete_lifecycle(json.dumps(sequence()[:1])))
    def test_no_applied_third_generation(self): self.assertFalse(complete_lifecycle(json.dumps(sequence()[:2])))
    def test_restart_does_not_count(self):
        events = sequence(); events[-1]['processID'] = 43
        self.assertFalse(complete_lifecycle(json.dumps(events)))
    def test_malformed_and_missing_capture(self):
        for raw in ('bad', '{}', '[]', json.dumps([event(42, sceneBackground=1, sceneActive=2, rowsApplied=3)])):
            self.assertFalse(complete_lifecycle(raw))
if __name__ == '__main__': unittest.main()
