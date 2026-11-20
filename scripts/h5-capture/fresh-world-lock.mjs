/** Pure manifest and public-path policy shared by acquisition and disconnected replay. */
import {join} from 'node:path';
import {ORIGIN,SOURCE,ROUTE,SHA,EXPECTED,digest,pinnedRead,cacheName} from './world-replay.mjs';
export const FRESH_SCOPE='FRESH_PUBLIC_H5_OBSERVED_SNAPSHOT';
export const CAP=160;
export const MAX_ROUNDS=8;
export const MAX_TOTAL_BYTES=96*1024*1024;
const HASH=/^[a-f0-9]{64}$/;
const COMMIT=/^[a-f0-9]{40}$/;
// Current observed generated names only, not a generic public-URL fetcher. Prefix is a
// Vite locale marker, NOT proof of one deployment. The root bytes bracket all batches.
const VITE=/^\/vite\/(?:zh-CN|assets)\/([A-Za-z0-9_]{8,24})-[A-Za-z0-9_-]{8}\.(?:js|css|woff2|woff|png|svg|webp|gif|ico)$/;
const SOURCE_GLOBALS=/^\s*const\s+VERSION\s*=\s*'[^'\\\r\n]{1,128}'\s*;\s*const\s+CLIENT_ENTRY\s*=\s*"scripts\/([A-Za-z0-9_]{8,24}-[A-Za-z0-9_-]{8}\.js)"\s*;\s*const\s+CLIENT_PRELOADS\s*=\s*\[/;
const CLIENT_ENTRY_EVIDENCE='PUBLIC_HTML_CLIENT_ENTRY_ZH_CN';
const icons=new Set(['/static-assets/pubo-white-660-v1.webp','/favicon.ico','/apple-touch-icon.png']);
export const allowedPath=(path,marker)=>typeof path==='string' && /^[A-Za-z0-9_]{8,24}$/.test(marker??'') && (VITE.exec(path)?.[1]===marker ||
  icons.has(path) || /^\/twemoji\/[a-f0-9]{2,8}(?:-[a-f0-9]{2,8}){0,6}\.svg$/.test(path));
function literalViteRefs(html) {
  const refs=[...new Set([...html.matchAll(/["'](\/vite\/(?:zh-CN|assets)\/[A-Za-z0-9_]+-[A-Za-z0-9_-]{8}\.[a-z0-9]+)["']/g)].map(m=>m[1]))].sort();
  return refs;
}

// Source-compatible production shell: classic inline globals + stylesheet links.
// Only map the one source-declared entry; never evaluate a script or seed preload
// arrays. All other scripts discovered by the disconnected browser keep the old policy.
function inlineClientEntry(html,refs,marker) {
  if(!refs.length || refs.length>=24 || refs.some(p=>!p.startsWith('/vite/assets/')||!p.endsWith('.css'))) return;
  const head=html.slice(0,1024*1024);
  const scan=/<!--[\s\S]*?-->|<(script|link|style|title|template|noscript)\b((?:[^"'<>]|"[^"]*"|'[^']*')*)>|<head>|<\/head\s*>/gi;
  let open=false,closed=false,entries=0,entry;
  const styles=new Set();
  for(let tag;(tag=scan.exec(head));) {
    if(!tag[1]) {
      if(tag[0].toLowerCase()==='<head>') {if(open)return;open=true;}
      if(/^<\/head/i.test(tag[0])) {closed=open;break;}
      continue;
    }
    const kind=tag[1].toLowerCase(), attrs=tag[2];
    if(kind==='link') {
      if(!open)continue;
      const rel=readTagAttrs(attrs), href=rel.get('href');
      if(rel.get('rel')?.toLowerCase().split(/\s+/).includes('stylesheet')) {
        if(!refs.includes(href) || styles.has(href))return;
        styles.add(href);
      }
      continue;
    }
    if(kind==='template'||kind==='noscript')return;
    const end=new RegExp('</'+kind+'\\s*>','gi');
    end.lastIndex=scan.lastIndex;
    const close=end.exec(head);
    if(!close)return;
    if(open&&kind==='script') {
      const fields=readTagAttrs(attrs);
      if(fields.has('src')||fields.get('type')?.toLowerCase()==='module') return;
      if(!fields.has('type') || /^(?:text|application)\/javascript$/i.test(fields.get('type'))) {
        const script=head.slice(scan.lastIndex,close.index);
        entries+=[...script.matchAll(/\bCLIENT_ENTRY\s*=(?!=)/g)].length;
        if(!attrs.trim()) entry=SOURCE_GLOBALS.exec(script)?.[1]??entry;
      }
    }
    scan.lastIndex=end.lastIndex;
  }
  if(!closed||styles.size!==refs.length||entries!==1||!entry)return;
  const localized='/vite/zh-CN/'+entry;
  if(VITE.exec(localized)?.[1]===marker) return localized;
}

export function seedPaths(html) {
  if(!/<script type="application\/json" id="misskey_meta"[^>]*>/.test(html) || !html.includes('<head>')) {
    throw Error('Root is not the expected public H5 bootstrap');
  }
  const refs=literalViteRefs(html);
  const boot=refs.filter(path=>path.startsWith('/vite/zh-CN/')&&path.endsWith('.js'));
  const markers=new Set(refs.map(path=>VITE.exec(path)?.[1]));
  if(refs.length>24 || markers.size!==1 || markers.has(undefined)) throw Error('Unrecognized or mixed H5 bootstrap path family');
  const [marker]=markers;
  if(boot.length)return {marker,refs};
  const clientEntry=inlineClientEntry(html,refs,marker);
  if(!clientEntry) throw Error('Unrecognized or mixed H5 bootstrap path family');
  return {marker,refs:[...refs,clientEntry].sort(),clientEntry};
}

function readTagAttrs(attributes) {
  const attrs=new Map();
  const tokens=/([^\s=/"'<>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  for(const [,key,dq,sq,uq] of attributes.matchAll(tokens)) {
    if(!attrs.has(key.toLowerCase())) attrs.set(key.toLowerCase(),dq??sq??uq??'');
  }
  return attrs;
}

// Bounded, intentionally narrow recognition of the pinned HTML generator.
// Latin-1 maps the prefix one-to-one to byte offsets even with UTF-8 content.
function renderStampSpans(body) {
  const head=body.toString('latin1',0,1024*1024);
  const prologue=/^\s*<!DOCTYPE html>\s*(?:<!--[\s\S]*?-->\s*)*<html>\s*<head>/i.exec(head);
  if(!prologue)return;
  const open=/<(script|link|meta|style|title)(?=[\s/>])((?:[^"'<>]|"[^"]*"|'[^']*')*)>/iy;
  const whitespace=/\s*/y;
  const stamp=/^<script type="application\/json" id="(misskey_(?:meta|clientCtx))" data-generated-at="([1-9][0-9]{12})">$/d;
  const slots=new Set(), spans=[];
  let i=prologue[0].length;
  while(i<head.length) {
    whitespace.lastIndex=i; whitespace.exec(head); i=whitespace.lastIndex;
    if(head.startsWith('</head>',i))return slots.has('misskey_meta')?spans:undefined;
    if(head.startsWith('<!--',i)) {
      const end=head.indexOf('-->',i+4);
      if(end<0)return;
      i=end+3;continue;
    }
    open.lastIndex=i;
    const item=open.exec(head);
    if(!item)return;
    const kind=item[1].toLowerCase();
    const raw=item[0], attributes=readTagAttrs(item[2]);
    const knownID=attributes.get('id')?.toLowerCase();
    if(knownID==='misskey_meta'||knownID==='misskey_clientctx') {
      const fixed=stamp.exec(raw);
      if(!fixed||slots.has(fixed[1]))return;
      slots.add(fixed[1]);
      spans.push({slot:fixed[1],start:i+fixed.indices[2][0],end:i+fixed.indices[2][1]});
    }
    i=open.lastIndex;
    if(kind==='script'||kind==='style'||kind==='title') {
      const close=new RegExp('</'+kind+'\\s*>','gi');
      close.lastIndex=i;
      if(!close.exec(head))return;
      i=close.lastIndex;
    }
  }
}

// Diagnostic only. Compare all bytes outside the recognized digit spans; no
// input is changed or serialized. Ambiguity and ANY unrelated change stay unknown.
export function classifyInitialRootDrift(first,second) {
  const unknown='ROOT_DIFF_UNCLASSIFIED';
  const a=renderStampSpans(first),b=renderStampSpans(second);
  if(!a||!b||a.length!==b.length||first.length!==second.length)return unknown;
  let offset=0, changed=false;
  for(let i=0;i<a.length;i++) {
    const x=a[i],y=b[i];
    if(x.slot!==y.slot||x.start!==y.start||x.end!==y.end||
       !first.subarray(offset,x.start).equals(second.subarray(offset,x.start)))return unknown;
    if(!first.subarray(x.start,x.end).equals(second.subarray(x.start,x.end)))changed=true;
    offset=x.end;
  }
  return changed&&first.subarray(offset).equals(second.subarray(offset))?
    'ROOT_DIFF_FIXED_RENDER_STAMPS_ONLY':unknown;
}

// Diagnostic only: none of these shape categories authorizes an asset. No
// input text, attribute value, path, prefix, meta field, or match is returned.
export function describeBootstrapShape(body) {
  const html=body.toString('utf8');
  const refs=literalViteRefs(html);
  const accepted=refs.map(path=>VITE.exec(path)?.[1]);
  const kinds={moduleScriptSrc:0,moduleScriptInline:0,classicScriptSrc:0,
    modulePreload:0,stylesheet:0,loaderScriptSrc:0,clientEntryInlineAssignment:0,
    clientEntryInlineScriptsShape:0};
  const pathKinds={rootRelativeZhCN:0,rootRelativeOtherLocale:0,rootRelativeScripts:0,rootRelativeAssets:0,
    absoluteSameOriginVite:0,queryOrFragment:0,other:0};
  const headScan=html.slice(0,1024*1024);
  const scan=/<!--[\s\S]*?-->|<(script|link)\b((?:[^"'<>]|"[^"]*"|'[^']*')*)>|<\/head\s*>/gi;
  const closeScript=/<\/script\s*>/gi;
  function countPath(value) {
    if(/[?#]/.test(value)) pathKinds.queryOrFragment++;
    else if(value.startsWith('/vite/zh-CN/')) pathKinds.rootRelativeZhCN++;
    else if(value.startsWith('/vite/scripts/')) pathKinds.rootRelativeScripts++;
    else if(value.startsWith('/vite/assets/')) pathKinds.rootRelativeAssets++;
    else if(/^\/vite\/[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})+\//.test(value)) pathKinds.rootRelativeOtherLocale++;
    else if(value.startsWith(SOURCE+'vite/')) pathKinds.absoluteSameOriginVite++;
    else pathKinds.other++;
  }
  let headEnd=false;
  for(let match;(match=scan.exec(headScan));) {
    if(!match[1]) {
      if(/^<\/head/i.test(match[0])) {headEnd=true;break;}
      continue;
    }
    const tag=match[1].toLowerCase();
    const attrs=readTagAttrs(match[2]);
    if(tag==='script') {
      const src=attrs.get('src');
      const module=attrs.get('type')?.trim().toLowerCase()==='module';
      if(src) {
        kinds[module?'moduleScriptSrc':'classicScriptSrc']++;
        if(/^(?:\/)?loader\/boot\.js(?:[?#].*)?$/.test(src)) kinds.loaderScriptSrc++;
        countPath(src);
      } else if(module) kinds.moduleScriptInline++;
      closeScript.lastIndex=scan.lastIndex;
      const end=closeScript.exec(headScan);
      if(!end) break;
      if(!src && (module || !attrs.get('type') || /^(?:text|application)\/javascript$/i.test(attrs.get('type')))) {
        const script=headScan.slice(scan.lastIndex,end.index);
        if(/\bCLIENT_ENTRY\s*=(?!=)/.test(script)) kinds.clientEntryInlineAssignment++;
        if(/\bCLIENT_ENTRY\s*=\s*['"]scripts\/[^"'\r\n]+['"]/.test(script)) kinds.clientEntryInlineScriptsShape++;
      }
      scan.lastIndex=closeScript.lastIndex;
    } else {
      const href=attrs.get('href');
      const rel=attrs.get('rel')?.toLowerCase().split(/\s+/)??[];
      if(rel.includes('modulepreload')) {kinds.modulePreload++;if(href)countPath(href);}
      if(rel.includes('stylesheet')) {kinds.stylesheet++;if(href)countPath(href);}
    }
  }
  const zhBoot=refs.filter(path=>path.startsWith('/vite/zh-CN/')&&path.endsWith('.js')).length;
  const unknownCount=accepted.filter(x=>x===undefined).length;
  const markerCount=new Set(accepted.filter(x=>x!==undefined)).size;
  const fixedHead=html.includes('<head>');
  const fixedMeta=/<script type="application\/json" id="misskey_meta"[^>]*>/.test(html);
  let verdict=!fixedHead||!fixedMeta?'MARKER_MISSING':'PATH_FAMILY_UNRECOGNIZED';
  if(fixedHead&&fixedMeta) {
    try {seedPaths(html);verdict='ACCEPTS_CURRENT_SHAPE';} catch {/* fixed enum only */}
  }
  return {probe:'H5_BOOTSTRAP_SHAPE_ONLY',htmlSHA256:digest(body),responseBytes:body.byteLength,verdict,
    fixedHead,fixedMeta,legacy:{uniqueQuotedRefs:refs.length,zhCNJsRefs:zhBoot,unknownCount,markerCount,overCap:refs.length>24},
    tagScan:headEnd?'HEAD_END':html.length>headScan.length?'BOUND_REACHED':'NO_HEAD_END',kinds,pathKinds};
}

export const assetEvidence=(path,round,clientEntry)=>round!==0?'ISOLATED_WORLD_GET_GAP':
  path===clientEntry?CLIENT_ENTRY_EVIDENCE:'PUBLIC_HTML_LITERAL';

export function checkFresh(m,{draft=false}={}) {
  if(m?.schema!==1 || m.scope!==FRESH_SCOPE || m.origin!==SOURCE || m.fixtureBaselineCommit!==SHA ||
    !COMMIT.test(m.candidateCommit??'') || !HASH.test(m.htmlSHA256??'') || !/^[A-Za-z0-9_]{8,24}$/.test(m.marker??'') ||
    m.status!==(draft?'DRAFT':'SEALED') || !Number.isInteger(m.round) || m.round<0 || m.round>MAX_ROUNDS ||
    !m.entries || Array.isArray(m.entries) || typeof m.entries!=='object' ||
    !Array.isArray(m.rootChecks) || m.rootChecks.length!==(m.round+1)*2+(draft?0:2) ||
    m.rootChecks.some(x=>!Number.isFinite(Date.parse(x?.at)) || x.sha256!==m.htmlSHA256)) throw Error('Invalid fresh manifest or stage');
  const paths=Object.keys(m.entries);
  if(!paths.length || paths.length>CAP) throw Error('Invalid fresh asset count');
  let total=0;
  for(const path of paths) {
    const row=m.entries[path];
    if(!allowedPath(path,m.marker) || !HASH.test(row?.sha256??'') || !Number.isInteger(row.bytes) || row.bytes<1 ||
      row.bytes>12*1024*1024 || row.observations!==2 || !Number.isInteger(row.round) || row.round<0 || row.round>m.round ||
        (row.evidence!==assetEvidence(path,row.round) && !(row.round===0 &&
          path.startsWith('/vite/zh-CN/') && path.endsWith('.js') && row.evidence===CLIENT_ENTRY_EVIDENCE))) {
      throw Error('Invalid fresh asset receipt: '+path);
    }
    total+=row.bytes;
  }
  if(total>MAX_TOTAL_BYTES) throw Error('Fresh static byte budget exceeded');
  if(!draft && (!HASH.test(m.probeSHA256??'') || !HASH.test(m.sealedFromDraftSHA256??'') || !Number.isFinite(Date.parse(m.sealedAt)))) {
    throw Error('Missing completed probe seal receipt');
  }
  return {...m,assets:Object.fromEntries(paths.map(path=>[path,m.entries[path].sha256]))};
}
export async function readFreshLock(snapshotRoot, expectedManifestSHA, {draft=false,round=0}={}) {
  if(!HASH.test(expectedManifestSHA??'') || !Number.isInteger(round) || round<0 || round>MAX_ROUNDS) throw Error('Need exact external manifest digest and bounded round');
  const filename=draft?'draft-'+round+'.json':'snapshot.sealed.json';
  const m=checkFresh(JSON.parse(await pinnedRead(join(snapshotRoot,filename),expectedManifestSHA,1024*1024)),{draft});
  if(draft && m.round!==round) throw Error('Draft round mismatch');
  const html=await pinnedRead(join(snapshotRoot,'public-home.html'),m.htmlSHA256);
  const seed=seedPaths(html.toString('utf8'));
  if(seed.marker!==m.marker || Object.values(m.entries).filter(row=>row.round===0).length!==seed.refs.length ||
     seed.refs.some(path=>m.entries[path]?.round!==0 || m.entries[path].evidence!==assetEvidence(path,0,seed.clientEntry))) {
    throw Error('Bootstrap asset closure does not match root');
  }
  return m;
}
export async function verifyLocalAssetTree(dir,lock) {
  for(const [path,entry] of Object.entries(lock.entries)) {
    const bytes=await pinnedRead(join(dir,'cache',cacheName(path)),entry.sha256);
    if(bytes.length!==entry.bytes) throw Error('Fresh asset size mismatch: '+path);
  }
}
export function acceptedProbe(report,lock,sha,{seal=false}={}) {
  const ns=report?.networkNamespace;
  if(report?.referenceScope!==FRESH_SCOPE || report?.discoveryOnly!==true || report.pairEligible!==false ||
    report?.candidateCommit!==lock.candidateCommit || report?.fresh?.manifestSHA256!==sha ||
    report?.fresh?.htmlSHA256!==lock.htmlSHA256 || report?.fresh?.round!==lock.round ||
    !/^net:\[\d+\]$/.test(ns?.host??'') || !/^net:\[\d+\]$/.test(ns?.replay??'') || ns.host===ns.replay ||
    report.status!==(seal?'DISCOVERY_CONVERGED':'DISCOVERY_REQUIRED') || !Array.isArray(report.cases) ||
    report.cases.length!==4 || report.cases.some(c=>c.screenshot || !Array.isArray(c.deniedRequests) ||
      !Object.hasOwn(EXPECTED,c.slot) || Object.entries(EXPECTED[c.slot]).some(([k,v])=>c.size?.[k]!==v))) {
    throw Error('Probe is not the exact screenshotless draft/session');
  }
  const tuples=report.cases.map(c=>[c.slot,c.theme].join('/'));
  if(new Set(tuples).size!==4 || tuples.some(x=>!['small/light','small/dark','large/light','large/dark'].includes(x))) {
    throw Error('Probe profile/theme mismatch');
  }
  const misses=report.cases.flatMap(c=>c.deniedRequests);
  if(seal) {
    if(misses.length||report.cases.some(c=>c.passed!==true || c.errors?.length!==0 ||
      c.viewport?.width!==c.size.width || c.viewport?.height!==c.size.height || c.viewport?.dpr!==2 ||
      c.timeline?.[0]?.path!==ROUTE || c.timeline[0].untilId!==null || c.timeline[0].ids?.[0]!=='at4tltest0025' ||
      Object.keys(c.assets??{}).filter(x=>x.endsWith('.js')).length<2 ||
      Object.entries(c.assets).some(([path,h])=>lock.assets[path]!==h))) throw Error('Probe did not exercise all four exact cases');
    return [];
  }
  if(!misses.length || misses.some(x=>x.reason!=='STATIC_PATH_UNATTESTED' || x.origin!==ORIGIN ||
      !allowedPath(x.path,lock.marker) || Object.hasOwn(lock.assets,x.path))) throw Error('Probe contains non-static or inadmissible missing paths');
  return [...new Set(misses.map(x=>x.path))].sort();
}
export function canonicalJSON(value){return JSON.stringify(value,null,2)+'\n';}
export const hashManifest=value=>digest(canonicalJSON(value));
