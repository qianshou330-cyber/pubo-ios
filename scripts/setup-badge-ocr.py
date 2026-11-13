"""Prepare the official, content-pinned English OCR model for test-only use."""
import hashlib
import json
import urllib.request
from badge_pixel_gate import MODEL_DIR, MODEL_SHA256, ENGINE_VERSION, engine_identity

URL = 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/87416418657359cb625c412a48b6e1d6d41c29bd/eng.traineddata'
receipt = dict(status='FAIL', expectedEngine=ENGINE_VERSION, expectedModelSHA256=MODEL_SHA256, source=URL)
try:
    with urllib.request.urlopen(URL, timeout=60) as response:
        data = response.read(5 * 1024 * 1024)
    receipt['downloadedBytes'] = len(data)
    receipt['downloadedSHA256'] = hashlib.sha256(data).hexdigest()
    if receipt['downloadedSHA256'] != MODEL_SHA256:
        raise ValueError('Official model hash mismatch; refusing OCR')
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    (MODEL_DIR / 'eng.traineddata').write_bytes(data)
    receipt['identity'] = engine_identity()  # exact 5.5.3, not any 5.5.x
    receipt['status'] = 'PASS'
except Exception as error:
    receipt['error'] = type(error).__name__ + ': ' + str(error)
finally:
    MODEL_DIR.parent.mkdir(parents=True, exist_ok=True)
    (MODEL_DIR.parent / 'badge-ocr-setup.json').write_text(json.dumps(receipt, indent=2))
print(json.dumps(receipt, indent=2))
raise SystemExit(0 if receipt['status'] == 'PASS' else 1)
