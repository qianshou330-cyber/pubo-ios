"""Resolve capture tools consistently on Windows and GitHub-hosted Ubuntu."""
import os
from pathlib import Path
import shutil

def ffmpeg(root):
    found = os.environ.get('FFMPEG_BIN') or shutil.which('ffmpeg')
    if found:
        return found
    bundled = root.parent / 'ios-home-social-20261101/media-tools/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
    if bundled.is_file():
        return str(bundled)
    raise RuntimeError('Install ffmpeg with libx264 or provide FFMPEG_BIN')

def cjk_font():
    choices = [os.environ.get('PUBO_AUDIT_FONT'), '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', 'C:/Windows/Fonts/msyh.ttc']
    for value in choices:
        if value and Path(value).is_file():
            return value
    raise RuntimeError('Install fonts-noto-cjk or provide PUBO_AUDIT_FONT')
