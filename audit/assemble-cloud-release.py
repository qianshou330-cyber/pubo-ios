"""Verify the cloud inputs, make the offline archive and make a small review copy.

Run after the simulator and H5 indexing steps, on the evidence branch's Linux runner.
The application repository is never written by this script.
"""
import argparse
import csv
import hashlib
import html
import io
import json
import os
from pathlib import Path, PurePosixPath
import runpy
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent
lib = runpy.run_path(str(ROOT / "assemble-delivery.py"))
read, digest, require, safe_file = (lib[k] for k in ("read","digest","require","safe_file"))
escape = html.escape
REPO = "qianshou330-cyber/pubo-ios"
BASE_ZIP = "c17974495c659dcabffbc852dd6d3ef31225f65cfa7b1efed52e4bb1f7fcaa98"
BASE_IPA = "18ef4e429338953513f79612ea2a956aa39310ddc009aee00c6d9acf2e2b511b"

def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf8")

def gh(api,target=None):
    command = ["gh","api",f"repos/{REPO}/{api}"]
    if target is None:
        return json.loads(subprocess.check_output(command))
    with target.open("wb") as stream:
        subprocess.run(command,stdout=stream,check=True)

def verify_archives(b,t):
    index = read(b/"source-artifacts.json")
    require(index["productCommit"]==t["sha"],"Wrong artifact commit")
    expected = read(b/"runs.json")
    by_suite = {a["suite"]:a for a in index["artifacts"]}
    require(set(by_suite)=={"large","small","preserved","package","integration"} and len(index["artifacts"])==5,
            "Expected five distinct release artifacts")
    for suite,a in by_suite.items():
        run = expected["integration" if suite=="integration" else "visual"]
        local = safe_file(b,a["localZip"])
        require(a["run_id"]==run and a["name"].endswith(t["sha"]),f"Wrong run or commit for {suite}")
        size = local.stat().st_size
        raw_hash = digest(local)
        require(a["size_in_bytes"]==size==a["verifiedBytes"] and a["digest"]=="sha256:"+raw_hash
                and a["verifiedSHA256"]==raw_hash,f"Unverified archive for {suite}")
        if suite in ("package","integration"):
            write_json(b/(suite+".github.json"),dict(commit=t["sha"],id=a["id"],run=run))
            write_json(b/(suite+".verified.json"),dict(commit=t["sha"],artifactID=a["id"],sha=raw_hash,bytes=size))
    return by_suite

def verify_source(b,t):
    pin=read(b/"source-verification.json")
    archive=b/"source.zip"
    if not archive.exists():
        # The codeload prefix matches the original release archive, unlike API zipball archives.
        subprocess.run(["curl","--fail","--silent","--show-error","--location","--retry","2","--output",str(archive),
                        f"https://codeload.github.com/{REPO}/zip/{t['sha']}"],check=True)
    require(pin["commit"]==t["sha"] and pin["tree"]==t["tree"] and digest(archive)==pin["archiveSHA256"],"Wrong source archive")
    with zipfile.ZipFile(archive) as z:
        prefix="pubo-ios-"+t["sha"]+"/"
        names=[f.filename for f in z.infolist() if not f.is_dir()]
        require(len(names)==len(set(names)) and set(names)=={prefix+i["path"] for i in pin["files"]},"Unexpected source tree")
        for item in pin["files"]:
            data=z.read(prefix+item["path"])
            require(len(data)==item["bytes"] and hashlib.sha256(data).hexdigest()==item["sha256"] and
                    hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()==item["gitBlob"],
                    "Source differs from audited Git tree: "+item["path"])

def verify_baseline(b):
    destination=ROOT.parent/"ios-timeline-visual-20261105/build134/delivery/PUBO-0.9.3-134-iphoneos-arm64-unsigned.ipa"
    if not destination.is_file():
        result=gh("actions/runs/42966671681/artifacts?per_page=100")["artifacts"]
        entry, = [f for f in result if f.get("digest")=="sha256:"+BASE_ZIP and not f["expired"]]
        # Keep the baseline in the runner's temporary checkout. It is not part of the new ZIP.
        archive=b/"baseline-134.zip"
        gh(f"actions/artifacts/{entry['id']}/zip",archive)
        require(digest(archive)==BASE_ZIP and archive.stat().st_size==entry["size_in_bytes"],"Wrong baseline archive")
        with zipfile.ZipFile(archive) as z:
            name,=[n for n in z.namelist() if n.endswith(".ipa")]
            data=z.read(name)
            require(hashlib.sha256(data).hexdigest()==BASE_IPA,"Wrong baseline IPA")
            destination.parent.mkdir(parents=True,exist_ok=True)
            destination.write_bytes(data)
    require(digest(destination)==read(b/"package-verification.json")["build134SHA256"]==BASE_IPA,"Unverified baseline")

def original(artifacts,b,relative):
    parts=PurePosixPath(str(relative).replace("\\","/")).parts
    suite=parts[0].removeprefix("native-")
    artifact=artifacts[suite]
    member="/".join(parts[1:])
    require(member and safe_file(b,relative).is_file(),"Missing original")
    return dict(suite=suite,artifact=artifact["id"],member=member,
                url=f"https://github.com/{REPO}/actions/runs/{artifact['run_id']}/artifacts/{artifact['id']}",
                expires=artifact.get("expires_at"),sha256=artifact["verifiedSHA256"])

def write_light(light,b,t,artifacts,classification,archive_sha):
    light.mkdir(parents=True,exist_ok=True)
    pkg=read(b/"package-verification.json")
    prefix=f"PUBO-{t['version']}-{t['build']}"
    ipa=prefix+"-iphoneos-arm64-unsigned.ipa"
    src=prefix+"-source.zip"
    for source,target in ((safe_file(b,pkg["ipaRelativePath"]),ipa),(b/"source.zip",src)):
        shutil.copyfile(source,light/target)
    comparisons=read(b/"comparison/index.json")
    review_names={"overview-light.png","overview-dark.png","paired-interactions.mp4"}
    review_names.update(v["file"] for v in comparisons["pairs"]+comparisons["videos"])
    for name in review_names:
        item=safe_file(b/"comparison",name)
        shutil.copyfile(item,light/Path(name).name)
    routes=read(b/"native-routes.json")
    groups=read(b/"native-simulator-groups.json")
    shots={s["namedOriginal"]:s for s in read(b/"native-screenshot-index.json") if s.get("namedOriginal")}
    rows=[]
    source_index=[]
    with (light/"按钮检查表.csv").open("w",encoding="utf-8-sig",newline="") as f:
        writer=csv.writer(f)
        writer.writerow(["类别","操作","H5","IPA","返回","差异","下载原件","ZIP内原始截图","ZIP内原始录像","原片秒数"])
        for row,side in zip(routes,classification,strict=True):
            require(row["kind"]==side["来源类型"],"Misordered comparative route")
            screenshot=original(artifacts,b,shots[row["evidence"]]["path"])
            movie=original(artifacts,b,row["video"])
            source_index.append(dict(action=row["action"],screenshot=screenshot,movie=movie,seconds=row["videoSeconds"]))
            writer.writerow([row["kind"],row["action"],side["H5 实点"],row["target"],row["back"],side["差异或说明"],
                             movie["url"],screenshot["member"],movie["member"],row["videoSeconds"]])
            rows.append(lib["cells"]([escape(row["action"]),escape(side["H5 实点"]),escape(row["target"]),
                                      escape(row["back"]),escape(side["差异或说明"]),
                                      f'<a href="{movie["url"]}">原片 {row["videoSeconds"]:.1f} 秒</a>']))
    media=[]
    for video in comparisons["videos"]:
        for seg in video["segments"]:
            source=(b/"comparison"/seg["native"]).resolve(strict=True).relative_to(b)
            info=original(artifacts,b,source)
            media.append(dict(action=seg["action"],movie=info,seconds=seg["nativeOriginalStart"],h5=seg["h5"],h5Start=seg["h5Start"]))
    write_json(light/"原件索引.json",dict(product=t["sha"],retentionDays=14,
               archives=[dict(id=a["id"],run=a["run_id"],name=a["name"],digest=a["digest"],size=a["verifiedBytes"],
                              url=f"https://github.com/{REPO}/actions/runs/{a['run_id']}/artifacts/{a['id']}",
                              expires_at=a.get("expires_at")) for a in artifacts.values()],routes=source_index,segments=media))
    real=read(b/"real-and-core-results.json")
    images=" ".join(lib["link"](Path(r["file"]).name,
               lib["STATES"][r["state"]]+(" · 浅色" if r["theme"]=="light" else " · 深色")) for r in comparisons["pairs"])
    counts=sum(g["passed"] for g in groups.values())
    visuals=(b/"comparison/NOTIFICATION-COMPARISON.md").read_text("utf8")
    # Keep the paired report's precise visual limitations visible in the card.
    detail_section=visuals.partition("### 画面仍可见的差异")[2].split("\n## ",1)[0]
    details="".join("<li>"+escape(line[2:])+"</li>" for line in detail_section.splitlines() if line.startswith("- "))
    if not details:
        details="<li>系统字体、Emoji、安全区及底部四页导航保留 iOS 版式。</li>"
    run_page=f"https://github.com/{REPO}/actions/runs/{int(os.environ['GITHUB_RUN_ID'])}"
    body=f"""<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PUBO 通知页验收</title><style>:root{{color-scheme:light dark;font:16px system-ui,sans-serif}}body{{max-width:1050px;margin:auto;padding:32px 20px}}section{{margin:30px 0}}img,video{{max-width:100%;height:auto}}a{{color:LinkText}}p,li{{line-height:1.65}}table{{border-collapse:collapse}}td,th{{border:1px solid #8886;padding:7px;text-align:left}}.table{{overflow:auto}}.links a{{display:inline-block;margin:4px}}code{{overflow-wrap:anywhere}}</style>
<h1>PUBO {escape(t['version'])} 通知页</h1><p>build {int(t['build'])} · iPhone 17 Pro Max 模拟器 · 440×956pt · iOS 26.0.1</p>
<p>{lib['link'](ipa,'下载未签名 IPA')} · {lib['link'](src,'下载完整源码')} · <a href="{run_page}">下载完整验收 ZIP 与 SHA-256</a></p>
<p>IPA SHA-256 <code>{pkg['sha256']}</code><br>完整验收 ZIP SHA-256 <code>{archive_sha}</code></p>
<section><h2>页面与动画</h2><p>两端使用同一组隔离通知。网页由内置浏览器录制，模拟器保留原生状态栏、触控区域和四页导航。</p>
<img src="overview-light.png" alt="浅色对照"><img src="overview-dark.png" alt="深色对照"><div class="links">{images}</div>
<video controls preload="none" src="paired-interactions.mp4"></video><ul>{details}</ul></section>
<section><h2>分类、跳转与返回</h2><p>20类，含聚合变体及行内操作。{lib['link']('按钮检查表.csv','下载逐项检查表')} · {lib['link']('原件索引.json','查看原始截图、录像路径及秒数')}</p><div class="table"><table><thead>{lib['cells'](['操作','H5','IPA','返回','差异','来源'],'th')}</thead><tbody>{''.join(rows)}</tbody></table></div></section>
<section><h2>验证范围</h2><p>{real['core']} 项核心测试、{real['packageTests']} 项打包测试、{counts} 项模拟器界面测试和 {real['realUITests']} 项隔离后端界面测试通过。两台设备均验证短拉后没有新增请求，超过 200pt 松手取得新通知。</p>
<p>原片保存在 GitHub Actions，保留 14 天。打开原片链接后下载对应制品，按索引里的 ZIP 内路径和时间点定位。完整验收 ZIP 另含可离线查看的原件。</p>
<p>实体手机、最低 iOS 17、真机签名安装和覆盖升级、真实锁屏推送尚未验收。</p></section></html>"""
    (light/"REPORT.html").write_text(body,encoding="utf8")
    sums="".join(f"{digest(f)}  {f.name}\n" for f in sorted(light.iterdir()) if f.is_file() and f.name!="SHA256SUMS.txt")
    (light/"SHA256SUMS.txt").write_text(sums,encoding="utf8")

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("build",nargs="?",default="138",choices=["138"])
    p.add_argument("--prepare",action="store_true",help="Audit downloaded source and results, then stop")
    args=p.parse_args()
    require(os.environ.get("GITHUB_ACTIONS")=="true" and os.environ.get("RUNNER_OS")=="Linux",
            "This stage runs on the cloud Linux evidence runner")
    b=ROOT/("build"+args.build)
    t=read(b/"target.json")
    artifacts=verify_archives(b,t)
    verify_source(b,t)
    verify_baseline(b)
    subprocess.run([sys.executable,str(ROOT/"verify-real-and-core.py"),str(b)],check=True)
    if args.prepare: return
    require(read(b/"comparison/index.json").get("windowsReview")=="confirmed","Footage awaits visual review")
    d=lib["Delivery"](b,t)
    d.collect(None)
    d.from_b("source-artifacts.json","evidence/github-artifacts.json")
    d.generated["H5-原件说明.txt"]="内置浏览器的原始 MP4、成对截图、样本帧及完整采帧时间索引均随附。逐帧 JPEG 序列的其余文件保留在原采集目录。\n"
    output=b/"delivery-output"
    archive_root=output/"whole"
    archive_root.mkdir(parents=True,exist_ok=True)
    name=f"PUBO-{t['version']}-{t['build']}-evidence.zip"
    archive=archive_root/name
    partial=archive_root/(name+".partial")
    manifest={}
    with zipfile.ZipFile(partial,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=2,allowZip64=True) as z:
        for rel,source in sorted(d.files.items()):
            manifest[rel]=d.hashes.get(source) or digest(source)
            stored=source.suffix.lower() in (".mp4",".mov",".png",".jpg",".ipa",".zip")
            z.write(source,rel,compress_type=zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED)
        for rel,text in d.generated.items():
            require(rel not in manifest,"Duplicate entry "+rel)
            data=text.encode("utf8")
            manifest[rel]=hashlib.sha256(data).hexdigest()
            z.writestr(rel,data)
        z.writestr("SHA256SUMS.txt","".join(f"{h}  {rel}\n" for rel,h in sorted(manifest.items())))
    with zipfile.ZipFile(partial) as z:
        for rel,checksum in manifest.items():
            with z.open(rel) as raw:
                require(hashlib.file_digest(raw,"sha256").hexdigest()==checksum,"ZIP verification failed: "+rel)
        links=lib["LocalLinks"]()
        links.feed(z.read("REPORT.html").decode("utf8"))
        require(all(h in z.namelist() for h in links.references),"Offline report has a missing local link")
    partial.replace(archive)
    archive_sha=digest(archive)
    (archive_root/(name+".sha256")).write_text(archive_sha+"  "+name+"\n",encoding="ascii")
    classification=list(csv.DictReader((b/"comparison/buttons.csv").read_text("utf-8-sig").splitlines()))
    write_light(output/"light",b,t,artifacts,classification,archive_sha)
    print(json.dumps(dict(build=t["build"],sha=t["sha"],archive=name,archiveBytes=archive.stat().st_size,
                          archiveSHA256=archive_sha,lightBytes=sum(f.stat().st_size for f in (output/"light").rglob("*") if f.is_file()))))

if __name__=="__main__":
    main()
