import assert from 'node:assert/strict';
import {readFile,writeFile,access} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {z} from 'zod';
import {Host} from './host.js';
import {GeminiProvider} from '../src/provider.js';
import {FeatureRunner,featureContext} from '../src/features.js';
import {outputStyle,inspectOutput} from '../src/output-quality.js';
const live=process.env.DRYRUN_LIVE_HOUSING==='1';
const runID=new Date().toISOString().replace(/[:.]/g,'-');
const livePath=process.env.DRYRUN_HOUSING_OUTPUT??'../../fixtures/ai/housing-layout-live-'+runID+'.json';
if(live){try{await access(livePath);throw new Error('output_already_exists');}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}}
const host=new Host(),provider=live?new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??''):undefined;
const schema=z.object({status:z.enum(['feasibleUnderRecordedAssumptions','notEstablished']),reason:z.string().min(25).max(600),evidenceIDs:z.array(z.string()).min(1).max(10),unknowns:z.array(z.string().min(1).max(300)).min(1).max(5)}).strict();
const results:any[]=[],features:any[]=[],replies:any[]=[];let currentFeature:unknown;
const sourceHashes=Object.fromEntries(await Promise.all(['scripts/housing-layout-eval.ts','src/features.ts','src/output-quality.ts','../../DryRun_AI_Implementation_Reference.md'].map(async p=>[p,createHash('sha256').update(await readFile(p)).digest('hex')])));
try{
 const seed=await host.request({op:'initialize',scenarioID:'home-fire'});
 for(const kind of ['apartment-complex','manufactured','twostory']){
  const home=JSON.parse(await readFile('../../fixtures/homes/home-sample-'+kind+'.json','utf8'));
  const input=structuredClone(seed.session.initial);input.home=home;input.household.equipment=[];input.household.backupPower=[];
  input.household.housing.homeType=kind==='manufactured'?'manufacturedHome':kind==='apartment-complex'?'apartment':'singleFamily';
  input.household.housing.floorCount=home.floors.length;
  input.household.people=[{...input.household.people[0],sleepingSpaceID:'sp-bed1',needs:[],helperPersonID:undefined}];
  const state=await host.request({op:'initialize',input});
  const context=featureContext.parse({household:state.householdContext,scene:state.homeScene,tasks:[],gaps:[],allowedActionIDs:state.preparationActions,allowedCriterionIDs:[]});
  assert.equal(context.household.housing?.homeType,input.household.housing.homeType);
  assert.equal(context.scene?.schemaVersion,'dryrun.home-scene/2');
  if(context.scene?.schemaVersion==='dryrun.home-scene/2'){
   const baseline=context.scene.planningRoutes?.[0];assert.ok(baseline?.alternativeStatus);
   if(kind==='twostory'){assert.equal(baseline.alternativeStatus,'sharesChokepoint');assert.ok(baseline.sharedChokepointIDs?.includes('cn-stairs'));}
  }
  const tests=process.env.DRYRUN_HOUSING_FEATURES_ONLY==='1'?[]:[{id:kind+'-walking',stepFree:false,blocked:[],expected:true},
   {id:kind+'-blocked-or-stepfree',stepFree:kind!=='twostory',blocked:kind==='twostory'?['cn-stairs']:[],expected:false}];
  for(const test of tests){
   const request={personID:input.household.people[0].id,startSpaceID:'sp-bed1',mobility:{requiresStepFree:test.stepFree,minimumClearWidthMeters:test.stepFree?0.82:0.7},exclusions:{blockedSpaceIDs:[],blockedPortalIDs:[],blockedConnectorIDs:test.blocked}};
   const queried=await host.request({op:'query',session:state.session,tool:{kind:'queryRoutes',baseRevision:0,routeRequest:request}});
   const route=queried.tool.route;assert.equal(Boolean(route.primary),test.expected);
   const evidenceIDs=[...home.spaces.map((r:any)=>r.id),...home.portals.map((r:any)=>r.id),...home.connectors.map((r:any)=>r.id)];
   const assessmentInput={allowedEvidenceIDs:evidenceIDs,household:context.household,scene:context.scene,course:{startRoomID:'sp-bed1',purpose:'outdoorEgress',stepFreeRequired:test.stepFree,blockedConnectorIDs:test.blocked},hostRoute:{primary:route.primary??null,alternativeStatus:route.alternativeStatus,sharedChokepointIDs:route.sharedChokepoints,noRouteReason:route.noRouteReason??null,exclusions:route.exclusions},instruction:'Cite exact allowedEvidenceIDs only. Assess this exact course only. A path requires a host primary route. Do not invent a window escape, elevator exception or structural safety. Explain the concrete dependency and one material unknown. In manufactured homes never propose the closet for tornado shelter; in upper floors windows are not walking exits. Feasible means recorded practice assumptions only.'};
   let output:unknown;
   if(provider){
    const boundSchema=schema.extend({evidenceIDs:z.array(z.enum(evidenceIDs as [string,...string[]])).min(1).max(3)});
    const history:import('../src/provider.js').History=[{type:'user_input',content:[{type:'text',text:JSON.stringify(assessmentInput)}]}];
    for(let repair=0;repair<2;repair++){
     const reply:Awaited<ReturnType<GeminiProvider['turn']>>=await provider.turn({history,instruction:'DryRun synthetic housing interpretation evaluation. Return JSON matching the schema. Cite one to three exact allowedEvidenceIDs, never the full allowlist. '+outputStyle,tools:[],outputSchema:z.toJSONSchema(boundSchema),signal:AbortSignal.timeout(60000)});
     replies.push({id:test.id,repair,text:reply.text});
     try{
      assert.equal(reply.calls.length,0);output=boundSchema.parse(JSON.parse(reply.text));
      assert.equal(schema.parse(output).status,test.expected?'feasibleUnderRecordedAssumptions':'notEstablished');
      break;
     }catch(error){if(repair)throw error;history.push(...reply.steps,{type:'user_input',content:[{type:'text',text:'Repair once. Return the exact schema, one to three IDs from allowedEvidenceIDs, and status based only on whether hostRoute.primary exists.'}]});}
    }
   }

   results.push({id:test.id,liveModel:live,source:state.session,context:assessmentInput,expected:test.expected?'feasibleUnderRecordedAssumptions':'notEstablished',output:output??null,outputReview:output?inspectOutput('layout',output):[],hostReceiptUnchanged:queried.receipt.contextDigest===state.receipt.contextDigest});
  }
  if(provider){
   const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
   const assessed=await host.request({op:'assess',session:state.session,rubric});
   const runner=new FeatureRunner(provider);
   const prepContext={...context,taskCatalog:assessed.taskCatalog,allowedCriterionIDs:rubric.criteria.map((r:any)=>r.id),gaps:assessed.gaps??[]};
   currentFeature={sample:kind,stage:'preparation',context:prepContext};
   const preparation=await runner.run('preparation',prepContext);
   currentFeature={sample:kind,stage:'resources',context:prepContext,preparation};
   const resources=await runner.run('resources',{...prepContext,tasks:(preparation as any).tasks});
   features.push({sample:kind,context:prepContext,preparation,resources});
  }
 }
 const path=live?livePath:'../../fixtures/ai/housing-layout-host.json';
 await writeFile(path,JSON.stringify({synthetic:true,liveModel:live,featuresOnly:process.env.DRYRUN_HOUSING_FEATURES_ONLY==='1',model:provider?.model,recordedAt:new Date().toISOString(),sourceHashes,replies,calls:provider?.budget.calls??0,budgetAccountedUSD:provider?.budget.spentUSD??0,results,outputs:features,limitations:['Synthetic geometry; not a RoomPlan/device accuracy test','Interpretation matches host route feasibility, not real-world safety','Human review and wired iPhone visual/function checks pending']},null,2)+'\n',live?{flag:'wx'}:undefined);
 console.log(JSON.stringify({passed:true,cases:results.length,featureHouseholds:features.length,liveModel:live,calls:provider?.budget.calls??0,budgetAccountedUSD:provider?.budget.spentUSD??0}));
}catch(error){await writeFile('../../fixtures/ai/housing-layout-failure-'+Date.now()+'.json',JSON.stringify({synthetic:true,liveModel:live,sourceHashes,results,replies,currentFeature,outputs:features,failure:error instanceof Error?error.message:'failed',calls:provider?.budget.calls??0},null,2)+'\n');throw error;}finally{host.close();}
