"""Collect proof on the GitHub runner. Large archives never leave the cloud."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener
from zipfile import ZipFile

root = Path(__file__).resolve().parent
build = root / 'build138'
build.mkdir(exist_ok=True)
target = json.loads((build / 'target.json').read_bytes())
commit = target['sha']
assert target['build'] == 138 and commit == '68aee1cadedae645a5f5823a5c062fdb296db56f'
repository = os.environ['GITHUB_REPOSITORY']
assert repository == 'qianshou330-cyber/pubo-ios'
api = 'https://api.github.com/repos/' + repository
runs = {'ui': 42990563590, 'integration': 42990563415}
names = {**{k:'notification-' + k + '-' + commit for k in ('large','small','preserved','package')},
         'integration':'native-backend-integration-' + commit}
destinations = {k: ('native-' + k if k in ('large','small','preserved') else k) for k in names}
class SafeRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        request = super().redirect_request(req, fp, code, msg, headers, newurl)
        if request and urlparse(req.full_url).hostname != urlparse(newurl).hostname:
            request.remove_header('Authorization')
        return request
opener = build_opener(SafeRedirect)
def get(url):
    headers = {'User-Agent': 'PUBO-notification-evidence', 'Accept': 'application/vnd.github+json'}
    if url.startswith(api + '/'): headers['Authorization'] = 'Bearer ' + os.environ['GH_TOKEN']
    return opener.open(Request(url, headers=headers), timeout=150)
def read(url):
    with get(url) as response: return json.load(response)
def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf8')
def sha(path):
    with path.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
def discover():
    items, states = {}, {}
    for kind, run in runs.items():
        info = read(api + '/actions/runs/' + str(run))
        assert info['head_sha'] == commit and info['id'] == run
        states[kind] = {k: info[k] for k in ('id','head_sha','status','conclusion','html_url')}
        for a in read(api + '/actions/runs/' + str(run) + '/artifacts?per_page=100')['artifacts']:
            suite = next((s for s, n in names.items() if n == a['name']), None)
            if suite is None: continue
            assert not a['expired'] and a['digest'].startswith('sha256:')
            assert (suite == 'integration') == (kind == 'integration')
            items[suite] = {**{k:a[k] for k in ('id','name','size_in_bytes','digest','created_at','expires_at')},
                'suite': suite, 'run_id':run, 'productCommit':commit, 'localRoot':destinations[suite],
                'localZip':destinations[suite]+'.zip',
                'url':f'https://github.com/{repository}/actions/runs/{run}/artifacts/{a["id"]}'}
    return items, states
def safe_extract(archive, output, force=False):
    with ZipFile(archive) as z:
        assert z.testzip() is None
        for info in z.infolist():
            p = PurePosixPath(info.filename)
            assert not p.is_absolute() and '..' not in p.parts and '\\' not in info.filename and ':' not in info.filename
            assert stat.S_IFMT(info.external_attr >> 16) != stat.S_IFLNK
        if force: z.extractall(output)
def acquire(item):
    path = build / item['localZip']; dest = build / item['localRoot']
    if not path.is_file():
        partial = path.with_suffix('.part')
        for attempt in range(3):
            try:
                with get(api + '/actions/artifacts/' + str(item['id']) + '/zip') as remote, partial.open('wb') as out:
                    shutil.copyfileobj(remote,out,1024*1024)
                assert partial.stat().st_size == item['size_in_bytes'] and 'sha256:'+sha(partial) == item['digest']
                partial.replace(path); break
            except (HTTPError, URLError, TimeoutError, OSError):
                if attempt == 2: raise
                time.sleep(6)
    checksum = sha(path)
    assert 'sha256:'+checksum == item['digest'] and path.stat().st_size == item['size_in_bytes']
    safe_extract(path, dest, force=True)
    item.update(verifiedSHA256=checksum, verifiedBytes=path.stat().st_size)
    suite = item['suite']
    if suite in ('large','small','preserved'):
        source = json.loads((dest/'integration-product-source.json').read_bytes())
        assert source['productCommit'] == source['testCommit'] == commit
        assert source['runtime'] == '26.0.1' and source['runtimeBuild'] == '23A8464'
        for name, blob in source['productTrees'].items():
            expected = subprocess.check_output(['git','rev-parse',commit+':'+name],text=True).strip()
            assert blob == expected
        assert source['fixtureSHA256'] == '02c140c8c3ab9c08232a8f74f46f424224fe6d3ff0b0e91c4df1e17ba260b33c'
        summaries = {}
        for file in dest.glob('*-summary.json'):
            data=json.loads(file.read_bytes())
            summaries[file.stem] = {k:data.get(k) for k in ('passedTests','failedTests','skippedTests','expectedFailures','result')}
        save(dest/'artifact-audit.json',{'source':source,'suite':suite,'testResults':summaries,'sha256':checksum,'bytes':path.stat().st_size})
    else:
        save(build/(suite+'.github.json'), {**item,'run':item['run_id'],'commit':commit})
        save(build/(suite+'.verified.json'), {'productCommit':commit,'sha256':checksum,'bytes':path.stat().st_size})
    print('Verified',suite, path.stat().st_size,checksum,flush=True)
def write_index(items, states):
    save(build/'source-artifacts.json',{'productCommit':commit,'workflows':runs,'states':states,'artifacts':list(items.values())})
def collect_summary():
    summary = build / 'cloud-summary'
    summary.mkdir(exist_ok=True)
    for item in [build/'source-artifacts.json',build/'target.json',build/'source-verification.json',build/'package-verification.json',
                 *build.glob('native-*/*-summary.json'),*build.glob('native-*/artifact-audit.json'),*build.glob('native-*/notification-*.json'),
                 *build.glob('native-*/timeline-environment-*.json'),*build.glob('integration/*-contract.json'),*build.glob('integration/integration-result.json')]:
        if not item.is_file() or item.stat().st_size>2*1024*1024: continue
        out=summary/item.relative_to(build);out.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(item,out)
def source_archive():
    path=build/'source.zip'
    if not path.is_file():
        with get(f'https://codeload.github.com/{repository}/zip/{commit}') as response, path.open('wb') as file:
            shutil.copyfileobj(response,file,1024*1024)
    expected= json.loads((build/'source-verification.json').read_bytes())
    assert expected['commit']==commit and expected['archiveSHA256']==sha(path)
    git_files={}
    for record in subprocess.check_output(['git','ls-tree','-rz','--full-tree',commit]).split(b'\0'):
        if not record:continue
        details,name=record.split(b'\t',1)
        git_files[name.decode()]=details.split()[-1].decode()
    checked=set()
    with ZipFile(path) as z:
        for item in z.infolist():
            if item.is_dir():continue
            part=PurePosixPath(item.filename)
            assert part.parts[0]=='pubo-ios-'+commit and '..' not in part.parts
            rel=PurePosixPath(*part.parts[1:]).as_posix();data=z.read(item)
            assert rel not in checked and hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()==git_files[rel]
            checked.add(rel)
    assert checked == set(git_files)
def ensure_results():
    shortfalls=[]
    for suite in ('large','small','preserved'):
        base=build/destinations[suite]
        audit=json.loads((base/'artifact-audit.json').read_bytes())
        if not audit['testResults'] or any(r['result']!='Passed' or r['failedTests'] or r['skippedTests'] for r in audit['testResults'].values()):
            shortfalls.append(suite+' UI')
        if suite in ('large','small'):
            for name,predicate in [('notification-refresh-count',lambda x:x=={'groupedReads':2,'responsesWithNewRow':1}),
                                   ('notification-visible-badge',lambda x:x.get('passes') is True and x.get('expected')=='12')]:
                f=base/(name+'.json')
                if not f.is_file() or not predicate(json.loads(f.read_bytes())): shortfalls.append(suite+' '+name)
    print('Verification gaps',shortfalls,flush=True)
    if shortfalls: raise SystemExit(3)
if __name__=='__main__':
    arg=argparse.ArgumentParser();arg.add_argument('action', choices=['discover','collect','summary','gate']);mode=arg.parse_args().action
    if mode=='summary':collect_summary()
    elif mode=='gate':ensure_results()
    else:
        if mode=='collect':source_archive()
        done={};deadline=time.monotonic()+65*60
        while True:
            items,states=discover()
            if mode=='collect':
                for key,item in items.items():
                    if key not in done: acquire(item);done[key]=item
                    else:items[key]=done[key]
            write_index(items,states)
            if mode=='discover' or len(done)==len(names): break
            if all(s['status']=='completed' for s in states.values()) or time.monotonic()>deadline:
                raise RuntimeError('Missing source artifacts: '+', '.join(sorted(set(names)-set(done))))
            time.sleep(40)
