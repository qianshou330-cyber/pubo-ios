"""Join the delivered simulator captures with inspected, full-height H5 frames."""
import argparse, csv, hashlib, json, os, subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from audit_platform import ffmpeg, cjk_font

p = argparse.ArgumentParser()
p.add_argument('build')
p.add_argument('--images', action='store_true')
p.add_argument('--video', action='store_true')
p.add_argument('--report', action='store_true')
p.add_argument('--precheck', action='store_true', help='Export only scenes that currently have a simulator reference frame.')
p.add_argument('--suggested-windows',action='store_true',help='Render a review copy from unconfirmed presentation timestamps.')
args = p.parse_args()
ROOT = Path(__file__).resolve().parent
B = ROOT / ('build' + args.build)
H = ROOT / 'h5'
OUT = B / 'comparison'
OUT.mkdir(exist_ok=True)
FF = ffmpeg(ROOT)
FONT = cjk_font()
def font(size): return ImageFont.truetype(FONT, size)
def load(f): return json.loads(f.read_text('utf8'))
def write(f, v): f.write_text(json.dumps(v, ensure_ascii=False, indent=2), 'utf8')
def rel(path): return Path(os.path.relpath(path, OUT)).as_posix()
def sha(f): return hashlib.sha256(f.read_bytes()).hexdigest()
def run(*s): subprocess.run([str(FF),'-nostdin','-hide_banner','-loglevel','error','-y',*map(str,s)],check=True)
index_path = OUT/'index.json'
index = load(index_path) if index_path.exists() else {}
index.update(build=args.build, range='通知', simulator='iPhone 17 Pro Max, iOS 26.0.1, 440×956pt', h5='内置浏览器，440×956 CSS，完整画面等比显示为 330×717 像素')
states = [('all','all','全部通知'),('filter','filter','类别菜单'),('follow','follow','关注筛选'),('mentions','mentions','提到我的'),('specified','directNotes','指定用户帖子')]
def label(draw, point, text, size=18, color='#1d2927'): draw.text(point,text,font=font(size),fill=color)
def write_images():
    pairs = []
    for theme in ('light','dark'):
        for key, nkey, title in states:
            h = H / f'{key}-{theme}.png'
            n = B / 'native-originals/large'/f'notifications-{nkey}-{theme}.png'
            lhs, rhs = Image.open(h).convert('RGB'), Image.open(n).convert('RGB')
            assert lhs.size == (330,717) and rhs.size == (1320,2868)
            pic = Image.new('RGB',(682,779),'#e7ecea')
            draw = ImageDraw.Draw(pic)
            label(draw,(8,5),'H5 · 内置浏览器')
            label(draw,(344,5),'IPA · iPhone 17 Pro Max 模拟器')
            label(draw,(8,32),title,14,'#56665f')
            label(draw,(344,32),f'0.9.4 / build {args.build}',14,'#56665f')
            pic.paste(lhs,(8,54)); pic.paste(rhs.resize(lhs.size,Image.Resampling.LANCZOS),(344,54))
            name = f'{key}-{theme}.png';pic.save(OUT/name)
            pairs.append(dict(state=key,theme=theme,h5=rel(h),native=rel(n),file=name,h5SHA256=sha(h),nativeSHA256=sha(n)))
        # The main link opens the full-size first-screen comparison; the grid index links the remaining pairs.
        first = Image.open(OUT/f'all-{theme}.png')
        first.save(OUT/f'overview-{theme}.png')
    index['pairs']=pairs
def write_video():
    alignment = load(B/'notifications-visual-pts.json')
    original = B/alignment['recording']
    overrides_file=B/'notification-pair-windows.json'
    overrides=load(overrides_file) if overrides_file.is_file() else {}
    # XCTest wall-clock attachment times do not always match the simulator MP4's PTS.
    # Use stable display spans on the original video, after checking the motion contact sheets.
    sizes = {r['name']:r for r in load(H/'videos/index.json')['files']}
    seq = [
      ('进入分类菜单','switch-and-filter-light',.25,'notifications-filter-light',-1.25,2.8),
      ('选择关注筛选','switch-and-filter-light',2.3,'notifications-follow-light',-1.4,2.95),
      ('切换提到我的','switch-and-filter-light',4.9,'notifications-mentions-light',-1.15,2.5),
      ('切换指定用户帖子','switch-and-filter-light',7.7,'notifications-directNotes-light',-.9,2.8),
      ('下拉刷新','refresh-live-note',.35,'notifications-pull-refreshed',-2.8,6.5),
      ('新通知入场','refresh-live-note',3.6,'notifications-live-arrived',-1.2,2.3),
    ]
    seq=[(title,h,hs,n,delta,float(overrides.get(n,{}).get('seconds',dt))) for title,h,hs,n,delta,dt in seq]
    if args.precheck:
        seq=[case for case in seq if case[3] in alignment['matches'] and case[3] not in ('notifications-pull-refreshed','notifications-live-arrived')]
        index['pending']='初轮对照；下拉刷新与实时新行入场的录像待同产品源的模拟器专验。'
    else:
        index.pop('pending',None)
    # A seek into simctl's variable-frame-rate movie can return a different scene.
    # Decode the original presentation timeline from zero, then trim all verified scenes in one pass.
    by_video={}
    windows={}
    for i,(_,_,_,n,delta,dt) in enumerate(seq):
        manual=overrides.get(n)
        if manual:
            src=(B/manual['source'].replace('\\','/')).resolve();start=manual['startPTS']
            assert src.is_relative_to(B) and src.is_file() and src.suffix.lower() in ('.mp4','.mov'),src
            assert (manual['reviewed'] or args.suggested_windows) and dt>0 and 0<=start and start+dt<=manual['durationPTS'], manual
        else:
            src=original;start=max(0,alignment['matches'][n]['stableFrom']+delta)
            assert start+dt<=alignment['presentationSeconds']
        by_video.setdefault(src,[]).append((i,start,dt))
        windows[n]=(src,start)
    for src,parts in by_video.items():
        filters='[0:v]scale=440:956:flags=lanczos:force_original_aspect_ratio=decrease,pad=440:956:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30'
        if len(parts)>1:filters+=',split='+str(len(parts))
        filters+=''.join(f'[s{i}]' for i,_,_ in parts)
        outputs=[]
        for i,start,dt in parts:
            filters+=f';[s{i}]trim=start={start:.3f}:duration={dt:.3f},setpts=PTS-STARTPTS[part{i}]'
            outputs+=['-map',f'[part{i}]','-an','-c:v','libx264','-threads','2','-crf','16','-pix_fmt','yuv420p',OUT/f'.native-{i}.mp4']
        run('-i',src,'-filter_complex',filters,*outputs)
    concat=[]; entries=[]; t=0
    for i,(title,h,hs,n,delta,dt) in enumerate(seq):
        src,ns=windows[n]
        hv=H/'videos'/sizes[h]['file']
        assert dt>0 and hs>=0 and hs+dt<=sizes[h]['elapsed']
        nv=OUT/f'.native-{i}.mp4'
        # Metadata tracks may outlast the last real sample in an XCTest video.
        # Verify the extracted frames before composing side by side at normal speed.
        count_bytes=subprocess.check_output([str(FF),'-v','error','-i',str(nv),'-map','0:v:0','-an','-vf','scale=2:2','-fps_mode','passthrough','-pix_fmt','gray','-f','rawvideo','-'])
        assert len(count_bytes)%4==0 and abs(len(count_bytes)/4-30*dt)<=1.001,(n,len(count_bytes)/4,dt)
        head=Image.new('RGB',(682,64),'#e7ecea');d=ImageDraw.Draw(head)
        label(d,(8,4),'H5 · 内置浏览器',17);label(d,(344,4),'IPA · iPhone 17 Pro Max 模拟器',17)
        label(d,(8,33),title,15,'#465751');label(d,(344,33),f'0.9.4 / build {args.build}',14,'#465751')
        header=OUT/f'.head-{i}.png';head.save(header);segment=OUT/f'.segment-{i}.mp4'
        run('-ss',hs,'-i',hv,'-i',nv,'-loop','1','-i',header,'-t',dt,'-filter_complex',
            '[0:v]crop=330:717:0:0:exact=1,fps=30,format=rgb24,setsar=1[h];[1:v]fps=30,scale=330:717:flags=lanczos,format=rgb24,setsar=1[n];[h]pad=682:718:8:0:color=0xe7ecea[base];[base][n]overlay=344:0:format=rgb[views];[2:v][views]vstack=inputs=2,format=yuv420p[out]',
            '-map','[out]','-an','-r',30,'-c:v','libx264','-threads',2,'-crf',18,'-pix_fmt','yuv420p',segment)
        entries.append(dict(action=title,pairedStart=round(t,3),seconds=dt,h5=rel(hv),h5Start=hs,native=rel(src),nativeOriginalStart=round(ns,3),reference=n))
        t+=dt
        concat.append("file '"+segment.name+"'")
    listing=OUT/'.segments.ffconcat';listing.write_text('\n'.join(concat),'ascii')
    video=OUT/'paired-interactions.mp4'
    run('-safe',0,'-f','concat','-i',listing,'-c','copy','-movflags','+faststart',video)
    index['videos']=[dict(name='分类菜单、关注筛选、提及和指定用户帖子' if args.precheck else '分类、切页、下拉刷新及新通知',file=video.name,h5=rel(H/'videos/index.json'),native=rel(original),sha256=sha(video),segments=entries)]
    for f in [listing, *[OUT/f'.head-{i}.png' for i in range(len(seq))], *[OUT/f'.native-{i}.mp4' for i in range(len(seq))], *[OUT/f'.segment-{i}.mp4' for i in range(len(seq))]]:f.unlink()
def write_report():
    h5=load(H/'routes-final.json')
    hc={r['type']:r for r in h5['cases']}
    nr=load(B/'native-routes.json')
    cats=load(H/'categories.json')
    labels={v['kind']:v['label'] for v in cats}
    labels.update({'reaction:grouped':'聚合回应','renote:grouped':'聚合转贴'})
    diffs={'chatRoomInvitationReceived':'H5 群名为纯文字，原生提供进入相应群聊的快捷入口。','login':'H5 正文为信息，原生提供受保护的会话入口。','roleAssigned':'H5 角色名为纯文字，原生直达自己的主页。','scheduledNotePostFailed':'H5 显示失败，原生可直达定时帖子。','receiveFollowRequest':'H5 在行内处理，可点头像或昵称查看申请人；原生同时提供关注申请列表入口。','createToken':'H5 打开网页应用设置，原生在需要时重新验证后显示已授权应用。','exportCompleted':'两端都打开对应文件，原生继续使用文件 ID 读取授权内容。','test':'点正文后保持在原处。','app':'本样例为纯文字正文，未覆盖含外部链接的应用通知。'}
    def clean(s):return s.replace('\n',' ').replace('|','／')
    rows=[]
    for n in nr:
        kind=n['kind'];r=hc[kind]
        h=r['observed']['url']
        h='正文留在通知页' if h=='/my/notifications' else h
        remark=diffs.get(kind,'对应同一对象。')
        if '第二位参与者头像' in n['action']:
            h='第二个头像链接 /@violet';remark='H5 已核对该头像的实际链接，原生已点开资料。'
        elif kind=='receiveFollowRequest' and '打开申请' not in n['action']:
            h='同行显示允许、拒绝两个按钮';remark='H5 核对了按钮呈现。此处原生结论来自隔离模拟器实点，实际后端回执见联调记录。'
        title=n['action'] if kind in ('reaction:grouped','receiveFollowRequest') else labels[kind]
        rows.append([title,kind,h,n['target'],n['back'],remark,rel(B/n['evidence'].replace('\\','/')),rel(B/n['video'].replace('\\','/'))+f"#t={max(0,n['videoSeconds']-4):.1f},{n['videoSeconds']+4:.1f}"])
    with (OUT/'buttons.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.writer(f);w.writerow(['分类','来源类型','H5 实点','IPA 实点','返回结果','差异或说明','原生截图','原生录像']);w.writerows(rows)
    h5row=rel(H/'routes-final.json'); att=rel(B/'原生通知按钮检查表.md')
    t=[f'# PUBO 0.9.4 build {args.build} 通知页对照','',
       'H5 使用本次重新获取的线上前端，在内置浏览器中运行。原生使用 iPhone 17 Pro Max 模拟器和 iOS 26.0.1。两端内容区域按 440×956 逻辑尺寸设置，使用同一个合成数据文件。H5 的页面接口与实时推送指向本地隔离服务。','',
       '[浅色全部通知](overview-light.png) · [深色全部通知](overview-dark.png) · [双端操作实录](paired-interactions.mp4) · [逐项按钮表](buttons.csv)','',
       '## 分类、未读和动画','',
       'H5 分类菜单 20 项；回应与转贴各有单条及多人聚合形态。按菜单逐项点击，返回的类别与预期相符。两端的「提到我的」展示含提及的帖子，「私信」仅展示指定用户可见的帖子，日常聊天仍由底部私信入口进入。','',
       'H5 首页显示 12 条未读，点击铃铛进入有数据的全部页后归零。已读状态再点右上勾，会出现约 96px 的居中成功提示。原生使用服务端未读数，保留四页底部导航。','',
       '两端下拉实录使用同样的播放速度。H5 在 2.390 秒发出刷新请求，稍后通过隔离实时流收到新通知。原生由模拟器拖动，经过「下拉刷新」「松开以刷新」「刷新中」，刷新响应带回新首行后收起提示。两次手势的拖动时长不同。独立的实时入场片段展示原生收到推送时插入首行的效果。','',
       '## 双主题截图','', '| 状态 | 浅色 | 深色 |','|---|---|---|']
    for key,nkey,labeltxt in states:t.append(f'| {labeltxt} | [对照]({key}-light.png) | [对照]({key}-dark.png) |')
    if args.precheck:t+=['','初轮原生刷新手势尚未取得新行，实时入场已有正确截图。两项动作的实录正在同产品源码的模拟器专验中补录。当前并排片收录分类菜单、关注筛选、提及和指定用户帖子。']
    t+=['','H5 原始帧中页面以 75% 比例显示，完整内容为 330×717 像素。模拟器截图原件为 1320×2868 像素，配对图按同一比例缩小。两端按各自实际时钟显示相对时间。','',
        '### 画面仍可见的差异','',
        '- 原生保留系统状态栏、安全区和四页底栏，因此同时可见的通知数量较少。H5 的底栏包含网页导航和发帖按钮。',
        '- H5 下拉菜单可同屏列出更多类别；iOS 系统菜单行距较大，向下滚动可到达后面的类别。', 
        '- H5 使用网页轮廓图标和网页表情图，原生使用系统图标、Apple 表情和头像占位轮廓。原生保留紧凑的回复上文卡片，H5 可显示上文作者和正文。测试账号未配置头像，H5 提及标签里的小头像显示为占位，真实账号的头像效果须另核对。','',
        '## 类型、目的地与返回','',f'[H5 全部实际记录]({h5row}) · [原生逐按钮截图和原片时间]({att})','',
        '| 类别 | H5 触点及去向 | IPA 触点及去向 | 影响及保留差异 | 证据 |','|---|---|---|---|---|']
    for row in rows:t.append('| '+' | '.join([clean(row[0]),clean(row[2]),clean(row[3]),clean(row[5]),f'[原生截图]({row[6]})'])+' |')
    t+=['','H5 打开有目的地的条目后，使用浏览器返回通知。聚合通知的头像仍链接相应参与者。原生已逐类打开目标，按返回后检查原筛选和条目。群聊与会话的进一步操作仍受账号权限约束。','',
        '## 录像与原始记录','',f'[五段 H5 实录、时间和校验]({rel(H/"videos/index.json")}) · [原生截图与时间]({rel(B/"native-screenshot-index.json")}) · [配对剪辑的起止时间](index.json)','',
        '普通用户界面使用隔离合成数据。H5 的本地回执用于验证界面行为，实际后端回执和真机安装条件请参见版本交付记录。实体 iPhone、最低 iOS 17 和签名覆盖升级仍待验证。','']
    (OUT/'NOTIFICATION-COMPARISON.md').write_text('\n'.join(t),'utf8')
    index['buttons']=dict(file='buttons.csv',count=len(rows),h5=h5row,native=rel(B/'native-routes.json'))
if args.images:write_images()
if args.video:write_video()
if args.report:write_report()
write(index_path,index)
