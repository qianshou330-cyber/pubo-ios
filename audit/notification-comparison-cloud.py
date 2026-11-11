"""Create a lightweight proof index and full comparison on a Linux Actions worker."""
import json
import os
from pathlib import Path
import subprocess
import sys

root=Path(__file__).resolve().parent
number=sys.argv[1]
if not number.isdecimal():raise ValueError('A build number is required')
b=root/('build'+number)
def load(p):return json.loads(p.read_text('utf8'))
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2),'utf8')
def run(script,*args):subprocess.run([sys.executable,str(root/script),number,*args],cwd=root,check=True)

video_pts=b/'notifications-visual-pts.json'
if not video_pts.exists():run('locate-real-motion.py')
run('inspect-method-movies.py')
group=load(video_pts)
methods=load(b/'native-method-timing-candidates.json')
offsets={'notifications-filter-light':-1.25,'notifications-follow-light':-1.4,
         'notifications-mentions-light':-1.15,'notifications-directNotes-light':-.9,
         'notifications-pull-refreshed':-2.8,'notifications-live-arrived':-1.2}
needs={'notifications-filter-light':2.8,'notifications-follow-light':2.95,
       'notifications-mentions-light':2.5,'notifications-directNotes-light':2.8,
       'notifications-pull-refreshed':3.7,'notifications-live-arrived':2.3}
windows={}
for name,delta in offsets.items():
    if name in methods:
        item=methods[name];source=item['source'];duration=item['durationPTS']
        stable=item['matchingSpans'][0][0]
    else:
        source=group['recording'];duration=group['presentationSeconds'];stable=group['matches'][name]['stableFrom']
    windows[name]=dict(source=source, startPTS=round(max(0,min(duration-needs[name],stable+delta)),3),durationPTS=duration,reviewed=False)
write(b/'notification-proposed-windows.json',windows)
manual=os.environ.get('NOTIFICATION_WINDOWS_JSON','').strip()
review_file=b/'notification-reviewed-windows.json'
reviewed=bool(manual or review_file.is_file())
if reviewed:
    edits=json.loads(manual) if manual else load(review_file)
    if set(edits)!=set(windows):raise ValueError('Supply a reviewed start timestamp for each of the six actions')
    for name,entry in edits.items():
        if isinstance(entry,(float,int)):
            windows[name]['startPTS']=float(entry)
        else:
            for key in ('source','startPTS','durationPTS'):windows[name][key]=entry[key]
        windows[name]['reviewed']=True
write(b/'notification-pair-windows.json',windows)
run('pair-notification-evidence.py','--images','--video','--report',*([] if reviewed else ['--suggested-windows']))
run('inspect-pairs.py')
out=b/'comparison';ix=load(out/'index.json');ix['windowsReview']='confirmed' if reviewed else 'awaiting frame review'
write(out/'index.json',ix)
print('Rendered',out,'with',len(ix['pairs']),'pairs and',len(windows),'real-motion excerpts')
print('Inspect comparison/paired-motion-review.jpg and *-method-near.jpg. Confirm all six points with NOTIFICATION_WINDOWS_JSON or notification-reviewed-windows.json before release.')
