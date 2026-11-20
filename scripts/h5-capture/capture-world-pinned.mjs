/** Feed-first, locked raw H5 replay; no HTTP server, origin forwarding, or composer actions. */
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { mkdir, writeFile, readlink } from 'node:fs/promises';
import {
  ORIGIN, SOURCE, SHA, HTML_SHA, FIXTURE_SHA, MEDIA_SOURCE_SHA, ASSET_LOCK_SHA,
  ROUTE, BROWSER_INPUT_SHA, pinnedRead, checkLock, digest, verifyMatrix, preprocess, installReplayRoutes,
} from './world-replay.mjs';
import {FRESH_SCOPE,allowedPath,readFreshLock} from './fresh-world-lock.mjs';
const [repoPath, staticPath, outPath, mode, manifestSHA256, roundArgument] = process.argv.slice(2);
const probe=mode==='fresh-probe';
const fresh=probe || mode==='fresh-final';
if (!((!mode && process.argv.length===5) || (probe && process.argv.length===8) ||
      (mode==='fresh-final' && process.argv.length===7))) {
  throw Error('usage: node capture-world-pinned.mjs VERIFIED_CHECKOUT STATIC_DIR NEW_OUTPUT_DIR [fresh-probe SHA ROUND | fresh-final SHA]');
}
const round=probe?Number(roundArgument):0;
const [repo, staticRoot, output] = [repoPath,staticPath,outPath].map(x=>resolve(x));
await mkdir(output,{recursive:false});
const dir=dirname(fileURLToPath(import.meta.url));
const report={status:'BLOCKED',scope:'Pinned public H5 HTML/static bytes; synthetic World local feed; Chromium mobile emulation, not native Safari or production account',
  source:SOURCE,fixtureBaselineCommit:SHA,candidateCommit:process.env.WORLD_COMMIT??null,cases:[],pairEligible:false,
  referenceScope:fresh?FRESH_SCOPE:'C83_HISTORICAL_H5_CHAT_ATTESTED',discoveryOnly:probe};
let browser;
try {
  let lock;
  if(fresh) {
    lock=await readFreshLock(staticRoot,manifestSHA256,{draft:probe,round});
    if(lock.candidateCommit!==report.candidateCommit) throw Error('Wrong checkout for fresh snapshot');
    report.fresh={manifestSHA256,htmlSHA256:lock.htmlSHA256,round:lock.round,marker:lock.marker,
      observedStaticAssets:Object.keys(lock.assets).length,sealedAt:lock.sealedAt??null};
  } else {
    lock=JSON.parse(await pinnedRead(join(dir,'world-build-lock-c83.json'),ASSET_LOCK_SHA));
    checkLock(lock);
  }
  // Fresh and historical modes both require the same exact iOS comparison fixtures,
  // but do not conflate their H5 deployment observations.
  const fixtureMediaLock=JSON.parse(await pinnedRead(join(dir,'world-build-lock-c83.json'),ASSET_LOCK_SHA)).nativeMedia;
  const files={
    fixture:await pinnedRead(join(repo,'App/Resources/TimelineParity.json'),FIXTURE_SHA),
    media:await pinnedRead(join(repo,'App/Infrastructure/GIFTestFixtures.swift'),MEDIA_SOURCE_SHA),
    html:await pinnedRead(join(staticRoot,'public-home.html'),fresh?lock.htmlSHA256:HTML_SHA),
  };
  const pinnedInputs={};
  for(const [path,sha] of Object.entries(BROWSER_INPUT_SHA)) pinnedInputs[path]=await pinnedRead(join(repo,path),sha);
  const sizes=verifyMatrix(JSON.parse(pinnedInputs['scripts/iphone-qa-matrix.json']));
  const bundle=preprocess(files.html.toString('utf8'),JSON.parse(files.fixture),files.media.toString('utf8'));
  if (Object.entries(bundle.media).some(([name,bytes])=>digest(bytes)!==fixtureMediaLock[name])) {
    throw Error('Native fixture media hash mismatch');
  }
  const expectedID='at4tltest0025';
  const expectedText='欢迎加入 PUBO，分享音乐和日常。';
  if (bundle.fixture.posts[0]?.id !== expectedID || !bundle.fixture.posts[0]?.text?.startsWith(expectedText)) {
    throw Error('Wrong initial World fixture');
  }
  report.lock={...(!fresh?lock.h5BuildLockEvidence:{}),lockSHA256:fresh?manifestSHA256:ASSET_LOCK_SHA,
    htmlSHA256:fresh?lock.htmlSHA256:HTML_SHA,
    fixtureSHA256:FIXTURE_SHA,nativeMediaSourceSha256:MEDIA_SOURCE_SHA,
    browserInputSHA256:BROWSER_INPUT_SHA,
    nativeMediaSha256:Object.fromEntries(Object.entries(bundle.media).map(([k,v])=>[k,digest(v)]))};
  if(!/^[a-f0-9]{40}$/.test(report.candidateCommit??'')) throw Error('Missing exact CI checkout receipt');
  const parent=process.env.WORLD_HOST_NETNS;
  const isolated=await readlink('/proc/self/ns/net');
  if(!/^net:\[\d+\]$/.test(parent??'') || !/^net:\[\d+\]$/.test(isolated) || parent===isolated) {
    throw Error('Replay must be inside a separate Linux network namespace');
  }
  report.networkNamespace={host:parent,replay:isolated};
  // Resolve only from the C83 Playwright package; no network/dependency bootstrap.
  const require=createRequire(join(repo,'scripts/h5-capture/package.json'));
  if (require('playwright/package.json').version !== '1.56.1') throw Error('Need pinned Playwright 1.56.1');
  const {chromium}=require('playwright');
  browser=await chromium.launch({
    headless:true,
    args:['--disable-background-networking','--disable-component-update',
          '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE localhost, EXCLUDE 127.0.0.1'],
  });
  report.browser={playwright:'1.56.1',chromium:browser.version(),deviceScaleFactor:2,locale:'zh-CN'};
  const cached=new Map();
  let pinBlock;
  allCases: for (const [slot,size] of sizes) for (const theme of ['light','dark']) {
    const c={slot,size,theme,errors:[],deniedRequests:[],assets:{},fixtureMedia:{},timeline:[],passed:false};
    report.cases.push(c);
    const context=await browser.newContext({
      viewport:{width:size.width,height:size.height},deviceScaleFactor:2,isMobile:true,
      hasTouch:true,locale:'zh-CN',timezoneId:'UTC',colorScheme:theme,serviceWorkers:'block',
    });
    try {
      await context.addInitScript(({origin,me})=>{
        if (location.origin!==origin) return;
        const seed={account:JSON.stringify(me),lang:'zh-CN',lastVersion:'2026.9.0',
          puboDefaultLanguageVersion:'1',neverShowDonationInfo:'true',hidePreferencesRestoreSuggestion:'true'};
        for (const [key,value] of Object.entries(seed)) localStorage.setItem(key,value);
        // Identical inert first-boot socket behavior to the existing isolated H5 fixture.
        window.WebSocket=class extends EventTarget {
          static CONNECTING=0; static OPEN=1; static CLOSING=2; static CLOSED=3;
          constructor(){super();this.readyState=0;setTimeout(()=>{
            this.readyState=1;const e=new Event('open');this.dispatchEvent(e);this.onopen?.(e);
          },10);}
          send(){} close(){this.readyState=3;}
        };
      },{origin:ORIGIN,me:bundle.me});
      await installReplayRoutes(context,bundle,lock,join(staticRoot,'cache'),cached,c);
      const page=await context.newPage();
      page.on('pageerror',e=>c.errors.push(String(e)));
      page.on('console',msg=>{
        if(msg.type()!=='error') return;
        let path;
        try {path=new URL(msg.location().url).pathname;} catch {}
        // Only the fixture's explicitly checked default-key read may be absent.
        if(path==='/api/i/registry/get' && /^Failed to load resource: the server responded with a status of 404/.test(msg.text())) return;
        c.errors.push(msg.text());
      });
      await page.goto(ORIGIN+'/',{waitUntil:'domcontentloaded',timeout:probe?15_000:45_000});
      const post=page.getByText(expectedText,{exact:false}).first();
      await post.waitFor({state:'visible',timeout:probe?10_000:45_000});
      const dismiss=page.getByRole('button',{name:'一会再说',exact:true});
      if(await dismiss.isVisible()) {
        await dismiss.click();
        const prompt=page.getByText('要稍后再进行初始设定吗？',{exact:true});
        await prompt.waitFor({state:'visible',timeout:8000});
        await prompt.locator('xpath=ancestor::div[.//*[@data-testid="modal-dialog-ok"]][1]').locator('[data-testid="modal-dialog-ok"]').click({timeout:8000});
        await dismiss.waitFor({state:'hidden',timeout:8000});
      }
      await page.evaluate(()=>Promise.race([document.fonts.ready.then(()=>true),
        new Promise((_,reject)=>setTimeout(()=>reject(Error('Font readiness timed out')),10_000))]));
      c.viewport=await page.evaluate(()=>({width:window.innerWidth,height:window.innerHeight,dpr:devicePixelRatio}));
      c.postRect=await post.boundingBox();
      if (await page.locator('html').getAttribute('data-color-scheme')!==theme ||
          c.viewport.width!==size.width || c.viewport.height!==size.height || c.viewport.dpr!==2 ||
          !c.postRect || c.postRect.y<0 || c.postRect.y+c.postRect.height>size.height ||
          c.timeline[0]?.path!==ROUTE || c.timeline[0]?.untilId!==null || c.timeline[0]?.ids[0]!==expectedID ||
          Object.keys(c.assets).filter(x=>x.endsWith('.js')).length<2 ||
          c.errors.length || c.deniedRequests.length || page.url()!==ORIGIN+'/') {
        throw Error('Exact feed, appearance, request closure, or model geometry not verified');
      }
      if(!probe) {
        const bytes=await page.screenshot({fullPage:false,timeout:15_000});
        if(bytes.length<24 || !bytes.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex')) ||
           bytes.readUInt32BE(16)!==2*size.width || bytes.readUInt32BE(20)!==2*size.height ||
           c.errors.length || c.deniedRequests.length) throw Error('Original raster or closure changed');
        const name=(fresh?'fresh-':'')+'h5-world-local-'+slot+'-'+theme+'.png';
        await writeFile(join(output,name),bytes,{flag:'wx'});
        c.screenshot={file:name,sha256:digest(bytes),width:2*size.width,height:2*size.height};
      }
      c.passed=true;
    } catch(e) {c.failure=String(e);}
    finally {await context.close();}
    pinBlock=c.deniedRequests.find(x=>x.reason.startsWith('STATIC_'));
    if(pinBlock && !probe) break allCases;
  }
  if(probe) {
    const allDenied=report.cases.flatMap(c=>c.deniedRequests);
    if(report.cases.length===4 && report.cases.every(c=>c.passed) && !allDenied.length) {
      report.status='DISCOVERY_CONVERGED';
    } else if(report.cases.length===4 && allDenied.length && report.cases.every(c=>c.passed||c.deniedRequests.length) &&
        allDenied.every(x=>x.origin===ORIGIN && x.reason==='STATIC_PATH_UNATTESTED' && allowedPath(x.path,lock.marker))) {
      report.status='DISCOVERY_REQUIRED';
    } else {
      report.failure='Isolated World probe encountered non-static, inadmissible or incomplete evidence';
    }
  } else if(pinBlock) {
    report.status='BLOCKED';
    report.failure='World route requires absent, changed, or unattested static bytes';
    report.blockingAsset=pinBlock;
  } else {
    report.status=report.cases.length===4 && report.cases.every(c=>c.passed)?'CAPTURED_NOT_YET_PAIRED':'INCOMPLETE';
  }
} catch(e) {report.failure=String(e);}
finally {
  try { await browser?.close(); }
  catch(error) {report.status='BLOCKED';report.failure=String(error);}
  await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
  console.log(report.status);
  process.exitCode=['CAPTURED_NOT_YET_PAIRED','DISCOVERY_REQUIRED','DISCOVERY_CONVERGED'].includes(report.status)?0:1;
}
