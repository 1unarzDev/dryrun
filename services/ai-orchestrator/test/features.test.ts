import {describe,it,expect} from 'vitest';
import {featureContext,imageManifest,homeOutput,resourcePlan,strategyFingerprint} from '../src/features.js';
import {PublicEvidenceTools,validateOfficialCapability} from '../src/evidence.js';
import {resolve} from 'node:path';
describe('feature privacy and provenance',()=>{
 it('finds actual bundled Tarrant records and preserves unknown capability',async()=>{const tools=await PublicEvidenceTools.bundled(resolve('../..'));const rows=tools.find_official_resources('48439','all');expect(rows.length).toBeGreaterThan(0);expect(rows.every(r=>r.reviewState==='needsReview'&&r.capabilitiesVerified===false)).toBe(true);expect(tools.find_official_resources('99999','all')).toEqual([]);expect(()=>tools.read_resource_evidence('http://127.0.0.1')).toThrow();expect(validateOfficialCapability({resourceID:'r',field:'acceptsPets',value:true},[{id:'r'}])).toBe(false);});
 it('prohibits map payloads and mixed-unit geometry in cloud context',()=>{expect(()=>featureContext.parse({household:{name:'private'},tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[]})).toThrow();expect(()=>resourcePlan.parse({cloudReturnPolicy:'send_listings'})).toThrow();expect(()=>imageManifest.parse({digest:'unbound-file'})).toThrow();});
 it('requires visible concern alternatives and bounded submitted-image boxes',()=>{expect(()=>homeOutput.parse({concerns:[{box:[1,0,0,1]}],limitations:[]})).toThrow();});
});

describe('cross-language recorded contracts',()=>{
 it('parses actual Swift manifests and Gemini proposal fixtures with strict TS schemas',async()=>{
  const {readFile}=await import('node:fs/promises');const {directorOutput}=await import('../src/contracts.js');
  const images=JSON.parse(await readFile('../../fixtures/ai/images/annotations.json','utf8'));for(const c of images.cases)expect(imageManifest.safeParse(c.manifest).success).toBe(true);
  for(const action of ['all','essential']){const trace=JSON.parse(await readFile(`../../fixtures/ai/adaptive-trace-${action}.json`,'utf8'));for(const t of trace.trace)if(t.result?.proposal){const {id,actor,baseRevision,...proposal}=t.result.proposal;expect(directorOutput.safeParse(proposal).success).toBe(true);}}
 });
});

it('blocks a council critical false pass against committed predicates',async()=>{
 const {reconcileCouncil}=await import('../src/features.js');
 const result=reconcileCouncil({assessments:[{criterionID:'device',status:'met',evidenceIDs:['e'],reason:'unsupported pass'}],question:null},{rubric:{version:'test',criteria:[{id:'device',predicateIDs:['approvedAlternative','capacity'],applicabilityRule:'no-device'}]},acceptedPredicates:[{criterionID:'device',predicates:{approvedAlternative:false},evidenceIDs:['e']}]} as any);
 expect(result.accepted[0]?.status).toBe('partlyMet');expect(result.disagreements).toHaveLength(1);
});

it('rejects a driving search strategy for a household with no car after bounded repair',async()=>{
 const {readFile}=await import('node:fs/promises');const {FeatureRunner}=await import('../src/features.js');
 const fixture=JSON.parse(await readFile('../../fixtures/ai/integrated-pipeline.json','utf8')).outputs[1];
 const context={...fixture.context,household:{...fixture.context.household,transport:'noCar'},tasks:fixture.preparation.tasks};
 const plan={...fixture.resources.searchPlans[0],travelMode:'driving'};
 let calls=0;
 const runner=new FeatureRunner({async turn(){calls++;return {steps:[],calls:[],usage:{},text:JSON.stringify({searchPlans:[plan],question:null})}}});
 await expect(runner.run('resources',context)).rejects.toThrow('unsupported_travel');expect(calls).toBe(2);
});

it('rejects noncanonical inventory categories before they bypass host arithmetic',async()=>{
 const {preparationOutput}=await import('../src/features.js');
 const observation={id:'bottle',physicalID:'one-bottle',category:'water',quantity:2,unit:'liter',evidenceIDs:['typed'],unknowns:[]};
 expect(preparationOutput.safeParse({tasks:[],inventoryObservations:[observation],question:null}).success).toBe(true);
 expect(preparationOutput.safeParse({tasks:[],inventoryObservations:[{...observation,category:'hydration'}],question:null}).success).toBe(false);
});


it('supports station and meetup searches without granting geographic data forwarding',()=>{
 const base={id:'meetup-search',taskID:'recorded-meetup-task',dependencyIDs:['meetingPlace'],hazardIDs:[],purpose:'Review a communication or meetup preparation option',mandatoryCapabilities:[],unknowns:['Actual role and household agreement; no shelter capability established'],travelMode:'walking',maximumDistanceKm:5,expansionLimit:0,requiredEvidence:['Confirm the household arrangement and actual facility role'],cloudReturnPolicy:'local_only'};
 for(const category of ['policeStation','fireStation','trustedMeetup']){
  expect(resourcePlan.safeParse({...base,category}).success).toBe(true);
  expect(resourcePlan.safeParse({...base,category,cloudReturnPolicy:'send_listings'}).success).toBe(false);
 }
});


it('keeps optional reviewed item kind separate from broad inventory category',async()=>{
 const {preparationOutput}=await import('../src/features.js');
 const observation={id:'one-batch',physicalID:'batch',category:'light',quantity:3,unit:'count',evidenceIDs:['typed'],unknowns:[]};
 for(const preparationKind of [undefined,null,'flashlight'])expect(preparationOutput.safeParse({tasks:[],inventoryObservations:[{...observation,preparationKind}],question:null}).success).toBe(true);
 expect(preparationOutput.safeParse({tasks:[],inventoryObservations:[{...observation,preparationKind:'any-light-is-a-flashlight'}],question:null}).success).toBe(false);
});

it('accepts submitted-image metadata but rejects the actual local calibration companion before provider dispatch',async()=>{
 const {readFile}=await import('node:fs/promises');
 const {FeatureRunner}=await import('../src/features.js');
 const fixture=JSON.parse(await readFile('../../fixtures/ai/image-geometry-v1.json','utf8'));
 expect(imageManifest.parse(fixture.manifest)).toEqual(fixture.manifest);
 const household={revision:1,people:[],pets:[],equipment:[],transport:'unknown',limitedBudget:false,regionID:'synthetic',evidence:[]};
 const context={household,tasks:[],gaps:[],allowedActionIDs:[],allowedCriterionIDs:[],images:[fixture.manifest]};
 let calls=0;
 const runner=new FeatureRunner({async turn(){calls++;throw new Error('must_not_dispatch')}});
 await expect(runner.run('home',{...context,images:[{...fixture.manifest,captureGeometry:fixture.geometry}]})).rejects.toThrow();
 await expect(runner.run('home',{...context,cameraToCapture:fixture.geometry.cameraToCapture})).rejects.toThrow();
 expect(calls).toBe(0);
});
