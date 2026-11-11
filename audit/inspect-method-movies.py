"""Inspect successful individual XCTest recordings on their own presentation timelines."""
import json
import subprocess
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from audit_platform import ffmpeg

root=Path(__file__).resolve().parent
b=root/('build'+sys.argv[1])
group='native-large'
directory=b/group
shots=directory/'screenshots/notifications'
ff=ffmpeg(root)
def load(p):return json.loads(p.read_text('utf8'))
recordings=load(directory/'notification-test-recordings.json')
measures={'testUnreadAndPullToRefresh':['notifications-pull-refreshed'],'testNewNotificationArrivesWhileReadingAtTop':['notifications-live-arrived'],'testThreeTabsAndFilterInBothAppearances':['notifications-filter-light','notifications-follow-light','notifications-mentions-light','notifications-directNotes-light']}
info={}
for method,references in measures.items():
    refs=next((v for k,v in recordings.items() if method in k),None)
    if not refs:continue
    file=shots/refs[0]
    w,h,fps=132,287,5
    data=subprocess.check_output([str(ff),'-v','error','-i',str(file),'-vf',f'fps={fps},scale={w}:{h}:flags=lanczos','-an','-threads','2','-pix_fmt','rgb24','-f','rawvideo','-'])
    frames=np.frombuffer(data,np.uint8).reshape(-1,h,w,3)
    for ref_index,reference in enumerate(references):
        image=b/'native-originals/large'/(reference+'.png')
        if not image.is_file():continue
        target=np.asarray(Image.open(image).convert('RGB').resize((w,h),Image.Resampling.LANCZOS))[29:249,2:-2].astype(np.int16)
        grey=target.mean(axis=2);weights=(1+8*(np.abs(grey-np.roll(grey,1,0))>11)+4*(np.abs(grey-np.roll(grey,1,1))>11)+3*(np.ptp(target,axis=2)>18)).astype(np.float32)
        scores=[float((np.abs(f[29:249,2:-2].astype(np.int16)-target).mean(axis=2)*weights).sum()/weights.sum()) for f in frames]
        best=min(scores);hit=np.flatnonzero(np.asarray(scores)<best+.65);spans=[[s[0]/fps,s[-1]/fps] for s in np.split(hit,np.flatnonzero(np.diff(hit)>1)+1) if len(s)]
        info[reference]={'source':file.relative_to(b).as_posix(),'durationPTS':len(frames)/fps,'minMeanError':best,'matchingSpans':spans}
        views=[('near',list(range(max(0,hit[0]-fps*5),min(len(frames),hit[0]+fps*3))))]
        if ref_index==0:views.insert(0,('whole',list(range(0,len(frames),max(2,len(frames)//30)))))
        for title,indices in views:
            cols=8
            grid=Image.new('RGB',(cols*(w+2),(h+17)*((len(indices)+cols-1)//cols)),'white');d=ImageDraw.Draw(grid)
            for no,ix in enumerate(indices):
                x=(no%cols)*(w+2);y=(no//cols)*(h+17)
                grid.paste(Image.fromarray(frames[ix]),(x,y));d.text((x,y+h),f'{ix/fps:.1f}s',fill='black')
            grid.save(b/f'{reference}-method-{title}.jpg')
print(json.dumps(info,indent=2))
(b/'native-method-timing-candidates.json').write_text(json.dumps(info,indent=2),'utf8')
