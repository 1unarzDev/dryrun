import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host(),cases:any[]=[];
try {
 const source=await host.request({op:'initialize',scenarioID:'home-fire'});
 const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
 const input=structuredClone(source.session.initial);
 input.household.contacts=[{id:'synthetic-trusted-contact',role:'other',alias:'Synthetic trusted contact',phone:'5550100'}];
 input.household.preparedness??={items:{}};delete input.household.preparedness.items.reconnect;
 let baseline:any;
 for(const value of [null,true,false]){
  const variant=structuredClone(input);
  if(value!==null)variant.household.preparedness.items.reconnect={available:{value,status:'confirmed',origin:'userConfirmed',sourceIDs:[],inputIDs:[]},location:'Legacy household arrangement',notes:'Preserve this owner-written legacy note'};
  const initialized=await host.request({op:'initialize',input:variant,rubric});
  const assessed=await host.request({op:'assess',session:initialized.session,rubric});
  assert.equal(assessed.scorecard.assessmentVersion,'dryrun.household-assessment/7');
  const contact=assessed.assessments.find((a:any)=>a.criterionID==='contact');
  assert.deepEqual(contact.predicates,{usableContact:true});assert.deepEqual(contact.evidenceIDs,['contacts']);
  assert(!initialized.taskCatalog.some((t:any)=>t.actionID==='prep.reconnect'));
  if(value===null)baseline=assessed.scorecard;else assert.deepEqual(assessed.scorecard,baseline,'obsolete boolean cannot change score or evidence coverage');
  const restored=await host.request({op:'query',session:JSON.parse(JSON.stringify(initialized.session))});
  assert.deepEqual(restored.session.initial.household,initialized.session.initial.household);
  assert.deepEqual(restored.receipt,initialized.receipt);
  assert.deepEqual(restored.session.initial.household.contacts,variant.household.contacts);
  if(value!==null){assert.equal(restored.session.initial.household.preparedness.items.reconnect.available.value,value);assert.equal(restored.session.initial.household.preparedness.items.reconnect.notes,'Preserve this owner-written legacy note');}
  cases.push({legacyValue:value,initialSession:initialized.session,receipt:initialized.receipt,contactAssessment:contact,scorecard:assessed.scorecard});
 }
 await writeFile('../../fixtures/ai/reconnection-retirement.json',JSON.stringify({synthetic:true,liveModelCalls:0,mode:'actual host source assessment/7 and serialized session restore',cases,offlineCopyEvidence:'Not represented by this household model; remains unknown. Generic reconnection, a solo card review and a saved number do not establish a separately accessible copy.',native:'pending',humanReview:'pending'},null,2)+'\n');
 console.log(JSON.stringify({passed:true,variants:3,legacyDataAndContactsPreserved:true,noReconnectionTask:true,noOfflineCopyInference:true,sameScoreAndCoverage:true,replay:'exact',liveModelCalls:0,native:'pending'}));
}finally{host.close();}
