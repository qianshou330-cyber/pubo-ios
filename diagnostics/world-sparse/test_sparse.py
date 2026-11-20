"""Offline contracts/negative controls, not native test results. Set SPARSE_BASELINE for source checks."""
import copy,json,os,sys,tempfile,unittest
from pathlib import Path
import materialize as mat
from verify import verify,seq

def fixtures():
    ids=seq(200)
    def event(i,t,outer,prev):
        keys=sorted(outer|{'w80-shared','w80-leaf'}) if outer else []
        return {'i':i,'t':t,'branch':('binary' if 1<=len(outer)<=8 else 'filter'),'outer':sorted(outer),
                'added':sorted(outer-prev) if prev is not None else [],'removed':sorted(prev-outer) if prev is not None else [],
                'input':keys.copy(),'stored':keys.copy(),'oracle':keys.copy()}
    t=['w80-0200','w80-0199','w80-0198','w80-0197'];groups=[set(t[:2]),set(t[:3]),set(t[1:3]),set(t[1:4])]
    events=[event(i+1,when,group,groups[i-1] if i else None) for i,(when,group) in enumerate(zip([5,11,12,15],groups))]
    n='097DFBC0-49CB-49CB-B393-10240F678BC0'
    r={'schema':1,'nonce':n,'scope':'instrumented synthetic simulator only','ready':True,'invalid':False,'recordedAt':20,
       'drags':[11.2,15.7],'events':events,'merged':[{'count':k,'oldest':ids[k-1]} for k in range(20,201,20)],
       'pages':[{'cursor':ids[i-1] if i else '', 'ids':ids[i:i+20]} for i in range(0,200,20)]}
    g={'nonce':n,'baselineEnd':8,'drags':[[10,13],[14,16]],'end':18,'flush':{'requested':18.5,'checked':21,'ack':True},
       'before':{'note.open.w80-0200':220},'after':{'note.open.w80-0198':250}}
    return r,g

class Evidence(unittest.TestCase):
    def test_direct_branch_and_exact_received_set(self):
        r,g=fixtures();v=verify(r,g);self.assertEqual(v['observedChangesInBinaryBranch'],[2,3,4])
        self.assertEqual(v['retainedSharedReferenceAfterRemoval'],[3])
        self.assertEqual(v['status'],'EXERCISED_SYNTHETIC')
    def test_wrong_or_mutually_agreeing_incorrect_nested_output_rejected(self):
        for select in [('input',),('stored',),('oracle',),('input','stored','oracle')]:
            r,g=fixtures()
            for f in select:r['events'][2][f].remove('w80-leaf')
            with self.assertRaises(ValueError):verify(r,g)
    def test_durable_ack_and_nonce_matched_post_home_bytes_are_both_required(self):
        for issue in ('missing', 'timeout', 'wrongnonce', 'during-gestures','stale','replaced','nonfinite'):
            r,g=fixtures()
            if issue=='missing':del g['flush']
            if issue=='timeout':g['flush']['ack']=False
            if issue=='wrongnonce':g['nonce']='EA96A767-05E2-48C6-9502-E12C447C1307'
            if issue=='during-gestures':g['flush']['requested']=12
            if issue=='stale':r['recordedAt']=18.1
            if issue=='replaced':r['recordedAt']=21.1
            if issue=='nonfinite':g['flush']['checked']=float('nan')
            with self.subTest(issue=issue),self.assertRaises(ValueError):verify(r,g)

    def test_generation_and_pages(self):
        for typ in ['nonce','invalid','wrongcursor','dup','missing','wrongdepth','newgeneration']:
            r,g=fixtures()
            if typ=='nonce':g['nonce']='new'
            elif typ=='wrongcursor':r['pages'][2]['cursor']=r['pages'][1]['cursor']
            elif typ=='dup':r['pages'][1]['ids'][-1]=r['pages'][0]['ids'][0]
            elif typ=='missing':r['pages'].pop()
            elif typ=='wrongdepth':r['merged'][8]['count']=179
            elif typ=='newgeneration':r['ready']=False
            else:r['invalid']=True
            with self.subTest(typ=typ),self.assertRaises(ValueError):verify(r,g)
    def test_abstain_no_hit_during_gestures(self):
        r,g=fixtures();r['events']=r['events'][:1]
        self.assertEqual(verify(r,g)['status'],'UNEXERCISED')
        r['events']=[];self.assertEqual(verify(r,g)['status'],'UNEXERCISED')
    def test_do_not_truncate_dense_visible_sets(self):
        r,g=fixtures();o=sorted(seq(9));keys=sorted(o+['w80-shared','w80-leaf'])
        e={'i':1,'t':11.5,'outer':o,'added':[],'removed':[],'branch':'filter','input':keys,'stored':keys,'oracle':keys}
        r['events']=[e];self.assertEqual(verify(r,g)['status'],'UNEXERCISED')
        e['branch']='binary'
        with self.assertRaises(ValueError):verify(r,g)
    def test_missing_actual_arm_gesture_wrong_route_and_dup(self):
        for typ in ('actual','timing','no-movement','double','preflight','late','nonce','unknown'):
            r,g=fixtures()
            if typ=='actual':r['events'][1]['branch']='unobserved'
            if typ=='timing':r['drags'][1]=12
            if typ=='no-movement':g['after']=g['before']
            if typ=='double':r['drags'].append(16)
            if typ=='preflight':r['recordedAt']=7
            if typ=='late':r['events'][3]['t']=26
            if typ=='nonce':g['nonce']='39D9AA53-85D5-4E35-BDD9-B82BFF1DF50E'
            if typ=='unknown':r['events'][1]['outer'][0]='genuine-data'
            with self.subTest(typ=typ),self.assertRaises(ValueError):verify(r,g)

class Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root=Path(os.environ.get('SPARSE_BASELINE',Path(__file__).resolve().parents[2]))
        cls.src=mat.instrument(cls.root)
    def test_six_variant_files_only(self):
        self.assertEqual(set(self.src),set(mat.REL)|{'App/Infrastructure/SparseProbe.swift','UITests/SparseWorldUITests.swift'})
        for p in ['.github/workflows/four-tabs.yml','project.yml','scripts/ui_selection.py','scripts/test_visibility_capture_integration.py']:
            self.assertNotIn(p,self.src)
    def test_scope_native_row_and_ordinary_merge_order(self):
        s=self.src[mat.REL[0]].decode();orig=(self.root/mat.REL[0]).read_text()
        self.assertIn('for _ in 0..<9',s); self.assertIn('await load(older:true)',s)
        self.assertIn('firstContext==context, SparseObserver.mergedPage(feed,context)',s)
        for x in ['session.stream.captureNotes(active ? feed.capturedIDsForVisibilityChange(visibleIDs: visibleIDs) : [])',
                  '.onAppear { appeared(note, index: index) }',
                  '.onDisappear { visibleIDs.remove(note.id); captureVisibleAfterRowChange() }',
                  'fields["limit"] = .number(20)','feed.page(result, older: older, preferences: selected, accountID: session.user?.id)']:
            self.assertEqual(s.count(x),orig.count(x));self.assertGreater(s.count(x),0)
        self.assertNotIn('visibleIDs.prefix(',s);self.assertNotIn('visibleIDs = Set(',s.replace('@State private var visibleIDs = Set',''))
    def test_marks_inside_real_switch_and_as_actual_owner(self):
        s=self.src[mat.REL[3]].decode()
        for case,ret in [('binary','experimentalCapturedIDs(visibleIDs: visibleIDs)'),('filter','TimelinePresentation.capturedIDs(notes.filter { visibleIDs.contains($0.id) })')]:
            chunk=s.split('case .'+case+':',1)[1].split('return '+ret,1)[0]
            self.assertIn('threadDictionary["pubo.sparse.branch"] = "'+case+'"',chunk)
        stream=self.src[mat.REL[2]].decode()
        self.assertLess(stream.index('captureOwners[owner] = ids'),stream.index('SparseObserver.received(ids,stored:captureOwners[owner] ?? [],owner:owner)'))
        self.assertLess(stream.index('SparseObserver.received'),stream.index('let next = Set(captureOwners'))
    def test_nonce_ack_emitted_only_after_atomic_save_and_wait_registered_before_home(self):
        s=self.src['App/Infrastructure/SparseProbe.swift'].decode().split('static func saveInactive()',1)[1]
        self.assertLess(s.index('try bytes.write'),s.index('options:.atomic)'))
        self.assertLess(s.index('options:.atomic)'),s.index('CFNotificationCenterPostNotification('))
        self.assertNotIn('CFNotificationCenterPostNotification(',s.split('} catch',1)[1])
        u=self.src['UITests/SparseWorldUITests.swift'].decode()
        self.assertIn('"com.bolubo.native.sparse.flush." + SparseFixture.nonce',s)
        self.assertIn('"com.bolubo.native.sparse.flush." + nonce',u)
        ordered=['shot(app,"sparse-after")','XCTDarwinNotificationExpectation(','let requested = now','XCUIDevice.shared.press(.home)',
                 'XCTWaiter.wait(for:[durable],timeout:15)','let verifiedBy = now','a.name="sparse-gestures"','XCTAssertEqual(result,.completed']
        self.assertEqual([u.index(x) for x in ordered],sorted(u.index(x) for x in ordered))
        self.assertNotIn('runningBackground',u)
        host=(Path(__file__).parent/'run.py').read_text()
        self.assertIn("receipts[0].name=='pubo-sparse-'+g['nonce']+'.json'",host)
        self.assertIn("rc==0 and common.counts(summary,True)",host)

    def test_synthetic_only_and_two_real_drags(self):
        s=self.src['App/Infrastructure/SparseProbe.swift'].decode();u=self.src['UITests/SparseWorldUITests.swift'].decode()
        for x in ['a.contains("--ui-testing")','a.contains("--timeline-align")','!a.contains("--isolated-backend")',
                  's.oracle','context == nil','events.count < 384','SparseFixture.ids(count)','SparseFixture.pageReceipt()']:
            self.assertIn(x,s)
        for x in ['for _ in 0..<2','start.press(forDuration:0.05,thenDragTo:end)','puboSnapshotDescendants(try app.snapshot())','XCUIDevice.shared.press(.home)']:
            self.assertIn(x,u)
        for x in ['scrollTo(', 'sleep(', 'setContentOffset','XCTSkip']:self.assertNotIn(x,u)
