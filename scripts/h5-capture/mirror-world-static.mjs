/** Acquisition only: public GET, exact existing hash allowlist, no browser or API. */
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
import {assertPinnedAssetRequest,checkLock,pinnedRead,digest,cacheName,SOURCE,SHA,ASSET_LOCK_SHA,HTML_SHA} from './world-replay.mjs';

const MAX_BYTES=12*1024*1024;
export async function downloadPinned(path, sha, lock, fetchImplementation=fetch) {
  assertPinnedAssetRequest(path,sha,lock);
  const url=new URL(path,SOURCE);
  if(url.origin!==new URL(SOURCE).origin || url.pathname!==path || url.search || url.hash || url.username || url.password) {
    throw Error('Unsafe static URL');
  }
  const options={method:'GET',credentials:'omit',redirect:'manual',cache:'no-store',
    signal:AbortSignal.timeout(20_000),headers:{'user-agent':'PUBO isolated visual reference'}};
  const r=await fetchImplementation(url,options);
  if (r.status>=300 && r.status<400) throw Error('Static redirect refused: '+path);
  if (r.status!==200 || r.redirected || r.url!==url.href) throw Error('Static retrieval failed: '+path+' HTTP '+r.status);
  const declaredSize=r.headers.get('content-length');
  if (!r.body || (declaredSize!==null && Number(declaredSize)>MAX_BYTES)) throw Error('Invalid static size: '+path);
  const chunks=[];
  let size=0;
  const stream=r.body.getReader();
  try {
    for (;;) {
      const {done,value}=await stream.read();
      if(done) break;
      size+=value.byteLength;
      if(size>MAX_BYTES) throw Error('Invalid static size: '+path);
      chunks.push(value);
    }
  } catch(error) {
    await stream.cancel().catch(()=>{});
    throw error;
  } finally {stream.releaseLock();}
  const data=Buffer.concat(chunks,size);
  if(!size || digest(data)!==sha) throw Error('Static build drift: '+path);
  return data;
}

async function mirror([target,receiptPath,existing]) {
  if(!target || !receiptPath) throw Error('Usage: node mirror-world-static.mjs NEW_STATIC_DIR RECEIPT_JSON [OLD_CACHE_DIR]');
  const dir=dirname(fileURLToPath(import.meta.url));
  const receipt={stage:'static-mirror',status:'BLOCKED',publicOrigin:SOURCE,fixtureBaselineCommit:SHA,
    lockSHA256:ASSET_LOCK_SHA,htmlSHA256:HTML_SHA,verifiedAssets:0,verifiedHTML:false};
  try {
    const lock=JSON.parse(await pinnedRead(join(dir,'world-build-lock-c83.json'),ASSET_LOCK_SHA));
    checkLock(lock);
    receipt.lockEvidence=lock.h5BuildLockEvidence;
    const root=resolve(target);
    await mkdir(root);
    await mkdir(join(root,'cache'));
    // Check HTML before any asset GET. One exact request per uncached lock entry, no retry/fallback.
    await writeFile(join(root,'public-home.html'),await downloadPinned('/',HTML_SHA,lock),{flag:'wx'});
    receipt.verifiedHTML=true;
    const entries=Object.entries(lock.assets);
    for(let i=0;i<entries.length;i+=5) {
      const batch=await Promise.allSettled(entries.slice(i,i+5).map(async ([path,sha])=>{
        const file=cacheName(path);
        let data;
        if(existing) try {data=await pinnedRead(join(resolve(existing),file),sha);} catch {}
        data ??= await downloadPinned(path,sha,lock);
        await writeFile(join(root,'cache',file),data,{flag:'wx'});
        receipt.verifiedAssets++;
      }));
      const rejected=batch.find(x=>x.status==='rejected');
      if(rejected) throw rejected.reason;
    }
    receipt.status='VERIFIED_STATIC_ONLY';
  } catch(error) {
    receipt.failure=String(error);
    process.exitCode=1;
  } finally {
    await writeFile(resolve(receiptPath),JSON.stringify(receipt,null,2)+'\n',{flag:'wx'});
    console.log(receipt.status, receipt.failure??'');
  }
}
if (process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  if(process.argv.length<4 || process.argv.length>5) throw Error('Wrong argument count');
  await mirror(process.argv.slice(2));
}
