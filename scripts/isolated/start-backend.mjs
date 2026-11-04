import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { createServer } from 'node:http';
import { writeFile } from 'node:fs/promises';
import { writeFileSync } from 'node:fs';
import { randomBytes, randomUUID } from 'node:crypto';
import { verifyAdminContracts } from './admin-contract.mjs';
import { prepareVerificationFixture, verifyExtendedContracts } from './extended-contract.mjs';
import { verifyChatContracts } from './chat-contract.mjs';
import { setupAuthChannels, verifyAuthContracts } from './auth-contract.mjs';

if (process.env.GITHUB_ACTIONS !== 'true' || process.env.NODE_ENV !== 'test') throw new Error('Disposable test runner required');
let startupPhase='initialization';
process.on('uncaughtExceptionMonitor',error=>{writeFileSync(join(process.env.GITHUB_WORKSPACE,'build/integration-startup-failure.json'),JSON.stringify({status:'FAIL',phase:startupPhase,errorType:error.name,productionAPIRequests:0}));});
const root = join(process.env.RUNNER_TEMP, 'pubo-isolated-backend/packages/backend');
process.chdir(root);
process.env.MISSKEY_VERIFICATION_ENCRYPTION_KEY=randomBytes(32).toString('hex');
await prepareVerificationFixture();
const { loadConfig } = await import(pathToFileURL(join(root, 'built/config.js')));
const config = loadConfig();
if (config.url !== 'http://127.0.0.1:61812' || config.db.db !== 'pubo_native_integration' || config.db.host !== '127.0.0.1' || config.redis.host !== '127.0.0.1' || config.nativePush?.enabled) throw new Error('Unsafe integration configuration');
const harness = await import(pathToFileURL(join(root, 'built-test/entry.js')));
startupPhase='test-outbound-channels';
const authChannels = await setupAuthChannels(root);
startupPhase='backend-setup';
await harness.setup();
async function api(path, fields={}, token) {
 const response=await fetch('http://127.0.0.1:61812/api/'+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...fields,...(token?{i:token}:{})})});
 const text=await response.text();const value=text?JSON.parse(text):null;
 if(!response.ok)throw new Error('Synthetic setup failed: '+path+' '+response.status+' '+(value?.error?.code??''));
 return value;
}
// The first account owns the isolated instance. The App uses the second, ordinary account.
const ownerPassword=randomBytes(24).toString('hex');
const owner=await api('signup',{username:'isolated_owner',password:ownerPassword});
startupPhase='authentication-contract';
await verifyAuthContracts(api,owner,authChannels,root,join(process.env.GITHUB_WORKSPACE,'build/integration-auth-contract.json'));
startupPhase='existing-contracts';
// A fresh instance defaults to disallowing note search. Exercise the real supported API
// with a permitted ordinary account, without changing any production role policy.
const before=await api('meta');
await api('admin/roles/update-default-policies',{policies:{...before.policies,canSearchNotes:true,scheduledNoteLimit:10,canInvite:true}},owner.token);
const announcement=await api('admin/announcements/create',{title:'隔离原生公告',text:'Synthetic announcement',imageUrl:null,display:'marquee'},owner.token);
const alice=await api('signup',{username:'native_alice',password:randomBytes(24).toString('hex')});
const bob=await api('signup',{username:'native_bob',password:randomBytes(24).toString('hex')});
await verifyAdminContracts(api,owner,alice,join(process.env.GITHUB_WORKSPACE,'build/integration-admin-contract.json'));
try { await verifyExtendedContracts(api,owner,join(process.env.GITHUB_WORKSPACE,'build/integration-extended-contract.json')); }
catch(error) { await writeFile(join(process.env.GITHUB_WORKSPACE,'build/integration-extended-failure.json'),JSON.stringify({status:'FAIL',productionAPIRequests:0,error:String(error.message)},null,2)); throw new Error('Isolated extended contract failed; see sanitized evidence'); }
await verifyChatContracts(api,owner,join(process.env.GITHUB_WORKSPACE,'build/integration-chat-contract.json'));
await api('i/update',{name:'原生验收用户',chatScope:'mutual'},alice.token);
await api('i/update',{name:'隔离测试朋友',chatScope:'mutual'},bob.token);
const note=await api('notes/create',{text:'PUBO joint proof #PUBO',visibility:'public'},alice.token);
await api('notes/reactions/create',{noteId:note.createdNote.id,reaction:'❤️'},bob.token);
let timelineEvent;
const searchProof=await api('notes/search',{query:'PUBO joint proof',limit:30},alice.token);
if(!searchProof.some(x=>x.id===note.createdNote.id))throw new Error('Isolated search setup is not ready');
const poll=await api('notes/create',{text:'真实接口投票',visibility:'public',poll:{choices:['Morning','Evening'],multiple:false}},bob.token);
await api('following/create',{userId:bob.id},alice.token);
await api('following/create',{userId:alice.id},bob.token);
const received=await api('chat/messages/create-to-user',{toUserId:alice.id,text:'真实隔离后端私信',clientMessageId:randomUUID()},bob.token);
const sent=await api('chat/messages/create-to-user',{toUserId:bob.id,text:'原生编辑验收',clientMessageId:randomUUID()},alice.token);
const historicalPeer=await api('signup',{username:'native_history',password:randomBytes(24).toString('hex')});
await api('i/update',{name:'历史引用验收朋友'},historicalPeer.token);
await api('following/create',{userId:historicalPeer.id},alice.token);
await api('following/create',{userId:alice.id},historicalPeer.token);
const original=await api('chat/messages/create-to-user',{toUserId:alice.id,text:'跨页历史原消息',clientMessageId:randomUUID()},historicalPeer.token);
for(let n=0;n<52;n++) await api('chat/messages/create-to-user',{toUserId:historicalPeer.id,text:'隔离分页 '+n,clientMessageId:randomUUID()},alice.token);
const quote=await api('chat/messages/create-to-user',{toUserId:historicalPeer.id,text:'真实跨页引用',replyToId:original.id,clientMessageId:randomUUID()},alice.token);
await api('chat/conversation-settings/update',{userId:historicalPeer.id,isMuted:true},alice.token);
const muted=await api('chat/unread-summary',{},alice.token);
if(!(muted.unreadCount>muted.notificationUnreadCount))throw new Error('Muted unread contract mismatch');
const parityRoom=await api('chat/rooms/create',{name:'普通成员群聊验收',description:'Isolated native chat parity'},bob.token);
await api('chat/rooms/invitations/create',{roomId:parityRoom.id,userId:alice.id},bob.token);
await api('chat/rooms/join',{roomId:parityRoom.id},alice.token);
const parityOld=await api('chat/messages/create-to-room',{toRoomId:parityRoom.id,text:'Native historical group target'},bob.token);
for(let n=0;n<35;n++) await api('chat/messages/create-to-room',{toRoomId:parityRoom.id,text:'Isolated group history '+n},bob.token);
const parityMessage=await api('chat/messages/create-to-room',{toRoomId:parityRoom.id,text:'Native ordinary member reaction'},bob.token);
let parityEvent;
const context={roomId:parityRoom.id,roomOldId:parityOld.id,roomMessageId:parityMessage.id,token:alice.token,userId:alice.id,peerId:bob.id,noteId:note.createdNote.id,pollId:poll.createdNote.id,receivedId:received.id,sentId:sent.id,quoteId:quote.id,adminToken:owner.token,adminPassword:ownerPassword};
// Loopback-only ephemeral credentials; never logged, written to artifacts, or sent to production.
const control=createServer(async(req,res)=>{
 try {
  if(req.method==='POST'&&req.url==='/prepare-test'){
   // Reset only shared synthetic settings: a failed test must not hide the next test's poll.
   const rows=await api('mute/list',{limit:100},alice.token);
   if(rows.some(x=>x.muteeId===bob.id)) await api('mute/delete',{userId:bob.id},alice.token);
   await api('i/update',{hideOnlineStatus:false},alice.token);
   res.writeHead(204);res.end();return;
  }
  if(req.method==='GET'&&req.url==='/context'){res.setHeader('content-type','application/json');res.end(JSON.stringify(context));return;}
  if(req.method==='POST'&&req.url==='/chat-event'){
   parityEvent=await api('chat/messages/create-to-room',{toRoomId:parityRoom.id,text:'Native live group arrival'},bob.token);
   res.setHeader('content-type','application/json');res.end(JSON.stringify({id:parityEvent.id}));return;
  }
  if(req.method==='POST'&&req.url==='/chat-delete'&&parityEvent){
   await api('chat/messages/delete',{messageId:parityEvent.id},bob.token);res.writeHead(204);res.end();return;
  }
  if(req.method==='GET'&&req.url==='/chat-proof'){
   const rows=await api('chat/messages/room-timeline',{roomId:parityRoom.id,limit:100},bob.token);
   const reports=await api('admin/abuse-user-reports',{limit:100},owner.token);
   const reaction=rows.find(x=>x.id===parityMessage.id)?.reactions.some(x=>x.user.id===alice.id&&x.reaction.replace(/\ufe0f/g,'')==='❤');
   res.setHeader('content-type','application/json');res.end(JSON.stringify({reacted:reaction===true,unreacted:reaction!==true,reported:reports.some(x=>x.reporterId===alice.id&&x.targetUserId===bob.id&&x.comment.includes('/chat/messages/'+parityMessage.id)),liveDeleted:parityEvent?!rows.some(x=>x.id===parityEvent.id):false}));return;
  }
  if(req.method==='POST'&&req.url==='/timeline-create'){
   timelineEvent=await api('notes/create',{text:'Isolated live timeline event',visibility:'public',localOnly:true},bob.token);
   res.setHeader('content-type','application/json');res.end(JSON.stringify({id:timelineEvent.createdNote.id}));return;
  }
  if(req.method==='POST'&&req.url==='/timeline-delete'&&timelineEvent){
   await api('notes/delete',{noteId:timelineEvent.createdNote.id},bob.token);
   res.writeHead(204);res.end();return;
  }
  if(req.method==='GET'&&req.url==='/proof'){
   const favorites=await api('i/favorites',{limit:100},alice.token);
   const timelineNote=await api('notes/show',{noteId:note.createdNote.id},alice.token);
   const vote=await api('notes/show',{noteId:poll.createdNote.id},alice.token);
   const message=await api('chat/messages/show',{messageId:sent.id},alice.token);
   const reactionMessage=await api('chat/messages/show',{messageId:received.id},alice.token);
   const old=await api('chat/messages/show',{messageId:original.id},historicalPeer.token);
   const scheduled=await api('notes/drafts/list',{scheduled:true,limit:100},alice.token);
   const drafts=await api('notes/drafts/list',{scheduled:false,limit:100},alice.token);
   const announcements=await api('announcements',{display:'marquee',isActive:true,limit:100});
   const contacts=await api('chat/contact-groups/list',{},alice.token);
   const rooms=await api('chat/rooms/owned',{limit:100},alice.token);
   const room=rooms.find(x=>x.name==='Native room proof');
   const roomMessages=room?await api('chat/messages/room-timeline',{roomId:room.id,limit:100},alice.token):[];
   const folders=await api('drive/folders',{limit:100},alice.token);
   const clips=await api('clips/list',{limit:100},alice.token);
   const privacy=await api('i',{},alice.token); const invites=await api('invite/list',{limit:100},alice.token); const mutes=await api('mute/list',{limit:100},alice.token);
   const adminAnnouncements=await api('admin/announcements/list',{status:'all',limit:100},owner.token);
   const daily={adminAnnouncementCreated:adminAnnouncements.some(x=>x.title==='Native administrator announcement'&&x.text==='Native administrator body'),privacyChanged:privacy.hideOnlineStatus===true,invitationCreated:invites.length>0,muted:mutes.some(x=>x.muteeId===bob.id),notMuted:!mutes.some(x=>x.muteeId===bob.id),contactsCreated:contacts.some(x=>x.name==='Native contacts proof'),roomMessageCreated:roomMessages.some(x=>x.text==='Native room message proof'&&x.fromUserId===alice.id),folderCreated:folders.some(x=>x.name==='Native folder proof'),clipCreated:clips.some(x=>x.name==='Native clip proof')};
   const reacted=reactionMessage.reactions.some(x=>x.user.id===alice.id&&x.reaction.replace(/\ufe0f/g,'')==='❤');
   res.setHeader('content-type','application/json');res.end(JSON.stringify({...daily,timelineReacted:timelineNote.myReaction?.replace(/\ufe0f/g,'')==='❤',timelineUnreacted:timelineNote.myReaction==null,favorite:favorites.some(x=>x.note.id===note.createdNote.id),voted:vote.poll.choices.some(x=>x.isVoted),edited:message.text?.includes('Edited')??false,recalled:message.recalledAt!=null,reacted,unreacted:!reacted,contextUnread:old.readState==='unread',scheduled:scheduled.some(x=>x.text==='Native scheduled proof'),scheduledCancelled:!scheduled.some(x=>x.text==='Native scheduled proof')&&drafts.some(x=>x.text==='Native scheduled proof'),announcementEdited:announcements.some(x=>x.id===announcement.id&&x.title==='隔离原生公告 Edited')}));return;
  }
  res.writeHead(404);res.end();
 }catch{res.writeHead(500);res.end('Synthetic control failed');}
});
await new Promise(resolve=>control.listen(61913,'127.0.0.1',resolve));
console.log('Isolated native integration ready; synthetic credentials remain in memory.');
process.on('SIGTERM',async()=>{control.close();await harness.teardown();process.exit(0);});

