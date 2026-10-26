import {createHash} from 'node:crypto';
import {executeDirectorTool} from './director-tools.js';
import {readFile,writeFile,access} from 'node:fs/promises';
import {PublicEvidenceTools} from '../src/evidence.js';
import {Host} from './host.js';
import {GeminiProvider} from '../src/provider.js';
import {Gateway} from '../src/gateway.js';
import {minimizedSnapshot,minimizedAssistance} from '../src/contracts.js';
import {FeatureRunner,preparationOutput,resourceOutput,stressOutput,featureContext,rubricSchema} from '../src/features.js';
const runID=new Date().toISOString().replace(/[:.]/g,'-');
const outputPath=process.env.DRYRUN_PIPELINE_OUTPUT??'../../fixtures/ai/integrated-pipeline-'+runID+'.json';
try{await access(outputPath);throw new Error('output_already_exists');}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}
const host=new Host();const provider=new GeminiProvider(process.env.GOOGLE_AI_STUDIO_KEY??'');
const failurePath=outputPath.replace(/\.json$/,'')+'-failure-'+runID+'.json';
const captured:unknown[]=[];
const sourceHashes=Object.fromEntries(await Promise.all(['scripts/pipeline.ts','src/output-quality.ts','src/provider.ts','src/gateway.ts','src/features.ts','src/contracts.ts','../../content/manifest.json','../../content/ai/rubric-v0.json','../../DryRun_AI_Implementation_Reference.md'].map(async path=>[path,createHash('sha256').update(await readFile(path)).digest('hex')])));
let stage='initialize',currentSample='',currentState:unknown;

const recording={async turn(input:Parameters<typeof provider.turn>[0]){const started=Date.now();const reply=await provider.turn(input);captured.push({text:reply.text,calls:reply.calls.map(c=>({name:c.name,arguments:c.arguments})),usage:reply.usage,latencyMs:Date.now()-started});return reply;}};
const gateway=new Gateway(recording);
const runner=new FeatureRunner(recording,40,await PublicEvidenceTools.bundled('../..'));
const rubric=rubricSchema.parse(JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8')));
const outputs:unknown[]=[];
try{
 for(const sample of ['oak','lake']){
  currentSample=sample;stage='initialize';
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
  currentState=state;stage='preparation';
  const preparation=preparationOutput.parse(await runner.run('preparation',context));
  stage='resources';
  const resources=resourceOutput.parse(await runner.run('resources',{...context,tasks:preparation.tasks}));
  stage='stress';
  const stress=stressOutput.parse(await runner.run('stress',{...context,tasks:preparation.tasks,allowedCriterionIDs:['water','device','contact']}));
  const executed=[];for(const challenge of stress.challenges){const result=await host.request({op:'stress',session:state.session,profileIDs:challenge.profileIDs});executed.push(result.stress);}
  stage='host_action';
  const incident=state.profiles.find((p:any)=>p.id.includes(sample==='oak'?'well-pump-failure':'main-break'));
  state=await host.request({op:'commit',session:state.session,commit:{id:'incident',actor:'director',baseRevision:0,commands:[{kind:'schedule',target:incident.id,minute:0},{kind:'advance',minute:0}]}});
  state=await host.request({op:'commit',session:state.session,commit:{id:'water-policy',actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'useStoredWater',value:sample==='oak'?'essential':'all'}]}});
  const binding={sessionID:state.receipt.sessionID,revision:state.receipt.revision,eventSequence:state.receipt.eventSequence,contextDigest:state.receipt.contextDigest,householdRevision:state.session.initial.household.revision,homeRevision:state.session.initial.home?.revision??0};
  currentState=state;stage='director';
  const directorContext={binding,snapshot:minimizedSnapshot(state.receipt),assistance:minimizedAssistance(state.receipt),household:state.householdContext,homeScene:state.homeScene,directorPolicy:state.session.directorPolicy,directorState:state.receipt.directorState,pending:state.receipt.pending,closedPortalIDs:state.receipt.closedPortalIDs,profiles:state.directorProfiles??state.profiles.map((p:any)=>({id:p.id,rule:p.rule,minute:p.minute})),learningObjectives:['Inspect committed water conservation consequences and direct the next useful incident or decision'],lastAction:state.lastAction,recentActions:state.recentActions};
  let directed:any=await gateway.start('synthetic-pipeline',{contractVersion:'dryrun.ai/1',requestID:'pipeline-'+sample,role:'director',synthetic:true,context:directorContext});
  const adaptiveTrace:unknown[]=[];
  while(directed.status==='needs_client_tools'){
   const call=directed.calls[0];const preview=await executeDirectorTool(host,state,binding,call);
   adaptiveTrace.push({tool:call.name,arguments:call.arguments,preview:preview.receipt});
   directed=await gateway.resume('synthetic-pipeline',{token:directed.token,binding,callID:call.id,result:preview.result});
  }
  if(directed.status!=='completed')throw new Error('adaptive_pipeline_unavailable');
  state=await host.request({op:'directorCommit',session:state.session,proposal:directed.proposal,binding});
  adaptiveTrace.push({proposal:directed.proposal,committed:state.receipt});
  currentState=state;stage='council';
  const preAssessment=await host.request({op:'assess',session:state.session,inventory:confirmedInventory,stressFindings:executed,rubric});
  const assessmentEvidence=preAssessment.assessments.flatMap((a:any)=>a.evidenceIDs.map((id:string)=>({id,origin:'derived',status:'confirmed',sourceIDs:[],fieldIDs:Object.keys(a.predicates)})));
  const council=await runner.council({...context,household:{...context.household,evidence:[...context.household.evidence,...assessmentEvidence]},acceptedPredicates:preAssessment.assessments});
  const assessment=await host.request({op:'assess',session:state.session,inventory:confirmedInventory,stressFindings:executed,rubric});
  console.log(JSON.stringify({sample,calls:runner.calls+gateway.metrics.calls,status:'completed'}));
  outputs.push({synthetic:true,sample,session:state.session,inventory:confirmedInventory,context,preparation,resources,stress,executed,adaptiveTrace,council,acceptedAssessments:assessment.assessments,scorecard:assessment.scorecard});
 }
 await writeFile(outputPath,JSON.stringify({synthetic:true,liveModel:true,model:provider.model,sdk:'2.30.0',recordedAt:new Date().toISOString(),sourceHashes,calls:provider.budget.calls,budgetAccountedUSD:provider.budget.spentUSD,usage:[...runner.usage,...gateway.metrics.usage],outputs},null,2)+'\n',{flag:'wx'});console.log(JSON.stringify({status:'passed',households:2,calls:provider.budget.calls,budgetAccountedUSD:provider.budget.spentUSD,output:outputPath}));
}catch(error){
 await writeFile(failurePath,JSON.stringify({synthetic:true,liveModel:true,passed:false,model:provider.model,sdk:'2.30.0',recordedAt:new Date().toISOString(),sourceHashes,stage,sample:currentSample,failure:error instanceof Error?error.name:'pipeline_failure',providerCalls:provider.budget.calls,budgetAccountedUSD:provider.budget.spentUSD,outputs,currentState,replies:captured},null,2)+'\n');
 console.error(JSON.stringify({status:'failed',stage,sample:currentSample,providerCalls:provider.budget.calls,failureArtifact:failurePath}));throw error;
}finally{host.close();}
