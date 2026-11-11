from PIL import Image,ImageDraw
from pathlib import Path
import subprocess,sys,json
from audit_platform import ffmpeg
r=Path(__file__).resolve().parent;b=r/('build'+sys.argv[1])/'comparison';f=ffmpeg(r);w,h=170,196;fps=4;data=subprocess.check_output([str(f),'-v','error','-i',str(b/'paired-interactions.mp4'),'-vf',f'fps={fps},scale={w}:{h}','-an','-pix_fmt','rgb24','-f','rawvideo','-']);step=w*h*3;n=len(data)//step; rows=json.loads((b/'index.json').read_text('utf8'))['videos'][0]['segments'];j=Image.new('RGB',(w*5,(h+18)*len(rows)),'white');d=ImageDraw.Draw(j)
for k,seg in enumerate(rows):
 for i,r in enumerate((.04,.28,.5,.72,.96)):
  t=seg['pairedStart']+seg['seconds']*r;fi=max(0,min(n-1,int(t*fps)));x=i*w;y=k*(h+18);img=Image.frombytes('RGB',(w,h),data[fi*step:(fi+1)*step]);j.paste(img,(x,y));d.text((x,y+h),f'{fi/fps:.2f}s',fill='black')
j.save(b/'paired-motion-review.jpg')
