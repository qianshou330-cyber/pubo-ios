"""Check native and backend evidence before assembling the release."""
import json
import re
import sys
from pathlib import Path

b=Path(sys.argv[1]).resolve()
def read(name):
    return json.loads((b/name).read_text('utf8'))
t=read('target.json')
for key in ['package', 'integration']:
    artifact=read(key+'.verified.json')
    metadata=read(key+'.github.json')
    assert artifact['productCommit']==metadata['commit']==t['sha']
    assert 'sha256:'+artifact['sha256']==metadata['digest'] and artifact['bytes']==metadata['size_in_bytes']
pack=read('package/device-package.json')
assert pack['commit']==t['sha'] and pack['status']=='PASS'
corelog=(b/'package/notification-core-test.log').read_text('utf8')
totals=re.findall(r'Executed (\d+) tests?, with (\d+) failures? \((\d+) unexpected\)',corelog)
assert totals and max(int(n) for n,_,_ in totals)>=95 and all(int(f)==int(u)==0 for _,f,u in totals)
pklog=(b/'package/notification-package-test.log').read_text('utf8')
assert re.search(r'Ran 6 tests\b',pklog) and re.search(r'^OK\s*$',pklog,re.M)
backend=read('integration/integration-result.json')
assert backend['status']=='PASS' and backend['productionAPIRequests']==0 and backend['ownerAPIAuthenticated']
summ=read('integration/integration-test-summary.json')
assert summ['passedTests']==summ['totalTestCount']==22 and summ['failedTests']==summ['skippedTests']==0
device=summ['devicesAndConfigurations'][0]['device']
assert device['modelName']=='iPhone 17 Pro Max' and device['osVersion']=='26.0.1'
cases=read('integration/individual-results.json')
assert any('testReadingNotificationsAndOpeningMentionLists' in s for s in cases)
contracts={}
for file in sorted((b/'integration').glob('integration-*-contract.json')):
    group=json.loads(file.read_text('utf8'))
    assert group['status']=='PASS' and group.get('productionAPIRequests',0)==0
    checks=group.get('checks',{})
    assert isinstance(checks,dict) and checks and all(value is True for value in checks.values()), file.name
    contracts[file.name]=list(checks)
assert len(contracts['integration-notifications-contract.json'])>=11
out=dict(product=t['sha'],build=t['build'],version=t['version'],core=max(int(n) for n,_,_ in totals),packageTests=6,realUITests=summ['passedTests'],device=device['modelName'],runtime=device['osVersion'],individualRealTests=list(cases),contracts=contracts,totalContractChecks=sum(map(len,contracts.values())),productionAPIRequests=0)
(b/'real-and-core-results.json').write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding='utf8')
print(json.dumps({k:v for k,v in out.items() if k not in ['contracts','individualRealTests']}))
