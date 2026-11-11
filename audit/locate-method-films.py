"""Locate each actual screenshot, in XCTest method order, within its own actual system recording."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
from PIL import Image

root = Path(__file__).resolve().parent / ("build" + sys.argv[1])
ff = "ffmpeg"
shots = json.loads((root / "native-screenshot-index.json").read_bytes())
load = lambda p: json.loads(p.read_bytes())
result = {}
for size in ("large", "small"):
    base = root / ("native-" + size)
    video_map = base / "notification-test-recordings.json"
    if not video_map.is_file(): continue
    width, height = (110, 239) if size == "large" else (112, 199)
    fps = 6
    device_result = {}
    for method, files in load(video_map).items():
        references = sorted([r for r in shots if r['group'] == size + '/notifications' and r.get('namedOriginal') and r['test'] == method],
                            key=lambda r: r['stamp'])
        if not references: continue
        movies = [base / "screenshots/notifications" / name for name in files]
        movie = max(movies, key=lambda p: p.stat().st_size)
        source = movie.relative_to(root).as_posix()
        pixels = subprocess.check_output([ff, "-v", "error", "-nostdin", "-i", str(movie), "-an", "-vf",
                                          f"fps={fps},scale={width}:{height}:flags=lanczos", "-threads", "1",
                                          "-pix_fmt", "rgb24", "-f", "rawvideo", "-"])
        frames = np.frombuffer(pixels, np.uint8).reshape(-1, height, width, 3)
        assert len(frames) >= 2, source
        row_scores = []
        for r in references:
            im = np.asarray(Image.open(root / r['namedOriginal']).convert("RGB").resize((width, height), Image.Resampling.LANCZOS), dtype=np.int16)
            g = im.mean(axis=2)
            edges = np.maximum(np.abs(np.diff(g, axis=0, prepend=g[:1])), np.abs(np.diff(g, axis=1, prepend=g[:, :1])))
            salient = (edges > 18) | (im.max(axis=2) - im.min(axis=2) > 45)
            salient[:height // 19] = False
            salient[-3:] = False
            header = salient.copy(); header[height // 5:] = False
            color = salient.copy(); color[:height // 8] = False
            values = []
            for i in range(0, len(frames), 24):
                diff = np.abs(frames[i:i+24].astype(np.int16) - im)
                whole = diff[:, height // 17:-3].mean(axis=(1,2,3))
                feature = diff[:, color].mean(axis=(1,2)) if color.any() else whole
                title = diff[:, header].mean(axis=(1,2)) if header.any() else feature
                values.extend(.20 * whole + .56 * feature + .24 * title)
            row_scores.append(np.array(values))
        # Each captured screenshot occurs once, in attachment order. A later method or
        # an earlier near-white screen cannot be chosen merely from its overall brightness.
        costs = row_scores[0].copy()
        predecessors = []
        for scores in row_scores[1:]:
            best_indices = np.zeros(len(costs), dtype=int)
            for i in range(1, len(costs)):
                best_indices[i] = i if costs[i] <= costs[best_indices[i-1]] else best_indices[i-1]
            prior = np.concatenate(([0], best_indices[:-1]))
            costs = scores + costs[prior]
            predecessors.append(prior)
        pos = int(costs.argmin())
        positions = [pos]
        for prior in reversed(predecessors):
            pos = int(prior[pos]); positions.insert(0, pos)
        for j, (r, scores, position) in enumerate(zip(references, row_scores, positions)):
            ceiling = scores[position] + max(1.0, scores[position] * .06)
            first = last = position
            while first > (positions[j-1] if j else 0) and scores[first-1] <= ceiling: first -= 1
            while last < (positions[j+1] if j+1 < len(positions) else len(scores)-1) and scores[last+1] <= ceiling: last += 1
            center = (first + last) // 2
            device_result[r['name']] = {'source': source, 'method': method, 'videoSeconds': center/fps,
                'matchingStart': first/fps, 'matchingEnd': last/fps, 'durationSeconds': len(frames)/fps,
                'error': round(float(scores[center]), 3)}
    result[size] = device_result
(root / 'notification-test-visual-pts.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
print('Matched per-test system recordings:', {k:len(v) for k,v in result.items()})
