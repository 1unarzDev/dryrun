// Authored synthetic inputs only; no recorded provider answers. Wave 3 (2026-10-22) fallback-safety host checks from
// the cleared reports report-v7-debrief-resources-director-six-run-review, report-resources6-two-tool-turns-en-es-review,
// report-groq-compact-debrief-restart-review and report-codex-deadline-restart-gemini-debrief-director-review, plus the
// household-isolation and Gemini director restart conformance checks.
import {afterEach,describe,expect,it,vi} from 'vitest';
import {readFile} from 'node:fs/promises';
const sdk=vi.hoisted(()=>({create:vi.fn()}));
vi.mock('@google/genai',()=>({GoogleGenAI:class {interactions={create:sdk.create};}}));
import {GeminiProvider,SpendBudget,type AgentProvider,type History,type ProviderReply} from '../src/provider.js';
import {FeatureRunner} from '../src/features.js';
import {debriefMustAddress,requireDebriefCoverage,rejectColdStorageWorkaround,rejectIdentifierDerivedNames,rejectEmbeddedMachineTokens,requireEnglishOrSpanish,rejectUtilityDependentPlans} from '../src/fallback-safety.js';
import {GeminiPrimaryFallback,type CodexRoute} from '../src/provider-fallback.js';
import {CodexFailure} from '../src/codex-errors.js';
import {Gateway} from '../src/gateway.js';
import {authorizedContextReader} from '../src/private-context.js';
import {groqDirectorInstruction} from '../src/groq-director.js';

const reply=(text:string):ProviderReply=>({steps:[],text,calls:[],usage:{}});
afterEach(()=>{vi.unstubAllEnvs();sdk.create.mockReset();});

const insulin={id:'eq-insulin',personID:'p-a',essential:true,powerRequired:false,documentation:'unknown' as const,purpose:'refrigeratedMedication',requiresColdStorage:true};
const household={revision:1,people:[{id:'p-a',ageBand:'adult',needs:['limitedMobility']}],pets:[],equipment:[insulin],transport:'noCar',limitedBudget:true,regionID:'synthetic',evidence:[{id:'recorded',origin:'userConfirmed',status:'confirmed',sourceIDs:[],fieldIDs:[]}]};
const task={id:'act.medical.continuity',actionID:'prep.coldStorage',criterionID:'medical',subjectID:'eq-insulin',why:'Authored host reason',evidenceIDs:['recorded'],completionPredicates:[],editor:'medical',dependencyIDs:[],priority:1};
const receipt={version:'dryrun.rehearsal-receipt/1',engineVersion:'cascade-engine/2',variants:[],choices:[{decisionID:'leave',simMinute:30,optionID:'leave-early',recommended:true,label:'Leave early'}],unansweredDecisionIDs:[],
 events:[{id:'evt.flash-flood.svc.grid.unavailable',simMinute:60,phaseID:'impact',severity:'caution'},{id:'evt.flash-flood.svc.device.eq-insulin.unknown',simMinute:60,phaseID:'impact',severity:'caution'},{id:'evt.flash-flood.svc.device.eq-insulin.unavailable',simMinute:300,phaseID:'impact',severity:'critical'},{id:'evt.flash-flood.res.water-depleted',simMinute:900,phaseID:'impact',severity:'critical'},{id:'evt.flash-flood.res.food-depleted',simMinute:900,phaseID:'impact',severity:'caution'}],
 finalServices:{},unmetRequirements:[],unknowns:[],routes:[],interventions:[]};
const debriefInput=(extra:Record<string,unknown>={})=>({household,tasks:[task],gaps:[],allowedActionIDs:['prep.coldStorage'],allowedCriterionIDs:['medical'],locale:'en',debrief:{scenarioID:'flash-flood',rehearsal:receipt},...extra});
const goodSummary='Leaving early was the right call. Stored water ran out, and the refrigerated medication could not stay cold once power failed: ask the pharmacist how long it keeps and what to do first.';

describe('debrief mustAddress coverage',()=>{
 it('groups device events by device and keeps only critical depletions',()=>{
  const groups=debriefMustAddress(receipt);
  expect(groups.map(g=>g.key)).toEqual(['device:eq-insulin','resource:water']);
  expect(groups[0]!.eventIDs).toHaveLength(2);
  expect(()=>requireDebriefCoverage(['evt.flash-flood.svc.device.eq-insulin.unknown','evt.flash-flood.res.water-depleted'],groups,receipt)).not.toThrow();
  expect(()=>requireDebriefCoverage(['evt.flash-flood.res.water-depleted'],groups,receipt)).toThrow('unaddressed_critical_event');
  expect(()=>requireDebriefCoverage(['evt.invented'],groups,receipt)).toThrow('unknown_event');
  expect(debriefMustAddress(undefined)).toEqual([]);
 });
 it('sends the host list, repairs once, then reports unaddressed_critical_event',async()=>{
  const seen:string[]=[];let calls=0,repair='';
  const provider:AgentProvider={providerID:'groq',async turn(input){calls++;seen.push(JSON.stringify(input.history[0]));repair=JSON.stringify(input.history.at(-1));return reply(JSON.stringify({summary:goodSummary,focusTaskIDs:[task.id]}));}};
  await expect(new FeatureRunner(provider).run('debrief',debriefInput())).rejects.toMatchObject({code:'unaddressed_critical_event'});
  expect(calls).toBe(2);expect(repair).toContain('evt.flash-flood.res.water-depleted');expect(seen[0]).toContain('debriefMustAddress');expect(seen[0]).toContain('device:eq-insulin');
 });
 it('accepts a covering answer and returns only summary and focusTaskIDs to the phone',async()=>{
  const provider:AgentProvider={providerID:'gemini',async turn(){return reply(JSON.stringify({summary:goodSummary,focusTaskIDs:[task.id],addressedEventIDs:['evt.flash-flood.svc.device.eq-insulin.unavailable','evt.flash-flood.res.water-depleted']}));}};
  const out:any=await new FeatureRunner(provider).run('debrief',debriefInput());
  expect(Object.keys(out).sort()).toEqual(['focusTaskIDs','summary']);
 });
 it('needs no addressedEventIDs without a receipt',async()=>{
  const provider:AgentProvider={async turn(){return reply(JSON.stringify({summary:'Practice leaving early before water rises, and ask the pharmacist how to keep the medication cold.',focusTaskIDs:[task.id]}));}};
  await expect(new FeatureRunner(provider).run('debrief',debriefInput({debrief:{scenarioID:'flash-flood'}}))).resolves.toBeTruthy();
 });
});

describe('debrief refrigerated-medication, identifier, token and locale checks',()=>{
 it('rejects a power or cooler workaround for non-powered refrigerated medication unless it points to the pharmacist',()=>{
  expect(()=>rejectColdStorageWorkaround(['Set up backup power so the medication stays cold.'],[insulin])).toThrow('cold_storage_workaround');
  expect(()=>rejectColdStorageWorkaround(['Borrow a cooler with ice packs for the medication.'],[insulin])).toThrow('cold_storage_workaround');
  expect(()=>rejectColdStorageWorkaround(['Ask the pharmacist whether a cooler with ice packs is suitable.'],[insulin])).not.toThrow();
  expect(()=>rejectColdStorageWorkaround(['Charge the battery station for the oxygen concentrator.'],[{...insulin,requiresColdStorage:false,powerRequired:true}])).not.toThrow();
 });
 it('fails a Groq debrief with a storage workaround after one repair',async()=>{
  let calls=0;const provider:AgentProvider={providerID:'groq',async turn(){calls++;return reply(JSON.stringify({summary:'Stored water ran out. Keep the refrigerated medication in a powered cooler on backup power.',focusTaskIDs:[task.id],addressedEventIDs:['evt.flash-flood.svc.device.eq-insulin.unknown','evt.flash-flood.res.water-depleted']}));}};
  await expect(new FeatureRunner(provider).run('debrief',debriefInput())).rejects.toMatchObject({code:'cold_storage_workaround'});expect(calls).toBe(2);
 });
 it('rejects a medication name read only from an identifier, allows recorded kinds and recorded medication text',()=>{
  expect(()=>rejectIdentifierDerivedNames(['Plan how to keep the insulin cold.'],household)).toThrow('identifier_derived_name');
  expect(()=>rejectIdentifierDerivedNames(['Plan with the pharmacist for the refrigerated medication.'],household)).not.toThrow();
  const recorded={...household,people:[{...household.people[0]!,essentialMedication:'Insulin pens, keep refrigerated'}]};
  expect(()=>rejectIdentifierDerivedNames(['Plan how to keep the insulin cold.'],recorded)).not.toThrow();
  expect(()=>rejectIdentifierDerivedNames(['Charge the oxygen concentrator.'],{people:[],equipment:[{id:'eq-oxygen',purpose:'oxygenConcentrator',powerRequired:true}]})).not.toThrow();
 });
 it('rejects camelCase or snake_case tokens inside family prose, keeps ordinary names',()=>{
  expect(()=>rejectEmbeddedMachineTokens(['Review the refrigeratedMedication plan.'])).toThrow('machine_token');
  expect(()=>rejectEmbeddedMachineTokens(['Review the eq_insulin plan.'])).toThrow('machine_token');
  expect(()=>rejectEmbeddedMachineTokens(['Charge the iPhone and call McDonald at 8 pm.'])).not.toThrow();
 });
 it('rejects Spanish for an English household and English for a Spanish one, keeps names',()=>{
  expect(()=>requireEnglishOrSpanish(['Pida al farmacéutico las instrucciones para el medicamento antes de que se vaya la luz y guarde agua para la familia.'],'en')).toThrow('wrong_locale');
  expect(()=>requireEnglishOrSpanish(['Ask Abuela Rosa and the pharmacist for the storage instructions before the outage.'],'en')).not.toThrow();
  expect(()=>requireEnglishOrSpanish(['Ask the pharmacist for the instructions before the power goes out and store water for the family.'],'es')).toThrow('wrong_locale');
  expect(()=>requireEnglishOrSpanish(['Pida al farmacéutico las instrucciones para el medicamento.'],'es')).not.toThrow();
  expect(()=>requireEnglishOrSpanish(['anything'],'vi')).not.toThrow();
 });
});

describe('resources: no warming or cooling plan that depends on the lost utility',()=>{
 const plan={id:'plan-a',taskID:'task-heat',dependencyIDs:['p-a'],hazardIDs:['freeze-power-loss'],category:'warmingCooling',purpose:'Buy electric space heaters to keep the older adult warm during the outage.',mandatoryCapabilities:['Space heater retailer'],unknowns:['Stock'],travelMode:'walking',maximumDistanceKm:5,expansionLimit:1,requiredEvidence:['Store identity'],cloudReturnPolicy:'local_only'};
 it('rejects grid-powered warming in a power-loss hazard, accepts a warming place or a self-powered option',()=>{
  expect(()=>rejectUtilityDependentPlans([plan])).toThrow('utility_dependent_plan');
  expect(()=>rejectUtilityDependentPlans([{...plan,purpose:'Find a warming center the older adult can reach with the recorded helper.',mandatoryCapabilities:['Open warming center']}])).not.toThrow();
  expect(()=>rejectUtilityDependentPlans([{...plan,purpose:'Check whether the owned battery station can run an electric blanket for the older adult.'}])).not.toThrow();
  expect(()=>rejectUtilityDependentPlans([{...plan,hazardIDs:['home-fire']}])).not.toThrow();
  expect(()=>rejectUtilityDependentPlans([{...plan,hazardIDs:[]}],()=>['freeze-power-loss'])).toThrow('utility_dependent_plan');
 });
 it('fails a Groq cooling plan through the linked task even without hazard IDs',async()=>{
  const coolTask={...task,id:'task-heat',actionID:'prep.coolingPlan',criterionID:'thermal',subjectID:'p-a'};
  const input={household:{...household,equipment:[]},tasks:[coolTask],gaps:[],allowedActionIDs:['prep.coolingPlan'],allowedCriterionIDs:['thermal'],locale:'en'};
  const cooling={...plan,hazardIDs:[],purpose:'Buy portable air conditioners for the older adult during the heat outage.',mandatoryCapabilities:['Air conditioner retailer']};
  let calls=0;const provider:AgentProvider={providerID:'groq',async turn(){calls++;return reply(JSON.stringify({searchPlans:[cooling],officialRecommendations:[],question:null}));}};
  await expect(new FeatureRunner(provider).run('resources',input)).rejects.toMatchObject({code:'utility_dependent_plan'});expect(calls).toBe(2);
 });
});

describe('Gemini director restart conformance',()=>{
 const binding={sessionID:'s',revision:1,eventSequence:1,contextDigest:'abc',householdRevision:1,homeRevision:1};
 const snap={simMinute:0,resources:{},services:{},unmetRequirements:[],unknowns:[]};
 const request={contractVersion:'dryrun.ai/1',requestID:'r-gemini-restart',role:'director',synthetic:true,providerConsent:['codex','gemini','groq'],context:{binding,snapshot:snap,profiles:[]}};
 it('after a Codex preview and deadline, the restarted Gemini turn is schema-constrained, tool-free and accepted',async()=>{
  vi.stubEnv('DRYRUN_CALL_SPACING_MS','0');
  sdk.create.mockResolvedValue({steps:[],output_text:JSON.stringify({commands:[{kind:'advance',minute:20}],purpose:'Examine the actual depletion at minute twenty and what the family can still decide.',evidenceIDs:[]}),usage:{total_input_tokens:10,total_output_tokens:2}});
  const preview={type:'function_call' as const,id:'call-1',name:'evaluateCandidateAction',arguments:{command:{kind:'advance',minute:20}}};
  let turn=0;
  const codex:AgentProvider={providerID:'codex',async turn(){throw new Error('unscoped');},scope(options){return {providerID:'codex',async turn(input){
   if(turn++===0)return {steps:[preview],text:'',calls:[preview],usage:{}};
   return new Promise<ProviderReply>((_r,reject)=>{const signal=AbortSignal.any([options.signal,input.signal]);const stop=()=>reject(new CodexFailure('cancelled'));if(signal.aborted)stop();else signal.addEventListener('abort',stop,{once:true});});}};}};
  const route:CodexRoute={provider:codex,images:false,research:false,turnMs:1200,fallbackReserveMs:1000};
  const gemini=new GeminiProvider('synthetic-test-secret','gemini-3.1-flash-lite',new SpendBudget(1));
  const gateway=new Gateway(new GeminiPrimaryFallback(gemini,undefined,45000,route));
  const start:any=await gateway.start('owner',request);expect(start.status).toBe('needs_client_tools');
  const done:any=await gateway.resume('owner',{token:start.token,binding,callID:'call-1',result:{binding,snapshot:snap,contextDigest:'preview-digest'}});
  expect(done.status).toBe('completed');expect(done.servedBy).toBe('gemini');
  const body=sdk.create.mock.calls.at(-1)![0];
  expect(body.response_format?.mime_type).toBe('application/json');expect(JSON.stringify(body.response_format.schema)).toContain('commands');
  expect(body.generation_config.tool_choice).toBe('none');
  expect(JSON.stringify(body.input)).not.toContain('function_call');expect(JSON.stringify(body.input)).toContain('hostRetrievedRecords');
 });
});

describe('Groq director instruction follows mechanics v6',()=>{
 it('names origin exclusion, the slow-onset physical opening and wait',()=>{
  const text=groqDirectorInstruction('DryRun RehearsalDirector prompt/32. synthetic dryrun.output-style/1: x');
  expect(text).toContain('Groq/7');expect(text).toContain('excludes that room from every route');expect(text).toContain('at least one physical household choice');
  expect(text).toContain('never put wait in suggestedActions');expect(text).toContain('mechanics/5 and later fire');
 });
});

describe('household isolation at identical revisions',()=>{
 it('rejects a context bound to another household even when every revision counter matches',async()=>{
  // Core writes this cleared synthetic wire on every swift test run (AuthorizedAIContextTests).
  const raw=JSON.parse(await readFile(new URL('../../../fixtures/ai/native-bridge/authorized-context-wire.json',import.meta.url),'utf8'));
  const own={scope:raw.scope,revisions:raw.revisions,snapshotID:raw.snapshotID,...(raw.homeID?{homeID:raw.homeID}:{})};
  expect(()=>authorizedContextReader(raw,'owner-a',own)).not.toThrow();
  const other={...own,scope:{...own.scope,householdID:own.scope.householdID+'-b'},revisions:{...own.revisions,stateFingerprint:own.revisions.stateFingerprint+'0'}};
  expect(other.revisions.household).toBe(own.revisions.household);expect(other.revisions.inventory).toBe(own.revisions.inventory);
  expect(()=>authorizedContextReader(raw,'owner-a',other)).toThrow('stale_context');
  // Same household scope but another household's fingerprint (the A->B->A late-result case) is rejected too.
  expect(()=>authorizedContextReader(raw,'owner-a',{...own,revisions:other.revisions})).toThrow('stale_context');
 });
 it('rejects a feature request whose private context belongs to another household at identical revisions',async()=>{
  const raw=JSON.parse(await readFile(new URL('../../../fixtures/ai/native-bridge/authorized-context-wire.json',import.meta.url),'utf8'));
  const own={scope:raw.scope,revisions:raw.revisions,snapshotID:raw.snapshotID,...(raw.homeID?{homeID:raw.homeID}:{})};
  const other={...own,scope:{...own.scope,householdID:own.scope.householdID+'-b'}};
  const provider:AgentProvider={async turn(){throw new Error('must_not_run');}};
  const input={...debriefInput({debrief:{scenarioID:'flash-flood'}}),household:{...household,revision:raw.revisions.household},privateContext:raw,contextBinding:other};
  await expect(new FeatureRunner(provider).run('debrief',input,undefined,[],'owner-a')).rejects.toThrow('stale_context');
 });
});

// Keep the History import used for type checks of restarted inputs.
export type _History=History;
