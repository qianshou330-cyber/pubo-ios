import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {SOURCE,SHA,ORIGIN,ROUTE,EXPECTED,digest,cacheName} from './world-replay.mjs';
import {FRESH_SCOPE,allowedPath,seedPaths,readFreshLock,verifyLocalAssetTree,acceptedProbe,canonicalJSON} from './fresh-world-lock.mjs';
import {publicStaticGET,initSnapshot,progressSnapshot} from './acquire-fresh-world-static.mjs';
const marker='sE2FIylr5', candidate='f'.repeat(40);
const entry='/vite/zh-CN/'+marker+'-2--13OMV.js';
const css='/vite/assets/'+marker+'-4RTeR85g.css';
const lazy='/vite/zh-CN/'+marker+'-l8YPdAU1.js';
const root=`<!doctype html><head><script type="application/json" id="misskey_meta">{"policies":{}}</script><script type="module" src="${entry}"></script><link rel="stylesheet" href="${css}"></head>`;
const fixedClock=()=> '2026-11-20T09:30:00.000Z';
const mk=async()=>{const base=await mkdtemp(join(tmpdir(),'pubo-fresh-static-test-'));return {base,dir:join(base,'fresh')};};
function stub({rewrite=(path,count,row)=>row}={}) {
  const hits=[],counts=new Map();
  const responses={
    '/':[root,'text/html'],[entry]:['entry JS','text/javascript'],[css]:['body{color:red}','text/css'],[lazy]:['lazy JS','application/javascript'],
  };
  const transport=async(url,opts)=>{
    assert.equal(url.origin,new URL(SOURCE).origin);assert.equal(url.search,'');assert.equal(url.hash,'');
    assert.equal(opts.method,'GET');assert.equal(opts.credentials,'omit');assert.equal(opts.redirect,'manual');
    assert.equal(opts.cache,'no-store');assert.deepEqual(Object.keys(opts.headers),['user-agent']);
    hits.push(url.pathname);
    counts.set(url.pathname,(counts.get(url.pathname)??0)+1);
    assert.ok(Object.hasOwn(responses,url.pathname), 'unexpected public URL');
    let [body,type,status=200,dest=url.href]=rewrite(url.pathname,counts.get(url.pathname),responses[url.pathname]);
    const r=new Response(body,{status,headers:{'content-type':type}});
    Object.defineProperty(r,'url',{value:dest});return r;
  };
  return {transport,hits,counts};
}
function probe(m,sha,withGap){
  return {candidateCommit:candidate,referenceScope:FRESH_SCOPE,discoveryOnly:true,pairEligible:false,
    networkNamespace:{host:'net:[111]',replay:'net:[222]'},
    status:withGap?'DISCOVERY_REQUIRED':'DISCOVERY_CONVERGED',
    fresh:{manifestSHA256:sha,htmlSHA256:m.htmlSHA256,round:m.round},
    cases:Object.entries(EXPECTED).flatMap(([slot,size])=>['light','dark'].map(theme=>({slot,size,theme,
      passed:!withGap,errors:[],deniedRequests:withGap?[{origin:ORIGIN,path:lazy,reason:'STATIC_PATH_UNATTESTED'}]:[],
      viewport:{width:size.width,height:size.height,dpr:2},
      timeline:[{path:ROUTE,untilId:null,ids:['at4tltest0025']}],assets:m.assets,
    }))),
  };
}
async function save(dir,name,obj){const bytes=canonicalJSON(obj),path=join(dir,name);await writeFile(path,bytes,{flag:'wx'});return [path,digest(bytes)];}

test('bootstrap only known literal Vite family; inconsistent locale marker or API scheme not admitted',()=>{
  assert.deepEqual(seedPaths(root),{marker,refs:[css,entry].sort()});
  assert.throws(()=>seedPaths(root.replace(css,css.replace(marker,'diffPrefix'))),/mixed/);
  for(const p of ['/api/i','/accounts/login','/proxy/x','/vite/assets/../foo.js',entry+'?v=1',entry+'%23',
     'https://bolubo.com'+entry,'//bolubo.com'+entry,entry.replace(marker,'diffPrefix'),'/favicon.ico/']) assert.equal(allowedPath(p,marker),false,p);
  assert.equal(allowedPath('/api/i',undefined),false);
  assert.equal(allowedPath(lazy,marker),true);
});

test('positive mock: fresh bootstrap, exact offline gap, separate sealed manifest and body replay',async()=>{
  const {base,dir}=await mk(), {transport,hits,counts}=stub();
  const one=await initSnapshot(dir,candidate,{transport,clock:fixedClock});
  assert.equal(one.status,'DRAFT');assert.equal(one.round,0);assert.equal(hits[0],'/');assert.equal(hits.at(-1),'/');
  let m=await readFreshLock(dir,one.manifestSHA256,{draft:true,round:0});
  assert.equal(m.fixtureBaselineCommit,SHA);assert.notEqual(m.candidateCommit,SHA);
  await assert.rejects(readFreshLock(dir,one.manifestSHA256),/ENOENT/);
  const gap=await save(base,'missing.json',probe(m,one.manifestSHA256,true));
  const two=await progressSnapshot(dir,0,one.manifestSHA256,...gap,{transport,clock:fixedClock});
  m=await readFreshLock(dir,two.manifestSHA256,{draft:true,round:1});
  assert.equal(m.entries[lazy].evidence,'ISOLATED_WORLD_GET_GAP');
  const done=await save(base,'ready.json',probe(m,two.manifestSHA256,false));
  const seal=await progressSnapshot(dir,1,two.manifestSHA256,...done,{seal:true,transport,clock:fixedClock});
  const frozen=await readFreshLock(dir,seal.manifestSHA256);
  assert.equal(frozen.scope,FRESH_SCOPE);assert.equal(frozen.status,'SEALED');assert.equal(frozen.probeSHA256,done[1]);
  assert.equal(frozen.sealedFromDraftSHA256,two.manifestSHA256);assert.equal(frozen.rootChecks.length,6);
  assert.equal(counts.get('/'),6);assert.equal(counts.get(entry),2);assert.equal(counts.get(css),2);assert.equal(counts.get(lazy),2);
  assert.equal(await readFile(join(dir,'snapshot.sealed.sha256'),'utf8'),seal.manifestSHA256+'\n');
  assert.equal((await readdir(base)).filter(p=>p.endsWith('.png')).length,0);
  await verifyLocalAssetTree(dir,frozen);
  await assert.rejects(readFreshLock(dir,two.manifestSHA256),/hash mismatch/);
  await writeFile(join(dir,'cache',cacheName(lazy)),'tampered');
  await assert.rejects(verifyLocalAssetTree(dir,frozen),/hash mismatch/);
});

test('verified root/asset drift prevents draft, redirect and wrong media type are rejected',async()=>{
  const changing=stub({rewrite:(path,n,row)=>path==='/'&&n===2?[root+'<!--changed-->','text/html']:row});
  const a=await mk();
  await assert.rejects(initSnapshot(a.dir,candidate,{...changing,clock:fixedClock}),/HTML changed/);
  assert.ok(!(await readdir(a.dir)).some(x=>x.endsWith('.json')));
  const mutating=stub({rewrite:(path,n,row)=>path===entry&&n===2?['other JS','text/javascript']:row});
  await assert.rejects(initSnapshot((await mk()).dir,candidate,{...mutating,clock:fixedClock}),/changed between independent reads/);
  const redirect=stub({rewrite:(_p,_n,[body,type])=>[body,type,302]});
  await assert.rejects(publicStaticGET('/',null,redirect),/redirect refused/);
  assert.equal(redirect.hits.length,1);
  const wrongType=stub({rewrite:(_p,_n,[body])=>[body,'application/json']});
  await assert.rejects(publicStaticGET('/',null,wrongType),/content-type mismatch/);
  await assert.rejects(publicStaticGET('/api/i',marker,{transport:()=>assert.fail('No API transport')}),/Disallowed/);
});

test('forged, stale, cross-origin, nonstatic or incomplete probe cannot authorize a new GET or seal',async()=>{
  const d=await mk(), x=stub();
  const a=await initSnapshot(d.dir,candidate,{...x,clock:fixedClock});
  const original=await readFreshLock(d.dir,a.manifestSHA256,{draft:true});
  const fixtures=[
    r=>r.fresh.manifestSHA256='0'.repeat(64),r=>r.referenceScope='C83_HISTORICAL_H5_CHAT_ATTESTED',
    r=>r.cases[0].deniedRequests[0].path='/api/i',r=>r.cases[0].deniedRequests[0].origin=SOURCE,
    r=>r.cases[0].screenshot='x.png',r=>r.cases[0].size={...r.cases[0].size,width:375},r=>r.networkNamespace.replay=r.networkNamespace.host,
  ];
  for(const [i,change] of fixtures.entries()){
    const p=probe(original,a.manifestSHA256,true);change(p);
    const before=x.hits.length;
    await assert.rejects(progressSnapshot(d.dir,0,a.manifestSHA256,...(await save(d.base,'bad-'+i+'.json',p)),{...x,clock:fixedClock}),/Probe/);
    assert.equal(x.hits.length,before);
  }
  const falseSeal=probe(original,a.manifestSHA256,false);falseSeal.cases[0].timeline[0].ids=['unexpected'];
  assert.throws(()=>acceptedProbe(falseSeal,original,a.manifestSHA256,{seal:true}),/did not exercise/);
});
