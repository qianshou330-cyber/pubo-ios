import { randomBytes } from 'node:crypto';
import { writeFile } from 'node:fs/promises';

export async function verifyChatContracts(api, owner, destination) {
 const checks = {};
 const assert = (name, value) => { if (!value) throw new Error('Chat contract failed: '+name); checks[name]=true; };
 try {
  const host=await api('signup',{username:'chat_contract_host',password:randomBytes(24).toString('hex')});
  const member=await api('signup',{username:'chat_contract_member',password:randomBytes(24).toString('hex')});
  await api('following/create',{userId:member.id},host.token); await api('following/create',{userId:host.id},member.token);
  const room=await api('chat/rooms/create',{name:'Chat contract isolated room'},host.token);
  await api('chat/rooms/invitations/create',{roomId:room.id,userId:member.id},host.token);
  const inbox=await api('chat/rooms/invitations/inbox',{limit:30},member.token);
  assert('invitationHasRoomTarget',inbox.some(x=>x.room.id===room.id));
  await api('chat/rooms/join',{roomId:room.id},member.token);
  const message=await api('chat/messages/create-to-room',{toRoomId:room.id,text:'Isolated searchable group target'},host.token);
  const recent=await api('chat/history',{room:true,limit:10},member.token);
  assert('mixedHistoryHasRoomAndUnread',recent.some(x=>x.toRoomId===room.id&&x.toRoom.id===room.id&&!x.isRead));
  const search=await api('chat/messages/search',{roomId:room.id,query:'searchable',limit:100},member.token);
  assert('searchReturnsExactMessage',search.some(x=>x.id===message.id&&x.toRoomId===room.id));
  const unread=await api('chat/history',{room:true,limit:10},member.token);
  assert('historyAndSearchDoNotReadRoom',unread.some(x=>x.toRoomId===room.id&&!x.isRead));
  const context=await api('chat/messages/room-timeline',{roomId:room.id,sinceDate:Date.parse(message.createdAt)-1,limit:100},member.token);
  assert('roomContextIncludesExactTarget',context.some(x=>x.id===message.id));
  await api('chat/messages/react',{messageId:message.id,reaction:'❤'},member.token);
  const reacted=await api('chat/messages/room-timeline',{roomId:room.id,limit:100},member.token);
  assert('ordinaryMemberReactionReadback',reacted.find(x=>x.id===message.id)?.reactions.some(x=>x.user.id===member.id&&x.reaction.replace(/\ufe0f/g,'')==='❤'));
  await api('chat/messages/unreact',{messageId:message.id,reaction:'❤'},member.token);
  const unreacted=await api('chat/messages/room-timeline',{roomId:room.id,limit:100},member.token);
  assert('ordinaryMemberUnreactionReadback',!unreacted.find(x=>x.id===message.id)?.reactions.some(x=>x.user.id===member.id));
  const comment='https://bolubo.com/chat/messages/'+message.id+'\n-----\nIsolated report contract';
  await api('users/report-abuse',{userId:host.id,comment},member.token);
  const reports=await api('admin/abuse-user-reports',{limit:100},owner.token);
  assert('reportTargetsSenderAndExactMessage',reports.some(x=>x.reporterId===member.id&&x.targetUserId===host.id&&x.comment===comment));
  await api('chat/rooms/leave',{roomId:room.id},member.token);
  async function denied(endpoint, fields) {
   const response=await fetch('http://127.0.0.1:61812/api/'+endpoint,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...fields,i:member.token})});
   return !response.ok;
  }
  assert('formerMemberCannotReact',await denied('chat/messages/react',{messageId:message.id,reaction:'❤'}));
  assert('formerMemberCannotReadRoom',await denied('chat/messages/room-timeline',{roomId:room.id,limit:30}));
  await writeFile(destination,JSON.stringify({status:'PASS',checks,productionAPIRequests:0},null,2));
 } catch(error) { await writeFile(destination,JSON.stringify({status:'FAIL',checks,error:String(error.message),productionAPIRequests:0},null,2)); throw error; }
}
