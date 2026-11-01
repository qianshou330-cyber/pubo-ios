// Synthetic-only HTTP contract proof. Never logs tokens, passwords or chat content.
import { randomBytes, randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
const base = 'http://pubo-ios-proof-web:3000';
let phase = 'startup', requests = 0, assertions = 0;
const checks = [];
const need = (value, name) => { assertions++; if (!value) throw new Error(name); };
async function api(path, body = {}, token) {
  requests++;
  const response = await fetch(base + '/api/' + path, { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({...body, ...(token ? {i:token} : {})}), redirect:'error', signal:AbortSignal.timeout(15000) });
  const text = await response.text(); let value = null;
  if (text) { try { value = JSON.parse(text); } catch { throw new Error('NON_JSON_' + path); } }
  return {status:response.status, value};
}
async function ok(path, body, token) { const r = await api(path, body, token); need(r.status >= 200 && r.status < 300, 'REJECTED_' + path + '_' + r.status + '_' + (r.value?.error?.code ?? 'UNKNOWN')); return r.value; }
async function check(name, work) { phase=name; await work(); checks.push(name); }
async function upload(token, peer) {
  const form = new FormData(); form.set('i', token); form.set('toUserId', peer); form.set('file', new Blob(['synthetic fixture file'], {type:'text/plain'}), 'fixture.txt');
  const response = await fetch(base + '/api/chat/attachments/create', {method:'POST',body:form,signal:AbortSignal.timeout(15000)});
  return {status:response.status, value:await response.json()};
}
async function main() {
  need(process.env.PUBO_ISOLATED_PROOF === '1', 'ISOLATED_ONLY');
  for (let i=0;i<90;i++) { try { const r=await api('meta'); if(r.status===200) break; } catch {} await new Promise(r=>setTimeout(r,1000)); }
  const meta=await ok('meta',{}); need(meta.uri===base && meta.requireSetup===true,'FRESH_INTERNAL_INSTANCE_REQUIRED');
  const password=randomBytes(24).toString('base64url');
  const admin=await ok('admin/accounts/create',{username:'ios_admin_fixture',password});
  await ok('admin/update-meta',{disableRegistration:false,emailRequiredForSignup:false},admin.token);
  let user, peer;
  await check('sms-native-signup-and-signin',async()=>{
    const phone='19900000001';
    await ok('signup/request-phone-code',{phoneNumber:phone});
    const limited=await api('signup/request-phone-code',{phoneNumber:phone}); need(limited.status===429,'SMS_COOLDOWN');
    const code=await (await fetch('http://sms:8080/code')).text(); need(/^\d{6}$/.test(code),'MOCK_PROVIDER_CAPTURE');
    const invalid=await api('signup',{username:'ios_user_fixture',password,phoneNumber:phone,smsCode:'wrong'}); need(invalid.status===400,'INVALID_SMS_DENIED');
    user=await ok('signup',{username:'ios_user_fixture',password,phoneNumber:phone,smsCode:code}); need(typeof user.token==='string','SIGNUP_TOKEN');
    const login=await ok('signin-flow',{username:'ios_user_fixture',password}); need(login.finished===true && login.i===user.token,'NATIVE_SIGNIN');
    const self=await ok('i',{},user.token); need(self.id===user.id && self.chatScope==='mutual','ACCOUNT_CONTRACT');
    peer=await ok('admin/accounts/create',{username:'ios_peer_fixture',password},admin.token);
  });
  await check('notes-and-reactions',async()=>{
    const posted=await ok('notes/create',{text:'Synthetic native contract fixture',visibility:'public'},user.token);
    const id=posted.createdNote.id;
    const shown=await ok('notes/show',{noteId:id},user.token); need(shown.user.id===user.id && shown.visibility==='public','NOTE_CONTRACT');
    await ok('notes/reactions/create',{noteId:id,reaction:'❤️'},peer.token);
    await ok('notes/reactions/delete',{noteId:id},peer.token);
    const reply=await ok('notes/create',{text:'Synthetic reply',replyId:id,visibility:'public'},peer.token); need(reply.createdNote.replyId===id,'REPLY_CONTRACT');
    const replies=await ok('notes/replies',{noteId:id,limit:30},user.token); need(replies.some(x=>x.id===reply.createdNote.id),'REPLIES_CONTRACT');
    const notes=await ok('notes/local-timeline',{limit:20},user.token); need(notes.some(x=>x.id===id),'TIMELINE_CONTRACT');
  });
  let first, firstID;
  await check('private-chat-first-message-and-durable-idempotency',async()=>{
    const deniedFile=await upload(user.token,peer.id); need(deniedFile.status===400 && deniedFile.value.error.code==='CHAT_FIRST_MESSAGE_TEXT_ONLY','FIRST_ATTACHMENT_BLOCKED');
    firstID=randomUUID();
    const payload={toUserId:peer.id,text:'Synthetic first message',attachmentIds:[],clientMessageId:firstID};
    first=await ok('chat/messages/create-to-user',payload,user.token);
    need(first.clientMessageId===firstID && first.fromUserId===user.id && first.toUserId===peer.id && first.attachments.length===0,'CHAT_ACK_CONTRACT');
    const duplicate=await ok('chat/messages/create-to-user',payload,user.token); need(first.id===duplicate.id,'IDEMPOTENT_RETRY');
    const second=await api('chat/messages/create-to-user',{...payload,clientMessageId:randomUUID()},user.token); need(second.status===400 && second.value.error.code==='CHAT_REPLY_REQUIRED','SECOND_BLOCKED');
    await ok('chat/messages/read',{userId:user.id,messageIds:[first.id]},peer.token);
    const still=await api('chat/messages/create-to-user',{...payload,clientMessageId:randomUUID()},user.token); need(still.value?.error?.code==='CHAT_REPLY_REQUIRED','READ_NOT_REPLY');
    const history=await ok('chat/messages/user-timeline',{userId:peer.id,limit:100},user.token); need(history.filter(x=>x.clientMessageId===firstID).length===1,'RECONCILE_HISTORY');
    const dated=await ok('chat/messages/user-timeline',{userId:peer.id,limit:100,sinceDate:Date.now()-60000},user.token); need(dated.some(x=>x.clientMessageId===firstID),'RECONCILE_INTEGER_MILLISECONDS');
  });
  await check('concurrent-first-message-and-token-rejection',async()=>{
    const racePeer=await ok('admin/accounts/create',{username:'ios_race_fixture',password},admin.token);
    const responses=await Promise.all([1,2].map(n=>api('chat/messages/create-to-user',{toUserId:racePeer.id,text:'Concurrent fixture '+n,attachmentIds:[],clientMessageId:randomUUID()},user.token)));
    need(responses.filter(x=>x.status===200).length===1,'ONE_CONCURRENT_FIRST_MESSAGE');
    need(responses.filter(x=>x.value?.error?.code==='CHAT_REPLY_REQUIRED').length===1,'CONCURRENT_QUOTA_ENFORCED');
    const invalid=await api('i',{},'synthetic-invalid-token'); need(invalid.status>=400,'INVALID_TOKEN_DENIED');
  });
  await check('reply-unlocks-private-attachment-and-bearer-download',async()=>{
    await ok('chat/messages/create-to-user',{toUserId:user.id,text:'Synthetic reply',clientMessageId:randomUUID(),attachmentIds:[]},peer.token);
    const file=await upload(user.token,peer.id); need(file.status===200 && typeof file.value.id==='string','PRIVATE_UPLOAD_CONTRACT');
    const sent=await ok('chat/messages/create-to-user',{toUserId:peer.id,text:'Synthetic attachment',clientMessageId:randomUUID(),attachmentIds:[file.value.id],replyToId:first.id},user.token);
    need(sent.attachments[0].id===file.value.id && sent.replyToId===first.id,'ATTACHMENT_REPLY_CONTRACT');
    const url=base+'/api/chat/attachments/'+file.value.id+'/original';
    const allowed=await fetch(url,{headers:{Authorization:'Bearer '+peer.token}}); need(allowed.status===200 && allowed.headers.get('cache-control')==='private, no-store','PRIVATE_DOWNLOAD_CONTRACT');
    const anonymous=await fetch(url); need(anonymous.status===401,'ANONYMOUS_PRIVATE_DENIED');
    const forbidden=await fetch(url,{headers:{Authorization:'Bearer '+admin.token}}); need(forbidden.status>=400,'UNRELATED_ADMIN_PRIVATE_DENIED');
  });
  await check('conversation-settings-notifications-profile-and-blocking',async()=>{
    await ok('chat/conversation-settings/update',{userId:peer.id,pinned:true,isMuted:true},user.token);
    const list=await ok('chat/conversations',{limit:30},user.token); const row=list.find(x=>x.user.id===peer.id); need(row?.isMuted===true && !!row.pinnedAt && typeof row.unreadCount==='number','CONVERSATION_CONTRACT');
    await ok('i/update',{name:'Synthetic native user',description:'Fixture',chatScope:'mutual'},user.token);
    await ok('following/create',{userId:peer.id},user.token);
    const search=await ok('users/search',{query:'ios_peer',origin:'local',limit:20},user.token); need(search.some(x=>x.id===peer.id),'SEARCH_CONTRACT');
    const notifications=await ok('i/notifications',{limit:20},peer.token); need(Array.isArray(notifications),'NOTIFICATION_CONTRACT');
    await ok('notifications/mark-all-as-read',{},peer.token);
    await ok('blocking/create',{userId:peer.id},user.token);
    const blocked=await api('chat/messages/create-to-user',{toUserId:peer.id,text:'Synthetic denied',clientMessageId:randomUUID()},user.token); need(blocked.status>=400,'BLOCKING_ENFORCED');
  });
  phase='complete';
  await writeFile('/proof/http-result.json',JSON.stringify({status:'PASS',checks,requests,assertions},null,2));
  console.log(JSON.stringify({status:'PASS',checks:checks.length,requests,assertions}));
}
main().catch(async error=>{const safe=String(error.message).replace(/[^A-Za-z0-9_/.-]/g,'_').slice(0,180); await writeFile('/proof/http-result.json',JSON.stringify({status:'FAIL',phase,error:safe,checks,requests,assertions},null,2)); console.log(JSON.stringify({status:'FAIL',phase,error:safe})); process.exitCode=1;});
