/** REVIEWER-ONLY live check of the production provider chain (Codex → Gemini → Groq) for the roles the phone
 * calls. Run it only under scripts/review/firewall.py capture: stdout carries exact execution inputs and actual
 * responses (protected). The only engineering-visible output is a safe receipt file of allowlisted machine
 * fields (run IDs, role, family, HTTP/status/reason codes, which provider served each turn, timing and
 * deterministic host-validation counts) written to DRYRUN_SAFE_RECEIPT (required).
 *
 * Usage: tsx scripts/codex-role-eval.ts <debrief-dir> <resources-request> <hazards,comma-separated>
 * Spend: one attempt per input; FeatureRunner/Gateway quotas, the Codex 10-call operation bound and
 * DRYRUN_MAX_USD (default 1) for Gemini apply. No retries until success. */
import {readFile,writeFile} from 'node:fs/promises';
import {randomBytes,randomUUID} from 'node:crypto';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {parseEnv} from 'node:util';
import {serviceEnvFile} from '../src/codex-config.js';
import {configuredProviders} from '../src/provider-routing.js';
import {Gateway,directorPrompt,fixtureAuthorize} from '../src/gateway.js';
import {featurePromptVersions} from '../src/prompt-experiments.js';
import {FeatureRunner,featureContext} from '../src/features.js';
import {IntentInterpreter} from '../src/intents.js';
import {createAIRequestHandler} from '../src/http.js';
import {PublicEvidenceTools} from '../src/evidence.js';
import {minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {Host} from './host.js';
import {executeDirectorTool} from './director-tools.js';
import {GeminiPrimaryFallback,type ProviderAttemptEvent} from '../src/provider-fallback.js';

const receiptPath=process.env.DRYRUN_SAFE_RECEIPT;if(!receiptPath)throw new Error('safe_receipt_path_required');
const [debriefDir,resourcesRequest,hazardList]=process.argv.slice(2);
const service=parseEnv(await readFile(serviceEnvFile(),'utf8'));
const env={...service,...process.env,DRYRUN_PROVIDER:'codex',DRYRUN_CODEX_CAPABILITIES_FILE:process.env.DRYRUN_CODEX_CAPABILITIES_FILE??new URL('../profiles/codex-local-synthetic.json',import.meta.url).pathname,DRYRUN_MAX_USD:process.env.DRYRUN_MAX_USD??'1'};
process.env.DRYRUN_MAX_USD=env.DRYRUN_MAX_USD;
const notes:string[]=[];
const {provider,codex,groqClients}=await configuredProviders(env,line=>notes.push(line.split(':')[0]!));
// Per-hop provider metadata (allowlisted machine fields) for the protected bundle and the receipt.
const hops:ProviderAttemptEvent[]=[];if(provider instanceof GeminiPrimaryFallback)provider.observe=event=>{hops.push(event);console.log(JSON.stringify({event:'provider_attempt',...event}));};
const hopSummary=(from:number)=>hops.slice(from).map(h=>[h.provider,h.result,h.kind,h.status,h.diagnostic].filter(v=>v!==undefined).map(v=>typeof v==='number'?String(v):code(v)).join(':'));
// Optional resources locale override for paired en/es checks (DRYRUN_RESOURCES_LOCALES=en,es).
const resourceLocales=(process.env.DRYRUN_RESOURCES_LOCALES??'').split(',').filter(l=>['en','es','vi'].includes(l));
const features=new FeatureRunner(provider,40,await PublicEvidenceTools.bundled('../..'));const gateway=new Gateway(provider);
const secret=randomBytes(32).toString('base64url');
const server=createServer(createAIRequestHandler({gateway,features,interpreter:new IntentInterpreter(provider),authorize:header=>fixtureAuthorize(header,secret,false)}));
server.listen(0,'127.0.0.1');await once(server,'listening');const address=server.address();if(!address||typeof address==='string')throw new Error('listen_failed');
const post=async(path:string,body:unknown)=>{const response=await fetch(`http://127.0.0.1:${address.port}/${path}`,{method:'POST',headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(110_000)});return {status:response.status,body:await response.json() as any};};
/** Machine-code allowlist: nothing model-authored can pass these filters into the receipt. */
const code=(value:unknown)=>typeof value==='string'&&/^[a-z_0-9]{1,48}$/.test(value)?value:value===undefined?undefined:'other';
const servedBy=(usage:unknown[])=>usage.map(u=>{const p=u&&typeof u==='object'?(u as any).provider:undefined;return p==='codex'||p==='groq'?p:'gemini';});
const attempts:Record<string,unknown>[]=[];
const record=(entry:Record<string,unknown>)=>{attempts.push(entry);};
try{
 for(const family of ['oak','lake','pine']){
  if(!debriefDir)break;
  const request=JSON.parse(await readFile(`${debriefDir}/debrief-${family}.json`,'utf8'));request.requestID=randomUUID();featureContext.parse(request.context);
  const runID=randomUUID(),start=Date.now(),usageStart=features.usage.length,hopStart=hops.length;
  console.log(JSON.stringify({event:'exact_execution_input',runID,role:'debrief',family,request}));
  try{const r=await post('v1/features',request);console.log(JSON.stringify({event:'protected_feature_response',runID,response:r}));
   record({runID,role:'debrief',family,input:`${debriefDir}/debrief-${family}.json`,httpStatus:r.status,status:code(r.body?.status),reason:code(r.body?.reason),provider:code(r.body?.provider),diagnostic:code(r.body?.diagnostic),servedBy:servedBy(features.usage.slice(usageStart)),hops:hopSummary(hopStart),elapsedMS:Date.now()-start});}
  catch{record({runID,role:'debrief',family,status:'transport_or_deadline',servedBy:servedBy(features.usage.slice(usageStart)),elapsedMS:Date.now()-start});}
 }
 if(resourcesRequest){
  for(const locale of resourceLocales.length?resourceLocales:[undefined]){
  const request=JSON.parse(await readFile(resourcesRequest,'utf8'));request.requestID=randomUUID();if(locale)request.context.locale=locale;featureContext.parse(request.context);
  const runID=randomUUID(),start=Date.now(),usageStart=features.usage.length,hopStart=hops.length;
  console.log(JSON.stringify({event:'exact_execution_input',runID,role:'resources',request}));
  try{const r=await post('v1/features',request);console.log(JSON.stringify({event:'protected_feature_response',runID,response:r}));
   record({runID,role:'resources',locale:locale??code(request.context.locale)??'en',input:resourcesRequest,httpStatus:r.status,status:code(r.body?.status),reason:code(r.body?.reason),provider:code(r.body?.provider),diagnostic:code(r.body?.diagnostic),servedBy:servedBy(features.usage.slice(usageStart)),hops:hopSummary(hopStart),elapsedMS:Date.now()-start});}
  catch{record({runID,role:'resources',status:'transport_or_deadline',servedBy:servedBy(features.usage.slice(usageStart)),hops:hopSummary(hopStart),elapsedMS:Date.now()-start});}
  }
 }
 const hazards=(hazardList??'').split(',').filter(Boolean);
 if(hazards.length){
  const host=new Host();
  try{
   for(const hazard of hazards){
    const runID=randomUUID(),start=Date.now(),usageStart=gateway.metrics.usage.length,outcomeStart=gateway.metrics.outcomes.length,validationStart=gateway.metrics.validationFailures.length,hopStart=hops.length;let toolRounds=0,status='not_started',reason:string|undefined,responseOutcome:string|undefined,responseProvider:string|undefined,committed=false,offered=0,hostAccepted=0,generation:number|undefined;
    try{
     const state=await host.request({op:'initialize',scenarioID:hazard});
     const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
     const context={binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),experience:state.receipt.experience,household:state.householdContext,homeScene:state.homeScene,profiles:state.directorProfiles,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,lastAction:state.lastAction,recentActions:state.recentActions,learningObjectives:['Offer concrete household actions and respond to their computed effects; teach this selected hazard.']};
     const request={contractVersion:'dryrun.ai/1',requestID:randomUUID(),role:'director',synthetic:true,providerConsent:['codex','gemini','groq'],context};
     console.log(JSON.stringify({event:'exact_execution_input',runID,role:'director',hazard,request}));
     let r=await post('v1/operations',request);console.log(JSON.stringify({event:'protected_director_response',runID,response:r}));
     while(r.body?.status==='needs_client_tools'&&toolRounds<12){
      toolRounds++;const call=r.body.calls[0];const tool=await executeDirectorTool(host,state,binding,call);
      console.log(JSON.stringify({event:'host_tool_result',runID,tool:call.name,result:tool.result}));
      r=await post('v1/continue',{token:r.body.token,binding,callID:call.id,result:tool.result});console.log(JSON.stringify({event:'protected_director_response',runID,response:r}));
     }
     status=code(r.body?.status)??'other';reason=code(r.body?.reason);responseOutcome=code(r.body?.outcome);responseProvider=code(r.body?.provider);generation=typeof r.body?.providerAttemptGeneration==='number'?r.body.providerAttemptGeneration:undefined;
     if(r.body?.status==='completed'){
      // Deterministic Core authority: the host must accept the proposal and preview each offered action.
      try{const after=await host.request({op:'directorCommit',session:state.session,proposal:r.body.proposal,binding});committed=true;
       for(const action of r.body.proposal.suggestedActions??[]){offered++;try{await host.request({op:'preview',session:after.session,commit:{id:`check-${offered}`,actor:'user',baseRevision:after.receipt.revision,commands:action.commands}});hostAccepted++;}catch{/* counted as rejected */}}
      }catch{committed=false;}
     }
    }catch{status=status==='not_started'?'harness_failure':status;}
    record({runID,role:'director',hazard,status,reason,outcome:responseOutcome,provider:responseProvider,hops:hopSummary(hopStart),toolRounds,hostCommitAccepted:committed,suggestedActionsOffered:offered,suggestedActionsHostAccepted:hostAccepted,providerAttemptGeneration:generation,servedBy:servedBy(gateway.metrics.usage.slice(usageStart)),
     // Gateway machine codes only; a schema failure keeps just its category before ':'.
     gatewayOutcomes:gateway.metrics.outcomes.slice(outcomeStart).map(code),validationFailures:gateway.metrics.validationFailures.slice(validationStart).map(v=>code(v.split(':')[0])),elapsedMS:Date.now()-start});
   }
  }finally{host.close();}
 }
}finally{
 server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));
 await writeFile(receiptPath,JSON.stringify({receipt:'dryrun.codex-role-eval/2',promptVersions:{debrief:'debrief/'+featurePromptVersions.debrief,resources:'resources/'+featurePromptVersions.resources,director:directorPrompt.version},chain:[...(codex?['codex']:[]),'gemini',...(groqClients?['groq']:[])],configurationNotes:notes.map(code),codexModel:codex?.capabilities.model,codexRuntime:codex?.capabilities.runtimeVersion,attempts},null,1),{mode:0o600});
}
process.exit(attempts.every(a=>a.status==='completed'&&(a.role!=='director'||a.hostCommitAccepted===true))?0:1);
