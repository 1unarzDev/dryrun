import assert from 'node:assert/strict';
import {practiceSource,practiceObservation} from '../src/practice-contracts.js';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host();
try {
 let state=await host.request({op:'initialize',sample:'oak',scenarioID:'water-outage'});
 state=await host.request({op:'commit',session:state.session,commit:{id:'loss',actor:'director',baseRevision:0,commands:[{kind:'schedule',target:'evt.water-outage.well-pump-failure',minute:0},{kind:'advance',minute:0}]}});
 state=await host.request({op:'practiceBegin',session:state.session,attemptID:'check',variantID:'practice-check-a/0'});
 const begun=structuredClone(state.aiState);practiceSource.parse(begun.practiceAttempts[0].source);
 // The generic rehearsal path cannot hide an initial answer from the practice capture path.
 const hidden=await host.request({op:'commit',session:state.session,commit:{id:'hidden-first-response',actor:'user',baseRevision:state.receipt.revision,commands:[{kind:'useStoredWater',value:'all'}]}});
 const contaminated=structuredClone(begun);contaminated.sessions=[hidden.session];
 await assert.rejects(host.request({op:'practiceSubmit',session:hidden.session,aiState:contaminated,attemptID:'check',competencyID:'initialResponse',commit:{id:'later-improved-answer',actor:'user',baseRevision:hidden.receipt.revision,commands:[{kind:'useStoredWater',value:'essential'}]}}),/invalidCommand/);
 const observations:unknown[]=[];
 for(const [competencyID,kind,value] of [['initialResponse','useStoredWater','essential'],['adaptation','unsupported',undefined],['communication','unsupported',undefined],['continuity','unsupported',undefined]]) {
  const actionID='answer-'+competencyID;
  state=await host.request({op:'practiceSubmit',session:state.session,aiState:state.aiState,attemptID:'check',competencyID,commit:{id:actionID,actor:'user',baseRevision:state.receipt.revision,commands:[{kind,...(value?{value}:{})}]}});
  const captured=structuredClone(state.aiState.practiceAttempts[0].observations.at(-1));
  practiceObservation.parse(captured);
  if(captured.feedbackRevealed)throw new Error('premature_feedback');
  const encoded=JSON.stringify(state.aiState);
  state=await host.request({op:'practiceFeedback',session:state.session,aiState:JSON.parse(encoded),attemptID:'check',feedbackActionID:actionID});
  observations.push({captured,feedback:state.aiState.practiceAttempts[0].observations.at(-1)});
 }
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 const assessment=await host.request({op:'assess',session:state.session,aiState:state.aiState,rubric});
 if(assessment.scorecard.practice!==25||assessment.scorecard.practiceAssessed!==1)throw new Error('unknown_competency_credit');
 let tamperingRejected=false;
 const tampered=structuredClone(state.aiState);tampered.practiceAttempts[0].observations[0].credit=0;
 try {await host.request({op:'assess',session:state.session,aiState:tampered,rubric});}catch{tamperingRejected=true;}
 if(!tamperingRejected)throw new Error('tampered_grade_accepted');
 await writeFile('../../fixtures/ai/practice-capture.json',JSON.stringify({synthetic:true,contractVersion:'dryrun.practice-capture/1',begun,observations,final:state.aiState,scorecard:assessment.scorecard,tamperingRejected,hiddenFirstResponseRejected:true},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',preFeedbackCapture:true,restored:true,practice:25,unassessed:3,tamperingRejected,hiddenFirstResponseRejected:true}));
}finally{host.close();}
