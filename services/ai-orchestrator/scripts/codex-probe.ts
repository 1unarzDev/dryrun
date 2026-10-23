/** REVIEWER ONLY execution: stdout contains protected runtime output. Use firewall capture. */
import {readFile} from 'node:fs/promises';
import {parseEnv} from 'node:util';
import {launchCodex,codexRuntimeVersion,codexEndpoint} from '../src/codex-runtime.js';

const env=parseEnv(await readFile(new URL('../.env',import.meta.url),'utf8'));
const key=process.env.CODEX_LB_API_KEY??env.CODEX_LB_API_KEY??'';
if(!key)throw new Error('missing_provider_secret');
const model=process.argv[2];if(!model)throw new Error('explicit_probe_model_required');
const abort=new AbortController();const timer=setTimeout(()=>abort.abort(),65_000);
const connection=await launchCodex(key,model,abort.signal);
let tools=0,finals=0,deltas=0,successfulTerminal=false;
let end!:()=>void;const completed=new Promise<void>(resolve=>{end=resolve});
connection.onFailure=()=>{console.log(JSON.stringify({event:'runtime_failed'}));end();};
connection.onMessage=m=>{
 // All actual content is protected. Only a fresh output reviewer reads this transcript.
 console.log(JSON.stringify(m));
 if(m.method==='item/agentMessage/delta')deltas++;
 if(m.method==='item/tool/call'&&m.id!==undefined){
  if(m.params?.tool!=='read_household_context'||tools++>1){abort.abort();return;}
  connection.respond(m.id,{success:true,contentItems:[{type:'inputText',text:JSON.stringify({snapshotID:'synthetic-context-v1',memberID:'person-a',factID:'equipment-a-runtime',equipment:'synthetic backup',recordedRuntimeHours:3,requiredHours:8,status:'confirmed',instruction:'Use only recorded quantities. No clinical settings.'})}]});
 }
 if(m.method==='turn/completed'){finals++;successfulTerminal=m.params?.turn?.status==='completed';end();}
};
try{
 const init=await connection.request('initialize',{clientInfo:{name:'dryrun_capability_probe',version:'1'},capabilities:{experimentalApi:true}});console.log(JSON.stringify({event:'initialized',init,runtimeVersion:codexRuntimeVersion,endpoint:codexEndpoint,model}));connection.notify('initialized');
 const started=await connection.request('thread/start',{model,modelProvider:'dryrun_lb',approvalPolicy:'never',sandbox:'read-only',ephemeral:true,baseInstructions:'DryRun synthetic compatibility probe. No real person or emergency. Call read_household_context to retrieve equipment runtime; do not guess. Then report the recorded deficit in hours. No clinical advice or commitments.',dynamicTools:[{type:'function',name:'read_household_context',description:'Read authorized synthetic equipment record. Read only; no household argument accepted.',inputSchema:{type:'object',properties:{},additionalProperties:false}}]});
 const schema={type:'object',properties:{factID:{type:'string'},deficitHours:{type:'number'},limitation:{type:'string'}},required:['factID','deficitHours','limitation'],additionalProperties:false};
 await connection.request('turn/start',{threadId:started.thread.id,input:[{type:'text',text:'Snapshot synthetic-context-v1 has one confirmed equipment runtime fact retrievable only through read_household_context. Retrieve it, calculate the shortfall against recorded required hours, and identify the factID. Return JSON.',text_elements:[]}],outputSchema:schema});
 await completed;
 console.log(JSON.stringify({event:'probe_receipt',tools,finals,deltas}));
 if(!successfulTerminal||tools<1)process.exitCode=1;
}finally{clearTimeout(timer);await connection.close();}
