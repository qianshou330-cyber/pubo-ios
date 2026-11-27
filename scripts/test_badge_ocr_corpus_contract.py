"""Contract guardrails for the 189-sample OCR regression corpus and tightened check-badge-ocr-corpus.py gate."""
import base64
import hashlib
import json
from pathlib import Path
import unittest

from badge_pixel_gate import ENGINE_VERSION, MIN_CONFIDENCE, MODEL_SHA256

ROOT = Path(__file__).resolve().parents[1]


class BadgeOCRCorpusContractTests(unittest.TestCase):
    def test_corpus_preserves_all_189_pngs_and_pins_exact_engine_identity(self):
        corpus = json.loads((ROOT / 'scripts/fixtures/badge-ocr-corpus.json').read_text())
        self.assertEqual(MIN_CONFIDENCE, 80.0)
        self.assertEqual(corpus['policy']['minimum_confidence'], 80)
        self.assertEqual(corpus['policy']['psm'], 7)
        self.assertFalse(corpus['policy']['whitelist'])
        self.assertEqual(corpus['engine']['tesseract'][0], ENGINE_VERSION)
        self.assertEqual(corpus['engine']['trainedDataSHA256'], MODEL_SHA256)
        samples = corpus['samples']
        self.assertEqual(len(samples), 189)
        for sample in samples:
            raw = base64.b64decode(sample['png_base64'], validate=True)
            self.assertEqual(hashlib.sha256(raw).hexdigest(), sample['png_sha256'], sample['id'])
        non_lim_accepts = [s for s in samples if not s['known_limitation'] and s['expected_decision'] == 'accept']
        self.assertEqual(len(non_lim_accepts), 63)
        known_limitations = [s for s in samples if s['known_limitation']]
        self.assertEqual(len(known_limitations), 4)
        self.assertEqual(corpus['coverage']['known_limitation_accepted_count'], 3)
        negatives = [s for s in samples if s['source']['kind'].startswith('synthetic-negative')]
        self.assertEqual(len(negatives), 51)
        self.assertTrue(all(s['expected_decision'] == 'reject' for s in negatives))

    def test_checker_enforces_engine_parity_positive_floor_and_tighter_clipped_ceiling(self):
        checker = (ROOT / 'scripts/check-badge-ocr-corpus.py').read_text()
        for token in (
            "corpus['engine']['tesseract'][0] != report['pinnedIdentity']['version']",
            "corpus['engine']['trainedDataSHA256'] != report['pinnedIdentity']['modelSHA256']",
            "report['counts']['acceptedCorrect'] < 63",
            "report['counts']['knownClippedFalseAccepts'] > 3",
        ):
            self.assertIn(token, checker)
        workflow = (ROOT / '.github/workflows/four-tabs.yml').read_text()
        ocr_job = workflow.split('  ocr-validation:\n', 1)[1].split('  navigation:\n', 1)[0]
        self.assertIn('HOMEBREW_NO_AUTO_UPDATE=1 brew install tesseract', ocr_job)


if __name__ == '__main__':
    unittest.main()
