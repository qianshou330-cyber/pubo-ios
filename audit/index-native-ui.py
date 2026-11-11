"""Index the original XCUI screenshots and derive navigation clip boundaries from attachment times."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("build")
parser.add_argument("--clips", action="store_true")
args = parser.parse_args()
root = Path(__file__).parent.resolve() / ("build" + args.build)
ff = "ffmpeg"

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def load(path):
    return json.loads(path.read_text(encoding="utf8"))

def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf8")

records = []
groups = {}
for variant in ["large", "small", "preserved", "evidence-large", "evidence-small"]:
    suite = variant.removeprefix("evidence-")
    anchor = root / ("native-" + variant)
    if not (anchor / "artifact-audit.json").is_file():
        continue
    audit = load(anchor / "artifact-audit.json")
    for manifest in anchor.glob("screenshots/*/manifest.json"):
        key = manifest.parent.name
        group_id = suite + "/" + key
        if variant == suite and (root / ("native-evidence-" + suite) / "screenshots" / key / "manifest.json").exists():
            continue
        summary = load(anchor / (key + "-summary.json"))
        clock = load(anchor / (key + "-recording.json"))
        video = manifest.parent / "interactions.mp4"
        assert video.stat().st_size > 1000
        device = summary["devicesAndConfigurations"][0]["device"]
        expected = "iPhone 17 Pro Max" if suite != "small" else "iPhone SE (3rd generation)"
        assert device["modelName"] == expected and device["osVersion"] == "26.0.1"
        px = (1320, 2868) if suite != "small" else (750, 1334)
        groups[group_id] = dict(source=str(video.relative_to(root)), rawVideoSHA256=digest(video), sourceCommit=audit["source"]["productCommit"],
                                testCommit=audit["source"].get("testCommit", audit["source"]["productCommit"]), productTrees=audit["source"].get("productTrees"),
                                fps="原始录制文件计时", runtime=device, passed=summary["passedTests"], failed=summary["failedTests"], skipped=summary["skippedTests"],
                                runStart=clock["startedAt"], runEnd=clock["finishedAt"], testStart=summary["startTime"], testEnd=summary["finishTime"])
        for test in load(manifest):
            for item in test["attachments"]:
                path = manifest.parent / item["exportedFileName"]
                if path.suffix.lower() != ".png" or item.get("isAssociatedWithFailure"):
                    continue
                name = item["suggestedHumanReadableName"].split("_0_")[0]
                ext = Path(item["suggestedHumanReadableName"]).suffix
                if name.startswith("notification-route-") and ext != ".png":
                    name += ext
                if name == "notification-badge-digits":
                    continue  # The full-resolution companion is notifications-unread-twelve.
                if key in ('notifications', 'notification-routes') and not name.startswith(('notification-', 'notifications-')):
                    continue
                with Image.open(path) as pic:
                    size = pic.size
                assert size == px, (path.name, size, px)
                record = dict(name=name, group=group_id, test=test["testIdentifier"], path=str(path.relative_to(root)), size=size,
                              stamp=item["timestamp"], wallSecondsSinceRecordingStart=round(item["timestamp"] - clock["startedAt"], 3), sha256=digest(path))
                if suite in ("large", "small") and name.startswith(("notifications-", "notification-")):
                    relative = Path("native-originals") / suite / (name + ".png")
                    (root / relative).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path, root / relative)
                    assert digest(root / relative) == record["sha256"]
                    record["namedOriginal"] = relative.as_posix()
                records.append(record)
write(root / "native-simulator-groups.json", groups)
write(root / "native-screenshot-index.json", records)
print("Indexed", len(records), "screenshots across", len(groups), "recordings")
if not args.clips:
    raise SystemExit

separate = {}
if (root / 'native-large/notification-test-recordings.json').is_file():
    subprocess.run([sys.executable, str(root.parent / 'locate-method-films.py'), args.build], check=True)
    separate = load(root / 'notification-test-visual-pts.json').get('large', {})

def get_duration(path):
    details = subprocess.run([str(ff), "-hide_banner", "-i", str(path)], capture_output=True, encoding="utf8", errors="replace").stderr
    h, m, s = re.search(r"Duration: (\d+):(\d+):([\d.]+)", details).groups()
    return int(h) * 3600 + int(m) * 60 + float(s)

# simctl records variable frame rate. The XCTest wall clock includes simulator setup,
# end-of-run waits, and holds with no new pixels. Index actual MP4 presentation times.
for group_id in ["large/notifications", "large/notification-routes"]:
    if group_id not in groups:
        continue
    g = groups[group_id]
    source = root / g["source"]
    g["rawMediaSeconds"] = get_duration(source)
    name = group_id.split("/")[-1]
    matches = [r for r in records if r["group"] == group_id and r.get("namedOriginal")]
    if name == 'notifications' and separate and all(r['name'] in separate for r in matches):
        for r in matches:
            match = separate[r['name']]
            r.update(rawVideoSource=match['source'], rawVideoSeconds=match['videoSeconds'],
                     rawMediaSeconds=get_duration(root / match['source']), matchingFrom=match['matchingStart'],
                     matchingUntil=match['matchingEnd'], frameMeanErrorOf255=match['error'],
                     timingMethod='Original XCTest method video matched in capture order using header, text and color at 6 fps')
        continue
    subprocess.run([sys.executable, str(root.parent / "locate-real-motion.py"), args.build, name], check=True)
    if name == "notification-routes":
        subprocess.run([sys.executable, str(root.parent / "refine-route-pts.py"), args.build], check=True)
    aligned = load(root / (name + "-visual-pts.json"))["matches"]
    for r in matches:
        match = aligned[r["name"]]
        r.update(rawVideoSeconds=match["likelyPTS"], matchingFrom=match["stableFrom"],
                 matchingUntil=match["stableThrough"], frameMeanErrorOf255=match["matchingError"],
                 timingMethod="original frame matched at 4 fps using header and text edges" if name == "notification-routes" else
                              "original frame matched at 5 fps; nearby similar states separated using shared clock offset")
write(root / "native-screenshot-index.json", records)
write(root / "native-simulator-groups.json", groups)

chosen = {
    "notifications-all-light": (4, 2), "notifications-all-dark": (4, 2),
    "notifications-filter-light": (4, 2), "notifications-follow-light": (5, 2),
    "notifications-mentions-light": (4, 2), "notifications-directNotes-light": (4, 4),
    "notifications-live-arrived": (6, 4), "notifications-pull-refreshed": (8, 3),
    "notifications-unread-twelve": (2, 5), "notifications-page-two": (7, 2),
    "notifications-mentions-date": (6, 3),
    "notification-route-notification.noticetest0032": (5, 4),
    "notification-route-notification.noticetest0028": (5, 4),
    "notification-route-notification.noticetest0014": (5, 4),
}
clips = []
for r in records:
    if not r["group"].startswith("large/") or r["name"] not in chosen:
        continue
    rel = Path("native-clips") / (r["name"] + ".mp4")
    before, after = chosen[r["name"]]
    start = max(0, r["matchingFrom"] - before)
    end = min(r.get('rawMediaSeconds', groups[r["group"]]["rawMediaSeconds"]), r["matchingUntil"] + after)
    clips.append(dict(name=r["name"], path=rel.as_posix(), source=r.get('rawVideoSource', groups[r["group"]]["source"]),
                      rawStartSeconds=round(start, 3), rawEndSeconds=round(end, 3),
                      screenshotStamp=round(r["rawVideoSeconds"] - start, 3), screenshot=r["namedOriginal"],
                      matchingFrom=r["matchingFrom"], matchingUntil=r["matchingUntil"], originalFrameError=r["frameMeanErrorOf255"]))

def encode(c):
    output = root / c["path"]
    output.parent.mkdir(exist_ok=True)
    span = c["rawEndSeconds"] - c["rawStartSeconds"]
    filters = f"fps=30,trim=start={c['rawStartSeconds']}:duration={span},setpts=PTS-STARTPTS,scale=440:956:flags=lanczos,setsar=1"
    # Decode the original stream from its start. Seeking to a keyframe in sparse simctl
    # recordings can pick a different state despite matching container timestamps.
    subprocess.run([str(ff), "-v", "error", "-nostdin", "-y", "-threads", "2", "-i", str(root / c["source"]),
                    "-an", "-vf", filters,
                    "-c:v", "libx264", "-threads", "2", "-crf", "18", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(output)], check=True)
    assert output.stat().st_size > 1000
    c["sha256"] = digest(output)
    c["durationSeconds"] = get_duration(output)
    assert abs(c["durationSeconds"] - span) < 0.16, (c["name"], c["durationSeconds"], span)
with ThreadPoolExecutor(max_workers=2) as workers:
    list(workers.map(encode, clips))
write(root / "native-clips.json", clips)
print("Indexed", len(clips), "real-time excerpts from original simulator video")
