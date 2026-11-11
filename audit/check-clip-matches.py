"""Locate each XCTest attachment in the adjacent real frames. No frames are generated from a still."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageChops, ImageStat

root = Path(__file__).parent / ("build" + sys.argv[1])
ffmpeg = "ffmpeg"
clips = json.loads((root / "native-clips.json").read_text(encoding="utf8"))
size = (110, 239)
frame_bytes = size[0] * size[1] * 3

def compare(clip):
    with Image.open(root / clip["screenshot"]) as photo:
        thumb = photo.convert("RGB").resize(size, Image.Resampling.LANCZOS)
    # Exclude the system status clock and home indicator when comparing page pixels.
    bounds = (0, 12, size[0], size[1] - 6)
    frame_stream = subprocess.check_output([ffmpeg, "-v", "error", "-nostdin", "-i", str(root / clip["path"]),
                                            "-an", "-vf", "fps=5,scale=110:239", "-threads", "1", "-f", "rawvideo",
                                            "-pix_fmt", "rgb24", "-"])
    assert len(frame_stream) > frame_bytes and len(frame_stream) % frame_bytes == 0
    scores = []
    reference = thumb.crop(bounds)
    for i in range(len(frame_stream) // frame_bytes):
        pic = Image.frombytes("RGB", size, frame_stream[i * frame_bytes:(i + 1) * frame_bytes])
        delta = ImageStat.Stat(ImageChops.difference(reference, pic.crop(bounds))).mean
        scores.append((round(sum(delta) / len(delta), 3), round(i / 5, 1)))
    error, stamp = min(scores, key=lambda x: (x[0], abs(x[1] - clip["screenshotStamp"])))
    return {"clip": clip["path"], "matchingScreenshot": clip["screenshot"], "bestMeanAbsoluteRGBErrorOf255": error,
            "closestFrameSeconds": stamp, "sampledFPS": 5, "comparisonArea": [*size, *bounds],
            "review": "接近截图" if error < 8 else "需核对原片时间码"}

with ThreadPoolExecutor(max_workers=2) as pool:
    match = list(pool.map(compare, clips))
(root / "native-clip-frame-matches.json").write_text(json.dumps(match, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
print("Frames compared", len(match), "check manually:", [r["clip"] for r in match if r["bestMeanAbsoluteRGBErrorOf255"] >= 8])
