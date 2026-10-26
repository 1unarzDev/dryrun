import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Host} from './host.js';
import {practicePhasePlan} from '../src/practice-contracts.js';
const host=new Host();
try {
 const fixture=JSON.parse(await readFile('../../fixtures/ai/practice-'+(process.env.DRYRUN_PRACTICE_NONDEVICE==='1'?'nondevice':'phases')+(process.env.DRYRUN_PRACTICE_REVERSE==='1'?'-reverse':'')+'.json','utf8'));
 const plan=practicePhasePlan.parse(fixture.plan);
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 for(const branch of fixture.branches){
  let local=JSON.parse(JSON.stringify(fixture.begun));
  for(const [index,step] of branch.checkpoints.entries()){
   const current=local.sessions.find((s:any)=>s.id===plan.phaseSources[index]!.sessionID);
   let state=await host.request({op:'practiceSubmit',session:current,aiState:local,attemptID:'four-situations',competencyID:step.competencyID,commit:step.commit});
   assert.deepEqual(state.aiState.practiceAttempts[0].observations.at(-1),step.observation);
   state=await host.request({op:'practiceFeedback',session:state.session,aiState:state.aiState,attemptID:'four-situations',feedbackActionID:step.commit.id});
   assert.deepEqual(state.receipt,step.receipt);assert.deepEqual(state.aiState.practiceAttempts[0].observations.at(-1),step.feedbackObservation);
   const scored=await host.request({op:'assess',session:state.session,aiState:state.aiState,rubric});
   assert.deepEqual(scored.scorecard,step.scorecard);
   local=state.aiState;
  }
  assert.deepEqual(local,branch.final);
  assert.equal(branch.practice,branch.wrongFirst?75:100);assert.equal(branch.practiceAssessed,4);
 }
 if(fixture.resourceProof){
  const source=fixture.sources.find((s:any)=>s.id===fixture.resourceProof.sourceID);
  for(const proof of fixture.resourceProof.projections){
   const action=await host.request({op:'commit',session:source,commit:proof.actionCommit});
   const projected=await host.request({op:'preview',session:action.session,commit:proof.forecastCommit});
   assert.deepEqual(projected.receipt,proof.receipt);
  }
  assert.deepEqual((await host.request({op:'query',session:source})).receipt,fixture.resourceProof.original);
 }
 console.log(JSON.stringify({passed:true,modelCalls:0,variantID:plan.variantID,branches:2,actionAndReceiptReplay:true,preFeedbackGradeReplay:true,scoreReplay:true,allFourCompetencies:true}));
}finally{host.close();}
