import { randomBytes, createHash, createHmac } from 'node:crypto';
import { writeFile, readFile, readdir, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { deflateSync } from 'node:zlib';

// A generated, non-personal 1x1 PNG. No uploaded identity document enters logs or artifacts.
function crc32(buffer) { let crc=0xffffffff; for(const byte of buffer){crc^=byte;for(let bit=0;bit<8;bit++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0; }
function chunk(type,data){const body=Buffer.concat([Buffer.from(type),data]);const size=Buffer.alloc(4);size.writeUInt32BE(data.length);const crc=Buffer.alloc(4);crc.writeUInt32BE(crc32(body));return Buffer.concat([size,body,crc]);}
const header=Buffer.alloc(13);header.writeUInt32BE(1);header.writeUInt32BE(1,4);header[8]=8;header[9]=6;
const fixture=Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('IDAT',deflateSync(Buffer.from([0,0,0,0,255]))),chunk('IEND',Buffer.alloc(0))]);
const digest=createHash('sha256').update(fixture).digest('hex');
function totp(secret){const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';let bits='';for(const char of secret.replace(/=+$/,''))bits+=alphabet.indexOf(char).toString(2).padStart(5,'0');const key=Buffer.from((bits.match(/.{8}/g)??[]).map(x=>parseInt(x,2)));const step=Buffer.alloc(8);step.writeBigUInt64BE(BigInt(Math.floor(Date.now()/30000)));const hash=createHmac('sha1',key).update(step).digest();const offset=hash.at(-1)&15;return String((hash.readUInt32BE(offset)&0x7fffffff)%1000000).padStart(6,'0');}
export async function prepareVerificationFixture(){
 if(process.env.GITHUB_ACTIONS!=='true'||process.env.NODE_ENV!=='test')throw new Error('Isolated runner only');
 const folder=join(process.env.RUNNER_TEMP,'pubo-synthetic-verification');await mkdir(folder,{recursive:true});
 const scanner=join(folder,'fixture-only-scanner.mjs');
 // Scanner boundary is a strict fixture allow-list, NOT a malware-engine validation.
 await writeFile(scanner,`#!/usr/bin/env node\nimport{readFile}from'node:fs/promises';import{createHash}from'node:crypto';const b=await readFile(process.argv.at(-1));process.exit(createHash('sha256').update(b).digest('hex')===${JSON.stringify(digest)}?0:1);\n`,{mode:0o700});
 process.env.MISSKEY_VERIFICATION_SCANNER_PATH=scanner;
 process.env.MISSKEY_VERIFICATION_STORAGE_PATH=join(folder,'encrypted');
}
export async function verifyExtendedContracts(api,owner,destination){
 const checks={};
 const password=randomBytes(24).toString('hex');
 const subject=await api('signup',{username:'contract_subject',password});
 const stranger=await api('signup',{username:'contract_other',password:randomBytes(24).toString('hex')});
 async function rejects(path,fields,token,expected){
  const response=await fetch('http://127.0.0.1:61812/api/'+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...fields,i:token})});
  const value=await response.json();if(response.ok||(expected&&value?.error?.code!==expected))throw new Error('Expected isolated rejection: '+path+' '+response.status);return true;
 }
 async function upload(path,fields={}){
  const body=new FormData();body.set('i',subject.token);for(const [key,value]of Object.entries(fields))body.set(key,value);body.set('file',new Blob([fixture],{type:'image/png'}),'synthetic.png');
  const response=await fetch('http://127.0.0.1:61812/api/'+path,{method:'POST',body});if(!response.ok)throw new Error('Synthetic upload failed: '+path+' '+response.status);return response.json();
 }
 const beforeDrive=await api('drive',{},subject.token);
 const front=await upload('verification/upload',{side:'front'}),back=await upload('verification/upload',{side:'back'});
 if(front.sha256!==digest||back.sha256!==digest)throw new Error('Verification upload hash mismatch');checks.protectedUpload=true;
 const application=await api('verification/create',{type:'other',description:'Disposable synthetic verification',contact:'synthetic@example.invalid',documentIds:[front.id,back.id],consentVersion:'2026-09-30'},subject.token);
 const detail=await api('admin/verification/show',{applicationId:application.id},owner.token);
 if(detail.status!=='pending')throw new Error('Verification not pending');
 const document=await api('admin/verification/document',{applicationId:application.id,documentId:front.id},owner.token);
 if(document.mime!=='image/png'||createHash('sha256').update(Buffer.from(document.data,'base64')).digest('hex')!==digest)throw new Error('Protected document mismatch');checks.adminProtectedDocument=true;
 checks.otherAccountDocumentDenied=await rejects('admin/verification/document',{applicationId:application.id,documentId:front.id},stranger.token,'PERMISSION_DENIED');
 const drive=await api('drive',{},subject.token);if(drive.usage!==beforeDrive.usage)throw new Error('Verification material entered drive');checks.verificationOutsideDrive=true;
 for(const name of await readdir(process.env.MISSKEY_VERIFICATION_STORAGE_PATH)){const bytes=await readFile(join(process.env.MISSKEY_VERIFICATION_STORAGE_PATH,name));if(bytes.includes(fixture))throw new Error('Unencrypted verification fixture');}checks.encryptedMaterialStorage=true;
 await api('admin/verification/approve',{applicationId:application.id,approvedType:'other',reason:'Synthetic isolated approval'},owner.token);
 if((await api('verification/show',{},subject.token)).status!=='approved')throw new Error('Approval not applied');checks.verificationApproval=true;
 checks.duplicateApprovalRejected=await rejects('admin/verification/approve',{applicationId:application.id},owner.token,'INVALID_VERIFICATION_STATUS');
 await api('admin/verification/revoke',{applicationId:application.id,reason:'Synthetic revocation'},owner.token);
 if((await api('verification/show',{},subject.token)).status!=='revoked')throw new Error('Revocation not applied');checks.verificationRevocation=true;
 const againFront=await upload('verification/upload',{side:'front'}),againBack=await upload('verification/upload',{side:'back'});
 await api('verification/create',{type:'other',description:'Disposable reapplication',contact:'synthetic@example.invalid',documentIds:[againFront.id,againBack.id],consentVersion:'2026-09-30'},subject.token);
 await api('verification/withdraw',{},subject.token);
 const withdrawn=await api('verification/show',{},subject.token);if(withdrawn.status!=='revoked'||withdrawn.documents.length!==0)throw new Error('Withdrawal did not revoke and clear materials');
 if((await readdir(process.env.MISSKEY_VERIFICATION_STORAGE_PATH)).length)throw new Error('Verification files not removed');checks.withdrawalCleansMaterial=true;
 const clip=await api('clips/create',{name:'Contract clip',description:'Keep existing description',isPublic:false},subject.token);
 const latestClip=await api('clips/show',{clipId:clip.id},subject.token);
 await api('clips/update',{clipId:clip.id,name:'Renamed clip',description:latestClip.description},subject.token);
 if((await api('clips/show',{clipId:clip.id},subject.token)).description!==latestClip.description)throw new Error('Clip description changed');checks.clipRenamePreservesDescription=true;
 const file=await upload('drive/files/create');
 const gallery=await api('gallery/posts/create',{title:'Sensitive synthetic gallery',fileIds:[file.id],isSensitive:true},subject.token);
 const latestGallery=await api('gallery/posts/show',{postId:gallery.id},subject.token);
 await api('gallery/posts/update',{postId:gallery.id,title:'Renamed gallery',isSensitive:latestGallery.isSensitive},subject.token);
 if(!(await api('gallery/posts/show',{postId:gallery.id},subject.token)).isSensitive)throw new Error('Gallery sensitivity changed');checks.galleryTitlePreservesSensitivity=true;
 const hook=await api('i/webhooks/create',{name:'Synthetic inactive subscription',url:'http://127.0.0.1:61914/unused',on:[],secret:'fixture-only'},subject.token);
 await api('i/webhooks/update',{webhookId:hook.id,active:false,name:'Renamed'},subject.token);
 const updatedHook=await api('i/webhooks/show',{webhookId:hook.id},subject.token);if(updatedHook.secret!=='fixture-only'||updatedHook.active!==false)throw new Error('Webhook update mismatch');checks.webhookPreservesSecret=true;
 checks.webhookOwnerEnforced=await rejects('i/webhooks/update',{webhookId:hook.id,name:'Not allowed'},stranger.token,'NO_SUCH_WEBHOOK');
 await api('i/webhooks/delete',{webhookId:hook.id},subject.token);
 if((await api('i/webhooks/list',{},subject.token)).length)throw new Error('Webhook remains');checks.webhookDelete=true;
 const room=await api('chat/rooms/create',{name:'Disposable permission room'},subject.token);
 checks.uninvitedRoomJoinDenied=await rejects('chat/rooms/join',{roomId:room.id},stranger.token);
 await api('chat/rooms/invitations/create',{roomId:room.id,userId:stranger.id},subject.token);
 await api('chat/rooms/join',{roomId:room.id},stranger.token);
 if(!(await api('chat/rooms/joining',{limit:100},stranger.token)).some(x=>x.room.id===room.id))throw new Error('Room membership missing');checks.invitedRoomJoin=true;
 checks.roomNonOwnerUpdateDenied=await rejects('chat/rooms/update',{roomId:room.id,name:'Must not change'},stranger.token);
 await api('chat/messages/create-to-room',{toRoomId:room.id,text:'Synthetic membership proof'},stranger.token);
 await api('chat/rooms/leave',{roomId:room.id},stranger.token);
 checks.leftRoomSendDenied=await rejects('chat/messages/create-to-room',{toRoomId:room.id,text:'Must not send'},stranger.token);
 await api('chat/rooms/delete',{roomId:room.id},subject.token);
 const newPassword=randomBytes(24).toString('hex');
 await api('i/change-password',{currentPassword:password,newPassword},subject.token);
 checks.oldPasswordRejected=await rejects('i/change-password',{currentPassword:password,newPassword:password},subject.token);
 const setup=await api('i/2fa/register',{password:newPassword},subject.token);
 const recovery=await api('i/2fa/done',{token:totp(setup.secret)},subject.token);
 if(!(await api('i',{},subject.token)).twoFactorEnabled||recovery.backupCodes.length!==5)throw new Error('TOTP setup failed');checks.totpSetupAndRecovery=true;
 await api('i/2fa/unregister',{password:newPassword,token:recovery.backupCodes[0]},subject.token);
 if((await api('i',{},subject.token)).twoFactorEnabled)throw new Error('TOTP not disabled');checks.totpDisableWithRecovery=true;
 await writeFile(destination,JSON.stringify({status:'PASS',productionAPIRequests:0,scanner:'strict synthetic PNG hash allow-list; real antivirus NOT_TESTED',checks},null,2));
}
