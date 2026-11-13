"""Prepare the official, content-pinned English OCR model for test-only use."""
import hashlib
import urllib.request
from badge_pixel_gate import MODEL_DIR, MODEL_SHA256, engine_identity

URL = 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/87416418657359cb625c412a48b6e1d6d41c29bd/eng.traineddata'
with urllib.request.urlopen(URL, timeout=60) as response:
    data = response.read(5 * 1024 * 1024)
if hashlib.sha256(data).hexdigest() != MODEL_SHA256:
    raise SystemExit('Official model hash mismatch; refusing OCR')
MODEL_DIR.mkdir(parents=True, exist_ok=True)
(MODEL_DIR / 'eng.traineddata').write_bytes(data)
print(engine_identity())  # exact engine 5.5.4; never silently accept a new version
