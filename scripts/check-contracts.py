"""Read current PUBO source contracts without changing the website checkout."""
import argparse
import hashlib
import json
import pathlib
import re

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=pathlib.Path, required=True)
parser.add_argument('--schema', type=pathlib.Path, required=True)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
doc = json.loads(args.schema.read_text(encoding='utf-8'))
paths = doc['paths']
checks = []
required = {
    'chat/messages/create-to-user': ['toUserId', 'clientMessageId', 'attachmentIds', 'replyToId'],
    'chat/messages/user-timeline': ['userId', 'sinceDate', 'sinceId', 'untilId'],
    'chat/messages/read': ['userId', 'messageIds'],
    'chat/conversation-settings/update': ['userId', 'pinned', 'isMuted'],
    'notes/create': ['text', 'fileIds', 'visibility', 'replyId', 'renoteId', 'cw'],
    'i/update': ['chatScope', 'name', 'description'],
    'users/search': ['query', 'origin'],
    'i/delete-account': ['password', 'token'],
}
for endpoint, fields in required.items():
    operation = paths['/' + endpoint]['post']
    schemas = [content['schema'] for content in operation['requestBody']['content'].values()]
    found = set().union(*(set(schema.get('properties', {})) for schema in schemas))
    assert set(fields) <= found, f'Contract fields missing: {endpoint}'
    checks.append(endpoint)
private = args.source / 'packages/backend/src/server/ChatAttachmentServerService.ts'
private_text = private.read_text(encoding='utf-8')
assert "url: '/api/chat/attachments/:id/:variant'" in private_text
assert "['original', 'preview', 'download']" in private_text
assert "startsWith('Bearer ')" in private_text
assert "Cache-Control', 'private, no-store'" in private_text
checks.append('private-media-auth-and-variants')
stream = args.source / 'packages/backend/src/server/api/StreamingApiServerService.ts'
assert "authorization?.startsWith('Bearer ')" in stream.read_text(encoding='utf-8')
checks.append('websocket-bearer-header')
router = (args.source / 'packages/backend/src/server/api/ApiServerService.ts').read_text(encoding='utf-8')
assert "('/signin-flow'," in router and "('/signup'," in router and "'/signup/request-phone-code'" in router
checks.append('native-signin-flow-signup-routes')
report = {'status': 'PASS', 'checks': checks, 'schemaSha256': hashlib.sha256(args.schema.read_bytes()).hexdigest(), 'privateMediaSourceSha256': hashlib.sha256(private.read_bytes()).hexdigest(), 'streamingSourceSha256': hashlib.sha256(stream.read_bytes()).hexdigest()}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps({'status': 'PASS', 'checks': len(checks)}))
