import pathlib,json
expected='2de3a496eaf6df9a1312862adcfd54acd73c39c0'
files=list(pathlib.Path('PUBO.xcodeproj').rglob('Package.resolved'))
assert files,'Missing package resolution receipt'
pins=[p for f in files for p in json.loads(f.read_text())['pins'] if p['identity']=='sdwebimage']
assert pins and all(p['state']['revision']==expected for p in pins),pins
pathlib.Path('build/image-dependency.json').write_text(json.dumps({'name':'SDWebImage','release':'5.21.7','revision':expected,'resolved':True,'api':'SDAnimatedImage(data:scale:options:) + SDAnimatedImageView; no URL loader/cache'},indent=2))
print('Pinned native GIF dependency verified')
