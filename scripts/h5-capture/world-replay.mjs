/** Pure, offline World-feed reference. Nothing in this module opens a socket. */
import { createHash } from 'node:crypto';
import { readFile, lstat } from 'node:fs/promises';
import { join } from 'node:path';

export const ORIGIN = 'http://127.0.0.1:8765';
export const SOURCE = 'https://bolubo.com/';
export const ROUTE = '/api/notes/local-timeline';
export const SHA = '414c972c73e55903cd4ddecd542218f148f3d6cd';
export const HTML_SHA = 'fd1063e595a4d19127596ef3648eeb2dfd17952e736ea750e2b0a49ee557091c';
export const FIXTURE_SHA = '709410cf5618e60986c9703df8d61ea9c68e4d4b103895fb68f13b9a5d78060b';
export const MEDIA_SOURCE_SHA = 'b259efa210b460d77b462c6754532b402bfa9a6975241d487db3bee444b85bd2';
export const ASSET_LOCK_SHA = '5d834f79187a9aaec245f8aa0a0a1408b1602bda37dccce994555b723f6be41f';
export const BROWSER_INPUT_SHA = {
  'scripts/iphone-qa-matrix.json': '0bac3617ad4f0b3599da0a277d9f14d971e591e4f37035220af03c934b9ef6b6',
  'scripts/h5-capture/package.json': '4be8a3cc628d007b118181518fb62a61d969b9ec48ff0bcc8942a1e36150df3e',
  'scripts/h5-capture/package-lock.json': '54fea327cd1455146f0620a8e80585a0cd5ffef9c502f85256dd5a0da143b96f',
};
export const EXPECTED = {
  small: {model:'iPhone 17', deviceTypeIdentifier:'com.apple.CoreSimulator.SimDeviceType.iPhone-17',width:402,height:874},
  large: {model:'iPhone 17 Pro Max', deviceTypeIdentifier:'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max',width:440,height:956},
};
export const digest = b => createHash('sha256').update(b).digest('hex');
export const cacheName = path => digest(path);
const contentTypes = {'.js':'application/javascript', '.css':'text/css', '.png':'image/png',
  '.gif':'image/gif', '.svg':'image/svg+xml', '.ico':'image/x-icon', '.json':'application/json',
  '.woff':'font/woff', '.woff2':'font/woff2', '.webp':'image/webp'};
const json = (value, status=200) => ({status,contentType:'application/json',body:JSON.stringify(value)});
const denied = (status, why) => ({...json({error:{code:why}},status), denied:why});
const staticPath = path => /^\/(?:vite|assets|static-assets|twemoji|fluent-emoji)\/[a-zA-Z0-9_./~-]+$/.test(path) ||
    ['/favicon.ico','/apple-touch-icon.png','/manifest.json'].includes(path);
const canonicalStaticPath = path => typeof path==='string' && staticPath(path) &&
  !path.includes('//') && !path.includes('..') && !path.split('/').slice(1).some(x=>!x || x==='.');

export function verifyMatrix(matrix) {
  if (matrix?.osVersion !== '26.1' || matrix.runtime !== 'com.apple.CoreSimulator.SimRuntime.iOS-26-1' ||
      Object.entries(EXPECTED).some(([size, expected]) =>
        Object.entries(expected).some(([k,v]) => matrix?.[size]?.[k] !== v))) {
    throw new Error('Unexpected simulator matrix');
  }
  return Object.entries(EXPECTED);
}
export async function pinnedRead(path, sha, max=12*1024*1024) {
  const stat = await lstat(path);
  if (!stat.isFile() || stat.size < 1 || stat.size > max) throw new Error('Invalid reference file: '+path);
  const data = await readFile(path);
  if (digest(data) !== sha) throw new Error('Reference hash mismatch: '+path);
  return data;
}
export function checkLock(lock) {
  if (lock?.publicOrigin !== SOURCE || lock.iosSourceSHA !== SHA || lock.htmlSHA256 !== HTML_SHA ||
      lock.fixtureSHA256 !== FIXTURE_SHA || lock.mediaSourceSHA256 !== MEDIA_SOURCE_SHA ||
      !lock.assets || Object.keys(lock.assets).length !== 118) throw new Error('Wrong build lock');
  for (const [path, sha] of Object.entries(lock.assets)) {
    if (!canonicalStaticPath(path) || !/^[a-f0-9]{64}$/.test(sha)) throw new Error('Unsafe build lock path');
  }
}
export function assertPinnedAssetRequest(path,sha,lock) {
  if(path==='/' && sha===HTML_SHA) return;
  if(!canonicalStaticPath(path) || !Object.hasOwn(lock.assets,path) || lock.assets[path]!==sha ||
      !/^[a-f0-9]{64}$/.test(sha)) throw Error('Unattested static path/hash: '+path);
}
function rewrite(value) {
  if (typeof value === 'string') return value.replaceAll('https://timeline-fixture.invalid/',ORIGIN+'/fixture/').replaceAll('https://bolubo.com',ORIGIN);
  if (Array.isArray(value)) return value.map(rewrite);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,rewrite(v)]));
  return value;
}
export function preprocess(html, fixture, mediaSource) {
  const metaPattern = /(<script type="application\/json" id="misskey_meta"[^>]*>)([\s\S]*?)(<\/script>)/;
  const target = metaPattern.exec(html);
  if (!target || !html.includes('<head>')) throw new Error('Unrecognized original H5 bootstrap');
  const meta = {...JSON.parse(target[2]),uri:ORIGIN,mediaProxy:ORIGIN+'/proxy',
                maintainerEmail:'fixture@example.invalid',maintainerName:'Synthetic'};
  const me = rewrite({...fixture.user,id:'syntheticself',username:'fixture',name:'测试用户',
    token:'synthetic-local-only',host:null,isAdmin:false,isModerator:false,isLocked:false,isExplorable:true,
    isSuspended:false,isDeleted:false,createdAt:'2026-11-01T00:00:00Z',updatedAt:null,description:'',
    location:null,birthday:null,fields:[],roles:[],pinnedNotes:[],pinnedNoteIds:[],followingCount:1,
    followersCount:1,notesCount:25,unreadNotificationsCount:0,hasUnreadNotification:false,
    hasUnreadMessagingMessage:false,hasUnreadAnnouncement:false,unreadAnnouncements:[],
    hasPendingReceivedFollowRequest:false,hasUnreadAntenna:false,hasUnreadChannel:false,
    policies:meta.policies,notificationRecieveConfig:{},injectFeaturedNote:false,emojis:{},
    avatarDecorations:[],twoFactorEnabled:false,securityKeys:false});
  const media = {};
  for (const key of ['avatar','still','looping']) {
    const m = new RegExp('static let '+key+' = Data\\(base64Encoded: "([A-Za-z0-9+/=]+)"').exec(mediaSource);
    if (!m) throw new Error('Missing pinned native media '+key);
    media[key] = Buffer.from(m[1],'base64');
  }
  const servedHTML = html.replace(metaPattern, (_whole, open, _old, close)=>open+
    JSON.stringify(meta).replaceAll('<','\\u003c')+close).replaceAll('https://bolubo.com',ORIGIN);
  return {html:servedHTML, meta, me, fixture:rewrite(fixture), media};
}

export function responseFor(req, bundle, assets) {
  const url = new URL(req.url);
  if (url.origin !== ORIGIN || url.username || url.password) return denied(403,'EXTERNAL_ORIGIN');
  const path = url.pathname;
  if (path.includes('%') || path.includes('..') || path.includes('//') || path.includes('\\')) return denied(403,'UNSAFE_PATH');
  const {html,meta,me,fixture,media}=bundle;
  if (req.method==='GET') {
    if (path==='/' && !url.search) return {status:200,contentType:'text/html; charset=utf-8',body:html};
    if (path==='/fixture/avatar.png') return {status:200,contentType:'image/png',body:media.avatar,fixtureMedia:path};
    if (path==='/fixture/badge.png' || path==='/fixture/image.png') return {status:200,contentType:'image/png',body:media.still,fixtureMedia:path};
    if (path==='/fixture/loop.gif') return {status:200,contentType:'image/gif',body:media.looping,fixtureMedia:path};
    if (path==='/url') return json({title:'下载 PUBO Android 版',description:'PUBO 官方下载页面',
      sitename:'bolubo.com',url:ORIGIN+'/download/android',icon:null,thumbnail:null});
    if (path==='/api/emojis') return json({emojis:fixture.emojis});
    if (staticPath(path) && url.search) return denied(404,'STATIC_QUERY_UNATTESTED');
    if (staticPath(path) && assets.has(path)) {
      const extension=path.slice(path.lastIndexOf('.'));
      return {status:200,contentType:contentTypes[extension]||'application/octet-stream',body:assets.get(path),asset:path};
    }
    return denied(404,staticPath(path)?'STATIC_PATH_UNATTESTED':'UNPINNED_PATH');
  }
  if (req.method!=='POST' || url.search) return denied(405,'UNSUPPORTED_METHOD');
  const body = req.body;
  if (!body || typeof body!=='object' || Array.isArray(body)) return denied(400,'INVALID_FIXTURE_BODY');
  if (path===ROUTE) {
    // Publish only the same synthetic bundle and the actual requested cursor slice.
    // Fail on an invalid cursor/limit instead of broadening what a pair represents.
    const limit=body.limit ?? 20;
    if (!Number.isInteger(limit) || limit<1 || limit>100 ||
        (body.untilId!=null && !/^at4tltest\d{4}$/.test(body.untilId)) ||
        body.sinceId!=null) return denied(400,'UNSUPPORTED_TIMELINE_QUERY');
    const rows = fixture.posts.filter(x=>!body.untilId||x.id<body.untilId).slice(0,limit);
    return {...json(rows), timeline:{path,limit,untilId:body.untilId ?? null,ids:rows.map(row=>row.id)}};
  }
  switch (path) {
    case '/api/i': return json(me);
    case '/api/meta': return json(meta);
    case '/api/emojis': return json({emojis:fixture.emojis});
    case '/api/announcements': return json(fixture.announcements);
    case '/api/chat/unread-summary': return json({notificationUnreadCount:0,hasNotificationLegacyUnread:false,hasUnreadRoom:false,unreadCount:0,hasUnread:false,unreadChatCount:0,unreadMessageCount:0});
    case '/api/i/registry/get-all': return json({});
    case '/api/i/registry/get': return json({error:{code:'NO_SUCH_KEY',id:'notfound'}},404);
    case '/api/users/show': return json(body.userId==='syntheticself'?me:fixture.user);
    case '/api/notes/show': return fixture.posts.some(x=>x.id===body.noteId) ?
      json(fixture.posts.find(x=>x.id===body.noteId)) : denied(404,'UNKNOWN_FIXTURE_NOTE');
    case '/api/music-charts/kpop-summary': {
      const chart={chartKey:'melon-top100',provider:'melon',label:'Melon TOP100',region:'KR',
        rankBasis:'official_rank',status:'available',observedAt:'2026-11-01T15:00:00Z'};
      return json({selected:chart,chart,charts:[chart],
        entries:[{songId:'fixturesong',title:'NEON',artists:[{name:'A2O LITE'}],
                  rank:2,bestRank7d:2,previousRank:1,change:-1,sourceMovement:{kind:'down',amount:1}}],
        total:1,hasMore:false});
    }
    // The actual H5 frontend emits these on first boot. A stateless local 204
    // never forwards them or writes a preference/account. No send/upload stubs.
    case '/api/i/claim-achievement':
    case '/api/i/registry/set':
    case '/api/i/read-announcement': return {status:204,body:''};
    default: return denied(405,'FIXTURE_ONLY_NO_WRITE_OR_UNKNOWN_API');
  }
}
export async function readAsset(cache, path, lock) {
  if (!Object.hasOwn(lock.assets,path)) throw new Error('Unattested static path: '+path);
  return pinnedRead(join(cache,cacheName(path)), lock.assets[path]);
}


// Playwright route closure is shared by visual capture and the local transport smoke test.
// No route.continue(), fetch(), listener, redirects or remote fallback.
export async function installReplayRoutes(context,bundle,lock,cacheDir,cached,c) {
  const csp="connect-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; frame-src 'none'; form-action 'none'; object-src 'none'";
  await context.routeWebSocket('**/*', ws=>ws.close());
  await context.route('**/*',async route=>{
    const r=route.request(), u=new URL(r.url());
    try {
      if(u.origin!==ORIGIN) {
        c.deniedRequests.push({origin:u.origin,path:u.pathname,reason:'EXTERNAL_ORIGIN'});
        return await route.abort();
      }
      if(r.method()==='GET' && !u.search && Object.hasOwn(lock.assets,u.pathname) && !cached.has(u.pathname)) {
        try {cached.set(u.pathname,await readAsset(cacheDir,u.pathname,lock));}
        catch(error) {
          c.deniedRequests.push({origin:u.origin,path:u.pathname,reason:'STATIC_BYTES_UNVERIFIED',detail:String(error)});
          return await route.abort();
        }
      }
      let body=null;
      try {body=r.method()==='POST' ? r.postDataJSON() : null;} catch {}
      const answer=responseFor({url:r.url(),method:r.method(),body},bundle,cached);
      if(answer.denied) c.deniedRequests.push({origin:u.origin,path:u.pathname,reason:answer.denied});
      if(answer.timeline) c.timeline.push(answer.timeline);
      if(answer.asset) c.assets[answer.asset]=lock.assets[answer.asset];
      if(answer.fixtureMedia && c.fixtureMedia) c.fixtureMedia[answer.fixtureMedia]=digest(answer.body);
      await route.fulfill({status:answer.status,body:answer.body,
        ...(answer.contentType?{contentType:answer.contentType}:{}),
        headers:{'content-security-policy':csp}});
    } catch(e) {
      c.deniedRequests.push({origin:u.origin,path:u.pathname,reason:String(e)});
      await route.abort().catch(()=>{});
    }
  });
}
