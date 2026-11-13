"""Replay all research inputs. Retain rejections and clipping limitations.

This is an OCR policy regression, not a claim that every number is recognized
or that OCR proves glyph completeness. Current-run three-phase proof is separate.
"""
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from badge_pixel_gate import read_pixels, engine_identity, OCRReadingError

corpus = json.loads(Path('scripts/fixtures/badge-ocr-corpus.json').read_text())
version = subprocess.run(['tesseract', '--version'], capture_output=True, text=True, check=True, timeout=10).stdout
languages = subprocess.run(['tesseract', '--list-langs'], capture_output=True, text=True, check=True, timeout=10)
report = dict(engine=version, languages=languages.stdout + languages.stderr, results=[], failures=[],
              warning='Conservative OCR regression only. 0/8 rejected in original corpus; four already-clipped glyphs falsely accepted. Original screenshot geometry remains mandatory.')
try:
    report['pinnedIdentity'] = engine_identity()
    if len(corpus['samples']) != 189:
        raise RuntimeError('Incomplete regression corpus')
    with tempfile.TemporaryDirectory(prefix='pubo-badge-ocr-') as directory:
        for sample in corpus['samples']:
            data = base64.b64decode(sample['png_base64'], validate=True)
            if hashlib.sha256(data).hexdigest() != sample['png_sha256']:
                raise RuntimeError('Corrupt corpus sample')
            path = Path(directory) / (sample['id'] + '.png')
            path.write_bytes(data)
            actual, error, diagnostics = None, None, None
            try:
                actual = read_pixels(path)
            except OCRReadingError as failure:
                error = str(failure)
                diagnostics = failure.diagnostics
            row = dict(id=sample['id'], truth=sample['truth'], actual=actual, rejection=error,
                       source=sample['source']['kind'], knownLimitation=sample['known_limitation'], rejectionDiagnostics=diagnostics)
            report['results'].append(row)
            if sample['known_limitation']:
                # Keep these four failures visible. Do not count them as
                # negative controls that passed or pretend OCR detects clipping.
                continue
            if actual is not None and actual['text'] != sample['truth']:
                report['failures'].append(sample['id'] + ': wrong numeric acceptance')
            if sample['expected_decision'] == 'accept' and actual is None:
                report['failures'].append(sample['id'] + ': previously readable positive rejected')
            if sample['source']['kind'].startswith('synthetic-negative') and actual is not None:
                report['failures'].append(sample['id'] + ': negative accepted')
    report['counts'] = dict(
        total=len(report['results']),
        acceptedCorrect=sum(r['actual'] is not None and r['actual']['text'] == r['truth'] for r in report['results'] if not r['knownLimitation']),
        rejected=sum(r['actual'] is None for r in report['results']),
        knownClippedFalseAccepts=sum(r['actual'] is not None for r in report['results'] if r['knownLimitation']),
    )
    report['policyRegression'] = 'PASS_WITH_DOCUMENTED_LIMITATIONS' if not report['failures'] else 'FAIL'
except Exception as error:
    report['failures'].append(type(error).__name__ + ': ' + str(error))
    report['policyRegression'] = 'FAIL'
finally:
    Path('build').mkdir(exist_ok=True)
    Path('build/badge-ocr-corpus-results.json').write_text(json.dumps(report, indent=2))
print(json.dumps({k: v for k, v in report.items() if k not in ('results', 'languages')}, indent=2))
raise SystemExit(1 if report['failures'] else 0)
