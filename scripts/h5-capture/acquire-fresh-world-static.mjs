/** The only network-bearing fresh module; never imported by the browser replay. */
import {mkdir,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {SOURCE,SHA,digest,cacheName,pinnedRead} from './world-replay.mjs';
import {
  FRESH_SCOPE,CAP,MAX_ROUNDS,MAX_TOTAL_BYTES,allowedPath,seedPaths,checkFresh,readFreshLock,
  verifyLocalAssetTree,acceptedProbe,canonicalJSON,describeBootstrapShape,assetEvidence,
} from './fresh-world-lock.mjs';
const MIME={js:['text/javascript','application/javascript'],css:['text/css'],
  woff2:['font/woff2','application/font-woff2','application/octet-stream'],woff:['font/woff','application/font-woff','application/octet-stream'],
  png:['image/png'],svg:['image/svg+xml'],webp:['image/webp'],gif:['image/gif'],ico:['image/x-icon','image/vnd.microsoft.icon']};
const MAX_BODY=12*1024*1024;

export async function publicStaticGET(path,marker,{transport=fetch}={}) {
  if(path!=='/' && !allowedPath(path,marker)) throw Error('Disallowed fresh static path: '+path);
  const url=new URL(path,SOURCE);
  if(url.origin!==new URL(SOURCE).origin || url.pathname!==path || url.search || url.hash || url.username || url.password) {
    throw Error('Disallowed fresh static URL');
  }
  const r=await transport(url,{method:'GET',redirect:'manual',credentials:'omit',cache:'no-store',
    signal:AbortSignal.timeout(8000),headers:{'user-agent':'PUBO isolated visual reference'}});
  if(r.status!==200 || r.redirected || r.url!==url.href) throw Error('Static response unavailable or redirect refused: '+path+' HTTP '+r.status);
  const allowedTypes=path==='/'?['text/html']:MIME[path.split('.').at(-1)];
  const receivedType=r.headers.get('content-type')?.split(';')[0]?.trim()?.toLowerCase();
  if(!allowedTypes.includes(receivedType)) throw Error('Static content-type mismatch: '+path);
  if(!r.body || Number(r.headers.get('content-length'))>MAX_BODY) throw Error('Invalid static size: '+path);
  const reader=r.body.getReader();
  let count=0;
  const chunks=[];
  try {
    for(;;) {
      const {value,done}=await reader.read();
      if(done)break;
      count+=value.byteLength;
      if(count>MAX_BODY)throw Error('Invalid static size: '+path);
      chunks.push(value);
    }
  } catch(error) {
    await reader.cancel().catch(()=>{});throw error;
  } finally {reader.releaseLock();}
  if(!count)throw Error('Empty static response: '+path);
  return Buffer.concat(chunks,count);
}
async function pinBody(path,marker,transport) {
  const one=await publicStaticGET(path,marker,{transport});
  const two=await publicStaticGET(path,marker,{transport});
  if(!one.equals(two)) throw Error('Public static bytes changed between independent reads: '+path);
  return one;
}
function rootObservation(data,base,clock) {
  const sha256=digest(data);
  if(sha256!==base)throw Error('Public HTML changed during fresh snapshot; restart with new receipt');
  return {sha256,at:clock()};
}
async function captureNewPaths(dir,m,paths,transport,clientEntry) {
  if(paths.length+Object.keys(m.entries).length>CAP)throw Error('Fresh static path budget exceeded');
  for(let i=0;i<paths.length;i+=6) {
    const batch=await Promise.allSettled(paths.slice(i,i+6).map(path=>pinBody(path,m.marker,transport)));
    const failed=batch.find(x=>x.status==='rejected');
    if(failed)throw failed.reason;
    const used=Object.values(m.entries).reduce((n,x)=>n+x.bytes,0);
    if(used+batch.reduce((n,x)=>n+x.value.length,0)>MAX_TOTAL_BYTES)throw Error('Fresh static byte budget exceeded');
    for(const [offset,{value}] of batch.entries()) {
      const path=paths[i+offset];
      await writeFile(join(dir,'cache',cacheName(path)),value,{flag:'wx'});
      m.entries[path]={sha256:digest(value),bytes:value.length,observations:2,round:m.round,
                      evidence:assetEvidence(path,m.round,clientEntry)};
    }
  }
}
async function commitManifest(dir,m,draft) {
  delete m.assets;
  checkFresh(m,{draft});
  const body=canonicalJSON(m);
  const stem=draft?'draft-'+m.round:'snapshot.sealed';
  await writeFile(join(dir,stem+'.json'),body,{flag:'wx'});
  const sha256=digest(body);
  await writeFile(join(dir,stem+'.sha256'),sha256+'\n',{flag:'wx'});
  return {scope:FRESH_SCOPE,status:m.status,round:m.round,manifestSHA256:sha256,htmlSHA256:m.htmlSHA256};
}
// One anonymous canonical root GET, no static files, replay, or write path.
export async function inspectBootstrapShape({transport=fetch}={}) {
  const html=await publicStaticGET('/',null,{transport});
  return describeBootstrapShape(html);
}
const utc=()=>new Date().toISOString();
export async function initSnapshot(dir,candidateCommit,{transport=fetch,clock=utc}={}) {
  if(!/^[a-f0-9]{40}$/.test(candidateCommit??''))throw Error('Exact candidate commit required before acquisition');
  await mkdir(dir);
  await mkdir(join(dir,'cache'));
  const html=await publicStaticGET('/',null,{transport});
  const htmlSHA256=digest(html);
  const {marker,refs,clientEntry}=seedPaths(html.toString('utf8'));
  const m={schema:1,scope:FRESH_SCOPE,origin:SOURCE,fixtureBaselineCommit:SHA,candidateCommit,status:'DRAFT',round:0,
    htmlSHA256,marker,entries:{},rootChecks:[rootObservation(html,htmlSHA256,clock)]};
  await captureNewPaths(dir,m,refs,transport,clientEntry);
  m.rootChecks.push(rootObservation(await publicStaticGET('/',null,{transport}),htmlSHA256,clock));
  await writeFile(join(dir,'public-home.html'),html,{flag:'wx'});
  return commitManifest(dir,m,true);
}
export async function progressSnapshot(dir,round,sha,probePath,probeSHA,{seal=false,transport=fetch,clock=utc}={}) {
  const m=await readFreshLock(dir,sha,{draft:true,round});
  const bytes=await pinnedRead(probePath,probeSHA,1024*1024);
  const paths=acceptedProbe(JSON.parse(bytes),m,sha,{seal});
  if(!seal && round===MAX_ROUNDS)throw Error('Fresh World probe round budget exhausted');
  m.rootChecks.push(rootObservation(await publicStaticGET('/',null,{transport}),m.htmlSHA256,clock));
  if(seal) {
    await verifyLocalAssetTree(dir,m);
    Object.assign(m,{status:'SEALED',sealedAt:clock(),probeSHA256:probeSHA,sealedFromDraftSHA256:sha});
  } else {
    m.round++;
    await captureNewPaths(dir,m,paths,transport);
  }
  m.rootChecks.push(rootObservation(await publicStaticGET('/',null,{transport}),m.htmlSHA256,clock));
  return commitManifest(dir,m,!seal);
}
if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const [mode,dir,a,b,c,d]=process.argv.slice(2);
    if(mode==='inspect-bootstrap-shape') {
      if(process.argv.length!==3) throw Error('Wrong shape-only argument count');
      console.log(JSON.stringify(await inspectBootstrapShape()));
    } else {
      if(!dir || !['init','extend','seal'].includes(mode) || (mode==='init'?process.argv.length!==5:process.argv.length!==8)) {
        throw Error('Use init DIR COMMIT | extend/seal DIR ROUND DRAFT_SHA PROBE_JSON PROBE_SHA');
      }
      const result=mode==='init'?await initSnapshot(dir,a):
        await progressSnapshot(dir,Number(a),b,c,d,{seal:mode==='seal'});
      console.log(JSON.stringify(result));
    }
  } catch(error) {
    if(process.argv[2]==='inspect-bootstrap-shape') {
      console.error(JSON.stringify({probe:'H5_BOOTSTRAP_SHAPE_ONLY',verdict:'ROOT_FETCH_OR_SHAPE_BLOCKED'}));
    } else {
      console.error(JSON.stringify({scope:FRESH_SCOPE,status:'BLOCKED',failure:String(error)}));
    }
    process.exitCode=1;
  }
}
