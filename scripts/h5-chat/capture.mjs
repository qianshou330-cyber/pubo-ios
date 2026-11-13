import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const dir = dirname(fileURLToPath(import.meta.url));
const out = resolve(process.env.OUTPUT_DIR || `${dir}/artifacts`);
await mkdir(out, {recursive:true});
// Remove this harness's known outputs only, never unrelated evidence files.
for (const size of ['small','large']) for (const theme of ['light','dark']) for (const kind of ['private','room']) {
 const name=`${kind}-${size}-${theme}`;
 for (const file of [`h5-${name}.png`,`h5-${name}-focused.png`,`DIAGNOSTIC-NOT-PARITY-${name}.png`]) await rm(`${out}/${file}`,{force:true});
}

const port = process.env.PORT || '8769';
if (!/^\d+$/.test(port) || +port < 1024 || +port > 65535) throw Error('Invalid port');
const origin = `http://127.0.0.1:${port}`;
const server = spawn('python3', [`${dir}/server.py`], {cwd:dir, env:{...process.env, PORT:port}, stdio:['ignore','pipe','pipe']});
let logs='', browser; server.stdout.on('data',x=>logs+=x);server.stderr.on('data',x=>logs+=x);
const report={startedAt:new Date().toISOString(),reference:'Actual public H5 bundles with native ChatParity.json synthetic messages. Production APIs blocked.',cases:[],success:false};
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
try {
 let ready=false; for(let n=0;n<50;n++){if(server.exitCode!==null)throw Error(`server exited ${server.exitCode}`);try{if((await fetch(origin+'/__health')).ok){ready=true;break;}}catch{}await sleep(1000);} if(!ready)throw Error('server timeout');
 browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{})});
 for(const size of [{name:'small',width:375,height:667},{name:'large',width:440,height:956}]) for(const theme of ['light','dark']) for(const kind of ['private','room']) {
  const name=`${kind}-${size.name}-${theme}`;
  const c={name,size,theme,kind,errors:[],consoleErrors:[],expectedConsoleErrors:[],expectedMissingKeys:[],blocked:[],failedResponses:[],responses:[],bundles:0,passed:false};report.cases.push(c);
  const context=await browser.newContext({viewport:{width:size.width,height:size.height},deviceScaleFactor:2,isMobile:true,hasTouch:true,locale:'zh-CN',timezoneId:'UTC',colorScheme:theme,serviceWorkers:'block'});
  await context.route('**/*',async route=>{const u=new URL(route.request().url());if(u.origin===origin)return route.continue();c.blocked.push({url:u.origin+u.pathname,method:route.request().method()});await route.abort('blockedbyclient');});
  const page=await context.newPage();
  const pendingResponses=[];
  page.on('pageerror',e=>c.errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error')c.consoleErrors.push({text:m.text(),url:m.location().url});});
  page.on('response',r=>{pendingResponses.push((async()=>{
   const path=new URL(r.url()).pathname;
   if(r.status()>=400) {
    let expected=false;
    if(path==='/api/i/registry/get'&&r.status()===404&&r.request().method()==='POST') {
     const body=await r.json().catch(()=>null);expected=body?.error?.code==='NO_SUCH_KEY';
    }
    (expected?c.expectedMissingKeys:c.failedResponses).push({path,status:r.status(),...(expected?{code:'NO_SUCH_KEY'}:{})});
   }
   if(path.startsWith('/api/'))c.responses.push({path,status:r.status()});
   if(r.ok()&&path.endsWith('.js'))c.bundles++;
  })());});
  const clean=async()=>{
   await Promise.all(pendingResponses);
   // Only Chromium's network-resource console line for a verified missing
   // preference key is expected; all other console/runtime/network errors fail.
   c.consoleErrors=c.consoleErrors.filter(e=>{
    let path;try{path=new URL(e.url).pathname;}catch{}
    const expected=path==='/api/i/registry/get'&&/^Failed to load resource: the server responded with a status of 404/.test(e.text)&&c.expectedMissingKeys.length>0&&!c.failedResponses.some(r=>r.path===path);
    if(expected)c.expectedConsoleErrors.push(e);return !expected;
   });
   if(c.errors.length||c.consoleErrors.length||c.blocked.length||c.failedResponses.length)throw Error('Runtime/network/fixture failure');
  };
  try {
   await page.goto(origin+(kind==='private'?'/chat/user/syntheticpeer':'/chat/room/socialroom'),{waitUntil:'domcontentloaded',timeout:60000});
   const text=kind==='private'?'收到，我们在这里聊天。':'今天一起分享喜欢的舞台。';
   await page.getByText(text,{exact:true}).first().waitFor({state:'visible',timeout:90000});
   await page.evaluate(()=>document.fonts.ready);await sleep(2000);
   const later=page.locator('[data-testid="user-setup-dialog"]').getByRole('button',{name:'一会再说',exact:true});
   if(await later.isVisible()) {await later.click();const q=page.getByText('要稍后再进行初始设定吗？',{exact:true});await q.waitFor({state:'visible'});await q.locator('xpath=ancestor::div[.//*[@data-testid="modal-dialog-ok"]][1]').locator('[data-testid="modal-dialog-ok"]').click();await later.waitFor({state:'hidden'});c.setupDismissed=true;}
   await clean();
   const timeline='/api/chat/messages/'+(kind==='private'?'user':'room')+'-timeline';
   if(!c.responses.some(r=>r.path===timeline&&r.status===200)||c.bundles<2)throw Error('Missing real H5/timeline fetch');
   if(await page.locator('html').getAttribute('data-color-scheme')!==theme)throw Error('Theme mismatch');
   const input=page.locator('textarea').first();await input.waitFor({state:'visible'});
   c.input=await input.boundingBox();if(!c.input||c.input.y+c.input.height>size.height)throw Error('Composer is offscreen');
   c.controls=await page.locator('button').evaluateAll(ns=>ns.filter(n=>n.getClientRects().length).map(n=>({text:n.textContent.trim(),label:n.getAttribute('aria-label'),title:n.getAttribute('title'),icons:[...n.querySelectorAll('i')].map(x=>x.className),rect:(()=>{const r=n.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}})()})));
   await page.screenshot({path:`${out}/h5-${name}.png`});
   await input.fill('草稿保留 '+kind);await input.focus();await clean();
   await page.screenshot({path:`${out}/h5-${name}-focused.png`});
   c.keyboard='Desktop Chromium focus only; NOT an iOS software keyboard test';c.passed=true;c.capturedAt=new Date().toISOString();
  } catch(e){c.failure=String(e);c.bodyText=await page.locator('body').innerText().catch(()=>'');await page.screenshot({path:`${out}/DIAGNOSTIC-NOT-PARITY-${name}.png`}).catch(()=>{});}
  finally{await context.close();}
 }
 report.success=report.cases.length===8&&report.cases.every(c=>c.passed);
} catch(e){report.failure=String(e);}
finally {
 try{report.provenance=await(await fetch(origin+'/__health')).json();}catch{}
 await browser?.close();server.kill('SIGTERM');report.finishedAt=new Date().toISOString();
 await writeFile(`${out}/report.json`,JSON.stringify(report,null,2));await writeFile(`${out}/server.log`,logs);await writeFile(`${out}/fixture-requests.log`,await readFile(`${dir}/requests.log`).catch(()=>''));
}
console.log(JSON.stringify({success:report.success,failure:report.failure,cases:report.cases.map(c=>({name:c.name,passed:c.passed,failure:c.failure}))}));process.exitCode=report.success?0:1;
