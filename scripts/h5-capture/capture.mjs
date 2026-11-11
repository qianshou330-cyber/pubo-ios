import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const dir=dirname(fileURLToPath(import.meta.url));
const output=resolve(process.env.OUTPUT_DIR || `${dir}/artifacts`);
await mkdir(output,{recursive:true});
// Only clear this harness's named outputs, never unrelated user files.
for(const name of ['h5-small-light.png','h5-large-light.png','DIAGNOSTIC-NOT-PARITY-small.png','DIAGNOSTIC-NOT-PARITY-large.png',...['small','large'].flatMap(size=>['light','dark'].flatMap(mode=>[`h5-${size}-${mode}.png`,`h5-${size}-${mode}-filters.png`,`DIAGNOSTIC-NOT-PARITY-${size}-${mode}.png`])),'report.json','server.log','fixture-requests.log']) await rm(`${output}/${name}`,{force:true});
const origin=`http://127.0.0.1:${process.env.PORT || '8765'}`;
const fixturePath=resolve(process.env.FIXTURE_PATH || `${dir}/../../App/Resources/TimelineParity.json`);
const fixture=JSON.parse(await readFile(fixturePath,'utf8'));
const server=spawn('python3',[`${dir}/server.py`],{cwd:dir,env:{...process.env,FIXTURE_PATH:fixturePath},stdio:['ignore','pipe','pipe']});
let log='';server.stdout.on('data',v=>log+=v);server.stderr.on('data',v=>log+=v);
let browser;
const report={startedAt:new Date().toISOString(),reference:'Actual public H5 bundles; synthetic API/account/media. NOT production account or true media parity.',cases:[],success:false};
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
try {
 let ready=false;
 for(let i=0;i<90;i++) {if(server.exitCode!==null)throw Error(`Fixture server exited ${server.exitCode}`);try {const r=await fetch(`${origin}/__health`);if(r.ok){ready=true;break;}}catch{}await sleep(1000);}
 if(!ready)throw Error('Fixture readiness timed out');
 browser=await chromium.launch({headless:true});
 for(const mode of ['light','dark']) for(const size of [{name:'small',width:375,height:667},{name:'large',width:430,height:932}]) {
  const test={size,mode,errors:[],consoleErrors:[],blocked:[],failedResponses:[],timeline:false,bundles:0,passed:false};report.cases.push(test);
  const context=await browser.newContext({viewport:{width:size.width,height:size.height},deviceScaleFactor:2,isMobile:true,hasTouch:true,locale:'zh-CN',timezoneId:'UTC',colorScheme:mode,serviceWorkers:'block'});
  // Defense in depth: no browser request can reach production, even GET, fetch or forms.
  await context.route('**/*',async route=>{const u=new URL(route.request().url());if(u.origin===origin)return route.continue();test.blocked.push({url:u.origin+u.pathname,method:route.request().method()});await route.abort('blockedbyclient');});
  const page=await context.newPage();
  page.on('pageerror',e=>test.errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error')test.consoleErrors.push(m.text());});
  page.on('response',r=>{const u=new URL(r.url());if(r.status()>=400)test.failedResponses.push({path:u.pathname,status:r.status()});if(r.ok()&&u.pathname.endsWith('.js'))test.bundles++;if(r.ok()&&/\/api\/notes\/(local|home|hybrid|global)-timeline$/.test(u.pathname))test.timeline=true;});
  try {
   await page.goto(origin,{waitUntil:'domcontentloaded',timeout:60000});
   const expected=fixture.posts[0].text.split(' :')[0];
   await page.getByText(expected,{exact:false}).first().waitFor({state:'visible',timeout:90000});
   // Render evidence must come from actual H5 components, not the injected bootstrap or an error page.
   if(await page.locator('button').count()<3)throw Error('Expected interactive H5 controls missing');
   if(!test.timeline||test.bundles<2)throw Error('Actual app bundle/timeline fetch evidence missing');
   await page.evaluate(()=>document.fonts.ready);
   await page.waitForTimeout(5000);
   // Dismiss optional onboarding via the actual visible control, never remove DOM.
   const later=page.getByRole('button',{name:'一会再说',exact:true});
   if(await later.isVisible()){await later.click();await page.getByRole('button',{name:'OK',exact:true}).click();await later.waitFor({state:'hidden'});test.onboarding='deferred through real UI and confirmed';await page.waitForTimeout(500);}
   if(test.errors.length)throw Error('Uncaught H5 runtime error');
   if(test.failedResponses.length)throw Error('Incomplete fixture/static responses; inspect failedResponses');
   // Use the app's own system-theme synchronization; verify it actually applied.
   test.theme=await page.locator('html').getAttribute('data-color-scheme');
   if(test.theme!==mode)throw Error(`H5 theme is ${test.theme}, expected ${mode}`);
   // We do not hide dialogs, rewrite CSS, or manufacture a native-looking page.
   await page.screenshot({path:`${output}/h5-${size.name}-${mode}.png`,fullPage:false});
   const options=page.locator('button').filter({has:page.locator('i.ti-dots')}).first();
   const optionBox=await options.boundingBox();
   if(!optionBox||optionBox.y>100)throw Error('Could not identify actual timeline header options control');
   await options.click();
   for(const label of ['显示转帖','在时间线中显示对他人的回复','仅限媒体']) await page.getByText(label,{exact:true}).waitFor({state:'visible',timeout:10000});
   await page.waitForTimeout(500);
   if(test.errors.length||test.failedResponses.length)throw Error('Filter UI produced errors');
   test.filterLabels=['显示转帖','在时间线中显示对他人的回复','仅限媒体'];
   await page.screenshot({path:`${output}/h5-${size.name}-${mode}-filters.png`,fullPage:false});
   test.passed=true;test.capturedAt=new Date().toISOString();
  } catch(e) {test.failure=String(e);test.buttons=await page.locator('button').evaluateAll(nodes=>nodes.map(n=>({text:n.innerText,aria:n.getAttribute('aria-label'),title:n.title,html:n.outerHTML.slice(0,600)})));test.bodyText=await page.locator('body').innerText().catch(()=> 'unavailable');await page.screenshot({path:`${output}/DIAGNOSTIC-NOT-PARITY-${size.name}-${mode}.png`,fullPage:false}).catch(()=>{});throw e;}
  finally {await context.close();}
 }
 report.success=true;
} catch(e) {report.failure=String(e);process.exitCode=1;}
finally {
 try{report.provenance=await (await fetch(`${origin}/__health`)).json();}catch{}
 await browser?.close();server.kill('SIGTERM');
 await writeFile(`${output}/report.json`,JSON.stringify(report,null,2));
 await writeFile(`${output}/server.log`,log);
 try{await writeFile(`${output}/fixture-requests.log`,await readFile(`${dir}/requests.log`));}catch{}
}
