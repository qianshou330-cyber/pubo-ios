import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createServer } from 'node:http';
import { randomBytes, randomUUID } from 'node:crypto';

if (process.env.GITHUB_ACTIONS !== 'true' || process.env.NODE_ENV !== 'test') throw new Error('Disposable test runner required');
const root = join(process.env.RUNNER_TEMP, 'pubo-isolated-backend/packages/backend');
process.chdir(root);
process.env.MISSKEY_VERIFICATION_ENCRYPTION_KEY=randomBytes(32).toString('hex');
const { loadConfig } = await import(pathToFileURL(join(root, 'built/config.js')));
const config = loadConfig();
if (config.url !== 'http://127.0.0.1:61812' || config.db.db !== 'pubo_native_integration' || config.db.host !== '127.0.0.1' || config.redis.host !== '127.0.0.1' || config.nativePush?.enabled) throw new Error('Unsafe integration configuration');
const harness = await import(pathToFileURL(join(root, 'built-test/entry.js')));
await harness.setup();
async function api(path, fields={}, token) {
 const response=await fetch('http://127.0.0.1:61812/api/'+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...fields,...(token?{i:token}:{})})});
 const text=await response.text();const value=text?JSON.parse(text):null;
 if(!response.ok)throw new Error('Synthetic setup failed: '+path+' '+response.status+' '+(value?.error?.code??''));
 return value;
}
// The first account owns the isolated instance. The App uses the second, ordinary account.
await api('signup',{username:'isolated_owner',password:randomBytes(24).toString('hex')});
const alice=await api('signup',{username:'native_alice',password:randomBytes(24).toString('hex')});
const bob=await api('signup',{username:'native_bob',password:randomBytes(24).toString('hex')});
await api('i/update',{name:'原生验收用户',chatScope:'mutual'},alice.token);
await api('i/update',{name:'隔离测试朋友',chatScope:'mutual'},bob.token);
const note=await api('notes/create',{text:'PUBO joint proof #PUBO',visibility:'public'},alice.token);
const poll=await api('notes/create',{text:'真实接口投票',visibility:'public',poll:{choices:['Morning','Evening'],multiple:false}},bob.token);
await api('following/create',{userId:bob.id},alice.token);
await api('following/create',{userId:alice.id},bob.token);
const received=await api('chat/messages/create-to-user',{toUserId:alice.id,text:'真实隔离后端私信',clientMessageId:randomUUID()},bob.token);
const sent=await api('chat/messages/create-to-user',{toUserId:bob.id,text:'原生编辑验收',clientMessageId:randomUUID()},alice.token);
const context={token:alice.token,userId:alice.id,peerId:bob.id,noteId:note.createdNote.id,pollId:poll.createdNote.id,receivedId:received.id,sentId:sent.id};
// Loopback-only ephemeral credentials; never logged, written to artifacts, or sent to production.
const control=createServer(async(req,res)=>{
 try {
  if(req.method==='GET'&&req.url==='/context'){res.setHeader('content-type','application/json');res.end(JSON.stringify(context));return;}
  if(req.method==='GET'&&req.url==='/proof'){
   const favorites=await api('i/favorites',{limit:100},alice.token);
   const vote=await api('notes/show',{noteId:poll.createdNote.id},alice.token);
   const message=await api('chat/messages/show',{messageId:sent.id},alice.token);
   res.setHeader('content-type','application/json');res.end(JSON.stringify({favorite:favorites.some(x=>x.note.id===note.createdNote.id),voted:vote.poll.choices.some(x=>x.isVoted),edited:message.text?.includes('Edited'),recalled:message.recalledAt!=null}));return;
  }
  res.writeHead(404);res.end();
 }catch{res.writeHead(500);res.end('Synthetic control failed');}
});
await new Promise(resolve=>control.listen(61913,'127.0.0.1',resolve));
console.log('Isolated native integration ready; synthetic credentials remain in memory.');
process.on('SIGTERM',async()=>{control.close();await harness.teardown();process.exit(0);});
