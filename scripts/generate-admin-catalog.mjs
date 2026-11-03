import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
const checkout=process.argv[2]; if(!checkout)throw new Error('Pass the audited PUBO H5 checkout path');
const backend=path.join(checkout,'packages/backend/src');
const root=path.join(backend,'server/api/endpoints');
const front=path.join(checkout,'packages/frontend/src');
const output=process.argv[3]; if(!output)throw new Error('Pass catalog output path');
function walk(p){return fs.readdirSync(p,{withFileTypes:true}).flatMap(x=>x.isDirectory()?walk(path.join(p,x.name)):[path.join(p,x.name)]);}
const files=walk(path.join(root,'admin')).filter(p=>p.endsWith('.ts'));
files.push(...walk(path.join(root,'v2/admin')).filter(p=>p.endsWith('.ts')));
for(const id of ['stats','get-online-users-count','federation/instances','federation/show-instance','federation/update-remote-user','roles/users','charts/users','charts/notes','charts/active-users','charts/ap-request','retention','server-info','drive/files/show','drive/files/update','drive/files/delete','export-custom-emojis']) { const f=path.join(root,id+'.ts');if(fs.existsSync(f))files.push(f); }
const context={VERIFICATION_TYPES:['actor','singer','model','contentCreator','novelist','other'],localUsernameSchema:{type:'string',pattern:'^\\w{1,20}$'},descriptionSchema:{type:'string',minLength:1,maxLength:1500},supportedCaptchaProviders:['none','hcaptcha','mcaptcha','recaptcha','turnstile','testcaptcha'],QUEUE_TYPES:['system','endedPollNotification','postScheduledNote','deliver','inbox','db','relationship','objectStorage','userWebhookDeliver','systemWebhookDeliver'],systemWebhookEventTypes:['abuseReport','abuseReportResolved','userCreated','inactiveModeratorsWarning','inactiveModeratorsInvitationOnlyChanged']};
context.passwordSchema={type:'string',minLength:1};
const emojiSource=fs.readFileSync(path.join(backend,'core/CustomEmojiService.ts'),'utf8');
for(const name of ['fetchEmojisHostTypes','fetchEmojisSortKeys']){ const expression=emojiSource.match(new RegExp('export const '+name+' = ([\\s\\S]*?) as const;'))?.[1];if(!expression)throw new Error(name);context[name]=vm.runInNewContext(expression,{}, {timeout:200}); }
let schemas={},failures=[];
for(const file of files){
 const source=fs.readFileSync(file,'utf8'), id=path.relative(root,file).replaceAll('\\','/').slice(0,-3);
 const text=source.match(/export const paramDef\s*=\s*([\s\S]*?)\s+as const;/)?.[1];
 if(!text){failures.push({id,error:'missing schema'});continue;}
 try{
  const schema=vm.runInNewContext('('+text+')',context,{timeout:200});
  const meta=source.slice(0,source.indexOf('export const paramDef'));
  schemas[id]={id,schema,requireAdmin:id==='admin/accounts/create'||/requireAdmin:\s*true/.test(meta),requireModerator:/requireModerator:\s*true/.test(meta),secure:/secure:\s*true/.test(meta),requiredRolePolicy:meta.match(/requiredRolePolicy:\s*'([^']+)'/)?.[1]??'',kind:meta.match(/kind:\s*'([^']+)'/)?.[1]??''};
 }catch(e){failures.push({id,error:e.message});}
}
const pages=walk(path.join(front,'pages/admin')).filter(p=>p.endsWith('.vue')||p.endsWith('.ts'));
for(const n of ['admin-user.vue','admin-file.vue','custom-emojis-manager.vue','avatar-decorations.vue'])pages.push(path.join(front,'pages',n));
let pageCalls={};for(const p of pages){const s=fs.readFileSync(p,'utf8');const calls=[...s.matchAll(/(?:misskeyApi|apiWithDialog|apiWithConfirm|endpoint:|endpoint\s*=)\s*\(?\s*'([^']+)'/g)].map(m=>m[1]);pageCalls[path.relative(front,p).replaceAll('\\','/')]=[...new Set(calls)];}
if(failures.length)throw new Error(JSON.stringify(failures));
for(const item of Object.values(schemas)) item.mutation=item.kind.startsWith('write:')||['admin/accounts/create','admin/emoji/import-zip','export-custom-emojis','federation/update-remote-user','admin/system-webhook/test'].includes(item.id);
const roleSource=fs.readFileSync(path.join(backend,'core/RoleService.ts'),'utf8');
const policyText=roleSource.match(/export const DEFAULT_POLICIES: RolePolicies = ([\s\S]*?);/)?.[1];
if(!policyText)throw new Error('Missing role policies');
const policyDefaults=vm.runInNewContext('('+policyText+')',{}, {timeout:200});
const policyProperties={};
for(const [key,value] of Object.entries(policyDefaults))policyProperties[key]=Array.isArray(value)?{type:'array',items:{type:'string'},default:value}:typeof value==='boolean'?{type:'boolean',default:value}:typeof value==='number'?{type:'number',minimum:0,default:value}:{type:'string',enum:key==='chatAvailability'?['available','readonly','unavailable']:undefined,default:value};
for(const id of ['admin/roles/create','admin/roles/update','admin/roles/update-default-policies']){
 const properties=id.endsWith('update-default-policies')?policyProperties:Object.fromEntries(Object.entries(policyProperties).map(([key,definition])=>[key,{type:'object',properties:{useDefault:{type:'boolean',default:true},priority:{type:'integer',enum:[0,1,2],default:0},value:definition},required:['useDefault','priority','value']}])) ;
 schemas[id].schema.properties.policies={...schemas[id].schema.properties.policies,type:'object',properties};
}
fs.mkdirSync(path.dirname(output),{recursive:true});
fs.writeFileSync(output,JSON.stringify({source:'PUBO audited H5/backend endpoint schemas; regenerated only during development',endpoints:Object.values(schemas),pageCalls},null,2)+'\n');
console.log(JSON.stringify({endpoints:Object.keys(schemas).length,failures,pages:pages.length}));

