"""Make review sheets directly from the original route test film with real media timestamps."""
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).parent / ("build" + sys.argv[1])
ff = "ffmpeg"
group = json.loads((root / "native-simulator-groups.json").read_text("utf8"))["large/notification-routes"]
rows = sorted((r for r in json.loads((root / "native-screenshot-index.json").read_text("utf8"))
               if r["group"] == "large/notification-routes" and r.get("matchingFrom") is not None), key=lambda r: r["stamp"])
w, h, fps = 110, 239, 3
raw = subprocess.check_output([str(ff), "-v", "error", "-nostdin", "-i", str(root / group["source"]),
                               "-an", "-vf", f"fps={fps},scale={w}:{h}:flags=lanczos",
                               "-threads", "2", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"])
frames = np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3)
font = ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", 12)
out = root / "route-film-review"
out.mkdir(exist_ok=True)
for page in range(0, len(rows), 6):
    chunk = rows[page:page + 6]
    sheet = Image.new("RGB", ((w + 9) * 6, 300 * len(chunk)), "#eef1f4")
    draw = ImageDraw.Draw(sheet)
    for row_num, item in enumerate(chunk):
        y = row_num * 300
        draw.text((4, y + 1), item["name"], fill="black", font=font)
        draw.text((4, y + 18), item["test"], fill="#444", font=font)
        start, end = item["matchingFrom"], item["matchingUntil"]
        for ci, t in enumerate([start - 1.8, start - 0.5, start, item["rawVideoSeconds"], end + 0.8, end + 2.3]):
            idx = min(len(frames) - 1, max(0, round(t * fps)))
            x = ci * (w + 9)
            sheet.paste(Image.fromarray(frames[idx]), (x, y + 36))
            draw.text((x + 2, y + 278), f"{idx / fps:.1f}s", "black", font=font)
    sheet.save(out / f"routes-{page // 6 + 1}.jpg", quality=93)
print(len(rows), "route snapshots checked against the original simulator video")
