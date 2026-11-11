"""Distinguish sparse, similarly white destination pages using the actual header and glyph edges."""
from pathlib import Path
import json
import subprocess
import sys

import numpy as np
from PIL import Image

root = Path(__file__).resolve().parent / ("build" + sys.argv[1])
ff = "ffmpeg"
group = json.loads((root / "native-simulator-groups.json").read_text("utf8"))["large/notification-routes"]
rows = [x for x in json.loads((root / "native-screenshot-index.json").read_text("utf8"))
        if x["group"] == "large/notification-routes" and x.get("namedOriginal")]
out = root / "notification-routes-visual-pts.json"
aligned = json.loads(out.read_text("utf8"))
w, h, fps = 110, 239, 4
raw = subprocess.check_output([str(ff), "-v", "error", "-nostdin", "-i", str(root / group["source"]), "-an",
                               "-vf", f"fps={fps},scale={w}:{h}:flags=lanczos", "-threads", "2", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"])
frames = np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3)
raw_time = np.arange(len(frames)) / fps
for r in rows:
    reference = np.asarray(Image.open(root / r["namedOriginal"]).convert("RGB").resize((w, h), Image.Resampling.LANCZOS), dtype=np.int16)
    # Weight pixels that identify each page: header, actor, body text and controls.
    gray = reference.mean(axis=2)
    gradients = np.maximum(np.abs(np.diff(gray, axis=0, prepend=gray[:1])), np.abs(np.diff(gray, axis=1, prepend=gray[:, :1])))
    mask = gradients > 13
    mask[:14] = False
    mask[-22:] = False
    header = mask.copy()
    header[33:] = False
    # Recordings may compress several minutes spent waiting for GitHub simulator services.
    # Search the whole real presentation; use the separately estimated clock only to distinguish near-ties.
    ids = np.arange(len(frames))
    diffs, rgbs = [], []
    for start in range(0, len(ids), 45):
        chunk = np.abs(frames[ids[start:start + 45]].astype(np.int16) - reference)
        rgb = chunk[:, 14:-10].mean(axis=(1, 2, 3))
        glyph = chunk[:, mask].mean(axis=(1, 2))
        title = chunk[:, header].mean(axis=(1, 2)) if header.any() else glyph
        diffs.extend(.25 * rgb + .53 * glyph + .22 * title)
        rgbs.extend(rgb)
    score = np.array(diffs)
    best = score.min()
    candidates = np.flatnonzero(score <= best + 1.1)
    spans = np.split(candidates, np.flatnonzero(np.diff(candidates) > 1) + 1)
    expected = r["wallSecondsSinceRecordingStart"] + aligned["commonOffset"]
    def distance(span):
        return max(0, raw_time[ids[span[0]]] - expected, expected - raw_time[ids[span[-1]]])
    span = min(spans, key=lambda x: (distance(x), min(score[x])))
    mid = int(span[len(span) // 2])
    aligned["matches"][r["name"]].update(likelyPTS=float(raw_time[ids[mid]]), stableFrom=float(raw_time[ids[span[0]]]),
                                          stableThrough=float(raw_time[ids[span[-1]]]), matchingError=round(rgbs[mid], 3),
                                          titleAndStrokeError=round(score[mid], 3))
aligned["routeMatchMethod"] = "Full simulator stream at 4 fps, weighted by navigation bar, letters and controls; selected stable interval midpoint"
out.write_text(json.dumps(aligned, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print("Verified destination features for", len(rows), "route captures")
