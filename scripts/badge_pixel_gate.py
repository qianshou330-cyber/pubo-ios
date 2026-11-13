"""Independent exported-pixel OCR. No expected value enters the image reader.

XCTest still asserts model-backed accessibility and valid pixel extraction.
This separate required gate reads every phase; no fallback to AX or Vision.
"""
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import re
import struct
import subprocess

PHASES = ('initial', 'notifications', 'returned')
BADGE_TEST = 'FourTabNavigationUITests/testOpeningNotificationsDoesNotClearChatBadge()'
MIN_CONFIDENCE = 80.0
ENGINE_VERSION = 'tesseract 5.5.3'
MODEL_SHA256 = '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2'
MODEL_DIR = Path(__file__).resolve().parents[1] / 'build' / 'badge-tessdata'
TSV_COLUMNS = ('level', 'page_num', 'block_num', 'par_num', 'line_num', 'word_num',
               'left', 'top', 'width', 'height', 'conf', 'text')


class OCRReadingError(ValueError):
    def __init__(self, message, diagnostics):
        super().__init__(message)
        self.diagnostics = diagnostics


def engine_identity():
    version = subprocess.run(['tesseract', '--version'], capture_output=True,
                             text=True, timeout=10, check=True).stdout.splitlines()[0]
    digest = hashlib.sha256((MODEL_DIR / 'eng.traineddata').read_bytes()).hexdigest()
    if version != ENGINE_VERSION or digest != MODEL_SHA256:
        raise ValueError(f'Unvalidated OCR engine/model: actual={version}/{digest}; expected={ENGINE_VERSION}/{MODEL_SHA256}')
    return dict(version=version, modelSHA256=digest)


def decode_tsv(raw):
    """One complete, confident numeric token. Never whitelist or repair text."""
    reader = csv.DictReader(io.StringIO(raw), delimiter='\t')
    if tuple(reader.fieldnames or ()) != TSV_COLUMNS:
        raise ValueError('OCR output is not the required TSV format')
    rows = list(reader)
    if any(None in row or any(value is None for value in row.values()) for row in rows):
        raise ValueError('OCR TSV row is malformed')
    words = [r for r in rows if r.get('level') == '5']
    if len(words) != 1:
        raise ValueError('OCR requires exactly one observed word')
    word = words[0]
    text = word.get('text', '')
    confidence = float(word['conf'])
    if not math.isfinite(confidence) or not MIN_CONFIDENCE <= confidence <= 100:
        raise ValueError('OCR confidence insufficient or invalid')
    if re.fullmatch(r'[0-9]+\+?', text) is None:
        raise ValueError('OCR token is not an unmodified numeric badge')
    return dict(text=text, confidence=confidence)


def read_pixels(path):
    """Fixed single-line recognition covers one or several badge digits."""
    # A custom tessdata directory intentionally contains only the pinned model.
    # A trailing "tsv" is a config filename relative to that directory, not an
    # output-format flag; missing configs can silently emit plain text with rc0.
    command = ['tesseract', str(path), 'stdout', '-l', 'eng',
               '--tessdata-dir', str(MODEL_DIR), '--psm', '7',
               '-c', 'tessedit_create_tsv=1', '-c', 'tessedit_create_txt=0']
    diagnostics = dict(file=Path(path).name, format='TSV', stdout='', stderr='')
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=False)
        diagnostics.update(returnCode=result.returncode, stdout=result.stdout, stderr=result.stderr)
        if result.returncode != 0:
            raise ValueError('OCR process failed')
        value = decode_tsv(result.stdout)
        value['diagnostics'] = diagnostics
        return value
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        if isinstance(error, subprocess.TimeoutExpired):
            for key, value in [('stdout', error.stdout), ('stderr', error.stderr)]:
                diagnostics[key] = value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')
            diagnostics['timedOut'] = True
        raise OCRReadingError(str(error), diagnostics) from error


def checked_file(root, filename, png=False):
    if not isinstance(filename, str) or Path(filename).name != filename:
        raise ValueError('Unsafe exported attachment name')
    path = root / filename
    if path.is_symlink() or not path.is_file() or path.resolve().parent != root.resolve():
        raise ValueError('Missing or unsafe exported attachment')
    data = path.read_bytes()
    if png:
        if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
            raise ValueError('Attachment is not a PNG')
        width, height = struct.unpack('>II', data[16:24])
        if not 1 <= width <= 10000 or not 1 <= height <= 10000:
            raise ValueError('Invalid image dimensions')
    return path, hashlib.sha256(data).hexdigest()


def verify_badge_phases(root, expected_device, commit, started, reader=read_pixels, identity=None):
    """The fixed scenario contract is 2 before/while/after notifications.

    Reader injection is solely for tests. The production call supplies no reader
    or expected value. Any missing phase/asset, duplicate, timeout, unsafe path,
    wrong digit, low confidence or missing engine fails the enclosing CI job.
    """
    root = Path(root)
    proof = dict(status='FAIL', phases=[], engine='tesseract', mode='single-line-7',
                 minimumConfidence=MIN_CONFIDENCE, expected='2')
    try:
        if not expected_device or re.fullmatch(r'[a-f0-9]{40}', commit) is None or not math.isfinite(started):
            raise ValueError('Missing current-run context')
        proof.update(commit=commit, expectedDevice=expected_device, started=started)
        if identity is None:
            identity = engine_identity()
        proof['engineIdentity'] = identity
        if identity.get('version') != ENGINE_VERSION or identity.get('modelSHA256') != MODEL_SHA256:
            raise ValueError('Unvalidated Tesseract engine or model')
        manifest = json.loads((root / 'manifest.json').read_text())
        tests = [t for t in manifest if t.get('testIdentifier') == BADGE_TEST]
        if len(tests) != 1:
            raise ValueError('Exactly one unread-isolation test result required')
        attachments = tests[0]['attachments']
        devices, configurations = set(), set()
        previous = -math.inf
        for phase in PHASES:
            observed = dict(phase=phase, attachments={})
            proof['phases'].append(observed)
            timestamps = []
            files = {}
            for kind in ('screen', 'tab', 'glyphs', 'readings', 'accessibility'):
                prefix = 'four-tabs-chat-badge-' + phase + '-' + kind + '_'
                matches = [a for a in attachments if a.get('suggestedHumanReadableName', '').startswith(prefix)]
                if len(matches) != 1:
                    raise ValueError(phase + ': require exactly one ' + kind)
                attachment = matches[0]
                timestamp = float(attachment['timestamp'])
                if not math.isfinite(timestamp) or timestamp < started:
                    raise ValueError('Invalid capture time')
                timestamps.append(timestamp)
                devices.add(attachment['deviceId'])
                configurations.add(attachment['configurationName'])
                path, digest = checked_file(root, attachment['exportedFileName'],
                                            png=kind in ('screen', 'tab', 'glyphs'))
                files[kind] = path
                observed['attachments'][kind] = dict(file=path.name, sha256=digest, timestamp=timestamp)
            if min(timestamps) <= previous or max(timestamps) - min(timestamps) > 30:
                raise ValueError('Nonsequential or stale phase attachments')
            previous = max(timestamps)
            # These are the unchanged extractor's actual geometry diagnostics,
            # not OCR input or an alternative source for the expected count.
            readings = files['readings'].read_text()
            if 'redComponents=1\n' not in readings or 'inkBounds=' not in readings:
                raise ValueError('Missing actual badge extraction evidence')
            observed['visionDiagnostic'] = readings
            try:
                observed['ocr'] = reader(files['glyphs'])
            except OCRReadingError as error:
                observed['ocrFailureDiagnostics'] = error.diagnostics
                raise
            if observed['ocr']['text'] != '2':
                raise ValueError(phase + ': rendered unread count changed')
        if devices != {expected_device} or len(configurations) != 1 or '' in configurations:
            raise ValueError('Mixed or unidentified test devices/configurations')
        proof['deviceId'] = next(iter(devices))
        proof['status'] = 'PASS'
    except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError, struct.error,
            subprocess.SubprocessError) as error:
        proof['error'] = type(error).__name__ + ': ' + str(error)
    return proof
