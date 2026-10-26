import {spawn} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {inputDigest} from '../src/intents.js';
if(process.env.DRYRUN_LIVE_INTENT!=='1')throw new Error('explicit_live_synthetic_flag_required');
const token=randomBytes(32).toString('hex'),port=18788;
const child=spawn('pnpm',['exec','tsx','src/server.ts'],{env:{...process.env,NODE_ENV:'development',PORT:String(port),DRYRUN_DEV_TOKEN:token},stdio:'ignore'});
const endpoint=`http://127.0.0.1:${port}/v1/intents`;
const binding={sessionID:'synthetic-http',revision:0,eventSequence:0,contextDigest:'synthetic',householdRevision:0,homeRevision:0};
const text='Use stored water only for drinking and cooking.';
const request={contractVersion:'dryrun.ai/1',requestID:'http-intent-1',synthetic:true,submission:{id:'input-1',text,inputDigest:inputDigest(text),binding},context:{people:[],rooms:[],portals:[],equipment:[],contacts:[],supplies:[],choices:[]}};
async function post(value:unknown,credential=token){return fetch(endpoint,{method:'POST',headers:{Authorization:'Bearer '+credential,'Content-Type':'application/json'},body:JSON.stringify(value)});}
try{
 let ready=false;for(let n=0;n<30;n++){try{await post({},'invalid');ready=true;break;}catch{await new Promise(r=>setTimeout(r,100));}}
 if(!ready)throw new Error('server_startup');
 const unauthorized=await post(request,'invalid');if(unauthorized.status!==400)throw new Error('unauthorized');
 const response=await post(request);const result=await response.json() as any;
 if(response.status!==200||result.status!=='completed'||result.proposal.commands?.[0]?.value!=='essential')throw new Error('intent_http_failure');
 const duplicate=await post(request);if(duplicate.status!==400)throw new Error('request_replayed');
 const privateInput=await post({...request,requestID:'private',synthetic:false});if(privateInput.status!==400)throw new Error('private_fixture_allowed');
 await writeFile('../../fixtures/ai/user-intent-http-live.json',JSON.stringify({synthetic:true,liveModel:true,endpoint:'/v1/intents',result,unauthorizedRejected:true,duplicateRejected:true,nonSyntheticRejected:true},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',live:true,endpoint:'/v1/intents',unauthorizedRejected:true,duplicateRejected:true,nonSyntheticRejected:true}));
}finally{child.kill('SIGTERM');}
