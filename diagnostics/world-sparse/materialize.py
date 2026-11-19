"""Only writes to a new detached git-archive source tree, never to the input checkout."""
import hashlib,json,subprocess,shutil,tempfile,pathlib
from pathlib import Path
BASE='c8227e6bceb62129c018b9b3f70f5c9324a01782'
P=Path(__file__).resolve().parent
REL=['App/Features/TimelineView.swift','App/Infrastructure/FixtureTransport.swift',
     'App/Infrastructure/StreamClient.swift','Sources/PUBOCore/TimelineState.swift']
PIN=['3472342fb7da16f1b845e3a14809750d017a92ca','0d92db08d97d274da2de3b494072a093327c16a4',
     'a9238979af9444e9932ec55786989af3dc08d501','35897552813bb69d84bc0afed42f7b4e91c60d58']
def gitblob(b):return hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
def one(s,a,b):
    if s.count(a)!=1:raise ValueError('Pinned injection point missing/ambiguous: '+a[:80])
    return s.replace(a,b,1)
def wrapped(code):
    return '\n#if DEBUG && PUBO_SPARSE_WORLD_PROBE\n'+code+'\n#endif\n'
def instrument(root):
    src=[(root/f).read_bytes() for f in REL]
    if [gitblob(s) for s in src]!=PIN:raise ValueError('Pinned App/Core sources mismatch')
    timeline,fixture,stream,core=[s.decode() for s in src]
    timeline=one(timeline,'    @State private var feed = TimelineState()', '    @State private var feed = TimelineState()'+wrapped('    @State private var sparseWindowReady = false'))
    timeline=one(timeline,'.onChange(of: active) { _, value in','.onChange(of: active) { _, value in'+wrapped('                    if !value { SparseObserver.saveInactive() }'))
    timeline=one(timeline,'.accessibilityIdentifier("world.more")','.accessibilityIdentifier("world.more")'+wrapped('                .accessibilityValue(sparseWindowReady ? "sparse-ready" : "sparse-warming")'))
    timeline=one(timeline,'        guard abs(value.translation.width)',wrapped('        SparseObserver.drag(value.translation,ctx:context)')+'        guard abs(value.translation.width)')
    mark='                    await load()\n    }\n    private func appeared'
    timeline=one(timeline,mark,wrapped('                    let firstContext = context')+'                    await load()'+wrapped('''                    if session.testMode, !session.isolatedBackend, session.user?.id == "syntheticself",
                       firstContext == context, SparseObserver.start(context), SparseObserver.mergedPage(feed,context) {
                        for _ in 0..<9 {
                            guard !Task.isCancelled, firstContext==context, error==nil, hasMore else { return }
                            await load(older:true)
                            guard !Task.isCancelled, firstContext==context, SparseObserver.mergedPage(feed,context) else { return }
                        }
                        sparseWindowReady = SparseObserver.ready
                    }''')+'    }\n    private func appeared')
    mark='    private func captureVisibleAfterRowChange() { session.stream.captureNotes(active ? feed.capturedIDsForVisibilityChange(visibleIDs: visibleIDs) : []) }'
    timeline=one(timeline,mark,'    private func captureVisibleAfterRowChange() {'+wrapped('''        SparseObserver.enter(feed, visibleIDs, active, context)
        defer { SparseObserver.leave() }''')+'        session.stream.captureNotes(active ? feed.capturedIDsForVisibilityChange(visibleIDs: visibleIDs) : [])\n    }')
    mark='posts = TimelineTestFixtures.posts; announcements ='
    fixture=one(fixture,mark,'posts = TimelineTestFixtures.posts;'+wrapped('            if SparseFixture.enabled { posts = SparseFixture.posts() }')+'            announcements =')
    mark='                    response = TimelineTestFixtures.page2Response(response, body: body.object, path: path, sawSeed: &page2PosterSawSeed)\n                }'
    fixture=one(fixture,mark,mark+wrapped('                SparseFixture.didServe(path:path,body:body,result:response)'))
    mark='        if ids.isEmpty { captureOwners.removeValue(forKey: owner) } else { captureOwners[owner] = ids }'
    stream=one(stream,mark,mark+wrapped('        SparseObserver.received(ids,stored:captureOwners[owner] ?? [],owner:owner)'))
    # SwiftPM debug builds define DEBUG. This intermediate source exists ONLY in this disposable instrumented tree.
    for case,expr in [('binary','experimentalCapturedIDs(visibleIDs: visibleIDs)'),('filter','TimelinePresentation.capturedIDs(notes.filter { visibleIDs.contains($0.id) })')]:
        a='case .'+case+': return '+expr
        b='case .'+case+':\n#if DEBUG\n            if Thread.current.threadDictionary["pubo.sparse.arm"] != nil { Thread.current.threadDictionary["pubo.sparse.branch"] = "'+case+'" }\n#endif\n            return '+expr
        core=one(core,a,b)
    data=dict(zip(REL,[x.encode() for x in (timeline,fixture,stream,core)]))
    for f,part in [('App/Infrastructure/SparseProbe.swift','SparseProbe.swift.inc'),('UITests/SparseWorldUITests.swift','SparseWorldUITests.swift.inc')]:
        if (root/f).exists():raise ValueError('Probe source already exists')
        data[f]=(P/part).read_bytes()
    return data
def write_variant(root):
    # Caller only passes its fresh temporary archive; all replacement anchors checked before writing.
    data=instrument(root);manifest={}
    import difflib
    diff=[]
    for rel,b in sorted(data.items()):
        f=root/rel;old=f.read_bytes() if f.exists() else b''
        diff.extend(difflib.unified_diff(old.decode().splitlines(keepends=True),b.decode().splitlines(keepends=True),
                                        'a/'+rel if f.exists() else '/dev/null','b/'+rel))
        f.write_bytes(b);manifest[rel]={'originalBlob':gitblob(old) if old else None,'instrumentedBlob':gitblob(b)}
    return manifest,''.join(diff)
def archive(repo,root):
    # git-archive export of the exact immutable commit, not copying a dirty checkout. No networking.
    if root.exists():raise ValueError('Variant destination already exists')
    root.mkdir()
    with tempfile.TemporaryFile() as tar:
        subprocess.run(['git','-C',str(repo),'archive','--format=tar',BASE],stdout=tar,check=True)
        tar.seek(0);subprocess.run(['tar','-xf','-','-C',str(root)],stdin=tar,check=True)
