// Authored synthetic inputs only. No recorded provider answers/fixtures.
// Released review report-forced-fallback-debrief-director-diagnosis FB1-FB4 and
// report-codex-served-debrief-resources-director-review R1/R2: honest attribution, Groq oversize classification,
// director outcome codes, per-hop harness metadata and resource text rules.
import {describe,it,expect} from 'vitest';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {GeminiPrimaryFallback,type CodexRoute,type ProviderAttemptEvent} from '../src/provider-fallback.js';
import {GroqClient,ProviderFailure,ProviderOperation} from '../src/groq.js';
import {CodexFailure} from '../src/codex-errors.js';
import {FeatureValidationFailure,validatorCode} from '../src/provider-failure.js';
import {FeatureRunner,resourceHostText,type FeatureEvent} from '../src/features.js';
import {Gateway} from '../src/gateway.js';
import {groqDirectorInstruction} from '../src/groq-director.js';
import {createAIRequestHandler} from '../src/http.js';
import {IntentInterpreter} from '../src/intents.js';
import {featurePromptVersions,preparationV16} from '../src/prompt-experiments.js';
import type {AgentProvider,ProviderReply} from '../src/provider.js';

const reply=(text:string):ProviderReply=>({steps:[],text,calls:[],usage:{}});
function codexRoute(provider:AgentProvider):CodexRoute{return {provider,images:false,research:false,turnMs:20000,fallbackReserveMs:1000};}
const failingCodex:AgentProvider={providerID:'codex',async turn(){throw new CodexFailure('unavailable');}};
const household={revision:1,people:[{id:'p-a',ageBand:'adult',needs:['limitedMobility']}],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[{id:'recorded',origin:'userConfirmed',status:'confirmed',sourceIDs:[],fieldIDs:[]}]};
const debrief={household,tasks:[{id:'task-a',actionID:'prep.contact',criterionID:'contact',subjectID:'household',why:'Authored host reason',evidenceIDs:['recorded'],completionPredicates:[],editor:'contacts',dependencyIDs:[],priority:1}],gaps:[],allowedActionIDs:['prep.contact'],allowedCriterionIDs:['contact'],debrief:{scenarioID:'flash-flood'}};

describe('provider-neutral feature validation failure (FB1)',()=>{
 it('attributes a twice-rejected Gemini-served debrief to Gemini with the validator code, never codex_unavailable',async()=>{
  let geminiTurns=0;
  const gemini:AgentProvider={providerID:'gemini',async turn(){geminiTurns++;return reply(JSON.stringify({summary:'Practice leaving early with the recorded helper.',focusTaskIDs:['invented-task']}));}};
  const router=new GeminiPrimaryFallback(gemini,undefined,45000,codexRoute(failingCodex));
  const failure=await new FeatureRunner(router).run('debrief',debrief,AbortSignal.timeout(20000),[],undefined,['codex','gemini']).catch(e=>e);
  expect(failure).toBeInstanceOf(FeatureValidationFailure);expect(failure.message).toBe('provider_validation_failure');
  expect(failure.provider).toBe('gemini');expect(failure.code).toBe('unknown_task');expect(geminiTurns).toBe(2);
 });
 it('reports the repair reason for internal IDs instead of malformed_json',async()=>{
  const seen:string[]=[];
  const provider:AgentProvider={providerID:'codex',async turn(input){seen.push(JSON.stringify(input.history.at(-1)));return reply(JSON.stringify({summary:'Ask p-a which route works before water rises.',focusTaskIDs:['task-a']}));}};
  const events:FeatureEvent[]=[];
  const failure=await new FeatureRunner(provider,40,undefined,{},{},e=>events.push(e)).run('debrief',debrief).catch(e=>e);
  expect(failure).toMatchObject({provider:'codex',code:'internal_id'});expect(seen[1]).toContain('Validation: internal_id');
  expect(events).toEqual([{event:'validation',code:'internal_id',repair:0},{event:'validation',code:'internal_id',repair:1}]);
 });
 it('serves provider_validation_failure over HTTP with provider attribution and keeps it replayable (provider_ prefix)',async()=>{
  const failing={run:async()=>{throw new FeatureValidationFailure('groq','unknown_task');}} as unknown as FeatureRunner;
  const secret='synthetic-token-'.padEnd(32,'x');
  const server=createServer(createAIRequestHandler({gateway:{} as Gateway,features:failing,interpreter:new IntentInterpreter(failingCodex),authorize:h=>{if(h!=='Bearer '+secret)throw new Error('unauthorized');return 'owner';}}));
  server.listen(0,'127.0.0.1');await once(server,'listening');const address=server.address();if(!address||typeof address==='string')throw new Error('listen');
  try{
   const response=await fetch(`http://127.0.0.1:${address.port}/v1/features`,{method:'POST',headers:{Authorization:'Bearer '+secret},body:JSON.stringify({contractVersion:'dryrun.ai/1',requestID:'r-validation',synthetic:true,role:'debrief',providerConsent:['codex','gemini','groq'],context:debrief})});
   const body=await response.json() as Record<string,unknown>;
   expect(response.status).toBe(200);
   expect(body).toEqual({status:'unavailable',reason:'provider_validation_failure',provider:'groq',diagnostic:'unknown_task',preservePriorResult:true,fallback:'existing_local_or_pending'});
  }finally{server.closeAllConnections();server.close();}
 });
 it('keeps provider and budget outcomes as themselves instead of converting them to codex_unavailable',async()=>{
  const gemini:AgentProvider={providerID:'gemini',async turn(){throw new Error('spend_budget');}};
  const router=new GeminiPrimaryFallback(gemini,undefined,45000,codexRoute(failingCodex));
  await expect(new FeatureRunner(router).run('debrief',debrief,AbortSignal.timeout(20000),[],undefined,['codex','gemini'])).rejects.toThrow('spend_budget');
 });
 it('allowlists validator codes',()=>{
  expect(validatorCode('unknown_task')).toBe('unknown_task');expect(validatorCode('Unexpected token < in JSON')).toBe('unclassified');expect(validatorCode('x'.repeat(60))).toBe('unclassified');
 });
});

describe('Groq request larger than the per-minute token ceiling (FB2)',()=>{
 const operation=()=>new ProviderOperation(AbortSignal.timeout(20000),4,1,20000);
 it('classifies an over-ceiling 413 rate_limit_exceeded as request_too_large without a retry hint, and does not resend it',async()=>{
  let sent=0;
  const client=new GroqClient('synthetic',undefined,async()=>{sent++;return Response.json({error:{code:'rate_limit_exceeded',type:'tokens'}},{status:413,headers:{'x-ratelimit-limit-tokens':'1000','retry-after':'21'}});});
  const big=[{role:'user' as const,content:'x'.repeat(20000)}];
  const first:any=await client.request(big,operation()).catch(e=>e);
  expect(first).toBeInstanceOf(ProviderFailure);expect(first.kind).toBe('request_too_large');expect(first.retryAfterMs).toBeUndefined();expect(first.diagnostic).toBe('request_exceeds_token_limit');
  const second:any=await client.request(big,operation()).catch(e=>e);
  expect(second.kind).toBe('request_too_large');expect(sent).toBe(1);
 });
 it('keeps an under-ceiling 413 and any 429 a replayable rate limit',async()=>{
  for(const status of [413,429]){
   const client=new GroqClient('synthetic',undefined,async()=>Response.json({error:{code:'rate_limit_exceeded',type:'tokens'}},{status,headers:{'x-ratelimit-limit-tokens':'200000'}}));
   const failure:any=await client.request([{role:'user',content:'small synthetic request'}],operation()).catch(e=>e);
   expect(failure.kind).toBe('rate_limit');
  }
 });
 it('surfaces provider_request_too_large on the wire with the provider named',async()=>{
  const groq=new GroqClient('synthetic',undefined,async()=>Response.json({error:{code:'rate_limit_exceeded',type:'tokens'}},{status:413,headers:{'x-ratelimit-limit-tokens':'10'}}));
  const router=new GeminiPrimaryFallback({async turn(){throw new Error('provider_rate_limited');}},groq);
  const secret='synthetic-token-'.padEnd(32,'x');
  const server=createServer(createAIRequestHandler({gateway:{} as Gateway,features:{} as FeatureRunner,interpreter:new IntentInterpreter(router),authorize:h=>{if(h!=='Bearer '+secret)throw new Error('unauthorized');return 'owner';}}));
  server.listen(0,'127.0.0.1');await once(server,'listening');const address=server.address();if(!address||typeof address==='string')throw new Error('listen');
  try{
   const {inputDigest}=await import('../src/intents.js');
   const binding={sessionID:'s',revision:0,eventSequence:0,contextDigest:'x',householdRevision:0,homeRevision:0};
   const body={contractVersion:'dryrun.ai/1',requestID:'r-too-large',synthetic:true,providerConsent:['gemini','groq'],submission:{id:'input',text:'Use water.',inputDigest:inputDigest('Use water.'),binding},context:{people:[],rooms:[],portals:[],equipment:[],contacts:[],supplies:[],choices:[]}};
   const decoded=await (await fetch(`http://127.0.0.1:${address.port}/v1/intents`,{method:'POST',headers:{Authorization:'Bearer '+secret},body:JSON.stringify(body)})).json() as Record<string,unknown>;
   expect(decoded.reason).toBe('provider_request_too_large');expect(decoded.provider).toBe('groq');expect(decoded.retryAfterMs).toBeUndefined();
  }finally{server.closeAllConnections();server.close();}
 });
});

describe('director unavailable outcome codes (FB3) and Groq label rule (FB4)',()=>{
 const binding={sessionID:'s',revision:1,eventSequence:1,contextDigest:'abc',householdRevision:1,homeRevision:1};
 const request={contractVersion:'dryrun.ai/1',requestID:'r',role:'director',synthetic:true,context:{binding,snapshot:{simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]},profiles:[]}};
 it('names the outcome, serving provider and last validator code without model text',async()=>{
  const bad:AgentProvider={providerID:'gemini',async turn(){return reply('untrusted synthetic narration');}};
  const result:any=await new Gateway(bad).start('a',request);
  expect(result).toMatchObject({status:'unavailable',reason:'provider_or_validation_failure',outcome:'invalid_output',provider:'gemini',validation:'tool_required'});
  expect(JSON.stringify(result)).not.toContain('untrusted');
 });
 it('names a Codex runtime outcome as codex_<kind>',async()=>{
  const result:any=await new Gateway({providerID:'codex',async turn(){throw new CodexFailure('throttled');}}).start('a',{...request,requestID:'r2'});
  expect(result).toMatchObject({outcome:'codex_throttled',provider:'codex'});expect(result.validation).toBeUndefined();
 });
 it('carries the recognize/review identifyGap label rule into the Groq director prompt',()=>{
  const text=groqDirectorInstruction('DryRun RehearsalDirector prompt/32. FINALIZATION: Keep exact commands. dryrun.output-style/1: details');
  expect(text).toContain('Groq/6');expect(text).toMatch(/never use the words Confirm, Verify or Establish/);
 });
});

describe('per-hop provider metadata for the reviewer harness',()=>{
 it('reports each hop with allowlisted kind/status/code only',async()=>{
  const events:ProviderAttemptEvent[]=[];
  const gemini:AgentProvider={providerID:'gemini',async turn(){throw new ProviderFailure('rate_limit','gemini',429,1000,'RESOURCE_EXHAUSTED','provider_rate_limited');}};
  const groq=new GroqClient('synthetic',undefined,async()=>Response.json({choices:[{message:{content:'{"ok":true}'}}]}));
  const router=new GeminiPrimaryFallback(gemini,groq,45000,codexRoute(failingCodex));router.observe=e=>events.push(e);
  await router.scope({signal:AbortSignal.timeout(20000),providers:['codex','gemini','groq'],capability:'privateText'}).turn({history:[{type:'user_input',content:[{type:'text',text:'synthetic'}]}],instruction:'Authored synthetic routing exercise',tools:[],signal:AbortSignal.timeout(20000)});
  expect(events.map(e=>[e.provider,e.result,e.kind,e.status,e.diagnostic,e.generation])).toEqual([['codex','failed','unavailable',undefined,undefined,0],['gemini','failed','rate_limit',429,'RESOURCE_EXHAUSTED',1],['groq','served',undefined,undefined,undefined,2]]);
 });
});

describe('versioned prompt package and resource text',()=>{
 it('sends preparation/16 by default and keeps preparation/15 selectable as the control',async()=>{
  const instructions:string[]=[];
  const provider:AgentProvider={async turn(input){instructions.push(input.instruction);return reply(JSON.stringify({tasks:[],inventoryObservations:[],question:null}));}};
  const context={household,tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[]};
  await new FeatureRunner(provider).run('preparation',context);await new FeatureRunner(provider,40,undefined,{preparationPrompt:15}).run('preparation',context);
  expect(featurePromptVersions.preparation).toBe(16);
  expect(instructions[0]).toContain('DryRun preparation prompt/16.');expect(instructions[0]).toContain(preparationV16.instruction);
  expect(instructions[1]).toContain('DryRun preparation prompt/15.');expect(instructions[1]).not.toContain('preparation/16 priorities');
 });
 it('sends debrief/4 with the host rehearsal receipt and resources/7 with the internal-ID rule',async()=>{
  const instructions:string[]=[];
  const provider:AgentProvider={async turn(input){instructions.push(input.instruction);return reply(JSON.stringify({summary:'Plan to leave early before water rises with the recorded helper.',focusTaskIDs:['task-a']}));}};
  await new FeatureRunner(provider).run('debrief',debrief);
  expect(instructions[0]).toContain('DryRun debrief prompt/4.');expect(instructions[0]).toContain('never as something the rehearsal showed');expect(instructions[0]).toContain('debrief.rehearsal');
  // D1: the host rehearsal receipt passes the strict context schema and reaches the provider unchanged.
  const receipt={version:'dryrun.rehearsal-receipt/1',engineVersion:'engine-1',variants:[],choices:[{decisionID:'decision-leave',simMinute:30,optionID:'leave-early',recommended:true,label:'Leave early'}],unansweredDecisionIDs:[],events:[{id:'event-warning',simMinute:0,phaseID:'warning',severity:'caution',title:'Flood warning'}],finalServices:{'svc.power':'operational'},unmetRequirements:[],unknowns:[],routes:[],interventions:[]};
  const seen:string[]=[];const withReceipt:AgentProvider={async turn(input){seen.push(JSON.stringify(input.history[0]));return reply(JSON.stringify({summary:'You left early before water rose; keep that plan.',focusTaskIDs:['task-a']}));}};
  await new FeatureRunner(withReceipt).run('debrief',{...debrief,debrief:{scenarioID:'flash-flood',rehearsal:receipt}});
  expect(seen[0]).toContain('leave-early');
  await expect(new FeatureRunner(withReceipt).run('debrief',{...debrief,debrief:{scenarioID:'flash-flood',rehearsal:{...receipt,modelNote:'x'}}})).rejects.toThrow();
 });
 it('rejects internal IDs in user-visible resource plan text, then fails with the validator code',async()=>{
  const plan={id:'plan-a',taskID:'task-a',dependencyIDs:['p-a'],hazardIDs:['flash-flood'],category:'pharmacy',purpose:'Find a pharmacy for context.family.person.p-a',mandatoryCapabilities:['Pharmacy'],unknowns:['Hours'],travelMode:'walking',maximumDistanceKm:5,expansionLimit:1,requiredEvidence:['Pharmacy identity'],cloudReturnPolicy:'local_only'};
  let calls=0;const provider:AgentProvider={providerID:'codex',async turn(input){calls++;expect(input.instruction).toContain('DryRun resources prompt/7.');return reply(JSON.stringify({searchPlans:[plan],officialRecommendations:[],question:null}));}};
  await expect(new FeatureRunner(provider).run('resources',{...debrief,debrief:undefined})).rejects.toMatchObject({code:'internal_id'});expect(calls).toBe(2);
  const clean={...plan,purpose:'Find a pharmacy within walking distance for the recorded medication task.'};
  const ok:any=await new FeatureRunner({async turn(){return reply(JSON.stringify({searchPlans:[clean],officialRecommendations:[],question:null}));}}).run('resources',{...debrief,debrief:undefined});
  expect(ok.searchPlans[0].dependencyIDs).toEqual(['p-a']);
 });
 it('renders host-owned CO-alarm text in the selected locale',async()=>{
  const coTask={...debrief.tasks[0],id:'co',actionID:'prep.coAlarms',criterionID:'co'};
  const plan={id:'plan-co',taskID:'co',dependencyIDs:[],hazardIDs:['home-fire'],category:'hardware',purpose:'Model text',mandatoryCapabilities:['Model'],unknowns:['Model'],travelMode:'walking',maximumDistanceKm:5,expansionLimit:1,requiredEvidence:['Model'],cloudReturnPolicy:'local_only'};
  for(const locale of ['en','es','vi'] as const){
   const out:any=await new FeatureRunner({async turn(){return reply(JSON.stringify({searchPlans:[plan],officialRecommendations:[],question:null}));}}).run('resources',{...debrief,debrief:undefined,locale,tasks:[coTask],allowedActionIDs:['prep.coAlarms'],allowedCriterionIDs:['co']});
   expect(out.searchPlans[0].purpose).toBe(resourceHostText(locale).coAlarms.purpose);expect(out.searchPlans[0].requiredEvidence).toEqual(resourceHostText(locale).coAlarms.requiredEvidence);
  }
  expect(resourceHostText('es').coAlarms.purpose).not.toBe(resourceHostText('en').coAlarms.purpose);
 });
});
