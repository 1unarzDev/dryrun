// Authored synthetic inputs only; no recorded provider answers. Audit wave 1 REL-01 / CODEX-01 (bd6974a):
// a fallback after Codex restarts from the canonical input plus host-retrieved records, never Codex tool history;
// Codex-served validation failures fail over before being reported; servedBy names the serving provider;
// Groq gets a compact context; quota windows are configurable.
import {describe,it,expect} from 'vitest';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {GeminiPrimaryFallback,fitGroqContext,groqContextBudget,restartHistory,type CodexRoute} from '../src/provider-fallback.js';
import {GroqClient,type GroqMessage} from '../src/groq.js';
import {CodexFailure} from '../src/codex-errors.js';
import {FeatureValidationFailure} from '../src/provider-failure.js';
import {FeatureRunner} from '../src/features.js';
import {Gateway} from '../src/gateway.js';
import {createAIRequestHandler} from '../src/http.js';
import {IntentInterpreter} from '../src/intents.js';
import {quotaLimitsFromEnv,defaultQuotaLimits,OwnerWindowQuota} from '../src/owner-window-quota.js';
import type {AgentProvider,History,ProviderReply} from '../src/provider.js';

const reply=(text:string):ProviderReply=>({steps:[],text,calls:[],usage:{}});
const hasCall=(h:History)=>h.some(s=>s.type==='function_call'||s.type==='function_result');
const hostRecords=(h:History)=>h.filter(s=>s.type==='user_input').map(s=>JSON.stringify(s)).find(t=>t.includes('hostRetrievedRecords'));
/** A scoped Codex double: scripted turns, then (optionally) a turn that stalls until the router aborts it. */
function codexDouble(turns:((input:Parameters<AgentProvider['turn']>[0])=>Promise<ProviderReply>|'stall')[],log:string[]):AgentProvider&{disposed:number}{
 const double={providerID:'codex' as const,disposed:0,async turn():Promise<ProviderReply>{throw new Error('unscoped');},
  scope(options:{signal:AbortSignal}):AgentProvider{let i=0;return {providerID:'codex',disposeOperation(){double.disposed++;},async turn(input){
   log.push('codex');const step=turns[Math.min(i++,turns.length-1)]!(input);
   if(step!=='stall')return step;
   return new Promise((_resolve,reject)=>{const stop=()=>reject(new CodexFailure('cancelled'));const signal=AbortSignal.any([options.signal,input.signal]);if(signal.aborted)stop();else signal.addEventListener('abort',stop,{once:true});});
  }};}};
 return double;
}
const route=(provider:AgentProvider,extra:Partial<CodexRoute>={}):CodexRoute=>({provider,images:false,research:false,turnMs:1200,fallbackReserveMs:1000,...extra});

const snapshot={version:'dryrun.private-context/1' as const,consent:true as const,scope:{householdID:'synthetic-household',origin:'example' as const,sessionID:'session-a'},snapshotID:'snapshot-a',revisions:{household:1,inventory:0,stateFingerprint:'synthetic-v1'},records:[{id:'context.medical.equipment-a',section:'medical' as const,subjectID:'person-a',sourcePath:'equipment.a',status:'recorded' as const,value:{storageInstructions:'Synthetic cool storage',personID:'person-a'}}]};
const contextBinding={scope:snapshot.scope,revisions:snapshot.revisions,snapshotID:snapshot.snapshotID};
const candidate=(id:string,actionID:string)=>({id,actionID,criterionID:'criterion-a',subjectID:'person-a',why:'Authored candidate explanation',evidenceIDs:['household-needs'],completionPredicates:['predicate-a'],editor:'medical',dependencyIDs:[],priority:1});
const preparation=()=>({privateContext:structuredClone(snapshot),contextBinding,household:{revision:1,people:[{id:'person-a',ageBand:'adult',needs:[]}],pets:[],equipment:[],transport:'noCar',limitedBudget:true,regionID:'synthetic',evidence:[{id:'household-needs',origin:'userConfirmed',status:'confirmed',sourceIDs:[],fieldIDs:['equipment.storageInstructions']}]},tasks:[],gaps:[],taskCatalog:[candidate('cold','prep.coldStorage'),candidate('helper','prep.helper')],allowedActionIDs:['prep.coldStorage','prep.helper'],allowedCriterionIDs:['criterion-a']});
const read=(id:string)=>({type:'function_call' as const,id,name:'read_household_context',arguments:{snapshotID:'snapshot-a',sections:['medical']}});
const selection=JSON.stringify({selected:[{candidateID:'cold',why:'Authored synthetic storage decision',evidenceIDs:['household-needs']}],inventoryObservations:[],question:null});

describe('canonical restart after Codex (router)',()=>{
 it('hands Gemini the user input plus host records, never Codex function calls, after a Codex tool call then deadline',async()=>{
  const log:string[]=[];let geminiHistory:History=[];
  const codex=codexDouble([async()=>({steps:[read('codex-1')],text:'',calls:[read('codex-1')],usage:{}}),()=>'stall'],log);
  const gemini:AgentProvider={providerID:'gemini',async turn(input){log.push('gemini');geminiHistory=structuredClone(input.history);return reply('gemini-final');}};
  const router=new GeminiPrimaryFallback(gemini,undefined,45000,route(codex));
  const scoped=router.scope({signal:AbortSignal.timeout(20000),providers:['codex','gemini','groq'],capability:'privateText',timeoutMs:20000});
  const h:History=[{type:'user_input',content:[{type:'text',text:'{"canonical":"synthetic request"}'}]}];
  const first=await scoped.turn({history:h,instruction:'Authored',tools:[],signal:AbortSignal.timeout(20000)});
  h.push(...first.steps,{type:'function_result',name:'read_household_context',call_id:'codex-1',result:[{type:'text',text:JSON.stringify({records:[{id:'context.medical.equipment-a'}],investigationBudget:{remainingToolTurns:7}})}]});
  const second=await scoped.turn({history:h,instruction:'Authored',tools:[],signal:AbortSignal.timeout(20000)});
  expect(second.text).toBe('gemini-final');expect(log).toEqual(['codex','codex','gemini']);
  expect(scoped.attemptProvider).toBe('gemini');expect(scoped.attemptGeneration).toBe(1);expect(codex.disposed).toBe(1);
  expect(hasCall(geminiHistory)).toBe(false);expect(JSON.stringify(geminiHistory[0])).toContain('synthetic request');
  const records=hostRecords(geminiHistory)!;expect(records).toContain('context.medical.equipment-a');expect(records).not.toContain('investigationBudget');
  // Steps the fallback adds later are kept as its own, after the restart input.
  h.push({type:'function_call',id:'gemini-1',name:'read_household_context',arguments:{}});
  await scoped.turn({history:h,instruction:'Authored',tools:[],signal:AbortSignal.timeout(20000)});
  expect(geminiHistory.filter(s=>s.type==='function_call').map(s=>s.type==='function_call'?s.id:'')).toEqual(['gemini-1']);
 });
 it('drops host error results about the abandoned provider and repair prompts about its output',()=>{
  const lead={type:'user_input' as const,content:[{type:'text' as const,text:'canonical'}]};
  const call={type:'function_call' as const,id:'x',name:'evaluateCandidateAction',arguments:{}};
  const bad={type:'function_result' as const,name:'evaluateCandidateAction',call_id:'x',result:[{type:'text' as const,text:'{"error":"invalid_tool_arguments"}'}]};
  const repair={type:'user_input' as const,content:[{type:'text' as const,text:'Output validation: something'}]};
  const abandoned=new WeakSet<object>([call,bad,repair]);
  expect(restartHistory([lead,call,bad,repair],abandoned)).toEqual([lead]);
 });
 it('fails over a Codex-served result only when another consented provider exists',async()=>{
  const codex=codexDouble([async()=>reply('codex')],[]);
  const gemini:AgentProvider={providerID:'gemini',async turn(){return reply('gemini');}};
  const router=new GeminiPrimaryFallback(gemini,undefined,45000,route(codex));
  const only=router.scope({signal:AbortSignal.timeout(20000),providers:['codex'],capability:'privateText'});
  await only.turn({history:[],instruction:'a',tools:[],signal:AbortSignal.timeout(20000)});
  expect(await only.failover!([])).toBe(false);
  const both=router.scope({signal:AbortSignal.timeout(20000),providers:['codex','gemini'],capability:'privateText'});
  await both.turn({history:[],instruction:'a',tools:[],signal:AbortSignal.timeout(20000)});
  expect(await both.failover!([])).toBe(true);expect(both.attemptProvider).toBe('gemini');expect(both.attemptGeneration).toBe(1);
  expect(await both.failover!([])).toBe(false);
 });
});

describe('feature fallback after Codex (end to end through FeatureRunner)',()=>{
 it('Codex reads, then misses its deadline; Gemini serves from the canonical input and host records',async()=>{
  const log:string[]=[];let geminiHistory:History=[];
  const codex=codexDouble([async()=>({steps:[read('codex-read')],text:'',calls:[read('codex-read')],usage:{}}),()=>'stall'],log);
  const gemini:AgentProvider={providerID:'gemini',async turn(input){log.push('gemini');geminiHistory=structuredClone(input.history);return reply(selection);}};
  const runner=new FeatureRunner(new GeminiPrimaryFallback(gemini,undefined,45000,route(codex)));
  const proposal=await runner.run('preparation',preparation(),AbortSignal.timeout(20000),[],'owner-a',['codex','gemini','groq'],20000) as {tasks:{actionID:string}[]};
  expect(proposal.tasks.map(t=>t.actionID)).toEqual(['prep.coldStorage']);expect(runner.servedBy(proposal)).toBe('gemini');
  expect(log).toEqual(['codex','codex','gemini']);expect(hasCall(geminiHistory)).toBe(false);expect(hostRecords(geminiHistory)).toContain('Synthetic cool storage');
 });
 it('fails a twice-rejected Codex-served proposal over to Gemini instead of reporting it',async()=>{
  const log:string[]=[];let codexTurns=0;
  const codex=codexDouble([async()=>{codexTurns++;return codexTurns===1?{steps:[read('r1')],text:'',calls:[read('r1')],usage:{}}:reply(JSON.stringify({selected:[{candidateID:'cold',why:'Authored',evidenceIDs:['invented-evidence']}],inventoryObservations:[],question:null}));}],log);
  const gemini:AgentProvider={providerID:'gemini',async turn(input){log.push('gemini');expect(hasCall(input.history)).toBe(false);expect(JSON.stringify(input.history)).not.toContain('Repair once');return reply(selection);}};
  const runner=new FeatureRunner(new GeminiPrimaryFallback(gemini,undefined,45000,route(codex,{turnMs:20000})));
  const proposal=await runner.run('preparation',preparation(),AbortSignal.timeout(20000),[],'owner-a',['codex','gemini'],20000);
  expect(runner.servedBy(proposal)).toBe('gemini');expect(log).toEqual(['codex','codex','codex','gemini']);
 });
 it('reports provider_validation_failure attributed to Codex (not codex_unavailable) when no fallback is consented',async()=>{
  const codex=codexDouble([async()=>({steps:[read('r1')],text:'',calls:[read('r1')],usage:{}}),async()=>reply(JSON.stringify({selected:[{candidateID:'cold',why:'Authored',evidenceIDs:['invented-evidence']}],inventoryObservations:[],question:null}))],[]);
  const runner=new FeatureRunner(new GeminiPrimaryFallback({providerID:'gemini',async turn(){throw new Error('must_not_run');}},undefined,45000,route(codex,{turnMs:20000})));
  const failure=await runner.run('preparation',preparation(),AbortSignal.timeout(20000),[],'owner-a',['codex'],20000).catch(e=>e);
  expect(failure).toBeInstanceOf(FeatureValidationFailure);expect(failure).toMatchObject({provider:'codex'});
 });
 it('attributes a Codex tool-argument rejection to Codex as provider_validation_failure, or fails over when consented',async()=>{
  const bad={type:'function_call' as const,id:'bad',name:'read_household_context',arguments:{snapshotID:'wrong-snapshot',sections:['medical']}};
  const only=codexDouble([async()=>({steps:[bad],text:'',calls:[bad],usage:{}})],[]);
  const failure=await new FeatureRunner(new GeminiPrimaryFallback({providerID:'gemini',async turn(){throw new Error('must_not_run');}},undefined,45000,route(only,{turnMs:20000}))).run('preparation',preparation(),AbortSignal.timeout(20000),[],'owner-a',['codex'],20000).catch(e=>e);
  expect(failure).toBeInstanceOf(FeatureValidationFailure);expect(failure).toMatchObject({provider:'codex'});
  const log:string[]=[];let geminiTurns=0;
  const codex=codexDouble([async()=>({steps:[bad],text:'',calls:[bad],usage:{}})],log);
  const gemini:AgentProvider={providerID:'gemini',async turn(){log.push('gemini');geminiTurns++;if(geminiTurns===1){return {steps:[read('g1')],text:'',calls:[read('g1')],usage:{}};}return reply(selection);}};
  const runner=new FeatureRunner(new GeminiPrimaryFallback(gemini,undefined,45000,route(codex,{turnMs:20000})));
  const proposal=await runner.run('preparation',preparation(),AbortSignal.timeout(20000),[],'owner-a',['codex','gemini'],20000);
  expect(runner.servedBy(proposal)).toBe('gemini');expect(log).toEqual(['codex','gemini','gemini']);
 });
 it('stops offering tools once 40% of the operation bound is spent so the provider finalizes in time',async()=>{
  let turns=0;const offered:number[]=[];
  const provider:AgentProvider={providerID:'codex',async turn(input){turns++;offered.push(input.tools.length);if(turns===1){await new Promise(r=>setTimeout(r,450));return {steps:[read('slow')],text:'',calls:[read('slow')],usage:{}};}return reply(selection);}};
  const runner=new FeatureRunner(provider);
  await runner.run('preparation',preparation(),AbortSignal.timeout(20000),[],'owner-a',['codex'],1000);
  expect(offered).toEqual([1,0]);
 });
});

describe('director fallback after a Codex tool call',()=>{
 const binding={sessionID:'s',revision:1,eventSequence:1,contextDigest:'abc',householdRevision:1,homeRevision:1};
 const snap={simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]};
 const request={contractVersion:'dryrun.ai/1',requestID:'r-fallback',role:'director',synthetic:true,providerConsent:['codex','gemini','groq'],context:{binding,snapshot:snap,profiles:[]}};
 it('Codex previews, the phone answers, Codex stalls; Gemini finalizes from host records and servedBy says so',async()=>{
  const log:string[]=[];let geminiHistory:History=[];
  const preview={type:'function_call' as const,id:'call-1',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};
  const codex=codexDouble([async()=>({steps:[preview],text:'',calls:[preview],usage:{}}),()=>'stall'],log);
  const gemini:AgentProvider={providerID:'gemini',async turn(input){log.push('gemini');geminiHistory=structuredClone(input.history);return reply(JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Examine actual depletion',evidenceIDs:[]}));}};
  const gateway=new Gateway(new GeminiPrimaryFallback(gemini,undefined,45000,route(codex)));
  const start:any=await gateway.start('owner',request);expect(start.status).toBe('needs_client_tools');expect(start.providerAttemptGeneration).toBe(0);
  const done:any=await gateway.resume('owner',{token:start.token,binding,callID:'call-1',result:{binding,snapshot:snap,contextDigest:'preview-digest'}});
  expect(done.status).toBe('completed');expect(done.servedBy).toBe('gemini');expect(log).toEqual(['codex','codex','gemini']);
  expect(hasCall(geminiHistory)).toBe(false);expect(hostRecords(geminiHistory)).toContain('preview-digest');
 });
 it('reports servedBy codex when Codex completes the director turn',async()=>{
  const preview={type:'function_call' as const,id:'call-1',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};
  const codex=codexDouble([async()=>({steps:[preview],text:'',calls:[preview],usage:{}}),async()=>reply(JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Examine actual depletion',evidenceIDs:[]}))],[]);
  const gateway=new Gateway(new GeminiPrimaryFallback({providerID:'gemini',async turn(){throw new Error('must_not_run');}},undefined,45000,route(codex,{turnMs:20000})));
  const start:any=await gateway.start('owner',{...request,requestID:'r-codex'});
  const done:any=await gateway.resume('owner',{token:start.token,binding,callID:'call-1',result:{binding,snapshot:snap,contextDigest:'abc'}});
  expect(done.status).toBe('completed');expect(done.servedBy).toBe('codex');
 });
});

describe('compact Groq context',()=>{
 it('fits an oversized debrief-like request under the budget, keeping people, tasks and gaps',()=>{
  const portals=Array.from({length:60},(_,n)=>({id:'pt-'+n,kind:'door',a:{x:n,y:n},b:{x:n+1,y:n},sideA:'r-1',sideB:'r-2',verification:'confirmed'}));
  const context={household:{people:[{id:'p-1',needs:['oxygen']}],equipment:[{id:'eq-1',powerRequired:true}]},tasks:[{id:'task-a',actionID:'prep.medicalBackup',why:'Authored',completionPredicates:['x'],dependencyIDs:['d'],editor:'medical'}],gaps:[{category:'water',deficit:2}],
   rubric:{criteria:Array.from({length:80},(_,n)=>({id:'criterion-'+n,predicateIDs:['p'],sourceIDs:['s'.repeat(40)]}))},taskCatalog:Array.from({length:60},(_,n)=>({id:'cat-'+n,actionID:'prep.x',subjectID:'household',criterionID:'c',why:'w'.repeat(120)})),
   scene:{schemaVersion:'dryrun.home-scene/2',rooms:[{id:'r-1',use:'kitchen',floorID:'f',polygon:[]}],portals,planningRoutes:portals,unknowns:[]}};
  const records={hostRetrievedRecords:Array.from({length:40},(_,n)=>({tool:'read_household_context',result:{id:'context.record.'+n,value:'v'.repeat(400)}}))};
  const messages:GroqMessage[]=[{role:'system',content:'Authored'},{role:'user',content:JSON.stringify(context)},{role:'user',content:JSON.stringify(records)}];
  const budget=groqContextBudget(8000,3000,2000);expect(budget).toBeLessThan(20000);
  expect(Buffer.byteLength(JSON.stringify(messages))).toBeGreaterThan(budget);
  const fitted=fitGroqContext(messages,budget);
  expect(Buffer.byteLength(JSON.stringify(fitted))).toBeLessThanOrEqual(budget);
  const kept=JSON.parse(fitted[1]!.content as string);expect(kept.household.people[0].needs).toEqual(['oxygen']);expect(kept.tasks[0].id).toBe('task-a');expect(kept.gaps).toHaveLength(1);
  expect(kept.rubric).toBeUndefined();expect(kept.scene.portals).toBeUndefined();expect(kept.taskCatalog[0]).toEqual({id:'cat-0',actionID:'prep.x',subjectID:'household',criterionID:'c'});
  const shortened=JSON.parse(fitted[2]!.content as string);expect(shortened.truncatedForProvider).toBe(true);expect(shortened.hostRetrievedRecords.length).toBeGreaterThan(0);
  expect(fitGroqContext(fitted,1e9)).toBe(fitted);
 });
 it('sends the compact request through the Groq fallback rather than the full one',async()=>{
  let sentBytes=0;
  const groq=new GroqClient('synthetic',undefined,async(_url,init)=>{sentBytes=Buffer.byteLength(String(init?.body));return Response.json({choices:[{message:{content:'{"summary":"ok"}'}}]});});
  const router=new GeminiPrimaryFallback({providerID:'gemini',async turn(){throw new Error('provider_overloaded');}},groq,45000);
  const scoped=router.scope({signal:AbortSignal.timeout(20000),providers:['gemini','groq'],capability:'privateText'});
  const big=JSON.stringify({tasks:[{id:'task-a'}],rubric:{text:'r'.repeat(60000)}});
  await scoped.turn({history:[{type:'user_input',content:[{type:'text',text:big}]}],instruction:'Authored',tools:[],signal:AbortSignal.timeout(20000)});
  expect(sentBytes).toBeGreaterThan(0);expect(sentBytes).toBeLessThan(30000);
 });
});

describe('configurable owner-window quotas',()=>{
 it('reads positive integer limits from the environment and ignores invalid values',()=>{
  expect(quotaLimitsFromEnv({})).toEqual(defaultQuotaLimits);
  expect(quotaLimitsFromEnv({DRYRUN_FEATURE_TURNS_PER_WINDOW:'400',DRYRUN_DIRECTOR_STARTS_PER_WINDOW:'120',DRYRUN_DIRECTOR_TURNS_PER_WINDOW:'600',DRYRUN_HTTP_REQUESTS_PER_WINDOW:'1000'})).toEqual({featureTurns:400,directorStarts:120,directorTurns:600,httpRequests:1000});
  expect(quotaLimitsFromEnv({DRYRUN_FEATURE_TURNS_PER_WINDOW:'0',DRYRUN_DIRECTOR_TURNS_PER_WINDOW:'many'})).toEqual(defaultQuotaLimits);
 });
 it('reports a director turn-window rejection as the allowlisted owner_window_quota outcome',async()=>{
  const binding={sessionID:'s',revision:1,eventSequence:1,contextDigest:'abc',householdRevision:1,homeRevision:1};
  const request=(id:string)=>({contractVersion:'dryrun.ai/1',requestID:id,role:'director',synthetic:true,context:{binding,snapshot:{simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]},profiles:[]}});
  const provider:AgentProvider={async turn(){const call={type:'function_call' as const,id:'c',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};return {steps:[call],text:'',calls:[call],usage:{}};}};
  const gateway=new Gateway(provider,undefined,1,5);
  expect((await gateway.start('owner',request('q1')) as any).status).toBe('needs_client_tools');
  const second:any=await gateway.start('owner',request('q2'));expect(second).toMatchObject({status:'unavailable',outcome:'owner_window_quota'});
  expect(()=>new OwnerWindowQuota(0)).toThrow('invalid_quota_configuration');
 });
 it('logs allowlisted servedBy, provider and outcome codes on the access log line, and returns servedBy on features',async()=>{
  const lines:string[]=[];const original=console.log;const previous=process.env.DRYRUN_ACCESS_LOG;process.env.DRYRUN_ACCESS_LOG='1';console.log=(line:string)=>{lines.push(line);};
  const proposal={summary:'host',focusTaskIDs:[]};
  const features={run:async()=>proposal,servedBy:(p:unknown)=>p===proposal?'codex':undefined} as unknown as FeatureRunner;
  const secret='synthetic-token-'.padEnd(32,'x');
  const server=createServer(createAIRequestHandler({gateway:{} as Gateway,features,interpreter:new IntentInterpreter({async turn(){throw new Error('unused');}}),authorize:h=>{if(h!=='Bearer '+secret)throw new Error('unauthorized');return 'owner';}}));
  server.listen(0,'127.0.0.1');await once(server,'listening');const address=server.address();if(!address||typeof address==='string')throw new Error('listen');
  try{
   const debrief={household:{revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[]},tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[],debrief:{scenarioID:'flash-flood'}};
   const response=await fetch(`http://127.0.0.1:${address.port}/v1/features`,{method:'POST',headers:{Authorization:'Bearer '+secret},body:JSON.stringify({contractVersion:'dryrun.ai/1',requestID:'r-served',synthetic:true,role:'debrief',context:debrief})});
   const body=await response.json() as Record<string,unknown>;expect(body.servedBy).toBe('codex');
   await new Promise(r=>setTimeout(r,20));
   expect(lines.some(l=>l.includes('/v1/features 200 completed servedBy=codex'))).toBe(true);
  }finally{console.log=original;if(previous===undefined)delete process.env.DRYRUN_ACCESS_LOG;else process.env.DRYRUN_ACCESS_LOG=previous;server.closeAllConnections();server.close();}
 });
});
