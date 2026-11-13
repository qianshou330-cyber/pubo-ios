"""Read test media from the same source used by the native synthetic transport."""
import base64
import pathlib
import re


def load_native_media(source):
    text = pathlib.Path(source).read_text(encoding='utf-8')
    result = {}
    for key in ('still', 'looping', 'finite', 'avatar'):
        match = re.search(r'static let ' + key + r' = Data\(base64Encoded: "([^"]+)"', text)
        if match is None:
            raise ValueError('Missing native media fixture: ' + key)
        result[key] = base64.b64decode(match.group(1), validate=True)
    return result
