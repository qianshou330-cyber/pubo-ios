import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {SOURCE,SHA,ORIGIN,ROUTE,EXPECTED,digest,cacheName} from './world-replay.mjs';
import {FRESH_SCOPE,allowedPath,seedPaths,readFreshLock,verifyLocalAssetTree,acceptedProbe,canonicalJSON,classifyInitialRootDrift} from './fresh-world-lock.mjs';
import {publicStaticGET,initSnapshot,progressSnapshot,inspectBootstrapShape,readInitialRootDrift} from './acquire-fresh-world-static.mjs';
const marker='sE2FIylr5', candidate='f'.repeat(40);
const entry='/vite/zh-CN/'+marker+'-2--13OMV.js';
const css='/vite/assets/'+marker+'-4RTeR85g.css';
const lazy='/vite/zh-CN/'+marker+'-l8YPdAU1.js';
const root=`<!doctype html><head><script type="application/json" id="misskey_meta">{"policies":{}}</script><script type="module" src="${entry}"></script><link rel="stylesheet" href="${css}"></head>`;
const relativeEntry='scripts/'+entry.split('/').at(-1);
const classic=`<script>const VERSION = '2026.9.0';
  const CLIENT_ENTRY = "${relativeEntry}";
  const CLIENT_PRELOADS = ["scripts/${lazy.split('/').at(-1)}"];
  const WELCOME_PRELOADS = ["https://example.invalid/must-not-fetch"];
  const WELCOME_CSS = []; const ICON_CSS = null; const LANGS = ["zh-CN"];</script>`;
const stylesheetPaths=[css,...Array.from({length:15},(_,i)=>`/vite/assets/${marker}-${i.toString().padStart(8,'0')}.css`)];
const stylesheetLinks=paths=>paths.map(path=>`<link rel="stylesheet" href="${path}">`).join('');
const compiledRoot=`<!DOCTYPE html><!-- source-compatible synthetic fixture --><html><head>
  ${classic}
  <script type="application/json" id="misskey_meta" data-generated-at="123">{"policies":{}}</script>
  <script>(() => { /* real bootstrap is not needed by mocked transport */ })();</script>
  ${stylesheetLinks(stylesheetPaths)}
  <style>body {color: blue}</style></head><body>fixture</body></html>`;
const fixedClock=()=> '2026-11-20T09:30:00.000Z';
const mk=async()=>{const base=await mkdtemp(join(tmpdir(),'pubo-fresh-static-test-'));return {base,dir:join(base,'fresh')};};
function stub({rewrite=(path,count,row)=>row,extra={}}={}) {
  const hits=[],counts=new Map();
  const responses={
    '/':[root,'text/html'],[entry]:['entry JS','text/javascript'],[css]:['body{color:red}','text/css'],[lazy]:['lazy JS','application/javascript'],...extra,
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

test('one-shot fresh bootstrap output never emits HTML, paths, config, prefix or arbitrary strings', async () => {
  const sample = `<!doctype html><head>
    <script type="application/json" id="misskey_meta">{"sensitive":"PRIVATE_CONFIG_CANARY","loader":"SHOULD_NEVER_LOG"}</script>
    <script>const CLIENT_ENTRY = "scripts/FIRST_VISIT_PRIVATE_CANARY.js";</script>
    <script src="/loader/boot.js"></script>
    <script type="module" src='https://bolubo.com/vite/zh-CN/PRIVATE_ABS_CANARY.js'></script>
    <script type="module">void "INLINE_PRIVATE_CANARY";</script>
    <link rel="modulepreload" href="/vite/ja-JP/OTHER_LOCALE_CANARY.js">
    <link rel="stylesheet" href="/vite/assets/CSS_PRIVATE_CANARY.css?token=QUERY_PRIVATE_CANARY">
    <!-- <script src="COMMENT_PRIVATE_CANARY"></script> -->
    </head><body><script src="BODY_PRIVATE_CANARY"></script></body>`;
  let count=0;
  const report=await inspectBootstrapShape({transport:async (url,options)=>{
    assert.equal(++count,1);
    assert.equal(url.href,SOURCE);assert.equal(url.pathname,'/');
    assert.equal(options.method,'GET');assert.equal(options.credentials,'omit');assert.equal(options.redirect,'manual');
    assert.deepEqual(Object.keys(options.headers),['user-agent']);
    const r=new Response(sample,{status:200,headers:{'content-type':'text/html'}});
    Object.defineProperty(r,'url',{value:url.href});return r;
  }});
  assert.equal(count,1);
  assert.equal(report.responseBytes,Buffer.byteLength(sample));
  assert.equal(report.htmlSHA256,digest(sample));
  assert.equal(report.verdict,'PATH_FAMILY_UNRECOGNIZED');
  assert.equal(report.tagScan,'HEAD_END');
  assert.deepEqual(report.kinds,{moduleScriptSrc:1,moduleScriptInline:1,classicScriptSrc:1,
    modulePreload:1,stylesheet:1,loaderScriptSrc:1,clientEntryInlineAssignment:1,clientEntryInlineScriptsShape:1});
  assert.deepEqual(report.pathKinds,{rootRelativeZhCN:0,rootRelativeOtherLocale:1,rootRelativeScripts:0,
    rootRelativeAssets:0,absoluteSameOriginVite:1,queryOrFragment:1,other:1});
  const serialized=JSON.stringify(report);
  for(const token of ['CANARY','SHOULD_NEVER_LOG','<script','PRIVATE','/vite/','https://','/loader/','sensitive']) {
    assert.ok(!serialized.includes(token),'unexpected input value');
  }
  function strings(x) {
    if(typeof x==='string') return [x];
    if(x&&typeof x==='object')return Object.values(x).flatMap(strings);
    return [];
  }
  assert.deepEqual(strings(report),['H5_BOOTSTRAP_SHAPE_ONLY',digest(sample),'PATH_FAMILY_UNRECOGNIZED','HEAD_END']);
});

test('diagnostic only: one root GET even if old shape passes, fail closed on a redirect', async () => {
  const x=stub();
  const report=await inspectBootstrapShape(x);
  assert.equal(report.verdict,'ACCEPTS_CURRENT_SHAPE');
  assert.deepEqual(x.hits,['/']);
  assert.deepEqual(x.counts,new Map([['/',1]]));
  const d=stub({rewrite:(_p,_n,[body,type])=>[body,type,302]});
  await assert.rejects(inspectBootstrapShape(d),/redirect refused/);
  assert.deepEqual(d.hits,['/']);
});

test('diagnostic distinguishes over-cap, unknown extension and mixed markers but never changes policy', async () => {
  const many=Array.from({length:25},(_,i)=>'/vite/zh-CN/'+marker+'-'+String(i).padStart(8,'0')+'.js');
  const mixed='/vite/zh-CN/MixedAbc0-nmN0ca45.js';
  const unknown='/vite/assets/'+marker+'-mnop2345.mp3';
  for(const [paths,expected] of [[many,{overCap:true}],[ [entry,mixed],{markerCount:2}],[[entry,unknown],{unknownCount:1}]]) {
    const html=root.replace('</head>',paths.map(r=>`<link rel="modulepreload" href="${r}">`).join('')+'</head>');
    const control=stub({rewrite:(p,_n,row)=>p==='/'?[html,'text/html']:row});
    const out=await inspectBootstrapShape(control);
    assert.throws(()=>seedPaths(html),/mixed H5 bootstrap path family/);
    assert.equal(out.verdict,'PATH_FAMILY_UNRECOGNIZED');
    for(const [name,item] of Object.entries(expected)) assert.equal(out.legacy[name],item);
    assert.deepEqual(control.hits,['/']);
  }
});

test('C85 shape: canonical source-declared entry plus sixteen literal stylesheets, no seed preload or extra fetch',async()=>{
  const expected=[entry,...stylesheetPaths].sort();
  assert.deepEqual(seedPaths(compiledRoot),{marker,refs:expected,clientEntry:entry});
  const {dir}=await mk(), extra=Object.fromEntries(stylesheetPaths.map(p=>[p,['fixture CSS','text/css']]));
  const control=stub({extra:{...extra,'/':[compiledRoot,'text/html']}});
  const summary=await initSnapshot(dir,candidate,{...control,clock:fixedClock});
  const manifest=await readFreshLock(dir,summary.manifestSHA256,{draft:true});
  assert.deepEqual(Object.keys(manifest.entries).sort(),expected);
  assert.equal(manifest.entries[entry].evidence,'PUBLIC_HTML_CLIENT_ENTRY_ZH_CN');
  assert.ok(stylesheetPaths.every(p=>manifest.entries[p].evidence==='PUBLIC_HTML_LITERAL'));
  assert.equal(control.hits[0],'/');assert.equal(control.hits.at(-1),'/');
  assert.equal(control.hits.length,36);
  assert.equal(control.counts.size,18);
  assert.ok([...control.counts.values()].every(n=>n===2));
  assert.equal(control.counts.has(lazy),false);
  const raw=await readFile(join(dir,'draft-0.json'));
  const retag=JSON.parse(raw);
  retag.entries[entry].evidence='PUBLIC_HTML_LITERAL';
  const retagBody=canonicalJSON(retag);
  await writeFile(join(dir,'draft-0.json'),retagBody);
  await assert.rejects(readFreshLock(dir,digest(retagBody),{draft:true}),/Bootstrap asset closure/);
  await writeFile(join(dir,'draft-0.json'),raw);
  const once=stub({extra:{'/':[compiledRoot,'text/html']}});
  const report=await inspectBootstrapShape(once);
  assert.deepEqual(report.legacy,{uniqueQuotedRefs:16,zhCNJsRefs:0,unknownCount:0,markerCount:1,overCap:false});
  assert.equal(report.verdict,'ACCEPTS_CURRENT_SHAPE');
  assert.deepEqual(once.hits,['/']);
});

test('compiled-shell fallback rejects ambiguous globals, noncanonical paths, unanchored styles, and cap overflow before any asset GET',async()=>{
  const literalName=relativeEntry.split('/').at(-1);
  const styles=stylesheetLinks(stylesheetPaths);
  const variants=[
    compiledRoot.replace(relativeEntry,'/vite/zh-CN/'+literalName+'?cache=1'),
    compiledRoot.replace(relativeEntry,'https://bolubo.com/'+relativeEntry),
    compiledRoot.replace(relativeEntry,'scripts/'+literalName+'?cache=1'),
    compiledRoot.replace(relativeEntry,'scripts/'+literalName+'#fragment'),
    compiledRoot.replace(relativeEntry,'scripts/../scripts/'+literalName),
    compiledRoot.replace(relativeEntry,'scripts/'+literalName.replace(marker,'OtherMark0')),
    compiledRoot.replace(relativeEntry,'scripts/%41'+literalName),
    compiledRoot.replace(relativeEntry,'scripts/'+literalName.replace(/\.js$/,'.css')),
    compiledRoot.replace(classic,'<!--'+classic+'-->'),
    compiledRoot.replace(classic,'<template>'+classic+'</template>'),
    compiledRoot.replace(classic,classic+classic),
    compiledRoot.replace(classic,classic+'<script src="/vite/loader/boot.js"></script>'),
    compiledRoot.replace(classic,'<script type="application/json">'+classic.slice(8)),
    compiledRoot.replace(classic,'').replace('</body>',classic+'</body>'),
    compiledRoot.replace(styles,'<!--'+styles+'-->'),
    compiledRoot.replace(styles,'').replace('</body>',styles+'</body>'),
    compiledRoot.replace(styles,stylesheetLinks([...stylesheetPaths,...Array.from({length:8},(_,i)=>`/vite/assets/${marker}-A000000${i}.css`)])),
  ];
  for(const html of variants) {
    assert.throws(()=>seedPaths(html),/mixed H5 bootstrap path family/);
    const stop=stub({extra:{'/':[html,'text/html']}});
    await assert.rejects(initSnapshot((await mk()).dir,candidate,stop),/mixed H5 bootstrap path family/);
    assert.deepEqual(stop.hits,['/']);
  }
});

test('compiled-shell fallback does not excuse root-byte drift, including data-generated-at',async()=>{
  const extra=Object.fromEntries(stylesheetPaths.map(p=>[p,['fixture CSS','text/css']]));
  const control=stub({extra:{...extra,'/':[compiledRoot,'text/html']},
    rewrite:(p,n,row)=>p==='/'&&n===2?[compiledRoot.replace('data-generated-at="123"','data-generated-at="124"'),'text/html']:row});
  const {dir}=await mk();
  await assert.rejects(initSnapshot(dir,candidate,control),/Public HTML changed/);
  assert.ok(!(await readdir(dir)).some(name=>name.endsWith('.json')||name==='public-home.html'));
  assert.equal(control.counts.get('/'),2);
});

const stamps=['1795183301100','1795183301200','1795183302100','1795183302200'];
const contextTag=`<script type="application/json" id="misskey_clientCtx" data-generated-at="${stamps[1]}">{"opaque":"TOKEN_VALUE_Z1","其他":"保持不变"}</script>`;
const observedRoot=compiledRoot.replace('source-compatible synthetic fixture','公开壳 fixture comment')
  .replace('data-generated-at="123"',`data-generated-at="${stamps[0]}"`)
  .replace('<style>',contextTag+'<style>');
const stampOnly=observedRoot.replace(stamps[0],stamps[2]).replace(stamps[1],stamps[3]);

test('initial mismatch emits only fixed diagnostic evidence and still refuses timestamp-only drift', async()=>{
  const extra=Object.fromEntries(stylesheetPaths.map(p=>[p,['fixture CSS','text/css']]));
  const control=stub({extra:{...extra,'/':[observedRoot,'text/html']},
    rewrite:(p,n,row)=>p==='/'&&n===2?[stampOnly,'text/html']:row});
  const {dir}=await mk();
  await assert.rejects(initSnapshot(dir,candidate,{...control,clock:fixedClock}),error=>{
    assert.equal(String(error),'Error: Public HTML changed during fresh snapshot; restart with new receipt');
    const report=readInitialRootDrift(error);
    assert.deepEqual(report,{classification:'ROOT_DIFF_FIXED_RENDER_STAMPS_ONLY',seedIdentity:'SAME',
      expectedSHA256:digest(observedRoot),observedSHA256:digest(stampOnly)});
    assert.deepEqual(Object.values(report).filter(x=>!/^[a-f0-9]{64}$/.test(x)),['ROOT_DIFF_FIXED_RENDER_STAMPS_ONLY','SAME']);
    for(const value of [...stamps,'TOKEN_VALUE_Z1','/vite/','https://','<script','保持不变']) {
      assert.ok(!JSON.stringify(report).includes(value));
    }
    assert.equal(readInitialRootDrift({rootMismatch:'untrusted string'}),undefined);
    return true;
  });
  assert.ok(!(await readdir(dir)).some(name=>name.endsWith('.json')||name.endsWith('.sha256')||name==='public-home.html'));
  assert.equal(control.hits.length,36); // Original seed bracket, no diagnostic requests.
  assert.equal(control.hits[0],'/');assert.equal(control.hits.at(-1),'/');
  assert.ok([...control.counts.values()].every(n=>n===2));
  assert.equal(control.counts.has(lazy),false);
});

test('unrelated changed bytes, fake stamp placement or ambiguous structure stay unclassified', async()=>{
  const unknown='ROOT_DIFF_UNCLASSIFIED', b=Buffer.from;
  assert.equal(classifyInitialRootDrift(b(observedRoot),b(observedRoot)),unknown);
  for(const changed of [stampOnly.replace('TOKEN_VALUE_Z1','TOKEN_VALUE_Z2'),stampOnly.replace('>fixture</body>','>Fixture</body>')]) {
    assert.equal(changed.length,observedRoot.length);
    assert.equal(classifyInitialRootDrift(b(observedRoot),b(changed)),unknown);
  }
  const duplicate=observedRoot.replace(contextTag,contextTag+contextTag);
  const malformed=observedRoot.replace('id="misskey_meta" data-generated-at=','id="misskey_meta" irrelevant="EXTRA_TOKEN" data-generated-at=');
  const inert=observedRoot.replace(contextTag,'<!--'+contextTag+'-->');
  const outside=observedRoot.replace(contextTag,'').replace('</body>',contextTag+'</body>');
  const oversize=observedRoot.replace('<html>','<!--'+'x'.repeat(1024*1024)+'--><html>');
  for(const candidateHTML of [duplicate,malformed,inert,outside,oversize]) {
    assert.equal(classifyInitialRootDrift(b(candidateHTML),b(candidateHTML.replaceAll(stamps[1],stamps[3]))),unknown);
  }
  const extra=Object.fromEntries(stylesheetPaths.map(p=>[p,['fixture CSS','text/css']]));
  const other=stampOnly.replace('TOKEN_VALUE_Z1','TOKEN_VALUE_Z2');
  const control=stub({extra:{...extra,'/':[observedRoot,'text/html']},
    rewrite:(p,n,row)=>p==='/'&&n===2?[other,'text/html']:row});
  const {dir}=await mk();
  await assert.rejects(initSnapshot(dir,candidate,{...control,clock:fixedClock}),error=>{
    assert.equal(String(error),'Error: Public HTML changed during fresh snapshot; restart with new receipt');
    assert.deepEqual(readInitialRootDrift(error),{classification:unknown,seedIdentity:'SAME',
      expectedSHA256:digest(observedRoot),observedSHA256:digest(other)});
    return true;
  });
  assert.equal(control.hits.length,36);
  assert.ok(!(await readdir(dir)).some(name=>name.endsWith('.json')||name==='public-home.html'));
});
