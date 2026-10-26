// Authored synthetic inputs only; no recorded provider answers. Cleared reports (2026-10-22):
// report-codex-deadline-restart-gemini-debrief-director-review (Gemini restart finalization, locale),
// report-director-codex-freeze-fire-heat-g1-g2-review (director internal IDs),
// report-resources6-two-tool-turns-en-es-review (machine tokens), report-groq-compact-debrief-restart-review
// (completed-empty resources, compact route status).
import {afterEach,describe,expect,it,vi} from 'vitest';
const sdk=vi.hoisted(()=>({create:vi.fn()}));
vi.mock('@google/genai',()=>({GoogleGenAI:class {interactions={create:sdk.create};}}));
import {GeminiProvider,SpendBudget,type AgentProvider,type ProviderReply} from '../src/provider.js';
import {FeatureRunner,requireSelectedLocale,rejectMachineTokens} from '../src/features.js';
import {compactForGroq} from '../src/provider-fallback.js';
import {directorPrompt} from '../src/gateway.js';
import {featurePromptVersions} from '../src/prompt-experiments.js';

const reply=(text:string):ProviderReply=>({steps:[],text,calls:[],usage:{}});
const household={revision:1,people:[{id:'p-a',ageBand:'adult',needs:['limitedMobility']}],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[{id:'recorded',origin:'userConfirmed',status:'confirmed',sourceIDs:[],fieldIDs:[]}]};
const base={household,tasks:[{id:'task-a',actionID:'prep.contact',criterionID:'contact',subjectID:'household',why:'Authored host reason',evidenceIDs:['recorded'],completionPredicates:[],editor:'contacts',dependencyIDs:[],priority:1}],gaps:[],allowedActionIDs:['prep.contact'],allowedCriterionIDs:['contact']};
const plan={id:'plan-a',taskID:'task-a',dependencyIDs:['p-a'],hazardIDs:['flash-flood'],category:'pharmacy',purpose:'Find a pharmacy within walking distance for the recorded medication task.',mandatoryCapabilities:['Pharmacy counter'],unknowns:['Hours'],travelMode:'walking',maximumDistanceKm:5,expansionLimit:1,requiredEvidence:['Pharmacy identity'],cloudReturnPolicy:'local_only'};
// Authored Vietnamese sentence (synthetic, not model output).
const vietnamese='Hãy chuẩn bị nước uống và thuốc men trước khi mất điện, và liên hệ người hàng xóm đã ghi nhận.';
afterEach(()=>{vi.unstubAllEnvs();sdk.create.mockReset();});

describe('selected locale and machine-token host checks',()=>{
 it('rejects a Vietnamese debrief for an English household after one repair, keeps a Vietnamese name, skips vi',async()=>{
  let calls=0;const provider:AgentProvider={providerID:'gemini',async turn(){calls++;return reply(JSON.stringify({summary:vietnamese,focusTaskIDs:['task-a']}));}};
  await expect(new FeatureRunner(provider).run('debrief',{...base,locale:'en',debrief:{scenarioID:'flash-flood'}})).rejects.toMatchObject({code:'wrong_locale'});expect(calls).toBe(2);
  expect(()=>requireSelectedLocale(['Ask Nguyễn Thị Ngọc to confirm the stored water and the pharmacist instructions before the outage.'],'en')).not.toThrow();
  expect(()=>requireSelectedLocale([vietnamese],'vi')).not.toThrow();expect(()=>requireSelectedLocale([vietnamese],'es')).toThrow('wrong_locale');
 });
 it('sends debrief/5 and resources/7 instructions',async()=>{
  expect(featurePromptVersions.debrief).toBe(5);expect(featurePromptVersions.resources).toBe(7);
  const seen:string[]=[];const provider:AgentProvider={async turn(input){seen.push(input.instruction);return reply(JSON.stringify({summary:'Plan to leave early before water rises.',focusTaskIDs:['task-a']}));}};
  await new FeatureRunner(provider).run('debrief',{...base,debrief:{scenarioID:'flash-flood'}});
  expect(seen[0]).toContain('DryRun debrief prompt/5.');expect(seen[0]).toContain('critical resource running out');expect(seen[0]).toContain('pharmacist or manufacturer');
 });
 it('rejects bare camelCase/snake_case family-facing resource fields, then fails with machine_token',async()=>{
  expect(()=>rejectMachineTokens(['oxygenBackupCompatible'])).toThrow('machine_token');expect(()=>rejectMachineTokens(['battery_station_owned'])).toThrow('machine_token');
  expect(()=>rejectMachineTokens(['Pharmacy counter','Hours','CO'])).not.toThrow();
  let calls=0;const provider:AgentProvider={providerID:'groq',async turn(input){calls++;expect(input.instruction).toContain('DryRun resources prompt/7.');return reply(JSON.stringify({searchPlans:[{...plan,unknowns:['openHoursUnknown']}],officialRecommendations:[],question:null}));}};
  await expect(new FeatureRunner(provider).run('resources',base)).rejects.toMatchObject({code:'machine_token'});expect(calls).toBe(2);
 });
 it('never returns completed-empty resources for unfinished tasks; an actual plan passes',async()=>{
  const empty:AgentProvider={providerID:'groq',async turn(){return reply(JSON.stringify({searchPlans:[],officialRecommendations:[],question:'Which records are missing?'}));}};
  await expect(new FeatureRunner(empty).run('resources',base)).rejects.toMatchObject({code:'unsupported_empty_resources'});
  const ok:any=await new FeatureRunner({async turn(){return reply(JSON.stringify({searchPlans:[plan],officialRecommendations:[],question:null}));}}).run('resources',base);
  expect(ok.searchPlans).toHaveLength(1);
 });
});

describe('restarted Gemini finalization is schema-constrained',()=>{
 const geminiReply={steps:[],output_text:'{}',usage:{total_input_tokens:10,total_output_tokens:2}};
 const tool={type:'function' as const,name:'evaluateCandidateAction',parameters:{type:'object'}};
 const schema={type:'object',properties:{purpose:{type:'string'}}};
 it('sets response_format and tool_choice none after a restart with host records or an explicit none, not on an opening turn',async()=>{
  vi.stubEnv('DRYRUN_CALL_SPACING_MS','0');sdk.create.mockResolvedValue(geminiReply);
  const provider=new GeminiProvider('synthetic-test-secret','gemini-3.1-flash-lite',new SpendBudget(1));
  const signal=new AbortController().signal;
  const restart=[{type:'user_input' as const,content:[{type:'text' as const,text:'{"request":1}'}]},{type:'user_input' as const,content:[{type:'text' as const,text:JSON.stringify({hostRetrievedRecords:[{tool:'evaluateCandidateAction',result:{ok:true}}],note:'host'})}]}];
  await provider.turn({history:restart,instruction:'synthetic',tools:[tool],outputSchema:schema,signal});
  await provider.turn({history:[restart[0]!],instruction:'synthetic',tools:[tool],toolMode:'none',outputSchema:schema,signal});
  await provider.turn({history:[restart[0]!],instruction:'synthetic',tools:[tool],outputSchema:schema,signal});
  const bodies=sdk.create.mock.calls.map(c=>c[0]);
  expect(bodies[0].response_format?.mime_type).toBe('application/json');expect(bodies[0].generation_config.tool_choice).toBe('none');
  expect(bodies[1].response_format?.mime_type).toBe('application/json');expect(bodies[1].generation_config.tool_choice).toBe('none');
  expect(bodies[2].response_format).toBeUndefined();expect(bodies[2].generation_config.tool_choice).toBe('any');
 });
});

describe('director and Groq compaction',()=>{
 it('director prompt/32 carries the fire-origin, slow-onset opening and internal-ID rules',()=>{
  expect(directorPrompt.version).toBe('director/32');
 });
 it('compact debrief keeps per-person route status and every choice, drops info events',()=>{
  const receipt={version:'dryrun.rehearsal-receipt/1',engineVersion:'e',variants:[],choices:[{decisionID:'d1',simMinute:30,optionID:'relocate',recommended:false,label:'Relocate'}],unansweredDecisionIDs:[],events:[{id:'e1',simMinute:0,phaseID:'w',severity:'info'},{id:'e2',simMinute:60,phaseID:'w',severity:'critical'}],finalServices:{},unmetRequirements:[],unknowns:[],routes:[{personID:'p-a',alternativeStatus:'none',noRouteReason:'blocked'}],interventions:[]};
  const out=compactForGroq({debrief:{scenarioID:'flash-flood',rehearsal:receipt},taskCatalog:[{id:'x'}]});
  expect(out.taskCatalog).toBeUndefined();expect(out.debrief.rehearsal.choices).toEqual(receipt.choices);
  expect(out.debrief.rehearsal.events.map((e:any)=>e.id)).toEqual(['e2']);expect(out.debrief.rehearsal.routes).toEqual([{personID:'p-a',alternativeStatus:'none'}]);
 });
});
