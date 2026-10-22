/** REVIEWER-ONLY. Exact native synthetic inputs and actual responses go to protected capture.
 *
 * Usage: tsx scripts/codex-feature-eval.ts <input-dir> <repeats 1-3> <condition> [case-order.json]
 *   condition: baseline (preparation/15), candidate (preparation/16), investigation (preparation/15+preparation-investigation/1)
 *   Without a case-order file: <input-dir>/{oak,lake,pine}.json, <repeats> each (development comparison).
 *   With a case-order file (sealed held-out order): a JSON array of case file names (or {file,label}) relative to
 *   <input-dir>, run once each in exactly that order; no reruns. The engineer never opens the case bytes.
 * Stdout (protected): exact inputs, responses, model-issued read_household_context arguments and validation codes.
 * DRYRUN_SAFE_RECEIPT (engineering-visible): allowlisted machine fields, counts and source/profile hashes only. */
import {readFile,writeFile} from 'node:fs/promises';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {configuredCodexProvider} from '../src/codex-config.js';
import {Gateway,fixtureAuthorize} from '../src/gateway.js';
import {FeatureRunner,featureContext,type FeatureEvent} from '../src/features.js';
import {IntentInterpreter} from '../src/intents.js';
import {createAIRequestHandler} from '../src/http.js';

const directory=process.argv[2]??'/private/tmp/dryrun-native-gateway-inputs';
const repeats=Number(process.argv[3]??2);if(!Number.isInteger(repeats)||repeats<1||repeats>3)throw new Error('bounded_repeats_required');
process.env.DRYRUN_CODEX_CAPABILITIES_FILE??=new URL('../profiles/codex-local-synthetic.json',import.meta.url).pathname;
const condition=process.argv[4]??'baseline';if(!['baseline','candidate','investigation'].includes(condition))throw new Error('unknown_condition');
const orderFile=process.argv[5];
const promptVersion=condition==='investigation'?'preparation/15+preparation-investigation/1':condition==='candidate'?'preparation/16':'preparation/15';
const sha=(bytes:string|Buffer)=>createHash('sha256').update(bytes).digest('hex');
// Execution addendum: exact hashes of the prompt/tool/validation source and the capability profile for this run.
const sourceFiles=['features.ts','prompt-experiments.ts','output-quality.ts','private-context.ts','claim-language.ts','codex-provider.ts','codex-schema.ts','codex-runtime.ts','provider-failure.ts','http.ts'];
const sourceHashes=Object.fromEntries(await Promise.all(sourceFiles.map(async f=>[f,sha(await readFile(new URL('../src/'+f,import.meta.url)))])));
const profileHash=sha(await readFile(process.env.DRYRUN_CODEX_CAPABILITIES_FILE));
type Case={file:string;label:string;repetition:number};
const cases:Case[]=[];
if(orderFile){
 const order=JSON.parse(await readFile(orderFile,'utf8'));if(!Array.isArray(order)||!order.length||order.length>40)throw new Error('bounded_case_order_required');
 order.forEach((entry:unknown,index:number)=>{const file=typeof entry==='string'?entry:(entry as {file?:unknown})?.file;const label=typeof entry==='object'&&entry&&typeof (entry as {label?:unknown}).label==='string'?(entry as {label:string}).label:'case-'+(index+1);if(typeof file!=='string'||file.includes('..')||file.startsWith('/'))throw new Error('case_file_relative_required');cases.push({file,label:/^[a-zA-Z0-9_.-]{1,64}$/.test(label)?label:'case-'+(index+1),repetition:1});});
}else for(const family of ['oak','lake','pine'])for(let repetition=1;repetition<=repeats;repetition++)cases.push({file:family+'.json',label:family,repetition});
const provider=await configuredCodexProvider();const secret=randomBytes(32).toString('base64url');
let current:{runID:string;contextReads:number;returned:number;validation:string[]}|undefined;
const observe=(event:FeatureEvent)=>{if(!current)return;console.log(JSON.stringify({event:'protected_feature_event',runID:current.runID,detail:event}));if(event.event==='context_read'){current.contextReads++;current.returned+=event.returned;}else current.validation.push(event.code);};
const server=createServer(createAIRequestHandler({gateway:new Gateway(provider),features:new FeatureRunner(provider,100,undefined,{preparationInvestigation:condition==='investigation',preparationPrompt:condition==='candidate'?16:15},{},observe),interpreter:new IntentInterpreter(provider),authorize:header=>fixtureAuthorize(header,secret,false)}));
server.listen(0,'127.0.0.1');await once(server,'listening');const address=server.address();if(!address||typeof address==='string')throw new Error('listen_failed');
let failed=0;
// Optional engineering-visible receipt: allowlisted machine fields only, never request/response content.
const code=(value:unknown)=>typeof value==='string'&&/^[a-z_0-9]{1,48}$/.test(value)?value:value===undefined?undefined:'other';
const attempts:Record<string,unknown>[]=[];
try{
 for(const item of cases){
  const raw=await readFile(directory+'/'+item.file,'utf8');const request=JSON.parse(raw);request.requestID=randomUUID();request.context.locale??='en';featureContext.parse(request.context);
  const runID=randomUUID();const start=Date.now();current={runID,contextReads:0,returned:0,validation:[]};
  console.log(JSON.stringify({event:'exact_execution_input',runID,case:item.label,file:item.file,repetition:item.repetition,request,promptVersion,capabilities:provider.capabilities}));
  try{
   const response=await fetch(`http://127.0.0.1:${address.port}/v1/features`,{method:'POST',headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},body:JSON.stringify(request),signal:AbortSignal.timeout(95_000)});
   const body=await response.json();console.log(JSON.stringify({event:'protected_feature_response',runID,status:response.status,body,elapsedMS:Date.now()-start}));
   if(!response.ok||body.status!=='completed')failed++;
   const proposal=body?.proposal;
   attempts.push({runID,case:item.label,inputSha256:sha(raw),repetition:item.repetition,condition,httpStatus:response.status,status:code(body?.status),reason:code(body?.reason),provider:code(body?.provider),diagnostic:code(body?.diagnostic),taskCount:Array.isArray(proposal?.tasks)?proposal.tasks.length:undefined,questionPresent:proposal?typeof proposal.question==='string':undefined,contextReads:current.contextReads,recordsReturned:current.returned,validationCodes:current.validation.map(code),elapsedMS:Date.now()-start});
  }catch{failed++;attempts.push({runID,case:item.label,inputSha256:sha(raw),repetition:item.repetition,condition,status:'transport_or_deadline',contextReads:current.contextReads,validationCodes:current.validation.map(code),elapsedMS:Date.now()-start});console.log(JSON.stringify({event:'feature_attempt_failure',runID,reason:'transport_or_deadline',elapsedMS:Date.now()-start}));}
 }
 console.log(JSON.stringify({event:'complete_attempt_receipt',attempts:cases.length,failed,promptVersion}));
 if(failed)process.exitCode=1;
}finally{current=undefined;server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));
 if(process.env.DRYRUN_SAFE_RECEIPT)await writeFile(process.env.DRYRUN_SAFE_RECEIPT,JSON.stringify({receipt:'dryrun.codex-feature-eval/2',inputDirectory:directory,caseOrder:orderFile?'sealed':'development',condition,promptVersion,model:provider.capabilities.model,runtime:provider.capabilities.runtimeVersion,capabilityProfileSha256:profileHash,sourceSha256:sourceHashes,attempts},null,1),{mode:0o600});
}
