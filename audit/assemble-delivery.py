"""Assemble verified local release artifacts after the final candidate is accepted.

Running without --write inspects inputs only. --write creates a portable directory
beside this candidate's evidence. An existing delivery is only reverified, never replaced.
"""
import argparse
import csv
import hashlib
import html
import io
import json
import re
import shutil
import tempfile
import zipfile
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from urllib.parse import quote, unquote, urlsplit

ROOT = Path(__file__).resolve().parent
REPO = "https://github.com/qianshou330-cyber/pubo-ios"
STATES = {"all": "全部通知", "filter": "筛选菜单", "follow": "关注筛选", "mentions": "提到我的", "specified": "私信标签（指定可见帖子）"}
KINDS = set("note follow mention reply renote quote reaction pollEnded scheduledNotePosted scheduledNotePostFailed receiveFollowRequest followRequestAccepted app roleAssigned chatRoomInvitationReceived achievementEarned exportCompleted test login createToken".split())
LIMITS = ["实体 iPhone 与最低 iOS 17 设备尚未实测。", "真机签名、首次安装、覆盖升级及真实锁屏推送尚未实测。"]
B_INPUTS = ["target.json", "source-verification.json", "package-verification.json", "real-and-core-results.json", "runs.json",
            "source.zip", "native-simulator-groups.json", "native-screenshot-index.json", "native-clips.json",
            "native-routes.json", "comparison/index.json", "comparison/buttons.csv", "comparison/NOTIFICATION-COMPARISON.md"]
H_INPUTS = ["source.json", "screens.json", "categories.json", "routes-final.json", "videos/index.json"]

def require(condition, message):
    if not condition:
        raise ValueError(message)

def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def json_text(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"

def safe_file(root, relative):
    raw = str(relative).replace("\\", "/")
    name = PurePosixPath(raw)
    require(not name.is_absolute() and ":" not in raw and ".." not in name.parts, f"Unexpected evidence path {raw}")
    path = (root / name).resolve(strict=True)
    require(path.is_relative_to(root.resolve()) and path.is_file(), f"Missing evidence {raw}")
    return path

def href(path):
    return quote(str(path).replace("\\", "/"), safe="/.-_")

def link(path, label):
    return '<a href="' + href(path) + '">' + html.escape(str(label)) + '</a>'

def cells(values, tag="td"):
    return "<tr>" + "".join(f"<{tag}>{v}</{tag}>" for v in values) + "</tr>"

class LocalLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ("src","href") and value:
                reference = urlsplit(value)
                if not reference.scheme and not reference.netloc and reference.path:
                    self.references.append(unquote(reference.path))

class Delivery:
    def __init__(self, root, target):
        self.b = root
        self.h = ROOT / "h5"
        self.t = target
        self.files = {}
        self.hashes = {}
        self.generated = {}
        self.supplement = None
        self.refresh_receipts = []

    def copy(self, src, relative, expected=None):
        relative = PurePosixPath(str(relative).replace("\\", "/")).as_posix()
        require(".." not in PurePosixPath(relative).parts and ":" not in relative and not relative.startswith("/"), relative)
        require(src.is_file(), f"Missing {src}")
        src = src.resolve()
        existing = self.files.get(relative)
        require(existing is None or existing == src, f"Conflicting evidence {relative}")
        self.files[relative] = src
        if expected:
            if src not in self.hashes:
                self.hashes[src] = digest(src)
            require(self.hashes[src] == expected, f"SHA-256 mismatch for {src}")
        return relative

    def from_b(self, name, dest=None, expected=None):
        return self.copy(safe_file(self.b, name), dest or name, expected)

    def from_h(self, name, dest=None):
        return self.copy(safe_file(self.h, name), dest or ("h5/" + str(name).replace("\\", "/")))

    def comparison_source(self, reference):
        origin = (self.b / "comparison" / reference).resolve(strict=True)
        if origin.is_relative_to(self.b):
            return self.from_b(origin.relative_to(self.b))
        require(origin.is_relative_to(self.h), f"Unknown comparison source {reference}")
        return self.from_h(origin.relative_to(self.h))

    def collect(self, main_commit):
        t = self.t
        expected_sha = t["sha"]
        require(t == read(self.b / "target.json"), "Candidate changed since targets were collected")
        source = read(self.b / "source-verification.json")
        pkg = read(self.b / "package-verification.json")
        real = read(self.b / "real-and-core-results.json")
        runs = read(self.b / "runs.json")
        require(source["commit"] == pkg["sourceCommit"] == pkg["commit"] == real["product"] == expected_sha, "Mixed build evidence")
        require(source["tree"] == t["tree"] and source["allGitBlobsVerified"], "Incomplete source tree")
        require(real["productionAPIRequests"] == 0 and real["realUITests"] > 0 and real["core"] > 0, "Missing isolated or core acceptance")
        require(pkg["localMetadataVerified"] and pkg["status"] == "PASS" and pkg["codesign"] == "UNSIGNED", "Unverified iPhone package")
        info = pkg["metadata"]
        require(info["CFBundleIdentifier"] == "com.bolubo.native" and info["CFBundleVersion"] == str(t["build"])
                and info["CFBundleShortVersionString"] == t["version"] and info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "IPA metadata mismatch")
        require(pkg["oldPackageUntouched"] and pkg["privacyUsageDescriptionsUnchangedSince134"], "Missing baseline checks")
        prefix = f"PUBO-{t['version']}-{t['build']}"
        ipa = self.from_b(pkg["ipaRelativePath"], prefix + "-iphoneos-arm64-unsigned.ipa", pkg["sha256"])
        src = self.from_b("source.zip", prefix + "-source.zip", source["archiveSHA256"])
        require(source["archiveSHA256"] == pkg["sourceArchiveSHA256"], "Package and source do not match")
        for name in B_INPUTS[:5]:
            self.from_b(name, "evidence/" + name)
        for name in H_INPUTS:
            self.from_h(name)
        h_routes = read(self.h / "routes-final.json")
        self.from_h(h_routes["allAttemptsFile"])
        self.from_h("note-tabs.json")
        self.from_h("rendered-rows.json")

        hinfo = read(self.h / "source.json")
        require(hinfo["isolatedAPI"] and hinfo["productionWrites"] == 0 and not hinfo["modifiedProductJSOrCSS"], "Unknown H5 baseline")
        with zipfile.ZipFile(self.b / "source.zip") as archive:
            fixture_name, = [name for name in archive.namelist() if name.endswith("/App/Resources/NotificationVisualCases.json")]
            fixture = archive.read(fixture_name).replace(b"\r\n",b"\n")
        hashes = {hashlib.sha256(data).hexdigest() for data in (fixture,fixture.replace(b"\n",b"\r\n"))}
        require(hinfo["fixtureSHA256"] in hashes, "H5 and native captured different records")
        self.generated["evidence/NotificationVisualCases.json"] = fixture.decode("utf8")
        categories = read(self.h / "categories.json")
        require({r["kind"] for r in categories if r["ok"]} == KINDS, "Incomplete H5 category verification")
        screens = read(self.h / "screens.json")
        require(all(f"{s}-{theme}" in screens for s in STATES for theme in ("light","dark")), "Missing H5 states")
        for name, meta in screens.items():
            self.from_h(name + ".png")
            self.from_h(meta["frame"])
            require(meta["sourceCSSViewport"] == [440,956], name)
        if (self.h / "mark-read-success.png").is_file():
            self.from_h("mark-read-success.png")
        h_movies = []
        h_movies_index = read(self.h / "videos/index.json")
        require(h_movies_index["cssViewport"] == [440,956] and h_movies_index["files"], "Missing browser recordings")
        for movie in h_movies_index["files"]:
            movie_path = safe_file(self.h / "videos", movie["file"])
            dest = self.copy(movie_path, Path("h5/videos") / movie["file"], movie["sha256"])
            h_movies.append((dest, movie["description"]))
            frames_file = safe_file(self.h, movie["relativeFrames"])
            frames = read(frames_file)
            require(len(frames) == movie["uniqueCapturedFrames"] and len(frames) >= 2, "Incomplete browser frame sequence")
            require(all(a["t"] <= b["t"] for a,b in zip(frames,frames[1:])), "Out-of-order browser frames")
            self.from_h(frames_file.relative_to(self.h))
        provenance = ROOT / "h5-source-index.json"
        self.copy(provenance,"h5/CAPTURE-SELECTION.json")
        for entry in read(provenance)["files"]:
            relative = PurePosixPath(entry["path"]).relative_to("audit/h5")
            path = safe_file(self.h,relative)
            require(path.stat().st_size == entry["bytes"],f"Incomplete H5 evidence {relative}")
            self.copy(path, "h5/" + str(relative),entry["sha256"])
        self.from_h("measurements.json")
        shots = read(self.b / "native-screenshot-index.json")
        groups = read(self.b / "native-simulator-groups.json")
        routes = read(self.b / "native-routes.json")
        clips = read(self.b / "native-clips.json")
        require({r["kind"].split(":")[0] for r in routes} == KINDS, "Incomplete native navigation coverage")
        for key,g in groups.items():
            require(g["sourceCommit"] == expected_sha and not g["failed"] and not g["skipped"] and g["passed"] > 0, f"Unverified simulator group {key}")
            self.from_b(g["source"], expected=g["rawVideoSHA256"])
        needed = {"large/notifications", "large/notification-routes"}
        require(needed <= groups.keys() and any(k.startswith("small/") for k in groups)
                and any(k.startswith("preserved/") for k in groups), "Missing simulator or regression group")
        for group_id in needed | {"small/notifications"}:
            g = groups[group_id]
            require(g["runtime"]["modelName"] == ("iPhone 17 Pro Max" if group_id.startswith("large/") else "iPhone SE (3rd generation)")
                    and g["runtime"]["osVersion"] == "26.0.1", group_id)
            self.from_b(g["source"], expected=g["rawVideoSHA256"])
        if any(g.get("testCommit", expected_sha) != expected_sha for g in groups.values()):
            self.collect_supplement(groups,expected_sha,source["archiveSHA256"])
        if int(t["build"]) >= 138:
            for key,title in (("large","iPhone 17 Pro Max"),("small","iPhone SE（第 3 代）")):
                directory = PurePosixPath(groups[key + "/notifications"]["source"].replace("\\","/")).parts[0]
                receipt = self.from_b(directory + "/notification-refresh-count.json")
                result = read(self.b / receipt)
                require(result["groupedReads"] == 2 and result["responsesWithNewRow"] == 1,
                        f"Unexpected first-page response count for {title}")
                self.refresh_receipts.append((title,receipt))
                self.from_b(directory + "/notification-visible-badge.json")
                recordings = self.from_b(directory + "/notification-test-recordings.json")
                for files in read(self.b / recordings).values():
                    for file in files:
                        self.from_b(directory + "/screenshots/notifications/" + file)
        shot_names = {}
        for shot in shots:
            self.from_b(shot["path"], expected=shot["sha256"])
            if not shot.get("namedOriginal"):
                continue
            path = self.from_b(shot["namedOriginal"], expected=shot["sha256"])
            if shot["group"].startswith("large/"):
                shot_names[shot["name"]] = path
        for row in routes:
            shot_path = self.from_b(row["evidence"])
            raw = safe_file(self.b, row["video"])
            require(raw in self.files.values(), f"Route origin was not captured in a verified group: {raw}")
            require(shot_path in shot_names.values() and row["videoSeconds"] >= 0, "Unmatched navigation evidence")
        for clip in clips:
            self.from_b(clip["source"], expected=clip.get("sourceSHA256"))
            self.from_b(clip["path"], expected=clip["sha256"])
            self.from_b(clip["screenshot"])
        for name in ("native-simulator-groups.json","native-routes.json","native-screenshot-index.json","native-clips.json","原生通知按钮检查表.md"):
            self.from_b(name)
        self.from_b("native-clip-frame-matches.json")
        self.from_b("integration/integration-notifications-contract.json")
        comparison = read(self.b / "comparison/index.json")
        require(int(comparison["build"]) == int(t["build"]) and {(r["state"],r["theme"]) for r in comparison["pairs"]} ==
                {(s,theme) for s in STATES for theme in ("light","dark")} and comparison["videos"], "Incomplete paired images or video")
        for row in comparison["pairs"]:
            for side in ("h5", "native"):
                origin = (self.b / "comparison" / row[side]).resolve(strict=True)
                require(origin in self.files.values() and digest(origin) == row[side + "SHA256"], f"Unmatched {side} in comparison")
        for row in comparison["pairs"] + comparison["videos"]:
            relative = str(row["file"]).replace("\\", "/")
            if not relative.startswith("comparison/"):
                relative = "comparison/" + relative
            self.from_b(relative, expected=row.get("sha256"))
        for video in comparison["videos"]:
            for segment in video.get("segments",[]):
                for side in ("h5","native"):
                    if segment.get(side):
                        self.comparison_source(segment[side])
        for name in ("overview-light.png","overview-dark.png","paired-interactions.mp4","buttons.csv"):
            self.from_b("comparison/" + name)
        # The capture workspace keeps h5/ one level above buildN. The portable
        # copy keeps h5/ inside delivery; preserve original indices separately.
        for name in ("index.json","NOTIFICATION-COMPARISON.md"):
            value = safe_file(self.b / "comparison",name)
            self.copy(value,"evidence/comparison-source/" + name)
            self.generated["comparison/" + name] = value.read_text("utf8").replace("../../h5/","../h5/")
        old = ROOT.parent / "ios-timeline-visual-20261105/build134/delivery/PUBO-0.9.3-134-iphoneos-arm64-unsigned.ipa"
        require(digest(old) == pkg["build134SHA256"], "Build 134 differs from its baseline")
        validation = dict(productCommit=expected_sha, build=t["build"], version=t["version"], sourceSHA256=source["archiveSHA256"],
                          ipaSHA256=pkg["sha256"], ipaBytes=pkg["bytes"], signed=False, preservedBuild134SHA256=pkg["build134SHA256"],
                          realAndCore=real, simulatorGroups=groups, sites=hinfo, mainCommit=main_commit or None, githubRuns=runs,
                          remaining=LIMITS)
        self.generated["VALIDATION.json"] = json_text(validation)
        self.report(ipa, src, pkg, real, routes, groups, clips, h_movies, main_commit)

    def collect_supplement(self,groups,product,archive_sha):
        proof = read(self.b / "verification-source-proof.json")
        require(proof["product"] == product and proof["productArchiveSHA256"] == archive_sha
                and proof["allProductSourcesAndResourcesByteIdentical"], "Supplement uses different product code")
        test_commit = proof["testCommit"]
        require(set(g.get("testCommit",product) for g in groups.values()) <= {product,test_commit}, "Unverified test revision")
        self.from_b(proof["testArchive"], expected=proof["testArchiveSHA256"])
        for name in ("verification-source-proof.json","verification-commit.json","qa-run.json",
                     "native-first-pass-groups.json","notification-verification.json"):
            self.from_b(name)
        first_pass = read(self.b / "native-first-pass-groups.json")
        observations = read(self.b / "notification-verification.json")
        for suite in ("large","small"):
            first = first_pass["native-" + suite]
            require(first["source"]["productCommit"] == product and first["suite"] == suite, "Wrong first-pass source")
            original = "native-" + suite + "/"
            first_result = read(self.b / original / "notifications-summary.json")
            require(all(first_result[k] == v for k,v in first["testResults"]["notifications-summary"].items()),
                    "Archived test summary differs from first-pass index")
            self.from_b(original + "screenshots/notifications/interactions.mp4")
            for name in ("notifications-summary.json","notifications-tests.json","notifications-recording.json"):
                self.from_b(original + name)
            group = groups[suite + "/notifications"]
            if group.get("testCommit", product) == product:
                continue
            observed = observations[suite]
            require(observed["productCommit"] == product and observed["testCommit"] == test_commit and
                    observed["firstPass"] == first["testResults"]["notifications-summary"] and
                    observed["verification"]["failedTests"] == 0 and observed["newRowConfirmed"],
                    "Supplemental pull results do not verify the checked product")
            follow = "native-evidence-" + suite + "/"
            src = read(self.b / follow / "integration-product-source.json")
            require(src["productCommit"] == product and src["testCommit"] == test_commit and
                    group["testCommit"] == test_commit and group["sourceCommit"] == product and not group["failed"],
                    "Supplement group does not match its product")
            for name in ("integration-product-source.json","notifications-summary.json","notifications-tests.json",
                         "notifications-recording.json","notification-visible-badge.json"):
                self.from_b(follow + name)
            for directory in (original,follow):
                manifest = directory + "screenshots/notifications/manifest.json"
                self.from_b(manifest)
                for case in read(self.b / manifest):
                    if "testUnreadAndPullToRefresh" not in case["testIdentifier"]:
                        continue
                    for item in case["attachments"]:
                        filename = item["exportedFileName"]
                        if Path(filename).suffix.lower() in (".png",".mp4"):
                            self.from_b(directory + "screenshots/notifications/" + filename)
        self.supplement = proof


    def report(self, ipa, source, pkg, real, routes, groups, clips, movies, main_commit):
        t = self.t
        h_routes = read(self.h / "routes-final.json")
        require(h_routes["allPassed"] and h_routes["allCategories"] == len(KINDS), "Incomplete H5 route results")
        web = {r["type"]:r for r in h_routes["cases"]}
        require(all(r["ok"] and r["back"] == "/my/notifications" for r in web.values()), "Unverified H5 return")
        by_id = {"chatRoomInvitationReceived":"App 可从通知进入群邀请。",
                 "roleAssigned":"App 可从通知进入自己的角色资料。",
                 "login":"App 保留账号安全验证入口。",
                 "scheduledNotePostFailed":"App 可从通知检查定时帖子。",
                 "receiveFollowRequest":"App 另提供关注申请列表入口。",
                 "app":"信息行就地阅读。", "test":"信息行就地阅读。",
                 "createToken":"App 使用账号安全验证。"}
        table_rows = []
        csv_buf = io.StringIO(newline="")
        csv_out = csv.writer(csv_buf)
        csv_out.writerow(["类别", "操作", "H5 目标", "H5 返回", "IPA 目标", "IPA 返回", "实现差异", "原始截图", "原片", "原片秒数"])
        for row in routes:
            kind = row["kind"]
            counterpart = web[kind]
            dest = counterpart["observed"]["url"]
            note = by_id.get(kind, "")
            if "第二位参与者头像" in row["action"]:
                dest = "H5 对应头像链接，见逐类实点记录"
            if kind == "receiveFollowRequest" and "打开申请" not in row["action"]:
                dest = "H5 同行接受／拒绝控件，结果见分类实测记录"
            elif dest == "/my/notifications":
                dest = "停留通知列表"
            columns = [kind,row["action"],dest,counterpart["back"],row["target"],row["back"],note,row["evidence"],row["video"],row["videoSeconds"]]
            csv_out.writerow(columns)
            stamp = float(row["videoSeconds"])
            movie_link = '<a href="' + href(row["video"]) + '#t=' + f'{max(0,stamp-3):.1f}">原片 {stamp:.1f}s</a>'
            table_rows.append(cells([html.escape(row["action"]), html.escape(dest), html.escape(row["target"]), html.escape(row["back"]),
                                     html.escape(note), link(row["evidence"], "截图") + " · " + movie_link]))
        self.generated["buttons.csv"] = "\ufeff" + csv_buf.getvalue()
        tests = sum(g["passed"] for g in groups.values())
        gh_links = " · ".join(f'<a href="{REPO}/actions/runs/{int(value)}">{html.escape(key)} 验证记录</a>' for key,value in read(self.b/"runs.json").items())
        src_link = f'<a href="{REPO}/tree/{t["sha"]}">{t["sha"][:12]}</a>'
        if main_commit:
            src_link += f' · <a href="{REPO}/commit/{main_commit}">GitHub 主分支同步记录</a>'
        labels = {"notifications":"通知页与交互","notification-routes":"分类跳转与返回","timeline-preview":"动态时间线",
                  "social":"社交操作","regression":"功能回归","gif":"GIF 显示","chat":"私信与群聊","favorites":"本机 GIF 收藏"}
        test_rows = []
        for key, g in sorted(groups.items()):
            group_name = key.split("/")[-1]
            test_rows.append(cells([html.escape(labels.get(group_name,group_name)),html.escape(g["runtime"]["modelName"]),str(g["passed"])]))
        heading = "PUBO " + html.escape(t["version"]) + " 通知页验收"
        browser_movie_links = "".join("<li>" + link(file,desc) + "</li>" for file,desc in movies)
        supplement_info = ""
        if self.supplement:
            supplement_info = "<p>部分模拟器案例使用字节一致的 App 源码和资源重新执行。设备表采用同一案例的最终结果，首轮与补验的原始回执分别存档。</p><p>" + " · ".join([
                link("notification-verification.json","手势、角标与补验结果"),
                link("native-first-pass-groups.json","首轮原始结果"),
                link("verification-source-proof.json","两份产品源码的逐文件比对")]) + "</p>"
        refresh_info = ""
        if self.refresh_receipts:
            refresh_info = "<p>短距离下拉没有刷新。下拉越过 200pt 后松手，列表取得了一次带新通知的响应。加上首次进入，两台设备分别发出两次首屏请求。" + " · ".join(link(path, title + " 刷新计数") for title,path in self.refresh_receipts) + "</p>"
        pair_links = []
        for pair in read(self.b / "comparison/index.json")["pairs"]:
            pair_path = "comparison/" + Path(pair["file"]).name
            pair_links.append(link(pair_path, STATES[pair["state"]] + " · " + ("浅色" if pair["theme"] == "light" else "深色")))
        block = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{heading} · build {t['build']}</title><style>
:root{{color-scheme:light dark;font-family:"Segoe UI","Microsoft YaHei",system-ui,sans-serif;color:#222a26;background:#f7f8f5}}
body{{max-width:1150px;margin:auto;padding:32px 24px 72px}}h1{{margin:0;font-size:clamp(1.75rem,4vw,2.5rem)}}h2{{margin-top:42px;border-bottom:1px solid #9ba78d;padding-bottom:8px}}p,li{{line-height:1.65}}a{{color:#426325;text-underline-offset:3px;overflow-wrap:anywhere}}
nav{{display:flex;flex-wrap:wrap;gap:1rem;padding:14px 0}}.links{{display:flex;flex-wrap:wrap;gap:14px}}.facts{{display:grid;grid-template-columns:max-content 1fr;gap:8px 18px}}dt{{font-weight:600}}dd{{margin:0;overflow-wrap:anywhere}}code{{overflow-wrap:anywhere;font-size:.86em}}
figure{{margin:14px 0}}figure img,video{{display:block;max-width:100%;height:auto;max-height:720px}}figcaption{{margin:.5em 0;color:#5d665a}}details{{margin:1em 0}}summary{{cursor:pointer}}.scroll{{overflow:auto}}table{{width:100%;border-collapse:collapse;line-height:1.45;font-size:.9rem}}td,th{{padding:.6em;text-align:left;border-bottom:1px solid #c8cfbf;vertical-align:top}}thead{{background:#e9eee3}}
@media(prefers-color-scheme:dark){{:root{{color:#e3e9e3;background:#101912}}a{{color:#abce83}}figcaption{{color:#bdc5b9}}thead{{background:#202f25}}td,th{{border-color:#3c4c40}}}}@media(max-width:650px){{body{{padding:22px 12px 48px}}.facts{{display:block}}dd{{margin:.2em 0 .85em}}td,th{{min-width:5em}}}}
</style><main><header><h1>{heading}</h1><p>build {t['build']} · iPhone 17 Pro Max 模拟器 · 440 × 956pt · iOS 26.0.1</p></header>
<nav aria-label="章节"><a href="#package">交付文件</a><a href="#comparison">页面与动画</a><a href="#buttons">分类与按钮</a><a href="#validation">验证范围</a></nav>
<section id="package"><h2>交付文件</h2><div class="links">{link(ipa,"未签名真机 IPA")} {link(source,"完整源码 ZIP")} {link("SHA256SUMS.txt","SHA-256 校验清单")}</div>
<dl class="facts"><dt>安装包</dt><dd>{int(pkg['bytes']):,} 字节 · arm64 · 最低 iOS {html.escape(pkg['metadata']['MinimumOSVersion'])}</dd>
<dt>安装包 SHA-256</dt><dd><code>{pkg['sha256']}</code></dd><dt>源码 SHA-256</dt><dd><code>{pkg['sourceArchiveSHA256']}</code></dd>
<dt>源码版本</dt><dd>{src_link}</dd><dt>build 134 备份校验</dt><dd><code>{pkg['build134SHA256']}</code></dd></dl></section>
<section id="comparison"><h2>页面与动画</h2><p>「全部」使用分组通知和单类别筛选。「提到我的」读取提及帖子，「私信」标签读取指定可见帖子。底部「私信」仍打开聊天。左、右两端使用同组隔离数据。</p>
<p>模拟器原截图为 1320 × 2868 像素。内置浏览器使用 440 × 956 CSS 视口，完整内容以 75% 比例取证。原始浏览器帧、导出图和对应时间点随包提供。</p>
<figure><a href="comparison/overview-light.png"><img loading="lazy" alt="浅色页面对照，点击查看原图" src="comparison/overview-light.png"></a><figcaption>浅色模式</figcaption></figure>
<figure><a href="comparison/overview-dark.png"><img loading="lazy" alt="深色页面对照，点击查看原图" src="comparison/overview-dark.png"></a><figcaption>深色模式</figcaption></figure>
<div class="links">{' '.join(pair_links)}</div>
<video controls preload="none" src="comparison/paired-interactions.mp4"></video><p>{link("comparison/paired-interactions.mp4","打开操作对照录像")} · {link("comparison/NOTIFICATION-COMPARISON.md","页面和动效的逐项差异")} · {link("comparison/index.json","对照图与录屏时间点")}</p>
<details><summary>查看两端原始证据</summary><ul>
<li>{link(groups['large/notifications']['source'],"模拟器页面与刷新原片")} · {link(groups['large/notification-routes']['source'],"逐类跳转及返回原片")} · {link(groups['small/notifications']['source'],"小屏通知原片")}</li>
{browser_movie_links}
<li>{link("h5/videos/index.json","浏览器实录及采帧时间")}</li>
</ul></details></section>
<section id="buttons"><h2>分类与按钮</h2><p>{len(KINDS)} 个类别，另含合并回应、合并转贴、关注申请的行内操作。返回路径按同组测试数据记录。</p>
<p>{link("buttons.csv","下载原生按钮与返回结果")} · {link("comparison/buttons.csv","H5 与原生逐项对照")} · {link("h5/routes-final.json","H5 点击目标与返回记录")}</p>
<div class="scroll"><table><thead>{cells(["位置与操作","H5","IPA","IPA 返回","差异说明","取证"],"th")}</thead><tbody>{''.join(table_rows)}</tbody></table></div></section>
<section id="validation"><h2>验证范围</h2><p>{real['core']} 项核心测试、{real['packageTests']} 项打包检查、{tests} 项模拟器界面测试和 {real['realUITests']} 项隔离后端界面测试通过。真实后端回执与视觉夹具的结果分别留档。</p>
{supplement_info}
{refresh_info}
<p>{link("evidence/real-and-core-results.json","联调与核心测试结果")} · {link("integration/integration-notifications-contract.json","通知接口回执检查")} · {link("evidence/package-verification.json","真机包、资源及权限检查")} · {gh_links}</p>
<details><summary>查看设备与回归项目</summary><div class="scroll"><table><thead>{cells(["项目","模拟器","通过数"],"th")}</thead><tbody>{''.join(test_rows)}</tbody></table></div></details>
<h3>待验证</h3><ul>{''.join('<li>'+html.escape(s)+'</li>' for s in LIMITS)}</ul><p>{link("VALIDATION.json","完整验收索引")}</p></section></main></html>'''
        self.generated["REPORT.html"] = block + "\n"

    def write(self, dest):
        for rel, src in self.files.items():
            path = dest / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, path)
            expected = self.hashes.get(src) or digest(src)
            require(digest(path) == expected, f"Copy mismatch for {rel}")
        for name, data in self.generated.items():
            require(name not in self.files, f"Name collision {name}")
            (dest / name).parent.mkdir(parents=True,exist_ok=True)
            (dest / name).write_text(data, encoding="utf8", newline="")
        links = LocalLinks()
        links.feed((dest / "REPORT.html").read_text("utf8"))
        for relative in links.references:
            if relative != "SHA256SUMS.txt":
                safe_file(dest,relative)
        for name in ("原生通知按钮检查表.md","comparison/NOTIFICATION-COMPARISON.md"):
            report = dest / name
            for raw in re.findall(r"\]\(([^)]+)\)",report.read_text("utf8")):
                target = urlsplit(raw.strip("<>"))
                if not target.scheme and not target.netloc and target.path:
                    local = (report.parent / unquote(target.path)).resolve(strict=True)
                    require(local.is_relative_to(dest.resolve()) and local.is_file(),f"Broken portable reference {raw}")
        checksum = self.manifest(dest)
        (dest / "SHA256SUMS.txt").write_text(checksum, encoding="utf8", newline="")
        return checksum

    @staticmethod
    def manifest(dest):
        entries = sorted((p.relative_to(dest).as_posix(),p) for p in dest.rglob("*") if p.is_file() and p.name != "SHA256SUMS.txt")
        return "".join(f"{digest(p)}  {name}\n" for name,p in entries)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--main-commit", help="Confirmed GitHub main SHA if promotion has been verified")
    parser.add_argument("--directory", default="delivery", help="Existing directories are immutable; use delivery-2 for a separate edition.")
    args = parser.parse_args()
    require(re.fullmatch(r"delivery(?:-[1-9]\d*)?", args.directory), "Unknown delivery directory")
    if args.main_commit:
        require(re.fullmatch(r"[a-f0-9]{40}", args.main_commit), "Expected full main SHA")
    target = read(ROOT / "candidate.json")
    build = str(target["build"])
    require(build.isdigit() and re.fullmatch(r"[a-f0-9]{40}", target["sha"]), "Invalid candidate")
    b = ROOT / ("build" + build)
    missing = [str(p.relative_to(ROOT)) for p in [*(b / n for n in B_INPUTS),*(ROOT / "h5" / n for n in H_INPUTS)] if not p.is_file()]
    if missing:
        print(json_text({"build":build,"state":"awaiting evidence","missing":missing}))
        return 2
    delivery = Delivery(b,target)
    delivery.collect(args.main_commit)
    if not args.write:
        print(json_text({"build":build,"state":"inputs verified","sourceFiles":len(delivery.files)}))
        return 0
    with tempfile.TemporaryDirectory(prefix=".assemble-",dir=b) as temp:
        stage = Path(temp) / "output"
        stage.mkdir()
        expected = delivery.write(stage)
        destination = b / args.directory
        if destination.exists():
            actual = (destination / "SHA256SUMS.txt").read_text("utf8")
            require(actual == expected == delivery.manifest(destination), f"Existing delivery differs; preserved {destination}")
        else:
            stage.rename(destination)
    print(json_text({"directory":str(destination),"build":build,"commit":target["sha"]}))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

