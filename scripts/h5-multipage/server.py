import os,sys,time,base64
import http.server,pathlib,urllib.request,urllib.parse,json,re,hashlib,threading,mimetypes
ROOT=pathlib.Path(__file__).resolve().parent; CACHE=ROOT/'cache';CACHE.mkdir(exist_ok=True)
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):raise ValueError('Redirect forbidden')
FETCH=urllib.request.build_opener(NoRedirect())
PORT=int(os.environ.get('PORT','8765')); ORIGIN=f'http://127.0.0.1:{PORT}'
FIXTURE=pathlib.Path(os.environ.get('FIXTURE_PATH','../../App/Resources/TimelineParity.json')).resolve()
HTML=pathlib.Path(os.environ.get('H5_HTML',str(ROOT/'public-home.html')))
if not HTML.exists():
 with FETCH.open('https://bolubo.com/',timeout=30) as r: HTML.write_bytes(r.read())
fixture=json.loads(FIXTURE.read_text()); html=HTML.read_text()
(ROOT/'requests.log').write_text('')
assets=[]
meta=json.loads(re.search(r'<script type="application/json" id="misskey_meta"[^>]*>(.*?)</script>',html,re.S).group(1));meta['uri']=ORIGIN;meta['mediaProxy']=ORIGIN+'/proxy';meta['maintainerEmail']='fixture@example.invalid';meta['maintainerName']='Synthetic'
me=dict(fixture['user']);me.update(id='syntheticself',username='fixture',name='测试用户',token='synthetic-local-only',host=None,isAdmin=False,isModerator=False,isLocked=False,isExplorable=True,isSuspended=False,isDeleted=False,createdAt='2026-11-01T00:00:00Z',updatedAt=None,description='',location=None,birthday=None,fields=[],roles=[],pinnedNotes=[],pinnedNoteIds=[],followingCount=1,followersCount=1,notesCount=25,unreadNotificationsCount=0,hasUnreadNotification=False,hasUnreadMessagingMessage=False,hasUnreadAnnouncement=False,unreadAnnouncements=[],hasPendingReceivedFollowRequest=False,hasUnreadAntenna=False,hasUnreadChannel=False,policies=meta['policies'],notificationRecieveConfig={},injectFeaturedNote=False,emojis={},avatarDecorations=[],twoFactorEnabled=False,securityKeys=False)
me.update(location='Tokyo (synthetic)',birthday='2000-02-29',autoAcceptFollowed=True,noCrawle=False,preventAiLearning=True,hideOnlineStatus=False,publicReactions=False,followingVisibility='public',followersVisibility='public',chatScope='everyone',lang='zh-CN',followedMessage='',avatarUrl=ORIGIN+'/fixture/avatar.png',bannerUrl=None)
# Paths only. The fixture never forwards API, authorization headers, cookies, or writes.
def patch(v):
 if isinstance(v,str):return v.replace('https://timeline-fixture.invalid/',ORIGIN+'/fixture/').replace('https://bolubo.com',ORIGIN)
 if isinstance(v,list):return [patch(x) for x in v]
 if isinstance(v,dict):return {k:patch(x) for k,x in v.items()}
 return v
fixture=patch(fixture);me=patch(me)
setup='''<script>localStorage.setItem('account',JSON.stringify(%s));localStorage.setItem('lang','zh-CN');localStorage.setItem('lastVersion','2026.9.0');localStorage.setItem('puboDefaultLanguageVersion','1');localStorage.setItem('neverShowDonationInfo','true');localStorage.setItem('hidePreferencesRestoreSuggestion','true');window.WebSocket=class extends EventTarget{static CONNECTING=0;static OPEN=1;static CLOSING=2;static CLOSED=3;constructor(){super();this.readyState=0;setTimeout(()=>{this.readyState=1;const e=new Event('open');this.dispatchEvent(e);this.onopen?.(e)},10)}send(){}close(){this.readyState=3;this.dispatchEvent(new Event('close'))}};</script>'''%json.dumps(me,ensure_ascii=False)
html=re.sub(r'(<script type="application/json" id="misskey_meta"[^>]*>).*?(</script>)',lambda m:m[1]+json.dumps(meta,ensure_ascii=False)+m[2],html,flags=re.S).replace('<head>','<head>'+setup,1).replace('https://bolubo.com',ORIGIN)
class H(http.server.BaseHTTPRequestHandler):
 def out(self,data,typ='application/json',status=200):
  if not isinstance(data,bytes):data=data.encode()
  self.send_response(status);self.send_header('Content-Type',typ);self.send_header('Content-Length',str(len(data)));self.send_header('Content-Security-Policy',"connect-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; frame-src 'self'; form-action 'none'");self.end_headers();self.wfile.write(data)
 def do_POST(self):
  p=urllib.parse.urlparse(self.path).path; body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))) or '{}'); result=[]
  with open(ROOT/'requests.log','a') as f:f.write(p+'\n')
  if p=='/api/i':result=me
  elif p=='/api/meta':result=meta
  elif p=='/api/emojis':result={'emojis':fixture['emojis']}
  elif p=='/api/announcements':result=fixture['announcements']
  elif p in ['/api/notes/local-timeline','/api/notes/home-timeline','/api/notes/hybrid-timeline','/api/notes/global-timeline']:
   result=[x for x in fixture['posts'] if not body.get('untilId') or x['id']<body['untilId']][:body.get('limit',20)]
  elif p=='/api/chat/unread-summary':result={'notificationUnreadCount':0,'hasNotificationLegacyUnread':False,'hasUnreadRoom':False,'unreadCount':0,'hasUnread':False,'unreadChatCount':0,'unreadMessageCount':0,'unreadRoomCount':0}
  elif p=='/api/i/registry/get-all':result={}
  elif p=='/api/users/show':result=me if body.get('userId')=='syntheticself' else fixture['user']
  elif p=='/api/notes/show':result=next((x for x in fixture['posts'] if x['id']==body.get('noteId')),fixture['posts'][0])
  elif p in ['/api/channels/featured','/api/channels/search','/api/channels/followed','/api/channels/my-favorites','/api/channels/owned']:
   result=[{'id':'syntheticchannel','name':'音乐交流（测试频道）','description':'仅供界面对照的合成数据，不是真实频道。','createdAt':'2026-11-01T00:00:00Z','lastNotedAt':'2026-11-01T00:00:00Z','hasUnreadNote':False,'isArchived':False,'isSensitive':False,'bannerUrl':None,'usersCount':12,'notesCount':24,'userId':'syntheticself','isFollowing':False,'isFavorited':False,'allowRenoteToExternal':True}]
  elif p in ['/api/drive/files','/api/drive/folders']:result=[]
  elif p=='/api/drive':result={'capacity':104857600,'usage':0}
  elif p=='/api/i/avatar-decorations':result=[]
  elif p=='/api/music-charts/kpop-summary':
   c={'chartKey':'melon-top100','provider':'melon','label':'Melon TOP100','status':'available','rankBasis':'official_rank','coverage':'complete','sourceUrl':'https://www.melon.com/chart/index.htm','observedAt':'2026-11-01T15:00:00Z','lastSuccessAt':'2026-11-01T15:00:00Z'}
   result={'selected':c,'chart':c,'charts':[c],'entries':[{'songId':'fixturesong','title':'NEON','artists':[{'name':'A2O LITE'}],'rank':2,'bestRank7d':1,'previousRank':1,'change':-1,'groupIds':['a2o-lite'],'sourceMovement':{'type':'same'}}],'total':1,'hasMore':False}
  elif p=='/api/i/registry/get':result={'error':{'code':'NO_SUCH_KEY','id':'notfound'}};return self.out(json.dumps(result),status=404)
  elif p in ['/api/i/claim-achievement','/api/i/registry/set','/api/i/read-announcement']:return self.out(b'',status=204)
  elif p in ['/api/i/read-all-unread-notes','/api/i/read-all-unread-notifications']:return self.out(b'',status=204)
  else:return self.out(json.dumps({'error':{'code':'FIXTURE_UNIMPLEMENTED','path':p}}),status=501)
  self.out(json.dumps(result,ensure_ascii=False))
 def do_GET(self):
  p=urllib.parse.urlparse(self.path).path
  if '..' in urllib.parse.unquote(p).split('/') or '\\' in p:return self.out('Invalid path','text/plain',400)
  if p=='/__health':return self.out(json.dumps({'ready':True,'fixtureSha256':hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),'htmlSha256':hashlib.sha256(HTML.read_bytes()).hexdigest(),'source':'https://bolubo.com/','assets':assets}))
  if p=='/capture':return self.out('<!doctype html><style>body{margin:0;background:#ddd}iframe{border:0;width:375px;height:667px;display:block}</style><iframe src="/"></iframe>','text/html')
  if p.startswith('/fixture/'):
   # Match iOS synthetic 1x1 image fixture; never fetch arbitrary image hosts.
   import base64
   return self.out(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='),'image/png')
  if p=='/url':return self.out(json.dumps({'title':'下载 PUBO Android 版','description':'PUBO 官方下载页面','sitename':'bolubo.com','url':ORIGIN+'/download/android','icon':None,'thumbnail':None}))
  if p.startswith(('/vite/','/assets/','/static-assets/','/twemoji/','/fluent-emoji/')) or p in ['/favicon.ico','/apple-touch-icon.png','/manifest.json']:
   key=CACHE/hashlib.sha256(p.encode()).hexdigest()
   try:
    if not key.exists():
     req=urllib.request.Request('https://bolubo.com'+p,headers={'User-Agent':'PUBO isolated visual reference'})
     with FETCH.open(req,timeout=30) as r:
      if urllib.parse.urlparse(r.url).netloc!='bolubo.com':raise ValueError('Cross-origin static redirect forbidden')
      data=r.read()
     key.write_bytes(data)
    data=key.read_bytes();assets.append({'path':p,'sha256':hashlib.sha256(data).hexdigest()});typ=mimetypes.guess_type(p)[0] or 'application/octet-stream'
    if p.endswith('.js'):typ='application/javascript'
    return self.out(data,typ)
   except Exception as e:return self.out(str(e),'text/plain',502)
  if p=='/streaming':return self.out('{}',status=404)
  if p=='/api/emojis':return self.out(json.dumps({'emojis':fixture['emojis']},ensure_ascii=False))
  if p.startswith('/api/'):return self.out('{}',status=405)
  if p in ['/', '/channels', '/my/drive', '/settings/profile', '/settings/privacy']:return self.out(html,'text/html')
  return self.out('Unknown fixture route','text/plain',404)
 def log_message(self,*args):pass
http.server.ThreadingHTTPServer(('127.0.0.1',PORT),H).serve_forever()
