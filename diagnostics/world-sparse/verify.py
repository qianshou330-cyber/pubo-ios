"""Verify actual arm, unmodified receiver input, gesture provenance and independent fixture truth."""
import math
import re
import uuid
def check(q, why):
    if not q: raise ValueError(why)
def num(t):
    return type(t) in (int,float) and math.isfinite(t)
def seq(n):return [f'w80-{k:04d}' for k in range(200,200-n,-1)]
def strictset(items):
    check(isinstance(items,list) and all(type(x) is str for x in items) and sorted(set(items))==items,'Malformed ID set')
    return set(items)
def movement(a,b):
    for d in (a,b):
        check(type(d) is dict and d and all(k.startswith('note.open.') and k[10:] in seq(200) and num(v) for k,v in d.items()),'Missing native viewport rows')
    return set(a)!=set(b) or any(abs(a[k]-b[k])>8 for k in a.keys() & b.keys())
def verify(r,g):
    check(str(uuid.UUID(r['nonce'])).upper()==r['nonce']==g['nonce'],'Mismatched app/test launch')
    check(r.get('schema')==1 and r.get('ready') is True and r.get('invalid') is False,'Bad or interrupted generation')
    pages,merged=r['pages'],r['merged']
    check(len(pages)==len(merged)==10,'Exactly ten normal pages required')
    ids=seq(200)
    for i,(p,m) in enumerate(zip(pages,merged)):
        end=(i+1)*20;check(p=={'cursor':ids[i*20-1] if i else '', 'ids':ids[20*i:end]} and
            m=={'count':end,'oldest':ids[end-1]},'Filter/cursor/merge proof failed')
    intervals=g['drags']; end=g['end']; start=g['baselineEnd']; freeze=r['recordedAt']
    check(all(map(num,[start,end,freeze])) and 0<start<end<=freeze and 1<=len(intervals)<=3,'Invalid observation window')
    flush=g.get('flush')
    check(type(flush) is dict and flush.get('ack') is True and
          all(num(flush.get(k)) for k in ('requested','checked')) and
          end<=flush['requested']<=freeze<=flush['checked'], 'No matching post-Home durable flush bracket')
    boundaries=[start]
    for pair in intervals:
        check(isinstance(pair,list) and len(pair)==2 and all(map(num,pair)) and boundaries[-1]<=pair[0]<pair[1]<=end,'Invalid gesture ordering');boundaries+=pair
    drags=r['drags']
    check(len(drags)==len(intervals) and all(num(t) and a<=t<=b for (a,b),t in zip(intervals,drags)),
          'Missing contemporaneous app vertical-gesture receipt')
    check(movement(g['before'],g['after']),'No native viewport advance')
    events=r['events'];check(isinstance(events,list) and len(events)<=384,'Truncated receipt');prev=None; previousT=0
    qualifying=[]; retained=[];within={'binary':0,'filter':0}
    for i,event in enumerate(events,1):
        outer=strictset(event['outer']);add=strictset(event['added']);remove=strictset(event['removed'])
        check(event['i']==i and num(event['t']) and previousT<=event['t']<=freeze and outer<=set(ids),'Malformed order/visible set')
        previousT=event['t']
        check(add==(outer-prev if prev is not None else set()) and remove==(prev-outer if prev is not None else set()),'Row lifecycle delta mismatch')
        expected=outer|{'w80-shared','w80-leaf'} if outer else set()
        check(strictset(event['oracle'])==strictset(event['input'])==strictset(event['stored'])==expected,
              'Receiver/owner/old filter differ from the independent nested fixture truth')
        path=event['branch'];check(path==('binary' if 1<=len(outer)<=8 else 'filter'),'Wrong/unobserved actual branch')
        if any(a<=event['t']<=b for a,b in intervals):
            within[path]+=1
            # Only count observed changes vs the preceding real event, not a startup entry or duplicate callback.
            if path=='binary' and prev is not None and (add or remove):
                qualifying.append(i)
                if remove and outer&prev:retained.append(i)
        prev=outer
    return {'status':'EXERCISED_SYNTHETIC' if qualifying else 'UNEXERCISED',
            'observedChangesInBinaryBranch':qualifying,'retainedSharedReferenceAfterRemoval':retained,
            'withinGestureCounts':within,'warmPages':10,'realDrags':len(intervals),
            'scope':'Instrumented simulator/local timeline-owner request only. No socket, frame, latency or physical-device claim.'}
