import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {Host} from './host.js';
const host=new Host(),results=[];
const rubric=JSON.parse(await readFile('../../content/ai/rubric-v0.json','utf8'));
const confirmed=(value:unknown)=>({value,origin:'userConfirmed',status:'confirmed',sourceIDs:[],inputIDs:[]});
const unknown={origin:'unknown',status:'unknown',sourceIDs:[],inputIDs:[]};
try {
 for(const category of ['water','food']){
  const original=await host.request({op:'initialize',sample:'oak',scenarioID:'water-outage'});
  const item={id:category,physicalID:category,category,quantity:confirmed(0),unit:category==='water'?'liter':'day',usableQuantity:unknown,accessible:confirmed(true),subjectIDs:[],evidenceIDs:['synthetic-confirmed-empty-container']};
  const state=await host.request({op:'confirmInventory',session:original.session,inventoryItems:[item]});
  const assessed=await host.request({op:'assess',session:state.session,inventory:state.inventory,rubric});
  const empty=assessed.assessments.find((a:any)=>a.criterionID===category);
  assert.deepEqual(empty.predicates,{quantity:false,accessible:false});
  assert.equal(assessed.scorecard.assessmentVersion,'dryrun.household-assessment/4');
  const unreadable=await host.request({op:'confirmInventory',session:state.session,inventory:state.inventory,inventoryItems:[{...item,quantity:confirmed(2)}]});
  const observed=await host.request({op:'assess',session:unreadable.session,inventory:unreadable.inventory,rubric});
  assert.deepEqual(observed.assessments.find((a:any)=>a.criterionID===category).predicates,{accessible:true});
  const malformed=structuredClone(unreadable.inventory);malformed.items[0].accessible.origin='scanObserved';
  await assert.rejects(host.request({op:'assess',session:unreadable.session,inventory:malformed,rubric}),/invalidCommand/);
  await assert.rejects(host.request({op:'confirmInventory',session:original.session,inventoryItems:[item,{...item,quantity:confirmed(3)}]}),/duplicate/);
  results.push({category,empty:empty.predicates,unknownUsable:observed.assessments.find((a:any)=>a.criterionID===category).predicates,gap:state.gaps.find((g:any)=>g.category===category),emptyWaterProjection:category==='water'?state.receipt.snapshot.resources['res.water.stored']:null,malformedOriginRejected:true,duplicateBatchRejected:true});
 }
 const original=await host.request({op:'initialize',sample:'oak',scenarioID:'water-outage'});
 const huge={id:'huge',physicalID:'huge',category:'water',quantity:confirmed(Number.MAX_VALUE),unit:'usGallon',usableQuantity:confirmed(Number.MAX_VALUE),accessible:confirmed(true),subjectIDs:[],evidenceIDs:['synthetic-overflow']};
 await assert.rejects(host.request({op:'confirmInventory',session:original.session,inventoryItems:[huge]}),/invalidCommand/);
 const personIDs=original.session.initial.household.people.map((p:any)=>p.id);
 const scoped={...huge,id:'scoped',physicalID:'scoped',quantity:confirmed(100),usableQuantity:confirmed(100),unit:'liter',subjectIDs:[personIDs[0]]};
 const restricted=await host.request({op:'confirmInventory',session:original.session,inventoryItems:[scoped]});
 const scopedGap=restricted.gaps.find((g:any)=>g.category==='water');
 assert.equal(scopedGap.scopeUnsupported,true);assert.equal(scopedGap.confirmedUsable,0);assert.equal(scopedGap.deficit,undefined);
 const scopedAssessment=await host.request({op:'assess',session:restricted.session,inventory:restricted.inventory,rubric});
 assert.deepEqual(scopedAssessment.assessments.find((a:any)=>a.criterionID==='water').predicates,{});
 assert.equal(restricted.receipt.inventory.items.find((i:any)=>i.id==='scoped').remaining,100);
 results.push({subjectScope:'partial household',gap:scopedGap,physicalRemaining:100,unsupportedAllocationDisclosed:true});
 await writeFile('../../fixtures/ai/inventory-validation-v4.json',JSON.stringify({synthetic:true,modelCalls:0,assessmentVersion:'dryrun.household-assessment/4',results,overflowRejected:true,limits:'Headless transaction/schema checks; inout state and failed persistence atomicity are separately covered in Core. Native UI/Vault save path still pending.'},null,2)+'\n');
 console.log(JSON.stringify({status:'passed',zeroNotUnknown:true,emptyNoAccessCredit:true,unknownPreserved:true,decodedOriginRejected:true,duplicateBatchRejected:true,overflowRejected:true,modelCalls:0}));
}finally{host.close();}
