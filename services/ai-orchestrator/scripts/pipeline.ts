import {executeDirectorTool} from './director-tools.js';
import {readFile,writeFile} from 'node:fs/promises';
import {PublicEvidenceTools} from '../src/evidence.js';
import {Host} from './host.js';
import {GeminiProvider} from '../src/provider.js';
import {Gateway} from '../src/gateway.js';
import {minimizedSnapshot} from '../src/contracts.js';
import {FeatureRunner,preparationOutput,resourceOutput,stressOutput,featureContext,rubricSchema} from '../src/features.js';
const host=new Host();const provider=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??'');
const captured:unknown[]=[];
const recording={async turn(input:Parameters<typeof provider.turn>[0]){const reply=await provider.turn(input);captured.push({text:reply.text,calls:reply.calls.map(c=>({id:c.id,name:c.name,arguments:c.arguments}))});await writeFile('/tmp/dryrun-synthetic-model-outputs.json',JSON.stringify(captured,null,2));return reply;}};
const gateway=new Gateway(recording);
const runner=new FeatureRunner(recording,40,await PublicEvidenceTools.bundled('../..'));
const rubric=rubricSchema.parse(JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8')));
const outputs:unknown[]=[];
try{
 for(const sample of ['oak','lake']){
  let state=await host.request({op:'initialize',sample,scenarioID:'water-outage'});
  const input=state.session.initial;
  if(sample==='oak'){input.household.people[2].ageBand='infant';}
  else{input.household.people=input.household.people.slice(0,2).map((p:any)=>({...p,ageBand:'adult',needs:[]}));input.household.equipment=[];input.household.pets=[];}
  state=await host.request({op:'initialize',input,rubric});
  // Migration fixture confirms the water total and accessibility explicitly; it is not model-inferred.
  const gallons=sample==='oak'?5:2;
  const inventory={revision:1,items:[{id:'water',physicalID:'stored-water',category:'water',quantity:{value:gallons,origin:'userConfirmed',status:'confirmed'},unit:'usGallon',usableQuantity:{value:gallons,origin:'userConfirmed',status:'confirmed'},accessible:{value:true,origin:'userConfirmed',status:'confirmed'},subjectIDs:[],evidenceIDs:['typed-water'],lastConfirmedAt:'2026-10-19T00:00:00Z'}]};
  state=await host.request({op:'confirmInventory',session:state.session,inventoryItems:inventory.items,rubric});
  const gaps=state;const confirmedInventory=state.inventory;
  if(state.session.initial.household.supplies.storedWaterGallons.value!==gallons)throw new Error('inventory_projection');
  const context=featureContext.parse({household:state.householdContext,taskCatalog:state.taskCatalog,tasks:[],gaps:gaps.gaps,allowedActionIDs:state.preparationActions,allowedCriterionIDs:rubric.criteria.map(c=>c.id),rubric,scene:state.homeScene,profiles:state.profiles.map((p:any)=>({id:p.id,scenarioID:'water-outage',rule:p.rule,minute:p.minute}))});
  const preparation=preparationOutput.parse(await runner.run('preparation',context));
  const resources=resourceOutput.parse(await runner.run('resources',{...context,tasks:preparation.tasks}));
  const stress=stressOutput.parse(await runner.run('stress',{...context,tasks:preparation.tasks,allowedCriterionIDs:['water','device','contact']}));
  const executed=[];for(const challenge of stress.challenges){const result=await host.request({op:'stress',session:state.session,profileIDs:challenge.profileIDs});executed.push(result.stress);}
  const incident=state.profiles.find((p:any)=>p.id.includes(sample==='oak'?'well-pump-failure':'main-break'));
  state=await host.request({op:'commit',session:state.session,commit:{id:'incident',actor:'director',baseRevision:0,commands:[{kind:'schedule',target:incident.id,minute:0},{kind:'advance',minute:0}]}});
  state=await host.request({op:'commit',session:state.session,commit:{id:'water-policy',actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'useStoredWater',value:sample==='oak'?'essential':'all'}]}});
  const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
  const directorContext={binding,snapshot:minimizedSnapshot(state.receipt),household:state.householdContext,homeScene:state.homeScene,profiles:state.profiles.map((p:any)=>({id:p.id,rule:p.rule,minute:p.minute})),learningObjectives:['Inspect committed water conservation consequences and direct the next useful incident or decision'],lastAction:{id:'water-policy',kind:'useStoredWater',value:sample==='oak'?'essential':'all'}};
  let directed:any=await gateway.start('synthetic-pipeline',{contractVersion:'dryrun.ai/1',requestID:'pipeline-'+sample,role:'director',synthetic:true,context:directorContext});
  const adaptiveTrace:unknown[]=[];
  while(directed.status==='needs_client_tools'){
   const call=directed.calls[0];const preview=await executeDirectorTool(host,state,binding,call);
   adaptiveTrace.push({tool:call.name,arguments:call.arguments,preview:preview.receipt});
   directed=await gateway.resume('synthetic-pipeline',{token:directed.token,binding,callID:call.id,result:preview.result});
  }
  if(directed.status!=='completed'){await writeFile('/tmp/dryrun-pipeline-failure.json',JSON.stringify({synthetic:true,sample,result:directed,metrics:gateway.metrics,adaptiveTrace},null,2));throw new Error('adaptive_pipeline_unavailable');}
  const {id,actor,baseRevision,commands}=directed.proposal;
  state=await host.request({op:'commit',session:state.session,commit:{id,actor,baseRevision,commands}});
  adaptiveTrace.push({proposal:directed.proposal,committed:state.receipt});
  const preAssessment=await host.request({op:'assess',session:state.session,inventory:confirmedInventory,stressFindings:executed,rubric});
  const assessmentEvidence=preAssessment.assessments.flatMap((a:any)=>a.evidenceIDs.map((id:string)=>({id,origin:'derived',status:'confirmed',sourceIDs:[],fieldIDs:Object.keys(a.predicates)})));
  const council=await runner.council({...context,household:{...context.household,evidence:[...context.household.evidence,...assessmentEvidence]},acceptedPredicates:preAssessment.assessments});
  const assessment=await host.request({op:'assess',session:state.session,inventory:confirmedInventory,stressFindings:executed,rubric});
  console.log(JSON.stringify({sample,calls:runner.calls+gateway.metrics.calls,status:'completed'}));
  outputs.push({synthetic:true,sample,session:state.session,inventory:confirmedInventory,context,preparation,resources,stress,executed,adaptiveTrace,council,acceptedAssessments:assessment.assessments,scorecard:assessment.scorecard});
 }
 await writeFile(process.env.DRYRUN_PIPELINE_OUTPUT??'../../fixtures/ai/integrated-pipeline.json',JSON.stringify({model:'gemini-3.1-flash-lite',sdk:'2.30.0',recordedAt:new Date().toISOString(),calls:runner.calls+gateway.metrics.calls,usage:[...runner.usage,...gateway.metrics.usage],outputs},null,2));console.log(JSON.stringify({status:'passed',households:2,calls:runner.calls+gateway.metrics.calls}));
}finally{host.close();}
