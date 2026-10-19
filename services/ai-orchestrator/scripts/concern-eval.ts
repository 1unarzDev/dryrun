import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
import {normalizeHomeReview} from '../src/home-review.js';
import {featureContext} from '../src/features.js';
const host=new Host();
try{
 let state=await host.request({op:'initialize',sample:'oak',scenarioID:'home-fire'});
 const annotations=JSON.parse(await readFile('../../fixtures/ai/images/annotations.json','utf8'));
 const manifest=annotations.cases.find((c:any)=>c.name==='obstructed').manifest;
 const vision=JSON.parse(await readFile('../../fixtures/ai/vision-evaluation-gemini-3.8-flash.json','utf8'));
 const output=vision.results.find((r:any)=>r.fixture==='obstructed').output;
 const context=featureContext.parse({household:state.householdContext,tasks:[],gaps:[],allowedActionIDs:state.preparationActions,allowedCriterionIDs:[],scene:state.homeScene,images:[manifest]});
 const proposals=normalizeHomeReview(output,context);
 const proposal=proposals[0];if(!proposal)throw new Error('recorded_observation_missing');
 const source=JSON.stringify(state.session.initial),rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 const uncertain=await host.request({op:'reviewConcern',session:state.session,concernProposal:proposal,imageManifest:manifest,concernDecision:'uncertain',rubric});
 if(uncertain.concernTasks.length)throw new Error('uncertain_created_task');
 const portal=state.homeScene.portals.find((p:any)=>(p.sideA===proposal.roomID&&p.sideB==='exterior')||(p.sideB===proposal.roomID&&p.sideA==='exterior'));
 if(!portal)throw new Error('manual_fixture_opening_missing');
 let permissionRejected=false;
 try{await host.request({op:'concernExercise',session:state.session,aiState:uncertain.aiState,concernID:proposal.id,selectedPortalIDs:[portal.id],allowHypothetical:false});}catch{permissionRejected=true;}
 if(!permissionRejected)throw new Error('hypothesis_without_permission');
 const hypothetical=await host.request({op:'concernExercise',session:state.session,aiState:uncertain.aiState,concernID:proposal.id,selectedPortalIDs:[portal.id],allowHypothetical:true});
 const confirmed=await host.request({op:'reviewConcern',session:state.session,aiState:uncertain.aiState,concernProposal:proposal,imageManifest:manifest,concernDecision:'confirmed',rubric});
 if(confirmed.concernTasks.length!==1||confirmed.concernTasks[0].earnsScoreByItself)throw new Error('bad_task_link');
 const commands=[{kind:'schedule',target:'evt.home-fire.alarm',minute:0},{kind:'advance',minute:0}];
 const baseline=await host.request({op:'commit',session:state.session,commit:{id:'alarm',actor:'director',baseRevision:0,commands}});
 const exercise=await host.request({op:'commit',session:hypothetical.session,commit:{id:'alarm',actor:'director',baseRevision:0,commands}});
 if(exercise.receipt.routes.some((r:any)=>r.primary?.portalSequence.includes(portal.id)))throw new Error('excluded_opening_used');
 if(!exercise.receipt.snapshot.spatialState.affectedPortalIDs.includes(portal.id))throw new Error('scene_mismatch');
 if(JSON.stringify(exercise.session.initial)!==source||JSON.stringify(baseline.session.initial)!==source)throw new Error('real_facts_changed');
 const replay=await host.request({op:'query',session:exercise.session});if(JSON.stringify(replay.receipt)!==JSON.stringify(exercise.receipt))throw new Error('replay_mismatch');
 const stress=await host.request({op:'stress',session:hypothetical.session,profileIDs:['evt.home-fire.alarm'],intervention:{actionID:'act.water.store-3day',parameters:{}}});
 if(!stress.stress.sourceConcernDigest||!stress.stress.controlledRetest)throw new Error('concern_stress_scope_lost');
 const plainScore=await host.request({op:'assess',session:state.session,rubric});
 const concernScore=await host.request({op:'assess',session:state.session,rubric,stressFindings:[stress.stress]});
 if(JSON.stringify(plainScore.scorecard)!==JSON.stringify(concernScore.scorecard))throw new Error('hypothesis_changed_score');
 const dismissed=await host.request({op:'reviewConcern',session:state.session,aiState:confirmed.aiState,concernProposal:proposal,imageManifest:manifest,concernDecision:'dismissed',rubric});
 if(dismissed.concernTasks.length)throw new Error('dismissed_task_retained');
 const revisedSession=structuredClone(state.session);revisedSession.initial.home.revision+=1;
 const revisedProposal={...proposal,id:'same-pixels-new-model-id',homeRevision:revisedSession.initial.home.revision};
 const revisedManifest={...manifest,homeRevision:revisedSession.initial.home.revision};
 await assert.rejects(host.request({op:'reviewConcern',session:revisedSession,aiState:dismissed.aiState,concernProposal:revisedProposal,imageManifest:revisedManifest,concernDecision:'confirmed',rubric}),/duplicate/);

 await writeFile('../../fixtures/ai/concern-integration.json',JSON.stringify({synthetic:true,newModelCalls:0,recordedVisionModel:vision.model,annotation:'Recorded synthetic image interpretation; explicitly fixture-selected opening, never inferred from pixels',proposal,manifest,uncertain:uncertain.aiState,permissionRejected,manualSelectedPortalID:portal.id,task:confirmed.concernTasks[0],hypotheticalSession:exercise.session,baselineReceipt:baseline.receipt,exerciseReceipt:exercise.receipt,controlledStress:stress.stress,scoreUnchanged:true,dismissed:dismissed.aiState,unchangedEvidenceAfterHomeRevisionRejected:true},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',recordedVision:true,uncertainPermission:true,taskLinked:true,openingExcluded:true,sceneSynced:true,replay:true,sourceUnchanged:true,controlledStress:true,scoreUnchanged:true,unchangedEvidenceAfterHomeRevisionRejected:true}));
}finally{host.close();}
