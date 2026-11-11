"""Locate actual simulator screenshot states on the MP4 presentation timeline."""
from pathlib import Path
import json, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw
from audit_platform import ffmpeg

r=Path(__file__).resolve().parent
b=r/('build'+sys.argv[1])
ff=ffmpeg(r)
group=sys.argv[2] if len(sys.argv)>2 else 'notifications'
g='large/'+group
load=lambda p:json.loads(p.read_text('utf8'))
v=b/load(b/'native-simulator-groups.json')[g]['source'].replace('\\','/')
items=[e for e in load(b/'native-screenshot-index.json') if e['group']==g and e.get('namedOriginal')]
w,h,fps=88,191,5
raw=subprocess.check_output([str(ff),'-nostdin','-hide_banner','-v','error','-i',str(v),'-vf',f'fps={fps},scale={w}:{h}:flags=lanczos','-threads','2','-an','-pix_fmt','rgb24','-f','rawvideo','-'])
frames=np.frombuffer(raw,np.uint8).reshape(-1,h,w,3)
times=np.arange(len(frames))/fps
profiles={}
for x in items:
 ref=np.asarray(Image.open(b/x['namedOriginal'].replace('\\','/')).convert('RGB').resize((w,h),Image.Resampling.LANCZOS)).astype(np.int16)
 point=x.get('wallSecondsSinceRecordingStart',x.get('rawVideoSeconds'))
 # Match across the entire presentation. A loaded simulator's encoded clock can drift
 # by more than 90s. Sparse white lists otherwise match blank transition screens.
 target=ref[18:169,1:-1,:]
 grey=target.mean(axis=2)
 edges=np.maximum(np.abs(grey-np.roll(grey,1,0)),np.abs(grey-np.roll(grey,1,1)))
 weights=(1+8*(edges>12)+4*(np.ptp(target,axis=2)>20)).astype(np.float32)
 weights[:21]*=1.6
 scores=[]
 for start in range(0,len(frames),100):
  delta=np.abs(frames[start:start+100,18:169,1:-1,:].astype(np.int16)-target)
  scores.extend((delta.mean(axis=3)*weights).sum(axis=(1,2))/weights.sum())
 scores=np.asarray(scores)
 timespan=times
 best=float(scores.min())
 profiles[x['name']]=(point,timespan,scores,best)
estimates=[]
for delta in np.arange(-min(280,len(frames)/fps),80,0.2):
 loss=[]
 for point,ts,sc,best in profiles.values():
  around=abs(ts-(point+delta))<1.0
  if around.any():loss.append(min(20,float(sc[around].min()-best)))
 if loss:estimates.append((float(np.mean(loss)),abs(delta),delta))
_,_,offset=min(estimates)
result={}
for name,(point,ts,sc,best) in profiles.items():
 ok=np.flatnonzero(sc<=best+.7)
 clusters=np.split(ok,np.where(np.diff(ok)>1)[0]+1)
 spans=[(float(ts[seq[0]]),float(ts[seq[-1]]),float(sc[seq].min())) for seq in clusters if len(seq)>0]
 projected=point+offset
 def distance(s):return max(0,s[0]-projected,projected-s[1])
 span=min(spans,key=lambda s:(distance(s),s[2]))
 result[name]=dict(wallRelative=point,bestRGBError=round(best,3),likelyPTS=round(float(np.clip(projected,*span[:2])),3),stableFrom=span[0],stableThrough=span[1],matchingError=round(span[2],3),otherSpans=[x[:2] for x in spans if x!=span][:8])
obj={'recording':v.relative_to(b).as_posix(),'sourceSampleRate':fps,'presentationSeconds':len(frames)/fps,'commonOffset':round(offset,2),'matches':result}
(b/f'{group}-visual-pts.json').write_text(json.dumps(obj,ensure_ascii=False,indent=2),'utf8')
names=['notifications-filter-light','notifications-follow-light','notifications-mentions-light','notifications-directNotes-light','notifications-pull-refreshed','notifications-live-arrived']
grid=Image.new('RGB',(98*9,214*len(names)),'white');d=ImageDraw.Draw(grid)
for j,n in enumerate(names):
 if n not in result:continue
 s=result[n]['stableFrom'];print(n, 'raw',result[n]['wallRelative'],'actual',result[n]['stableFrom'],result[n]['stableThrough'])
 for k,dt in enumerate([-4,-3,-2,-1.2,-.6,-.2,0,.5,1.5]):
  it=max(0,min(len(frames)-1,round((s+dt)*fps)));pic=Image.fromarray(frames[it]);x=k*98;y=j*214;grid.paste(pic,(x,y))
  d.text((x,y+192),f'{it/fps:.1f}',fill='black')
grid.save(b/f'{group}-motion-inspection.jpg')
