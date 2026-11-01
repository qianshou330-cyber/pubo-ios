"""Build the pinned PUBO backend plus reviewed overlay on a disposable CI runner."""
import hashlib,json,os,pathlib,subprocess,tarfile,urllib.request

if os.environ.get('GITHUB_ACTIONS')!='true':raise SystemExit('Disposable GitHub runner required')
base=pathlib.Path(os.environ['RUNNER_TEMP']).resolve()
root=base/'pubo-isolated-backend'
assert not root.exists()
archive=base/'pubo-pinned-source.tar.gz'
urllib.request.urlretrieve('https://bolubo.com/tarball/pubo-home-first-visit-20261031-v4-source.tar.gz',archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='a55531964027c23f29651252e534084b0ebad7ea9b56e0d161e14380d7e09a57'
root.mkdir()
with tarfile.open(archive) as source:
 members=source.getmembers()
 # The signed inventory records the archive's top-level source prefix.
 prefixes={m.name.split('/')[0] for m in members if m.name.strip('./')}
 prefix=next(iter(prefixes)) if len(prefixes)==1 else None
 for member in members:
  if not member.isfile():continue
  name=member.name[len(prefix)+1:] if prefix and member.name.startswith(prefix+'/') else member.name
  target=(root/name).resolve()
  assert target.is_relative_to(root)
  if any(p in target.relative_to(root).parts for p in ['.config','.git','node_modules']):continue
  target.parent.mkdir(parents=True,exist_ok=True)
  target.write_bytes(source.extractfile(member).read())
overlay=json.loads(pathlib.Path('scripts/isolated/backend-overlay.json').read_text())
for item in overlay['files']:
 target=(root/item['path']).resolve();assert target.is_relative_to(root)
 assert item['path'].startswith(('packages/backend/','packages/misskey-js/'))
 if item['before'] is not None:assert hashlib.sha256(target.read_bytes()).hexdigest()==item['before']
 else:assert not target.exists()
 content=item['content'].encode();assert hashlib.sha256(content).hexdigest()==item['after']
 target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
(root/'.config').mkdir()
config='url: http://127.0.0.1:61812\nport: 61812\nsetupPassword: synthetic-runner-only\ndb:\n  host: 127.0.0.1\n  port: 54312\n  db: pubo_native_integration\n  user: '+os.environ['USER']+'\n  pass: ""\n  disableCache: true\nredis:\n  host: 127.0.0.1\n  port: 56312\nid: aidx\nclusterLimit: 1\nenableIpRateLimit: false\n'
for name in ['default.yml','test.yml']:(root/'.config'/name).write_text(config)
subprocess.run(['pnpm','install','--frozen-lockfile'],cwd=root,check=True)
subprocess.run(['pnpm','--filter','misskey-js','build'],cwd=root,check=True)
subprocess.run(['pnpm','build-misskey-js-with-types'],cwd=root,check=True)
subprocess.run(['pnpm','--filter','backend','build:e2e'],cwd=root,check=True)
subprocess.run(['pnpm','--filter','backend','compile-config'],cwd=root,check=True)
subprocess.run(['node','node_modules/typeorm/cli.js','migration:run','-d','ormconfig.js'],cwd=root/'packages/backend',check=True)
pathlib.Path('build').mkdir(exist_ok=True)
pathlib.Path('build/integration-backend-source.json').write_text(json.dumps({'status':'PASS','baseSourceSHA256':hashlib.sha256(archive.read_bytes()).hexdigest(),'overlay':overlay['sha256'],'productionAPIRequests':0},indent=2))
print('Pinned isolated backend built; no production configuration loaded.')
