/** Reviewer-only live protocol probes (ES module). Every stdout byte is protected. */
import {readFile} from 'node:fs/promises';
import {parseEnv} from 'node:util';
import {launchCodex,type CodexConnection,type RpcMessage} from '../../services/ai-orchestrator/src/codex-runtime.js';

const environment=parseEnv(await readFile(new URL('../../services/ai-orchestrator/.env',import.meta.url),'utf8'));
const key=process.env.CODEX_LB_API_KEY??environment.CODEX_LB_API_KEY??'';
if(!key)throw new Error('missing_provider_secret');
const model='gpt-6.1-sol';
const schema={type:'object',properties:{factID:{type:'string'},deficitHours:{type:'number'},limitation:{type:'string'}},required:['factID','deficitHours','limitation'],additionalProperties:false};
const tool={type:'function',name:'read_household_context',description:'Read frozen authorized synthetic runtime fact; no mutation.',inputSchema:{type:'object',properties:{},additionalProperties:false}};
const record={snapshotID:'synthetic-context-v1',memberID:'person-a',factID:'equipment-a-runtime',recordedRuntimeHours:3,requiredHours:8,status:'confirmed'};
const text=(value:string)=>[{type:'text',text:value,text_elements:[]}];
const pause=(ms:number)=>new Promise(resolve=>setTimeout(resolve,ms));

async function create(label:string){
 const abort=new AbortController();
 const connection=await launchCodex(key,model,abort.signal);
 const messages:RpcMessage[]=[];
 connection.onMessage=m=>{messages.push(m);console.log(JSON.stringify({probe:label,message:m}));};
 connection.onFailure=()=>console.log(JSON.stringify({probe:label,event:'connection_failed'}));
 await connection.request('initialize',{clientInfo:{name:'dryrun_extended_probe',version:'1'},capabilities:{experimentalApi:true}});
 connection.notify('initialized');
 const started=await connection.request('thread/start',{model,modelProvider:'dryrun_lb',approvalPolicy:'never',sandbox:'read-only',ephemeral:true,baseInstructions:'Synthetic DryRun transport test. Retrieve the recorded fact once using read_household_context. Use only recorded quantities, no clinical advice. No mutations exist. Return only requested JSON.',dynamicTools:[tool]});
 const wait=async(test:(m:RpcMessage)=>boolean,after=0,ms=25000)=>{
  const deadline=Date.now()+ms;
  while(Date.now()<deadline){const found=messages.slice(after).find(test);if(found)return found;await pause(25);}
  throw new Error('probe_deadline');
 };
 return {abort,connection,messages,threadID:started.thread.id,wait};
}

async function continuation(){
 const p=await create('continuation');
 try{
  await p.connection.request('turn/start',{threadId:p.threadID,input:text('Retrieve the only recorded equipment fact from snapshot synthetic-context-v1. Compute shortfall and identify the factID.'),outputSchema:schema});
  const call=await p.wait(m=>m.method==='item/tool/call');
  p.connection.respond(call.id!,{success:true,contentItems:[{type:'inputText',text:JSON.stringify(record)}]});
  const first=await p.wait(m=>m.method==='turn/completed');
  if(first.params.turn.status!=='completed')throw new Error('first_turn_failed');
  const offset=p.messages.length;
  await p.connection.request('turn/start',{threadId:p.threadID,input:text('Follow-up on the same frozen snapshot. Reuse the already retrieved record; do not call any tool again. Return the same recorded shortfall and fact reference with a concise evidence limitation.'),outputSchema:schema});
  const second=await p.wait(m=>m.method==='turn/completed',offset);
  console.log(JSON.stringify({probe:'continuation',event:'summary',firstStatus:first.params.turn.status,secondStatus:second.params.turn.status,followupToolCalls:p.messages.slice(offset).filter(m=>m.method==='item/tool/call').length}));
  if(second.params.turn.status!=='completed')throw new Error('second_turn_failed');
 }finally{await p.connection.close();}
}

async function pausedCancel(){
 const p=await create('paused_cancel');
 try{
  await p.connection.request('turn/start',{threadId:p.threadID,input:text('Retrieve the frozen fact before answering.'),outputSchema:schema});
  const call=await p.wait(m=>m.method==='item/tool/call');
  p.abort.abort();
  await pause(100);
  let lateRejected=false;
  try{p.connection.respond(call.id!,{success:true,contentItems:[{type:'inputText',text:JSON.stringify(record)}]});}catch{lateRejected=true;}
  console.log(JSON.stringify({probe:'paused_cancel',event:'summary',lateToolResultRejected:lateRejected,commits:0}));
  if(!lateRejected)throw new Error('late_tool_result_accepted');
 }finally{await p.connection.close();}
}

async function activeDeadline(){
 const p=await create('active_deadline');
 try{
  await p.connection.request('turn/start',{threadId:p.threadID,input:text('Retrieve the frozen fact before answering.'),outputSchema:schema});
  await pause(50);p.abort.abort();await pause(100);
  let rejected=false;try{await p.connection.request('thread/read',{threadId:p.threadID});}catch{rejected=true;}
  console.log(JSON.stringify({probe:'active_deadline',event:'summary',postDeadlineRequestRejected:rejected,commits:0}));
  if(!rejected)throw new Error('deadline_did_not_close');
 }finally{await p.connection.close();}
}

async function malformedSchema(){
 const p=await create('malformed_schema');
 try{
  let rejected=false;
  try{await p.connection.request('turn/start',{threadId:p.threadID,input:text('Return a minimal result.'),outputSchema:{type:'not-a-json-schema-type'}});
   const result=await p.wait(m=>m.method==='turn/completed');rejected=result.params.turn.status==='failed';
  }catch{rejected=true;}
  console.log(JSON.stringify({probe:'malformed_schema',event:'summary',rejected,commits:0}));
  if(!rejected)throw new Error('invalid_schema_not_rejected');
 }finally{await p.connection.close();}
}

let failures=0;
for(const operation of [continuation,pausedCancel,activeDeadline,malformedSchema]){
 try{await operation();}catch{failures++;console.log(JSON.stringify({probe:operation.name,event:'probe_failed'}));}
}
console.log(JSON.stringify({event:'all_summary',failures,notTested:['real_429','search','images','native_fit']}));
if(failures)process.exitCode=1;
