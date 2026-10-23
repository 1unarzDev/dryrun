/** Latency probe for Beacon's gateway roles. Run through scripts/perf/beacon-latency.sh (firewall capture).
 *
 * Fires synthetic, fictional-household requests (fixtures/ai/native-bridge) at an already running gateway
 * (DRYRUN_PERF_URL, default http://127.0.0.1:8792) and writes ONLY timing/status/servedBy receipts to
 * DRYRUN_SAFE_RECEIPT. Response bodies are parsed in memory for allowlisted machine codes and then dropped;
 * nothing model-authored is printed or written.
 *
 * Usage: tsx scripts/beacon-latency.ts [runs-per-role 1-5] [roles comma list]
 *   roles: preparation,debrief,resources,director (default all)
 * Token: DRYRUN_DEV_TOKEN from services/ai-orchestrator/.env, loaded by path, never printed. */
import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {parseEnv} from 'node:util';

const receiptPath=process.env.DRYRUN_SAFE_RECEIPT;if(!receiptPath)throw new Error('safe_receipt_path_required');
const runs=Number(process.argv[2]??3);if(!Number.isInteger(runs)||runs<1||runs>5)throw new Error('bounded_runs_required');
const roles=(process.argv[3]??'preparation,debrief,resources,director').split(',').filter(Boolean);
const base=process.env.DRYRUN_PERF_URL??'http://127.0.0.1:8792';
const env=parseEnv(await readFile(process.env.DRYRUN_PERF_ENV??new URL('../.env',import.meta.url),'utf8'));
const token=process.env.DRYRUN_PERF_TOKEN??env.DRYRUN_DEV_TOKEN??'';if(token.length<24)throw new Error('token_required');
const fixtures=new URL('../../../fixtures/ai/native-bridge/',import.meta.url);
const fixture=async(name:string)=>JSON.parse(await readFile(new URL(name,fixtures),'utf8'));
const code=(value:unknown)=>typeof value==='string'&&/^[a-z_0-9]{1,48}$/.test(value)?value:value===undefined?undefined:'other';

type Sample={role:string;label:string;run:number;httpStatus?:number;status?:string;reason?:string;provider?:string;servedBy?:string;outcome?:string;ttfbMS?:number;totalMS:number;bytes?:number;toolRounds?:number;toolNames?:string[]};
const samples:Sample[]=[];

/** POST and time first byte (headers) separately from full body. Body is only machine-code parsed. */
async function post(path:string,body:unknown,deadlineMS:number){
 const start=performance.now();
 const response=await fetch(`${base}/${path}`,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(deadlineMS)});
 const ttfb=performance.now()-start;
 const text=await response.text();const total=performance.now()-start;
 let parsed:any;try{parsed=JSON.parse(text);}catch{parsed=undefined;}
 return {httpStatus:response.status,ttfbMS:Math.round(ttfb),totalMS:Math.round(total),bytes:text.length,body:parsed};
}
const machine=(r:{httpStatus:number;ttfbMS:number;totalMS:number;bytes:number;body:any})=>({httpStatus:r.httpStatus,status:code(r.body?.status),reason:code(r.body?.reason),provider:code(r.body?.provider),servedBy:code(r.body?.servedBy),outcome:code(r.body?.outcome),ttfbMS:r.ttfbMS,totalMS:r.totalMS,bytes:r.bytes});

const families=['oak','lake','pine'];
const hazards=['home-fire','water-outage','flash-flood'];
async function feature(role:'preparation'|'debrief'|'resources',run:number){
 const family=families[(run-1)%families.length]!;
 const request=await fixture(`feature-request-preparation-hh-${family}.json`);
 request.requestID=randomUUID();request.role=role;request.providerConsent=['codex','gemini','groq'];
 if(role==='debrief')request.context.debrief={scenarioID:hazards[(run-1)%hazards.length]};
 const start=performance.now();
 try{const r=await post('v1/features',request,role==='resources'?70_000:95_000);samples.push({role,label:family,run,...machine(r)});}
 catch{samples.push({role,label:family,run,status:'transport_or_deadline',totalMS:Math.round(performance.now()-start)});}
}
async function director(run:number){
 const hazard=['home-fire','water-outage'][(run-1)%2]!;
 const request=await fixture(`director-request-${hazard}.json`);request.requestID=randomUUID();request.providerConsent=['codex','gemini','groq'];
 const binding=request.context.binding;const opStart=performance.now();let rounds=0;const names:string[]=[];
 try{
  let r=await post('v1/operations',request,110_000);samples.push({role:'director_start',label:hazard,run,...machine(r)});
  // Continue with recorded host tool results so each continue is a real model turn; bounded rounds.
  while(r.body?.status==='needs_client_tools'&&rounds<4){
   const call=r.body.calls?.[0];const name=code(call?.name)??'other';names.push(name);
   let result:unknown;try{result=await fixture(`tool-result-${call?.name}.json`);}catch{break;}
   rounds++;
   r=await post('v1/continue',{token:r.body.token,binding,callID:call.id,result},110_000);
   samples.push({role:'director_turn',label:hazard+'#'+rounds,run,...machine(r)});
  }
  samples.push({role:'director_operation',label:hazard,run,status:code(r.body?.status),reason:code(r.body?.reason),servedBy:code(r.body?.servedBy),totalMS:Math.round(performance.now()-opStart),toolRounds:rounds,toolNames:names});
 }catch{samples.push({role:'director_operation',label:hazard,run,status:'transport_or_deadline',totalMS:Math.round(performance.now()-opStart),toolRounds:rounds,toolNames:names});}
}

const started=new Date().toISOString();
try{
 for(let run=1;run<=runs;run++){
  for(const role of roles){
   if(role==='director')await director(run);
   else if(role==='preparation'||role==='debrief'||role==='resources')await feature(role,run);
   console.log(JSON.stringify({event:'perf_progress',role,run,samples:samples.length}));
  }
 }
}finally{
 await writeFile(receiptPath,JSON.stringify({receipt:'dryrun.beacon-latency/1',started,finished:new Date().toISOString(),base,runs,roles,samples},null,1),{mode:0o600});
}
