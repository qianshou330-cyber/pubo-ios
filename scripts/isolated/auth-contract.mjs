import {createServer} from 'node:http';
import {createServer as createSMTPServer} from 'node:net';
import {randomBytes,createHmac} from 'node:crypto';
import {createRequire} from 'node:module';
import {join} from 'node:path';
import {writeFile,readFile} from 'node:fs/promises';

function requireIsolated(){if(process.env.GITHUB_ACTIONS!=='true'||process.env.NODE_ENV!=='test')throw new Error('Disposable authentication runner required');}
export async function setupAuthChannels(root){
 requireIsolated();const messages=[],codes=new Map();let deliveries=0;
 // A loopback SMTP sink exercises the real mail service without importing internals
 // from the bundled backend or contacting any external mail provider.
 const smtp=createSMTPServer(socket=>{
  let buffer='',data=false,lines=[],recipient='';socket.setTimeout(30000,()=>socket.destroy());socket.write('220 isolated SMTP ready\r\n');
  socket.on('data',chunk=>{
   buffer+=chunk.toString();let end;
   while((end=buffer.indexOf('\r\n'))>=0){
    const line=buffer.slice(0,end);buffer=buffer.slice(end+2);
    if(data){if(line!=='.'){lines.push(line.startsWith('..')?line.slice(1):line);continue;}messages.push({address:recipient,text:lines.join('\r\n').replace(/=\r\n/g,'')});lines=[];data=false;socket.write('250 accepted\r\n');continue;}
    if(/^(EHLO|HELO) /i.test(line))socket.write('250 isolated.local\r\n');
    else if(/^MAIL FROM:/i.test(line))socket.write('250 sender accepted\r\n');
    else if(/^RCPT TO:/i.test(line)){recipient=line.match(/<([^>]+)>/)?.[1]??'';socket.write('250 recipient accepted\r\n');}
    else if(/^DATA$/i.test(line)){data=true;socket.write('354 end with dot\r\n');}
    else if(/^QUIT$/i.test(line)){socket.end('221 bye\r\n');}
    else if(/^(RSET|NOOP)$/i.test(line))socket.write('250 ok\r\n');
    else socket.write('502 unsupported\r\n');
   }
  });socket.on('error',()=>{});
 });await new Promise((resolve,reject)=>{smtp.once('error',reject);smtp.listen(61916,'127.0.0.1',resolve);});
 const server=createServer(async(req,res)=>{
  if(req.method!=='POST'){res.writeHead(405);res.end();return;}
  let body='';for await(const chunk of req)body+=chunk;
  const form=new URLSearchParams(body),phone=form.get('mobile'),code=form.get('content')?.match(/\b\d{6}\b/)?.[0];
  if(!phone?.startsWith('19900000')||!code){res.writeHead(400);res.end('{}');return;}
  codes.set(phone,code);deliveries++;res.setHeader('content-type','application/json');res.end(JSON.stringify({ReturnStatus:'Success',SuccessCounts:1}));
 });await new Promise(resolve=>server.listen(61915,'127.0.0.1',resolve));
 process.env.MISSKEY_SMS_ACCOUNT='synthetic';process.env.MISSKEY_SMS_PASSWORD='synthetic';process.env.MISSKEY_SMS_USERID='synthetic';process.env.MISSKEY_SMS_SEND_URL='http://127.0.0.1:61915/send';
 return {codes,messages,server,smtp,get deliveries(){return deliveries;}};
}
function totp(secret){const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';let bits='';for(const c of secret.replace(/=+$/,''))bits+=alphabet.indexOf(c).toString(2).padStart(5,'0');const key=Buffer.from((bits.match(/.{8}/g)??[]).map(x=>parseInt(x,2))),step=Buffer.alloc(8);step.writeBigUInt64BE(BigInt(Math.floor(Date.now()/30000)));const hash=createHmac('sha1',key).update(step).digest(),offset=hash.at(-1)&15;return String((hash.readUInt32BE(offset)&0x7fffffff)%1000000).padStart(6,'0');}
export async function verifyAuthContracts(api,owner,channels,root,destination){
 requireIsolated();const checks={};let phase='setup';const need=(ok,key)=>{if(!ok)throw new Error('Authentication contract: '+key);checks[key]=true;};
 // The upstream test harness recreates entity tables and drops this SQL-only
 // migration table. Restore its exact existing definition only in the empty CI DB.
 const dbRequire=createRequire(join(root,'package.json'));const {Client:SchemaClient}=dbRequire('pg');
 const schema=new SchemaClient({host:'127.0.0.1',port:54312,database:'pubo_native_integration',user:process.env.USER});await schema.connect();
 try{
  if(!(await schema.query("SELECT to_regclass('public.sms_verification') AS table_name")).rows[0].table_name){
   const migration=await readFile(join(root,'migration/1788904810458-SmsRegistration.js'),'utf8');
   const statements=[...migration.matchAll(/queryRunner\.query\(`(CREATE (?:TABLE|INDEX) [^`]+)`\)/g)].map(x=>x[1]).filter(x=>x.includes('"sms_verification"'));
   if(statements.length!==2)throw new Error('Unexpected existing SMS migration');
   for(const sql of statements)await schema.query(sql);
   checks.existingSMSMigrationRestored=true;
  }
 }finally{await schema.end();}
 async function waitForMail(predicate){const deadline=Date.now()+5000;while(!predicate()&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,50));}
 async function response(path,fields={}){const r=await fetch('http://127.0.0.1:61812/api/'+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(fields),signal:AbortSignal.timeout(15000),redirect:'error'});const text=await r.text();return {status:r.status,value:text?JSON.parse(text):null};}
 const before=await api('meta');const password=randomBytes(24).toString('hex'),newPassword=randomBytes(24).toString('hex');
 try{
  // The isolated instance must exercise production signup guards (test mode skips SMS).
  process.env.NODE_ENV='production';
  await api('admin/update-meta',{disableRegistration:false,emailRequiredForSignup:false,enableActiveEmailValidation:false,enableEmail:true,smtpHost:'127.0.0.1',smtpPort:61916,smtpSecure:false,smtpUser:null,smtpPass:null},owner.token);
  phase='prechecks';need((await api('username/available',{username:'auth_fixture'})).available,'usernameAvailable');need(!(await api('username/available',{username:'isolated_owner'})).available,'usernameOccupied');
  need(!(await api('email-address/available',{emailAddress:'invalid'})).available,'emailFormatRejected');
  need((await api('email-address/available',{emailAddress:'auth-fixture@example.test'})).available,'emailAvailable');
  phase='sms-signup';const phone='19900000011';await api('signup/request-phone-code',{phoneNumber:phone});const limited=await response('signup/request-phone-code',{phoneNumber:phone});need(limited.status===429,'smsCooldown');
  const code=channels.codes.get(phone);need(/^\d{6}$/.test(code??''),'testSMSDelivery');
  const wrong=await response('signup',{username:'auth_fixture',password,phoneNumber:phone,smsCode:'bad'});need(wrong.status===400,'invalidSignupSMSRejected');
  const user=await api('signup',{username:'auth_fixture',password,phoneNumber:phone,smsCode:code});need(typeof user.token==='string','signupReceipt');
  phase='signin';const step=await api('signin-flow',{username:'auth_fixture'});need(step.next==='captcha'&&!step.finished,'usernameStep');
  need((await response('signin-flow',{username:'auth_fixture',password:'wrong'})).status===403,'wrongPasswordRejected');
  need((await api('signin-flow',{username:'auth_fixture',password})).finished,'passwordSignin');
  phase='totp-backup';const setup=await api('i/2fa/register',{password},user.token);const enrollmentCode=totp(setup.secret);const recovery=await api('i/2fa/done',{token:enrollmentCode},user.token);
  need((await api('signin-flow',{username:'auth_fixture',password})).next==='totp','totpStep');
  need((await response('signin-flow',{username:'auth_fixture',password,token:enrollmentCode})).status===403,'totpReplayRejected');
  // Enrollment consumes the current code. Wait for a naturally new time step;
  // never clear or bypass the server's replay protection to make this test pass.
  await new Promise(resolve=>setTimeout(resolve,30050-Date.now()%30000));
  need((await api('signin-flow',{username:'auth_fixture',password,token:totp(setup.secret)})).finished,'totpSignin');
  need((await api('signin-flow',{username:'auth_fixture',password,token:recovery.backupCodes[0]})).finished,'backupSignin');
  need((await response('signin-flow',{username:'auth_fixture',password,token:recovery.backupCodes[0]})).status===403,'backupSingleUse');
  await api('i/2fa/unregister',{password,token:recovery.backupCodes[1]},user.token);
  phase='email-reset';const require=createRequire(join(root,'package.json'));const {Client}=require('pg');const db=new Client({host:'127.0.0.1',port:54312,database:'pubo_native_integration',user:process.env.USER});await db.connect();
  try{await db.query('UPDATE "user_profile" SET "email"=$1,"emailVerified"=true WHERE "userId"=$2',['auth-fixture@example.test',user.id]);}finally{await db.end();}
  const mailCount=channels.messages.length;await api('request-reset-password',{username:'auth_fixture',email:'auth-fixture@example.test'});
  await waitForMail(()=>channels.messages.length>mailCount);
  need(channels.messages.length===mailCount+1&&channels.messages.at(-1).text.includes('http://127.0.0.1:61812/reset-password/'),'emailResetTestDelivery');
  await api('request-reset-password',{username:'auth_fixture',email:'unmatched@example.test'});need(channels.messages.length===mailCount+1,'emailNoEnumerationDelivery');
  phase='phone-reset';await api('request-reset-password-phone',{phoneNumber:phone,username:'auth_fixture'});const reset=channels.codes.get(phone);need(/^\d{6}$/.test(reset??''),'phoneResetTestDelivery');
  need((await response('reset-password-phone',{phoneNumber:phone,smsCode:'bad',newPassword})).status===400,'resetInvalidCodeRejected');
  await api('reset-password-phone',{phoneNumber:phone,smsCode:reset,newPassword});need((await api('signin-flow',{username:'auth_fixture',password:newPassword})).finished,'resetNewPasswordSignin');
  need((await response('signin-flow',{username:'auth_fixture',password})).status===403,'resetOldPasswordRejected');
  need((await response('reset-password-phone',{phoneNumber:phone,smsCode:reset,newPassword})).status===400,'resetSingleUse');
  phase='email-pending';await api('admin/update-meta',{emailRequiredForSignup:true},owner.token);const pendingPhone='19900000012';await api('signup/request-phone-code',{phoneNumber:pendingPhone});
  const pending=await response('signup',{username:'auth_pending',password,phoneNumber:pendingPhone,smsCode:channels.codes.get(pendingPhone),emailAddress:'pending@example.test'});need(pending.status===204&&pending.value===null,'signupEmailPending204');
  await waitForMail(()=>channels.messages.some(x=>x.address==='pending@example.test'));
  need(channels.messages.some(x=>x.address==='pending@example.test'&&x.text.includes('/signup-complete/')),'signupVerificationTestDelivery');
  phase='invitation';await api('admin/update-meta',{emailRequiredForSignup:false,disableRegistration:true},owner.token);const invitePhone='19900000013';await api('signup/request-phone-code',{phoneNumber:invitePhone});
  need((await response('signup',{username:'auth_restricted',password,phoneNumber:invitePhone,smsCode:channels.codes.get(invitePhone)})).status===400,'invitationRequired');
  await writeFile(destination,JSON.stringify({status:'PASS',checks,productionAPIRequests:0,outboundSMS:'loopback test provider',outboundEmail:'loopback SMTP test sink',signupProductionGuards:true},null,2));
 }catch(error){const reason=/^(Authentication contract:|Synthetic setup failed:)/.test(error.message)?error.message.slice(0,200):error.name;await writeFile(destination,JSON.stringify({status:'FAIL',phase,reason,checks,productionAPIRequests:0},null,2));throw new Error('Isolated authentication failed at '+phase);}
 finally{process.env.NODE_ENV='test';await api('admin/update-meta',{disableRegistration:before.disableRegistration,emailRequiredForSignup:before.emailRequiredForSignup,enableActiveEmailValidation:before.enableActiveEmailValidation??false},owner.token);}
}

