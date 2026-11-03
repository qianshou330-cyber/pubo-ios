import { randomBytes, randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';

// Only the disposable loopback backend is reachable; never save accounts, tokens or responses.
export async function verifyAdminContracts(api, owner, ordinary, destination) {
 if(process.env.GITHUB_ACTIONS!=='true'||process.env.NODE_ENV!=='test')throw new Error('Isolated runner only');
 const checks={};
 async function denied(path,fields,token,key){
  const response=await fetch('http://127.0.0.1:61812/api/'+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...fields,i:token})});
  if(response.status!==403)throw new Error('Expected protected operation rejection: '+key+' '+response.status);
  checks[key]=true;
 }
 await denied('admin/verification/list',{status:'all',type:null,limit:10,offset:0},ordinary.token,'ordinaryVerificationDenied');
 for(const status of ['pending','approved','rejected','revoked','all']) {const rows=await api('admin/verification/list',{status,type:null,limit:10,offset:0},owner.token);if(!Array.isArray(rows))throw new Error('Invalid status response');}
 checks.allVerificationStatuses=true;
 const restricted=await api('miauth/gen-token',{session:randomUUID(),name:'Disposable scope test',permission:['read:account']},owner.token);
 await denied('admin/verification/list',{status:'all'},restricted.token,'limitedAdminTokenDenied');
 const moderator=await api('signup',{username:'native_mod',password:randomBytes(24).toString('hex')});
 const role=await api('admin/roles/create',{name:'Disposable moderator',description:'Synthetic only',color:null,iconUrl:null,target:'manual',condFormula:{id:randomUUID(),type:'isLocal'},isPublic:false,isModerator:true,isAdministrator:false,asBadge:false,canEditMembersByModerator:false,displayOrder:0,policies:{}},owner.token);
 await api('admin/roles/assign',{roleId:role.id,userId:moderator.id},owner.token);
 const users=await api('admin/show-users',{limit:10},moderator.token);if(!Array.isArray(users))throw new Error('Moderator users failed');checks.moderatorUsersAllowed=true;
 await denied('admin/verification/list',{status:'all'},moderator.token,'moderatorVerificationDenied');
 await denied('admin/update-meta',{description:'Must not apply'},moderator.token,'moderatorConfigurationDenied');
 await api('admin/roles/unassign',{roleId:role.id,userId:moderator.id},owner.token);
 await denied('admin/show-users',{limit:10},moderator.token,'revokedModeratorDenied');
 const before=await api('admin/meta',{},owner.token);
 const description='Isolated native admin sparse-update proof';
 await api('admin/update-meta',{description},owner.token);
 const after=await api('admin/meta',{},owner.token);
 if(after.description!==description||after.name!==before.name||after.disableRegistration!==before.disableRegistration)throw new Error('Sparse configuration update mismatch');checks.sparseConfigurationPreservesOtherFields=true;
 await api('admin/update-meta',{description:before.description},owner.token);
 await writeFile(destination,JSON.stringify({status:'PASS',productionAPIRequests:0,checks},null,2));
}
