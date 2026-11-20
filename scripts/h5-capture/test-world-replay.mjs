import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ORIGIN, SOURCE, ROUTE, EXPECTED, SHA, ASSET_LOCK_SHA, HTML_SHA, FIXTURE_SHA, MEDIA_SOURCE_SHA, BROWSER_INPUT_SHA,
  digest, cacheName, pinnedRead, checkLock, verifyMatrix, preprocess,responseFor,readAsset,
} from './world-replay.mjs';
import {downloadPinned} from './mirror-world-static.mjs';
const lockPath=fileURLToPath(new URL('./world-build-lock-c83.json',import.meta.url));
const lock=JSON.parse(await pinnedRead(lockPath,ASSET_LOCK_SHA));
const matrix={...EXPECTED,osVersion:'26.1',runtime:'com.apple.CoreSimulator.SimRuntime.iOS-26-1'};
const fixture={user:{id:'syntheticpeer',avatarUrl:'https://timeline-fixture.invalid/avatar.png'},
  posts:[
    {id:'at4tltest0025',text:'Exact fixture header',files:[]},
    {id:'at4tltest0024',text:'GIF',files:[{url:'https://timeline-fixture.invalid/loop.gif'}]},
    {id:'at4tltest0023',text:'Sensitive',files:[{url:'https://timeline-fixture.invalid/badge.png'}]},
  ],emojis:[],announcements:[]};
const pureBundle=preprocess('<head></head><script type="application/json" id="misskey_meta">{"uri":"https://bolubo.com/","policies":{}}</script>',fixture,
  'static let avatar = Data(base64Encoded: "aGVsbG8=")!; static let looping = Data(base64Encoded: "R0lG")!; static let still = Data(base64Encoded: "UE5H")!;');
const ask = (method,path,body={})=>responseFor({url:path.startsWith('https:')?path:ORIGIN+path,method,body},pureBundle,new Map());

test('current public build lock and allowlisted static paths',()=>{
  checkLock(lock);
  assert.equal(lock.publicOrigin,SOURCE);
  assert.equal(lock.iosSourceSHA,SHA);
  assert.equal(lock.htmlSHA256,HTML_SHA);
  assert.equal(Object.keys(lock.assets).length,118);
  assert.throws(()=>checkLock({...lock,assets:{...lock.assets,'/api/notes/create':'a'.repeat(64)}}),/Wrong build lock/);
});
test('exact eligible screenshot geometries, no old-model fallback',()=>{
  assert.deepEqual(verifyMatrix(matrix).map(([k,s])=>[k,s.width,s.height]),[['small',402,874],['large',440,956]]);
  assert.throws(()=>verifyMatrix({...matrix,small:{...matrix.small,width:375,height:667}}),/matrix/);
  assert.throws(()=>verifyMatrix({...matrix,osVersion:'26.0'}),/matrix/);
});
test('same synthetic fixture ordering and exact bounded cursor',()=>{
  assert.deepEqual(ask('POST',ROUTE,{limit:2}).timeline.ids,['at4tltest0025','at4tltest0024']);
  assert.deepEqual(ask('POST',ROUTE,{limit:2,untilId:'at4tltest0025'}).timeline.ids,['at4tltest0024','at4tltest0023']);
  assert.equal(ask('POST',ROUTE,{limit:0}).status,400);
  assert.equal(ask('POST',ROUTE,{sinceId:'at4tltest0025'}).status,400);
  assert.equal(ask('POST','/api/notes/home-timeline').status,405);
});
test('write routes, external API, encoded traversal and unknown static never forward',()=>{
  for (const path of ['/api/notes/create','/api/drive/files/create','/api/i/update','/api/notes/delete'])
    assert.equal(ask('POST',path).status,405);
  assert.equal(ask('POST','https://bolubo.com/api/notes/create').denied,'EXTERNAL_ORIGIN');
  assert.equal(ask('GET','https://bolubo.com/').status,403);
  assert.equal(ask('GET','/vite/%2fnope.js').status,403);
  assert.equal(ask('GET','/vite/unknown.js').denied,'STATIC_PATH_UNATTESTED');
  assert.equal(ask('GET','/vite/unknown.js?unattested=yes').denied,'STATIC_QUERY_UNATTESTED');
  assert.equal(ask('GET','/compose').status,404);
  assert.equal(ask('POST','/api/i/registry/set').status,204);
});
test('native fixture media, instead of placeholder PNG',()=>{
  assert.deepEqual(ask('GET','/fixture/avatar.png').body,Buffer.from('hello'));
  assert.deepEqual(ask('GET','/fixture/loop.gif').body,Buffer.from('GIF'));
  assert.deepEqual(ask('GET','/fixture/badge.png').body,Buffer.from('PNG'));
  assert.equal(ask('GET','/fixture/poster-red.mp4').status,404);
  assert.equal(JSON.parse(ask('POST','/api/i').body).token,'synthetic-local-only');
});
test('file digest gate rejects bytes changed after archive',async()=>{
  const p=await mkdtemp(join(tmpdir(),'pubo-world-replay-'));
  const path='/vite/assets/exact.js',foo=Buffer.from('const ready=true');
  await writeFile(join(p,cacheName(path)),foo);
  const only={assets:{[path]:digest(foo)}};
  assert.deepEqual(await readAsset(p,path,only),foo);
  await writeFile(join(p,cacheName(path)),Buffer.from('wrong'));
  await assert.rejects(readAsset(p,path,only),/hash mismatch/);
  await assert.rejects(readAsset(p,path+'/unattested',only),/Unattested/);
});
test('checked-out C83 baseline fixture, browser manifests and native media match receipts',async()=>{
  if(!process.env.WORLD_VERIFIED_SOURCE) throw Error('need WORLD_VERIFIED_SOURCE');
  const p=process.env.WORLD_VERIFIED_SOURCE;
  const f=await pinnedRead(join(p,'App/Resources/TimelineParity.json'),FIXTURE_SHA);
  const m=await pinnedRead(join(p,'App/Infrastructure/GIFTestFixtures.swift'),MEDIA_SOURCE_SHA);
  for(const [r,sha] of Object.entries(BROWSER_INPUT_SHA)) await pinnedRead(join(p,r),sha);
  verifyMatrix(JSON.parse(await readFile(join(p,'scripts/iphone-qa-matrix.json'))));
  const b=preprocess('<head></head><script type="application/json" id="misskey_meta">{"policies":{}}</script>',JSON.parse(f),m.toString());
  assert.equal(b.fixture.posts[0].id,'at4tltest0025');
  for(const [k,v] of Object.entries(b.media)) assert.equal(digest(v),lock.nativeMedia[k]);
});

test('public static mirror is exact GET only; no cookies, credentials, query, user or extra destination',async()=>{
  const path='/vite/assets/locked.js', bytes='immutable reference fixture', sha=digest(bytes);
  const testLock={assets:{[path]:sha}};
  const ok=async (dest,opts)=>{
    assert.equal(dest.href,'https://bolubo.com'+path);
    assert.equal(opts.method,'GET');assert.equal(opts.credentials,'omit');
    assert.equal(opts.redirect,'manual');assert.equal(opts.cache,'no-store');
    assert.deepEqual(Object.keys(opts.headers),['user-agent']);
    const r=new Response(bytes);Object.defineProperty(r,'url',{value:dest.href});return r;
  };
  assert.equal((await downloadPinned(path,sha,testLock,ok)).toString(),bytes);
  for(const bad of ['/api/i','/vite/assets/./locked.js','/vite/assets/locked.js?test=1',
    '//api.bolubo.com/vite/assets/locked.js','https://third.invalid/file']) {
    await assert.rejects(downloadPinned(bad,sha,testLock,()=>assert.fail('Must not fetch unpinned target')),/Unattested/);
  }
  await assert.rejects(downloadPinned(path,'0'.repeat(64),testLock,()=>assert.fail('Must not fetch wrong expected hash')),/Unattested/);
});

test('public static mirror rejects redirect, changed bytes, unbounded content, and rewritten response URL',async()=>{
  const path='/vite/assets/locked.js', bytes='immutable reference fixture', sha=digest(bytes);
  const testLock={assets:{[path]:sha}};
  const reply=(body,opts={},url=SOURCE.slice(0,-1)+path)=>{
    const r=new Response(body,opts);Object.defineProperty(r,'url',{value:url});return r;
  };
  let calls=0;
  await assert.rejects(downloadPinned(path,sha,testLock,async()=>{
    calls++;
    return reply('',{status:302,headers:{location:'https://unknown.invalid/'}});
  }),/redirect refused/);
  assert.equal(calls,1);
  await assert.rejects(downloadPinned(path,sha,testLock,()=>reply(bytes,{},'https://mirror.invalid'+path)),/retrieval failed/);
  await assert.rejects(downloadPinned(path,sha,testLock,()=>reply('new deployment')),/build drift/);
  await assert.rejects(downloadPinned(path,sha,testLock,()=>reply('',{headers:{'content-length':'12582913'}})),/static size/);
  await assert.rejects(downloadPinned(path,sha,testLock,()=>reply(new Uint8Array(12582913))),/static size/);
});

test('capture registers deny-by-default routes, no continuation even when a network mock is provided',async()=>{
  const {installReplayRoutes}=await import('./world-replay.mjs');
  const callbacks={};
  const context={routeWebSocket:async (glob,f)=>{assert.equal(glob,'**/*');callbacks.ws=f;},
                 route:async (glob,f)=>{assert.equal(glob,'**/*');callbacks.route=f;}};
  const observed={deniedRequests:[],assets:{},timeline:[]};
  await installReplayRoutes(context,pureBundle,lock,'unused-cache',new Map(),observed);
  let closed=false;callbacks.ws({close:()=>{closed=true;}});assert(closed);
  const send=async (method,url,body={})=>{
    let result=null;
    await callbacks.route({request:()=>({url:()=>url,method:()=>method,postDataJSON:()=>body}),
      fulfill:async value=>{result=value;},abort:async()=>{result='aborted';},
      continue:async()=>{assert.fail('Forbidden network forwarding');}});
    return result;
  };
  assert.equal(await send('GET','https://bolubo.com/vite/example.js'),'aborted');
  assert.equal((await send('POST',ORIGIN+'/api/notes/create')).status,405);
  assert.equal((await send('GET',ORIGIN+'/')).status,200);
  assert.equal((await send('GET',ORIGIN+'/vite/assets/lazy-world-unattested.js')).status,404);
  assert(observed.deniedRequests.some(x=>x.reason==='STATIC_PATH_UNATTESTED'));
  assert.equal((await send('POST',ORIGIN+ROUTE,{limit:2})).status,200);
  assert.deepEqual(observed.timeline[0].ids,['at4tltest0025','at4tltest0024']);
});

test('Chromium smoke: route-only isolated fixture, no request reaches second origin',
  {skip:process.env.WORLD_CHROMIUM_SMOKE!=='1'},async()=>{
  const {createRequire}=await import('node:module');
  const {createServer}=await import('node:http');
  const require=createRequire(join(process.env.WORLD_VERIFIED_SOURCE,'scripts/h5-capture/package.json'));
  const {chromium}=require('playwright');
  assert.equal(require('playwright/package.json').version,'1.56.1');
  const {installReplayRoutes}=await import('./world-replay.mjs');
  const b=await chromium.launch({headless:true,
    args:['--disable-background-networking','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1']});
  let outsideConnections=0;
  const sentinel=createServer((_q,r)=>{outsideConnections++;r.end('must not be reached');});
  await new Promise((ok,bad)=>{sentinel.once('error',bad);sentinel.listen(0,'127.0.0.1',ok);});
  try {
    const c=await b.newContext({serviceWorkers:'block'});
    const observed={deniedRequests:[],assets:{},timeline:[]};
    await installReplayRoutes(c,{...pureBundle,html:'<!doctype html><title>Synthetic transport smoke only</title>'},
      lock,'unused-cache',new Map(),observed);
    const p=await c.newPage();
    await p.goto(ORIGIN+'/');
    assert.equal(await p.title(),'Synthetic transport smoke only');
    const result=await p.evaluate(async route=>{
      const q={method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({limit:2})};
      const timeline=await fetch(route,q);
      return {returned:(await timeline.json()).map(x=>x.id),writeStatus:(await fetch('/api/notes/create',q)).status};
    },ROUTE);
    assert.equal(result.writeStatus,405);
    assert.deepEqual(result.returned,['at4tltest0025','at4tltest0024']);
    await assert.rejects(p.goto('http://127.0.0.1:'+sentinel.address().port+'/sentinel'));
    assert.equal(outsideConnections,0);
    assert(observed.deniedRequests.some(x=>x.reason==='EXTERNAL_ORIGIN'));
  } finally {await b.close();await new Promise(ok=>sentinel.close(ok));}
});
